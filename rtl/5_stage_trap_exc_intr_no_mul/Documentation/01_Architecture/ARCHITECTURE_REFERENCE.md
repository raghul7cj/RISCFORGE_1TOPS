# Architecture Reference Guide

**Project**: RISCFORGE 1TOPS — 5-Stage RV32I Processor, Machine Mode Only  
**Model**: Propagate-and-Commit Precise Exception Architecture  

> **One-Line Summary**:  
> *Detect → Tag instruction → Continuous-flush younger → Propagate sideband → Gate side effects → Commit at WB → Redirect PC*

---

## 1. Pipeline Overview

```
Cycle:    1        2        3        4        5
         ┌────────┐
  IMEM   │ fetch  │
         └────────┘
                  ┌────────┐
  ID              │ decode │
                  └────────┘
                           ┌────────┐
  EX                       │  ALU   │
                           └────────┘
                                    ┌────────┐
  MEM                               │  DMEM  │
                                    └────────┘
                                             ┌────────┐
  WB                                         │  MUX   │ ← Trap commits here
                                             └────────┘
```

**5 Stages**: IF → ID → EX → MEM → WB  
**Pipeline Registers**: IF/ID, ID/EX, EX/MEM, MEM/WB  
**Hazard Unit**: `utils/hazard_unit.v` — forwarding, stalls, continuous flush wake  
**Trap Controller**: `wb_trap_mret_commit_controller.v` — purely combinational WB-boundary commit  

---

## 2. Key Architectural Decisions

### Decision 1: Propagate-and-Commit (No FSM)
- Exceptions travel with their instruction as **pipeline register sideband fields**
- No separate exception FSM or arbiter
- Trap is committed **combinationally at WB** when `valid_W & exc_valid_W`
- Rationale: in-order pipeline guarantees age ordering for free — oldest instruction always reaches WB first

### Decision 2: Continuous Flush "Wake"
- While an exception-tagged instruction is in EX or MEM, **all younger pipeline stages are continuously flushed**
- Not a one-shot flush — fetch may continue, but ID/EX are bubbled every cycle
- Guarantees no younger instruction can commit a side effect before trap fires
- Implementation: `exc_inflight_E` and `exc_inflight_M` signals drive `FlushD`/`FlushE`

### Decision 3: Triple Side-Effect Gating

| Gate | Mechanism | Location |
|------|-----------|----------|
| `valid == 0` | Instruction was flushed — no effect | All stages |
| `exc_valid == 1` | Instruction faulted — suppress normal writes | EX, MEM, WB |
| Local detection | Same-cycle MEM exception gates same-cycle write | MEM only |

```verilog
// EX: Don't let faulting instruction redirect PC
PCSrcE = yesE & valid_E & ~exc_valid_E;

// MEM: Don't let exception-tagged instruction write memory
MemWriteM_gated = MemWriteM & valid_M & ~exc_valid_M;

// WB: Gate register and CSR writes
RegWriteW_gated    = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;
csr_write_en_gated = csr_write_en_W & valid_W & ~exc_valid_W & ~mret_commit;
```

### Decision 4: M-Mode Only, Direct Mode mtvec
- Only Machine Mode implemented. No user/supervisor mode.
- `mstatus.MPP` always set to `2'b11` (M-mode) on trap entry and MRET.
- `mtvec.MODE` frozen to `2'b00` (Direct mode). All traps go to `mtvec.BASE`.
- Vectored mode can be added later by checking `mtvec[1:0]` and using `BASE + 4*cause`.

### Decision 5: MRET Is a Control Redirect
- MRET is not an exception. It flows through the pipeline as a normal instruction.
- At WB: triggers PC redirect to `mepc`, restores `mstatus`, flushes pipeline.
- `mret_commit = valid_W & is_mret_W & ~exc_valid_W` (exception beats MRET)

### Decision 6: mepc Semantics
- **Synchronous exceptions**: `mepc = PC of faulting instruction` (handler can retry or skip)
- **Asynchronous interrupts** (Phase 6): `mepc = PC_W + 4` (next instruction — retiring one completed)

---

## 3. Pipeline Register Field Map

### IF/ID Register (`fetch_cycle.v`)
| Signal | Width | Description |
|--------|-------|-------------|
| `InstrD` | 32 | Instruction |
| `PCD` | 32 | PC |
| `PCPlus4D` | 32 | PC+4 |
| `valid_D` | 1 | Instruction is architecturally valid |
| `exc_valid_D` | 1 | IF-stage exception detected |
| `exc_cause_D` | 5 | Exception cause code |
| `exc_tval_D` | 32 | Exception value (faulting address) |
| `exc_pc_D` | 32 | PC of faulting instruction |

### ID/EX Register (`decode_cycle.v`)
| Signal | Width | Description |
|--------|-------|-------------|
| *(all existing control signals)* | — | RegWriteE, ALUSrcE, MemWriteE, etc. |
| `PCE` | 32 | PC |
| `valid_E` | 1 | Valid bit |
| `exc_valid_E` | 1 | Exception (merged IF+ID) |
| `exc_cause_E` | 5 | Exception cause |
| `exc_tval_E` | 32 | Exception value |
| `exc_pc_E` | 32 | PC of faulting instruction |
| `is_mret_E` | 1 | MRET instruction flag |

### EX/MEM Register (`execute_cycle.v`)
| Signal | Width | Description |
|--------|-------|-------------|
| *(all existing: RegWriteM, MemWriteM, ALU_ResultM, etc.)* | — | — |
| `PC_M` | 32 | PC |
| `valid_M` | 1 | Valid bit |
| `exc_valid_M` | 1 | Exception (propagated from ID/EX) |
| `exc_cause_M` | 5 | Exception cause |
| `exc_tval_M` | 32 | Exception value |
| `exc_pc_M` | 32 | PC of faulting instruction |
| `is_mret_M` | 1 | MRET flag |

### MEM/WB Register (`memory_cycle.v`)
| Signal | Width | Description |
|--------|-------|-------------|
| *(all existing: RegWriteW, ResultSrcW, ALU_ResultW, ReadDataW, etc.)* | — | — |
| `PC_W` | 32 | PC |
| `valid_W` | 1 | Valid bit |
| `exc_valid_W` | 1 | Exception (merged all stages, including MEM-local) |
| `exc_cause_W` | 5 | Exception cause |
| `exc_tval_W` | 32 | Exception value |
| `exc_pc_W` | 32 | PC of faulting instruction |
| `is_mret_W` | 1 | MRET flag |

---

## 4. Exception Merging — "First Wins" Policy

```verilog
// At ID: merge IF sideband with ID-local exception
wire exc_merged_valid = exc_valid_from_if | exc_valid_id_local;
wire [4:0] exc_merged_cause = exc_valid_from_if ? exc_cause_from_if : exc_cause_id_local;
wire [31:0] exc_merged_tval = exc_valid_from_if ? exc_tval_from_if  : exc_tval_id_local;
wire [31:0] exc_merged_pc   = PCD;  // Always this instruction's PC

// At MEM: merge propagated with MEM-local misalignment
wire exc_valid_mem_final = exc_valid_M | exc_valid_mem_local;
wire [4:0] exc_cause_M_final = exc_valid_M ? exc_cause_M : exc_cause_mem_local;
wire [31:0] exc_tval_M_final = exc_valid_M ? exc_tval_M  : exc_tval_mem_local;
```

---

## 5. CSR Specification

### Implemented CSRs

| CSR | Address | Description | Write Mask |
|-----|---------|-------------|------------|
| `mstatus` | 0x300 | Machine Status | `32'h00001888` ({MPP,MPIE,MIE}) |
| `mie` | 0x304 | Interrupt Enable | `32'h00000888` (MEIE,MTIE,MSIE) |
| `mtvec` | 0x305 | Trap Vector | `32'hFFFFFFFC` (BASE only, MODE=00) |
| `mscratch` | 0x340 | Scratch | Fully writable |
| `mepc` | 0x341 | Exception PC | Fully writable |
| `mcause` | 0x342 | Exception Cause | Fully writable |
| `mtval` | 0x343 | Trap Value | Fully writable |
| `mip` | 0x344 | Interrupt Pending | Read-only (combined from hardware) |
| `mcycle` | 0xB00 | Cycle Counter (lo) | Writable (resets counter) |
| `mcycleh` | 0xB80 | Cycle Counter (hi) | Writable |
| `minstret` | 0xB02 | Retired Instr (lo) | Writable |
| `minstreth` | 0xB82 | Retired Instr (hi) | Writable |

### Trap Entry CSR Updates (when `wb_trap_commit`)

| CSR Field | Value |
|-----------|-------|
| `mepc` | `exc_pc_W` — PC of faulting instruction |
| `mcause[31]` | `0` — exception (not interrupt) |
| `mcause[30:0]` | `exc_cause_W` |
| `mtval` | `exc_tval_W` if `trap_addr_valid`, else `0` |
| `mstatus.MPIE` | ← `mstatus.MIE` (save) |
| `mstatus.MIE` | ← `0` (disable interrupts) |
| `mstatus.MPP` | ← `2'b11` (M-mode) |

### MRET CSR Updates (when `wb_mret_commit`)

| CSR Field | Value |
|-----------|-------|
| `mstatus.MIE` | ← `mstatus.MPIE` (restore) |
| `mstatus.MPIE` | ← `1` |
| `mstatus.MPP` | ← `2'b11` (M-only, stays in machine mode) |
| PC | ← `mepc` |

### Exception Cause Codes

| Code | Name | Detected In |
|------|------|-------------|
| 0 | Instruction address misaligned | IF |
| 1 | Instruction access fault | IF (future) |
| 2 | Illegal instruction | ID |
| 3 | Breakpoint (EBREAK) | ID |
| 4 | Load address misaligned | MEM ✅ Implemented |
| 5 | Load access fault | MEM (future) |
| 6 | Store/AMO address misaligned | MEM ✅ Implemented |
| 7 | Store/AMO access fault | MEM (future) |
| 11 | Environment call from M-mode (ECALL) | ID |

### Interrupt Cause Codes (Phase 6)

| Code + bit31 | Name |
|--------------|------|
| 0x80000003 | Machine software interrupt |
| 0x80000007 | Machine timer interrupt |
| 0x8000000B | Machine external interrupt |

---

## 6. Flush & Stall Truth Table

### Normal Execution

| Signal | Value | Source |
|--------|-------|--------|
| `StallF` | `lwstall \| csr_stall` | hazard_unit |
| `StallD` | `lwstall \| csr_stall` | hazard_unit |
| `FlushD` | `PCSrcE` | hazard_unit |
| `FlushE` | `lwstall \| PCSrcE \| csr_stall` | hazard_unit |
| `FlushM` | `0` | — |
| `FlushW` | `0` | — |

### Exception In-Flight (Continuous Wake)

| Signal | Value | Source |
|--------|-------|--------|
| `FlushD` | `1` while `exc_inflight_E \| exc_inflight_M` | hazard_unit |
| `FlushE` | `1` while `exc_inflight_M` | hazard_unit |
| `FlushM` | `0` (until WB commit) | — |
| `StallF` | Not asserted for exception drain | — |

### Trap Commit Cycle (WB)

| Signal | Value |
|--------|-------|
| `FlushD/E/M/W` | `1` via `flush_pipeline_onehot = 4'b1111` |
| PC mux | `trap_target = {mtvec[31:2], 2'b00}` |
| CSR writes | mepc, mcause, mtval, mstatus via trap port |
| `RegWriteW` | `0` (gated by `exc_valid_W`) |

### MRET Commit Cycle (WB)

| Signal | Value |
|--------|-------|
| `FlushD/E/M/W` | `1` via `flush_pipeline_onehot = 4'b1111` |
| PC mux | `trap_target = {mepc[31:2], 2'b00}` |
| CSR writes | mstatus (MIE/MPIE/MPP) via mret port |
| `RegWriteW` | `0` (gated by `mret_commit`) |

---

## 7. WB Commit Controller Logic (Combinational)

```verilog
// Trap commit
wire wb_trap_commit = valid_W & exc_valid_W;

// MRET commit (exception beats MRET)
wire wb_mret_commit = valid_W & is_mret_W & ~exc_valid_W;

// Interrupt commit (Phase 6 — not yet implemented)
wire wb_irq_commit  = valid_W & ~exc_valid_W & ~is_mret_W & irq_pending;

// Combined redirect
wire wb_trap_redirect = wb_trap_commit | wb_mret_commit | wb_irq_commit;

// Target priority
wire [31:0] trap_target = wb_trap_commit ? {mtvec[31:2], 2'b00} :
                          wb_mret_commit ? {mepc[31:2],  2'b00} :
                          wb_irq_commit  ? {mtvec[31:2], 2'b00} : 32'h0;

// Full pipeline flush on commit
wire [3:0] flush_pipeline_onehot = wb_trap_redirect ? 4'b1111 : 4'b0000;
```

---

## 8. Performance Counter Behavior

- `mcycle`: increments every clock cycle, regardless of instruction validity
- `minstret`: increments when `instr_retired_i = valid_W & ~exc_valid_W`
- Both are 64-bit; accessible via 32-bit halves at `mcycle/mcycleh` and `minstret/minstreth`
- Writable via CSR instructions (to allow software counter resets)
- Write priority: same as other CSRs (MRET port > Normal write port, trap port > all)

---

## 9. Corner Cases and How They Are Handled

| Case | Mechanism |
|------|-----------|
| Younger store writes memory before trap | Continuous flush kills younger instructions — they never have `valid=1` in MEM |
| Faulting branch redirects PC | `PCSrcE = yesE & valid_E & ~exc_valid_E` suppresses it |
| Same instruction faults in IF and ID | First-wins merge — IF cause has priority |
| Exception in EX, store in MEM simultaneously | `exc_valid_M` from propagated exception gates MEM store write |
| MRET with exception pending | `exc_valid_W` takes priority: `mret_commit = valid_W & is_mret_W & ~exc_valid_W` |
| WB redirect vs branch same cycle | WB redirect wins (PC mux priority: `wb_trap_redirect` before `PCSrcE`) |
| WB redirect vs stall same cycle | WB redirect overrides stalls in hazard_unit |
| Interrupt during exception | `wb_irq_commit` gated by `~exc_valid_W` — exception always wins |
