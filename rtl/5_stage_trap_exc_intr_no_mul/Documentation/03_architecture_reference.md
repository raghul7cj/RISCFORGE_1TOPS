# Part 3: Architecture Decisions & Signal Reference

> **Architecture**: Propagate-and-commit precise exception model.
> Exceptions travel with instructions. Younger instructions are flushed continuously.
> Side effects are blocked via valid + exception gating. Trap taken at WB. No FSM.

---

## Key Architectural Decisions

### Decision 1: Exception Sideband Propagation (Not Combinational Arbiter)

**Choice**: Exceptions propagate through pipeline registers as sideband fields, arriving at WB naturally.

**Rejected alternative**: Combinational arbiter that samples all stages simultaneously and uses an `oldest-wins` priority mux.

**Rationale**: In this simple in-order core, instructions flow in strict program order. An exception detected in ID for instruction N will reach WB *before* any exception for instruction N+1. There is no reordering. Therefore:
- The pipeline registers already enforce age ordering
- No separate arbiter is needed
- The trap is taken when the faulting instruction's sideband reaches WB
- Younger instructions behind it in the pipeline are killed by continuous flush + valid gating

### Decision 2: No FSM — Combinational Trap Commit at WB

**Choice**: Trap entry is a single-cycle combinational event at WB retirement. No FSM states.

**Rejected alternative**: `IDLE → TRAP_PENDING → TAKE_TRAP` FSM with drain/wait semantics.

**Rationale**: Since exceptions travel through the pipeline as sideband:
- When the sideband reaches WB, all older instructions have already retired
- All younger instructions are behind in the pipeline and have been continuously flushed
- A single-cycle CSR write + PC redirect + final flush is sufficient
- No state machine needed — the pipeline IS the state machine

**Implementation**:
```verilog
wire wb_trap_commit = valid_W & exc_valid_W;       // Combinational, not registered
wire wb_mret_commit = valid_W & is_mret_W & ~exc_valid_W;
```

If future complexity requires it (e.g., multi-cycle memory access), an FSM can be added back.

### Decision 3: Continuous Flush (Not One-Shot)

**Choice**: While an exception-tagged instruction is anywhere in the pipeline, younger stages are continuously flushed.

**Rejected alternative**: One-shot flush at detection time only.

**Rationale**: A one-shot flush kills the immediate younger instruction but allows new fetches to enter the pipeline. These new instructions are younger than the faulting instruction and could reach MEM and write memory before the trap fires at WB. Continuous flush prevents this by creating a "wake" of bubbles behind the exception-tagged instruction.

**Implementation (current RTL in `utils/hazard_unit.v`)**:
```verilog
exc_inflight_E = valid_E & exc_valid_E;
exc_inflight_M = valid_M & exc_valid_M;

// wb_redirect is asserted on WB trap commit OR WB mret commit
FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | wb_redirect | flush_pipeline_onehot[0];
FlushE = lwstall | PCSrcE | csr_stall | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1];
FlushM = wb_redirect | flush_pipeline_onehot[2];
FlushW = wb_redirect | flush_pipeline_onehot[3];
```

Notes:
- This design flushes **younger** stages behind an exception-tagged instruction (the “wake”), and fully empties the pipeline on WB redirect.
- Fetch is not currently stalled during exception drain; it can continue to fetch, but decode/execute are flushed so younger instructions do not become architecturally valid.

### Decision 4: Triple Gating (Valid + Exception + Local)

**Choice**: Side effects are suppressed by three independent mechanisms:

| Mechanism | What it does | Where |
|-----------|-------------|-------|
| `valid == 0` | Instruction was flushed — kills all effects | All stages |
| `exc_valid == 1` | Instruction has exception — kills normal effects | EX, MEM, WB |
| Local detection | Same-cycle exception gates same-cycle write | MEM only |

**Implementation at each stage**:
```verilog
// EX: Don't let faulting instruction redirect PC
PCSrcE = yesE & valid_E & ~exc_valid_E;

// MEM: Don't let exception-tagged instruction write memory
// NOTE: MEM-local misalignment/access-fault tagging is not implemented yet.
MemWriteM_gated = MemWriteM & valid_M & ~exc_valid_M;

// WB: Don't let faulting instruction write registers or CSRs
RegWriteW_gated    = RegWriteW_raw & valid_W & ~exc_valid_W;
csr_write_en_gated = csr_write_en_W_raw & valid_W & ~exc_valid_W;
```

### Decision 5: MRET Treated as Control Redirect

**Choice**: MRET is not an exception. It flows through the pipeline normally and at WB triggers a PC redirect + flush + CSR restore, similar to a taken branch but with CSR side effects.

**Implementation**:
```verilog
if (wb_mret_commit) begin
    pc <= mepc;
    mstatus.MIE <= mstatus.MPIE;
    FlushD = FlushE = FlushM = 1;
end
```

### Decision 6: M-Mode Only, Direct Mode mtvec

**Choice**: Only M-mode. `mtvec.MODE = 0` (Direct). All traps go to `mtvec.BASE`.

**Rationale**: Simplest initial implementation. Vectored mode can be added later by checking `mtvec[1:0]` and computing `BASE + 4*cause` for interrupts.

### Decision 7: mepc Semantics

**Choice**:
- **Exceptions**: `mepc = PC of faulting instruction` (handler can retry or skip)
- **Interrupts**: `mepc = PC_W + 4` (next instruction — the retiring one already completed)

---

## Complete Signal Map

### Pipeline Register Fields

#### IF/ID Register (`fetch_cycle.v`)
```
InstrD[31:0]       — Instruction
PCD[31:0]          — PC
PCPlus4D[31:0]     — PC+4
valid_D            — Valid bit (NEW)
exc_valid_D        — Exception from IF (NEW)
exc_cause_D[4:0]   — Exception cause from IF (NEW)
exc_tval_D[31:0]   — Exception value from IF (NEW)
exc_pc_D[31:0]     — PC of faulting instr (= PCD for IF) (NEW)
```

#### ID/EX Register (`decode_cycle.v`)
```
[existing control signals: RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE, etc.]
PCE[31:0]          — PC (exists)
valid_E            — Valid bit (NEW)
exc_valid_E        — Exception (merged IF+ID) (NEW)
exc_cause_E[4:0]   — Exception cause (NEW)
exc_tval_E[31:0]   — Exception value (NEW)
exc_pc_E[31:0]     — PC of faulting instruction (NEW)
is_mret_E          — MRET flag (exists)
```

#### EX/MEM Register (`execute_cycle.v`)
```
[existing: RegWriteM, MemWriteM, ResultSrcM, RD_M, ALU_ResultM, etc.]
PC_M[31:0]         — PC (NEW)
valid_M            — Valid bit (NEW)
exc_valid_M        — Exception (merged IF+ID+EX, propagated) (NEW)
exc_cause_M[4:0]   — Exception cause (NEW)
exc_tval_M[31:0]   — Exception value (NEW)
exc_pc_M[31:0]     — PC of faulting instruction (NEW)
is_mret_M          — MRET flag (NEW — propagate from E)
```

#### MEM/WB Register (`memory_cycle.v`)
```
[existing: RegWriteW, ResultSrcW, RD_W, ALU_ResultW, ReadDataW, etc.]
PC_W[31:0]         — PC (NEW)
valid_W            — Valid bit (NEW)
exc_valid_W        — Exception (merged all stages) (NEW)
exc_cause_W[4:0]   — Exception cause (NEW)
exc_tval_W[31:0]   — Exception value (NEW)
exc_pc_W[31:0]     — PC of faulting instruction (NEW)
is_mret_W          — MRET flag (NEW)
```

### Exception Merging Logic at Each Stage

All merges are for the **same instruction** as it flows through the pipeline. "First wins" — an exception from an earlier stage has priority because it represents a more fundamental fault (e.g., fetch fault precedes illegal instruction).

```verilog
// ---- At ID stage (merge IF exception with ID-local) ----
// Both are for the SAME instruction (it was in IF last cycle, now in ID)
wire exc_merged_valid = exc_valid_from_if | exc_valid_id_local;
wire [4:0] exc_merged_cause = exc_valid_from_if ? exc_cause_from_if : exc_cause_id_local;
wire [31:0] exc_merged_tval = exc_valid_from_if ? exc_tval_from_if  : exc_tval_id_local;
wire [31:0] exc_merged_pc   = PCD;  // Always this instruction's PC

// ---- At EX stage ----
// RV32I base: no EX exceptions. Pass through unchanged.

// ---- At MEM stage (merge propagated with MEM-local) ----
// If exc_valid already set (e.g., illegal from ID), the instruction shouldn't
// have done a memory access. Gating MemWriteM prevents writes; for loads,
// the read is harmless. Don't overwrite the earlier cause.
wire exc_valid_M_final = exc_valid_M_propagated | exc_valid_mem_local;
wire [4:0] exc_cause_M_final = exc_valid_M_propagated ? exc_cause_M_propagated
                                                       : exc_cause_mem_local;
wire [31:0] exc_tval_M_final = exc_valid_M_propagated ? exc_tval_M_propagated
                                                       : exc_tval_mem_local;
```

### Trap Commit Interface in `top.v`

Current implementation instantiates `utils/wb_trap_mret_commit_controller.v` in `core/top.v`.

Key behaviors (combinational in the WB commit controller):
```verilog
trap_commit = valid_W & exc_valid_W;
mret_commit = valid_W & is_mret_W & ~exc_valid_W;

wb_trap_redirect = trap_commit | mret_commit;
trap_target      = trap_commit ? {mtvec[31:2],2'b00} : {mepc[31:2],2'b00};

flush_pipeline_onehot = wb_trap_redirect ? 4'b1111 : 4'b0000;
```

WB-side-effect gating (current `core/top.v`):
```verilog
RegWriteW_gated      = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;
csr_write_en_W_gated = csr_write_en_W & valid_W & ~exc_valid_W & ~mret_commit;
```

---

## CSR Behavior Specification

### Trap Entry (when `wb_trap_commit` is true)

| CSR | Action |
|-----|--------|
| `mepc` | ← `exc_pc_W` (PC of faulting instruction) |
| `mcause` | ← `{1'b0, 26'b0, exc_cause_W}` (exception, interrupt bit = 0) |
| `mtval` | ← `exc_tval_W` (faulting address or instruction encoding) |
| `mstatus.MPIE` | ← `mstatus.MIE` (save current interrupt enable) |
| `mstatus.MIE` | ← `0` (disable interrupts on trap entry) |
| `mstatus.MPP` | ← `2'b11` (M-mode, since M-only core) |

### MRET (when `wb_mret_commit` is true)

| CSR | Action |
|-----|--------|
| `mstatus.MIE` | ← `mstatus.MPIE` (restore interrupt enable) |
| `mstatus.MPIE` | ← `1` |
| `mstatus.MPP` | ← `2'b00` (per current implementation) |
| PC | ← `mepc` |

### Interrupt Entry (Phase 6, when `wb_irq_commit` is true)

| CSR | Action |
|-----|--------|
| `mepc` | ← `PC_W + 4` (next instruction — current one completed) |
| `mcause` | ← `{1'b1, 26'b0, irq_cause}` (interrupt bit = 1) |
| `mtval` | ← `0` |
| `mstatus.MPIE` | ← `mstatus.MIE` |
| `mstatus.MIE` | ← `0` |
| `mstatus.MPP` | ← `2'b11` |

### mcause Encoding (M-mode exceptions)

| Code | Name | Detected In |
|------|------|-------------|
| 0 | Instruction address misaligned | IF |
| 1 | Instruction access fault | IF (future) |
| 2 | Illegal instruction | ID |
| 3 | Breakpoint (EBREAK) | ID |
| 4 | Load address misaligned | MEM |
| 5 | Load access fault | MEM (future) |
| 6 | Store/AMO address misaligned | MEM |
| 7 | Store/AMO access fault | MEM (future) |
| 11 | Environment call from M-mode | ID |

### mcause Encoding (M-mode interrupts — Phase 6)

| Code | Name | Source |
|------|------|--------|
| 3 + bit31 | Machine software interrupt | MSIP in CLINT |
| 7 + bit31 | Machine timer interrupt | mtime >= mtimecmp |
| 11 + bit31 | Machine external interrupt | PLIC/external pin |

---

## Flush & Stall — Complete Truth Table

### Normal Operation (No Exception)

| Signal | Value | Driven By |
|--------|-------|-----------|
| StallF | lwstall \| csr_stall (forced low on WB redirect) | hazard_unit |
| StallD | lwstall \| csr_stall (forced low on WB redirect) | hazard_unit |
| FlushD | PCSrcE | hazard_unit |
| FlushE | lwstall \| PCSrcE \| csr_stall | hazard_unit |
| FlushM | 0 | — |
| FlushW | 0 | — |

### Exception In-Flight (Continuous — While Tagged Instruction Propagates)

| Signal | Value | Driven By |
|--------|-------|-----------|
| StallF | Not asserted for exception drain (fetch may continue) | hazard_unit |
| FlushD | 1 while `exc_inflight_E` or `exc_inflight_M` | hazard_unit |
| FlushE | 1 while `exc_inflight_M` | hazard_unit |
| FlushM | 0 (until WB redirect) | — |
| PC mux | Continues; younger instructions are flushed | — |

### Trap Commit Cycle (WB)

| Signal | Value | Driven By |
|--------|-------|-----------|
| FlushD | 1 | wb_redirect / flush_pipeline_onehot |
| FlushE | 1 | wb_redirect / flush_pipeline_onehot |
| FlushM | 1 | wb_redirect / flush_pipeline_onehot |
| PC mux | Select mtvec | wb_trap_redirect |
| CSR writes | mepc, mcause, mtval, mstatus | trap port |
| RegWriteW | 0 (gated) | exc_valid_W |

### MRET Commit Cycle (WB)

| Signal | Value | Driven By |
|--------|-------|-----------|
| FlushD | 1 | wb_redirect / flush_pipeline_onehot |
| FlushE | 1 | wb_redirect / flush_pipeline_onehot |
| FlushM | 1 | wb_redirect / flush_pipeline_onehot |
| PC mux | Select mepc | wb_trap_redirect |
| CSR writes | mstatus (MIE/MPIE/MPP) | mret port |

---

## Corner Cases Covered

| Case | How It's Handled |
|------|------------------|
| Younger store writes memory before trap | **Continuous flush** kills younger instructions — they never have `valid=1` in MEM |
| Faulting branch redirects PC | **PCSrcE gating**: `PCSrcE = yesE & valid_E & ~exc_valid_E` |
| MEM-stage misaligned store writes memory same cycle | **Pending** until MEM-local misalignment exception detection is implemented |
| Same instruction faults in IF and ID | **First-wins merge**: IF cause has priority (checked first) |
| MEM exception on instruction N, ID exception on N+1 | N reaches WB first (in-order). N+1 was flushed by continuous flush. Only N's trap fires |
| Multiple instructions fault in different stages | In-order guarantees oldest reaches WB first. Continuous flush kills all younger |
| Faulting instruction itself is flushed | Never happens — only **younger** stages are flushed. The tagged instruction is always ahead |
| MRET with exception | `exc_valid_W` takes priority: `wb_mret_commit = valid_W & is_mret_W & ~exc_valid_W` |
| Interrupt during exception | Phase 6: `wb_irq_commit` requires `~exc_valid_W`, so exception wins |

---

## One-Line Summary

> **Detect → Tag instruction → Continuous-flush younger → Propagate sideband → Gate all side effects → Trap at WB → Redirect PC**
