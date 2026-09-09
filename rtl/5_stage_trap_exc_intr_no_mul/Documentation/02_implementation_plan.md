# Part 2: Implementation Plan — Phased Build Order

> **Core model**: Propagate-and-commit. Exceptions travel with instructions as sideband.
> Younger instructions are killed by continuous flush + valid gating.
> Side effects are blocked at every stage. Trap taken at WB. No FSM needed.

---

## Phase 0: Fix Synthesis-Blocking Bugs (Prerequisite) — Done

**Goal**: Get the existing RTL to elaborate/synthesize cleanly before adding anything.

### 0.1 Fix `Control_Unit_Top.v`
- **Line 101**: Remove trailing comma after last `.csr_valid(csr_valid),`
- **Line 149**: Replace `csr_valid_in = Main_Decoder.csr_valid` with proper input wire. `csr_valid` is already an output of `Main_Decoder` — just use it directly.
- **Line 161**: `is_mret` assignment needs to be inside an `always @(*)` block or use `assign`. Currently bare statement.
- Add proper `is_mret` detection: must check full instruction encoding `{funct7, rs2, rs1, funct3, rd, opcode}` = `0011000_00010_00000_000_00000_1110011`

### 0.2 Fix `Main_Decoder.v`
- **Line 153**: Change `/2/` to `//` (typo in comment)

### 0.3 Fix `csr_regfile.v` Instantiation in `top.v`
- Update the `csr_regfile` instantiation port names to match actual module ports
- Remove stale `csr_branch_o` / `csr_target_o` connections
- Connect `trap_valid_i`, `trap_cause_i`, `trap_pc_i` etc. to the WB commit controller outputs (no placeholders)

### 0.4 Fix `hazard_unit.v` Connections
- Connect `flush_pipeline_onehot[3:0]` from `wb_trap_mret_commit_controller` into `hazard_unit`

### 0.5 Fix `opcode_check.v`
- Remove duplicate `7'b1110011` line
- Note: Full illegal instruction detection (checking funct3/funct7) deferred to Phase 3

**Acceptance**: `iverilog` or Vivado elaboration passes with zero errors.

---

## Phase 1: Pipeline Infrastructure for Propagate-and-Commit — Done

**Goal**: Add valid bits, PC propagation, flush inputs, and exception sideband fields.

### 1.1 Add Valid Bits to Every Stage

Add a 1-bit `valid` signal propagated through each pipeline register:

```
valid_F → IF/ID reg → valid_D → ID/EX reg → valid_E → EX/MEM reg → valid_M → MEM/WB reg → valid_W
```

**Critical propagation rule — valid is killed by flush**:
```verilog
// In IF/ID register:
valid_D <= (FlushD) ? 1'b0 : (StallD) ? valid_D : 1'b1;

// In ID/EX register:
valid_E <= (FlushE) ? 1'b0 : valid_D;

// In EX/MEM register:
valid_M <= (FlushM) ? 1'b0 : valid_E;

// In MEM/WB register:
valid_W <= (FlushW) ? 1'b0 : valid_M;
```

- On reset: all `valid <= 0`
- `valid_W == 1` means an instruction is retiring this cycle

**Files changed**: `fetch_cycle.v`, `decode_cycle.v`, `execute_cycle.v`, `memory_cycle.v`, `top.v`

### 1.2 Propagate PC Through All Stages

Currently PC stops at EX (`PCE`). Add:

| Signal | Stage | Source |
|--------|-------|--------|
| `PCE` | EX | Already exists |
| `PC_M` | MEM | New: add to EX/MEM pipeline register in `execute_cycle.v` |
| `PC_W` | WB | New: add to MEM/WB pipeline register in `memory_cycle.v` |

**Files changed**: `execute_cycle.v`, `memory_cycle.v`, `top.v`

### 1.3 Add Flush to EX/MEM and MEM/WB Registers

**`execute_cycle.v`**: Add `FlushM` input. When asserted, clear all EX/MEM register fields and set `valid_M <= 0`.

**`memory_cycle.v`**: Add `FlushW` input. When asserted, clear all MEM/WB register fields and set `valid_W <= 0`.

Connect `FlushM` and `FlushW` from hazard_unit outputs (already declared but unconnected).

**Files changed**: `execute_cycle.v`, `memory_cycle.v`, `top.v`

### 1.4 Add Exception Sideband to Pipeline Registers

Each pipeline register carries exception metadata forward **with the instruction**:

```verilog
// Added to every pipeline register (IF/ID, ID/EX, EX/MEM, MEM/WB):
reg        exc_valid_r;     // Exception detected at or before this stage
reg [4:0]  exc_cause_r;     // mcause code (5 bits covers all M-mode exceptions)
reg [31:0] exc_tval_r;      // mtval value (bad address or instruction encoding)
reg [31:0] exc_pc_r;        // PC of the faulting instruction
```

**Propagation rule** (same instruction, so "first wins"):
```verilog
// If exc_valid already set from a prior stage for THIS instruction, keep it.
// A new local exception only fills in if exc_valid is not already set.
next_exc_valid = curr_exc_valid | new_exception_here;
next_exc_cause = curr_exc_valid ? curr_exc_cause : new_cause;
next_exc_tval  = curr_exc_valid ? curr_exc_tval  : new_tval;
next_exc_pc    = curr_exc_valid ? curr_exc_pc    : new_pc;
```

On flush, clear `exc_valid` (the instruction is killed, its exception is discarded).

### 1.5 Expand PC Mux to 4 Inputs

Replace the 2:1 `Mux2` PC mux in `fetch_cycle.v` with a priority mux:

| Priority | Source | When |
|----------|--------|------|
| Highest | `trap_target` | `wb_trap_commit` or `wb_mret_commit` |
| | `PCTargetE` | `PCSrcE` (branch/jump taken) |
| Lowest | `PCPlus4F` | Normal sequential |

Implementation (priority mux, not encoded select):
```verilog
assign PC_Next = wb_trap_redirect ? trap_target :
                 PCSrcE           ? PCTargetE   :
                                    PCPlus4F;
```

Add `trap_target[31:0]` and `wb_trap_redirect` inputs to `fetch_cycle.v`.

**Files changed**: `fetch_cycle.v`, `top.v`

**Acceptance**: Pipeline still executes bubble sort correctly. Valid bits toggle as expected. PC propagates to WB.

---

## Phase 2: CSR Regfile Cleanup

**Goal**: Clean up the CSR file to be pure passive storage with well-defined ports.

### 2.1 Finalize CSR Port Interface

The CSR regfile should have exactly 3 write sources with clear priority:

1. **Trap entry** (highest): Atomically writes `mepc`, `mcause`, `mtval`, updates `mstatus`
2. **MRET**: Restores `mstatus.MIE` from `mstatus.MPIE`
3. **CSR instruction** (lowest): Normal CSRRW/CSRRS/CSRRC from WB stage

### 2.2 Fix `mstatus` Write Mask

Current mask `32'h00001888` is correct for bits `{MPP[12:11], MPIE[7], MIE[3]}`.

### 2.3 Fix `mtvec` MODE Field

Current code masks `mtvec` writes to `[31:2]` only (MODE bits `[1:0]` frozen). For initial M-mode-only, this is acceptable (Direct mode = 0). Document this decision.

### 2.4 Add `MRET` Handling in CSR File

On `mret_valid` signal (from WB commit logic):
```verilog
mstatus_r[3]      <= mstatus_r[7];     // MIE = MPIE
mstatus_r[7]      <= 1'b1;             // MPIE = 1
mstatus_r[12:11]  <= 2'b11;            // MPP = M (since M-only)
```

### 2.5 Sideband Outputs

Already exist and are correct:
- `mtvec_out_o` → trap commit reads for PC redirect
- `mepc_out_o` → MRET reads for return address
- `mstatus_mie_out_o` → interrupt gating

**Acceptance**: CSR read/write instructions (CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI) work correctly. Verified by reading back written values.

---

## Phase 3: Exception Detection + Side-Effect Gating + Continuous Flush

**Goal**: Each stage detects exceptions locally. Side effects are gated. Continuous flush prevents younger instructions from committing while an exception is in-flight.

> This is the most critical phase. Three architectural invariants are established here:
> 1. **Continuous flush** — not one-shot
> 2. **PCSrcE gating** — faulting/flushed instructions don't redirect PC
> 3. **Same-cycle MEM gating** — MEM-local exception suppresses store in same cycle

### 3.1 IF-Stage Detector (`fetch_cycle.v`)

```verilog
// Instruction address misaligned — PC not 4-byte aligned
wire exc_valid_if    = (PCF[1:0] != 2'b00);
wire [4:0] exc_cause_if = 5'd0;   // cause 0: instruction address misaligned
wire [31:0] exc_tval_if = PCF;     // faulting address
wire [31:0] exc_pc_if   = PCF;
```

Note: In practice, PC is always aligned in this core (PC module increments by 4). This detector catches corrupted JAL/JALR targets.

### 3.2 ID-Stage Detector (`decode_cycle.v`)

Already partially exists. Clean up:

```verilog
wire is_ecall  = (InstrD == 32'h00000073);
wire is_ebreak = (InstrD == 32'h00100073);

wire illegal_full = illegal_instr_opcode  // from opcode_check
                  | illegal_funct3        // bad funct3 for given opcode
                  | illegal_csr_access;   // write to read-only CSR

wire exc_valid_id_local = illegal_full | is_ecall | is_ebreak;
wire [4:0] exc_cause_id = illegal_full ? 5'd2 :
                          is_ecall     ? 5'd11 :
                          is_ebreak    ? 5'd3  : 5'd0;
wire [31:0] exc_tval_id = illegal_full ? InstrD : 32'h0;
wire [31:0] exc_pc_id   = PCD;
```

### 3.3 EX-Stage Detector (`execute_cycle.v`)

For RV32I, no EX-stage exceptions. Reserve the interface:

```verilog
wire exc_valid_ex_local = 1'b0;  // Placeholder
```

### 3.4 MEM-Stage Detector (`memory_cycle.v`) — Pending

```verilog
// Only check alignment when the instruction is valid and not already faulting
wire is_load  = (lsunitM[4:3] == 2'b10);
wire is_store = (lsunitM[4:3] == 2'b11);

wire load_misaligned = is_load && (
    (lsunitM[2:0] == 3'b001 && ALU_ResultM[0] != 1'b0) ||   // LH/LHU
    (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00)    // LW
);

wire store_misaligned = is_store && (
    (lsunitM[2:0] == 3'b001 && ALU_ResultM[0] != 1'b0) ||
    (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00)
);

// Only detect if no earlier exception already tagged on this instruction
wire exc_valid_mem_local = ~exc_valid_M_propagated & (load_misaligned | store_misaligned);
wire [4:0] exc_cause_mem = load_misaligned  ? 5'd4 : 5'd6;
wire [31:0] exc_tval_mem = ALU_ResultM;  // Faulting address
```

### 3.5 Side-Effect Gating (MANDATORY) — Partially Implemented

> **Rule**: An instruction with `exc_valid` set, or with `valid == 0`, produces NO architectural side effects.

#### EX stage — Gate branch/jump decision:
```verilog
// In execute_cycle.v:
assign PCSrcE = yesE & valid_E & ~exc_valid_E;
```
This prevents a faulting or flushed instruction from redirecting the PC.

#### MEM stage — Gate memory write (propagated exception only, for now):
```verilog
// In memory_cycle.v (current implementation):
// NOTE: exc_valid_M_final does not yet include MEM-local misalignment detection.
Data_Memory.WE = MemWriteM & valid_M & ~exc_valid_M;
```
This already prevents exception-tagged instructions from performing stores. Once MEM-local misalignment exceptions are added, the gate should be upgraded to include same-cycle local detection.

#### WB stage — Gate register write and CSR write:
```verilog
// In top.v or writeback_cycle.v:
wire RegWriteW_gated    = RegWriteW_raw & valid_W & ~exc_valid_W;
wire csr_write_en_gated = csr_write_en_W_raw & valid_W & ~exc_valid_W;
```

Additionally, the current top-level gates out architectural writes on commit-qualified MRET:
```verilog
RegWriteW_gated      = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;
csr_write_en_W_gated = csr_write_en_W & valid_W & ~exc_valid_W & ~mret_commit;
```

### 3.6 Continuous Flush While Exception In-Flight (CRITICAL FIX)

> **Problem with one-shot flush**: After an exception is detected (e.g., in ID), a single-cycle flush kills the IF/ID register. But on the next cycle, fetch continues and new instructions enter the pipeline. These younger instructions can reach MEM and commit stores before the faulting instruction reaches WB.
>
> **Solution**: Continuously flush younger stages as long as an exception-tagged instruction is in the pipeline.

Current implementation in `utils/hazard_unit.v` uses `exc_inflight_E/M` plus a WB redirect pulse to continuously flush younger stages:
```verilog
exc_inflight_E = valid_E & exc_valid_E;
exc_inflight_M = valid_M & exc_valid_M;

FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | wb_redirect | flush_pipeline_onehot[0];
FlushE = lwstall | PCSrcE | csr_stall | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1];
FlushM = wb_redirect | flush_pipeline_onehot[2];
FlushW = wb_redirect | flush_pipeline_onehot[3];
```

**Effect**: The exception-tagged instruction creates a "wake" of bubbles behind it as it moves through EX→MEM→WB. No younger instruction ever has `valid=1` in any stage. The optional `StallF` stops fetch entirely to save power (functionally equivalent to flushing).

**Acceptance**: Exception detection signals toggle correctly. No false positives during normal execution. Stores/register writes suppressed on exception. Younger instructions after a faulting instruction never commit.

---

## Phase 4: Trap Commit at WB (No FSM)

**Goal**: When a faulting instruction retires at WB, write CSRs and redirect PC. No FSM needed.

### 4.1 Trap Commit Logic (Combinational in `utils/wb_trap_mret_commit_controller.v`) — Implemented

No separate `trap_controller.v` module with FSM states. The trap commit is purely combinational based on WB-stage outputs:

Implemented module behavior (purely combinational):
```verilog
trap_commit = valid_W & exc_valid_W;
mret_commit = valid_W & is_mret_W & ~exc_valid_W;

wb_trap_redirect = trap_commit | mret_commit;
trap_target      = trap_commit ? {mtvec[31:2],2'b00} : {mepc[31:2],2'b00};
flush_pipeline_onehot = wb_trap_redirect ? 4'b1111 : 4'b0000;
```

### 4.2 CSR Writes on Trap Entry

Connect to CSR regfile's trap port (already exists):

```verilog
// To csr_regfile trap inputs:
assign trap_valid_to_csr   = wb_trap_commit;
assign trap_cause_to_csr   = {26'b0, exc_cause_W};  // mcause[30:0]
assign trap_pc_to_csr      = exc_pc_W;               // mepc
assign trap_tval_to_csr    = exc_tval_W;              // mtval
assign trap_is_interrupt   = 1'b0;                    // Phase 6 adds interrupt support

// MRET to CSR:
assign mret_valid_to_csr   = wb_mret_commit;
```

### 4.3 Integration in `top.v`

1. Remove old `trap_controller.v` instantiation and all CLIC-related wires
2. Add `wb_trap_commit`, `wb_mret_commit`, `wb_trap_redirect`, `trap_target` wires
3. Connect `trap_valid_to_csr` → CSR file `trap_valid_i`
4. Connect `wb_trap_redirect` + `trap_target` → PC priority mux in `fetch_cycle.v`
5. Connect `wb_trap_commit` / `wb_mret_commit` → hazard unit for FlushD/E/M
6. Keep `flush_pipeline_onehot` as the “empty pipeline on commit” request (driven to `4'b1111` on trap/mret commit)

### 4.4 Side-Effect Suppression at WB

When `wb_trap_commit` fires:
- `RegWriteW_gated = 0` (already handled by gating from 3.5)
- `csr_write_en_gated = 0` (already handled)
- Only the trap port writes to CSRs (`mepc`, `mcause`, `mtval`, `mstatus`)

**Acceptance**: `ECALL` instruction causes trap entry: `mepc` = ECALL PC, `mcause` = 11, PC redirects to `mtvec`. Pipeline resumes at trap handler.

---

## Phase 5: MRET

**Goal**: Return from trap handler to interrupted code.

### 5.1 MRET Detection

Fix the detection in `Control_Unit_Top.v`:

```verilog
// Full MRET encoding: 0011000_00010_00000_000_00000_1110011
// Check: opcode=SYSTEM, funct3=000, funct7+rs2 = 0011000_00010
assign is_mret = (Op == 7'b1110011) && (funct3 == 3'b000) && (InstrD[31:20] == 12'h302);
```

### 5.2 Propagate `is_mret` Through Pipeline

Already partially exists. Ensure it propagates:
`is_mret_D` → `is_mret_E` → `is_mret_M` → `is_mret_W`

Add `is_mret` field to EX/MEM and MEM/WB pipeline registers.

### 5.3 MRET at WB

When `valid_W && is_mret_W && !exc_valid_W`:
- CSR file restores `mstatus`: `MIE = MPIE`, `MPIE = 1`, `MPP = 00` (per current implementation)
- PC redirects to `mepc`
- Pipeline flushed (FlushD, FlushE, FlushM via `wb_mret_commit`)

### 5.4 MRET Must Not Write Register File

MRET has `rd = x0` and no register side effects. Since SYSTEM opcode sets `RegWrite=1` in the decoder, gate it: if `is_mret`, force `RegWrite = 0` in the decoder.

Current implementation enforces “no architectural writes on MRET” by gating at retirement (WB) using `mret_commit`.

**Acceptance**: Write `mtvec` → execute `ECALL` → handler runs → `MRET` → returns to instruction after `ECALL`. `mstatus.MIE` restored correctly.

---

## Phase 6: External Interrupts

**Goal**: Accept synchronous-to-clk M-mode interrupts at instruction boundaries.

**Status**: Not implemented yet (core currently forces `trap_is_interrupt=0` and ties CSR interrupt inputs low in `top.v`).

### 6.1 Interrupt Pending Logic

```verilog
// In top.v:
wire msip_pending = mip_out[3]  & mie_out[3];   // Software interrupt
wire mtip_pending = mip_out[7]  & mie_out[7];   // Timer interrupt
wire meip_pending = mip_out[11] & mie_out[11];  // External interrupt

wire irq_pending = mstatus_mie_out & (msip_pending | mtip_pending | meip_pending);
```

### 6.2 Interrupt Acceptance

Interrupts are taken at instruction boundaries — when a valid instruction retires with no exception and no MRET:

```verilog
wire wb_irq_commit = valid_W & ~exc_valid_W & ~is_mret_W & irq_pending;

// Interrupt cause (priority: MEI > MTI > MSI)
wire [4:0] irq_cause = meip_pending ? 5'd11 :
                        mtip_pending ? 5'd7  : 5'd3;
```

When `wb_irq_commit`:
- Write `mepc = PC_W + 4` (return to NEXT instruction — the retiring one completed)
- Write `mcause = {1'b1, irq_cause}` (interrupt bit set)
- Write `mtval = 0`
- Update `mstatus` (MIE→MPIE, MIE=0)
- Redirect PC to `mtvec`
- Flush pipeline

### 6.3 Priority

Synchronous exceptions > MRET > asynchronous interrupts:
```verilog
wire wb_trap_redirect = wb_trap_commit | wb_mret_commit | wb_irq_commit;
wire [31:0] trap_target = wb_trap_commit ? mtvec_out :
                          wb_mret_commit ? mepc_out  :
                          wb_irq_commit  ? mtvec_out : 32'h0;
```

### 6.4 Interrupt Inputs

Connect external signals to `mip`:
- `timer_intr_i` → `mip[7]` (from CLINT/timer peripheral)
- `ext_intr_i` → `mip[11]` (from PLIC or external pin)
- `msft_intr_i` → `mip[3]` (from memory-mapped MSIP register)

**Acceptance**: Timer interrupt fires, handler runs, `MRET` returns, program continues. Interrupt during exception is deferred.

---

## Phase 7: Memory System for Bare-Metal C

**Goal**: Enable the core to run bare-metal C programs.

### 7.1 Unified Address Space

Replace separate instruction/data memory arrays with a unified memory model (for simulation):

```
0x0000_0000 — 0x0000_FFFF : RAM (64KB, instruction + data + stack)
0x1000_0000 — 0x1000_000F : UART (TX/RX registers)
0x0200_0000 — 0x0200_FFFF : CLINT (mtime, mtimecmp, msip)
```

### 7.2 Stack Pointer Initialization

Linker script sets `_stack_top`. Boot code (or reset vector) must:
```asm
la sp, _stack_top
la gp, _global_pointer
```

### 7.3 Trap Vector Setup

Boot code must set `mtvec` before any trap can occur:
```asm
la t0, _trap_handler
csrw mtvec, t0
```

### 7.4 `$readmemh` for Program Loading

Replace hardcoded `initial begin` blocks in `Instruction_Memory.v` with:
```verilog
initial begin
    $readmemh("program.hex", mem);
end
```

For unified memory, merge instruction and data memory into one module or use two ports into a single array.

### 7.5 Bare-Metal C Toolchain

```bash
# Compile
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T link.ld -o program.elf start.S main.c

# Extract hex
riscv32-unknown-elf-objcopy -O verilog program.elf program.hex
```

Minimal `start.S`:
```asm
.section .text.init
.global _start
_start:
    la sp, _stack_top
    la t0, _trap_handler
    csrw mtvec, t0
    call main
    j .              # infinite loop after main returns

_trap_handler:
    # save context, handle trap, restore context
    mret
```

**Acceptance**: "Hello World" bare-metal C program runs in simulation, writes to UART memory-mapped address.
