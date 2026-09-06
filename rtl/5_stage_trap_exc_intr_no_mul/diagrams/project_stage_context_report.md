# RISCFORGE 1TOPS — Project Stage Context Report

**Workspace**: [rtl/5_stage](../)
**Date**: May 1, 2026
**Scope**: Current implementation stage, module interactions, trap commit flow, CSR update flow, and MRET return behavior.

---

## 1. Executive Summary

The current RTL is a **5-stage in-order RV32I pipeline** with a **precise exception model** implemented using a **propagate-and-commit** strategy.

The key architectural shift is that trap handling is no longer treated as a standalone FSM in the active path. Instead:

- exceptions are detected in-stage,
- metadata is propagated with the instruction,
- younger instructions are continuously flushed,
- the oldest surviving faulting instruction commits at WB,
- the WB commit controller generates the redirect and CSR write bundle,
- the CSR regfile performs the architectural state update.

The active trap path is centered around these modules:

- [core/top.v](../core/top.v)
- [utils/wb_trap_mret_commit_controller.v](../wb_trap_mret_commit_controller.v)
- [csr_regfile.v](../csr_regfile.v)
- [utils/hazard_unit.v](../utils/hazard_unit.v)
- [pipeline/fetch_cycle.v](../pipeline/fetch_cycle.v)
- [pipeline/decode_cycle.v](../pipeline/decode_cycle.v)
- [pipeline/execute_cycle.v](../pipeline/execute_cycle.v)
- [pipeline/memory_cycle.v](../pipeline/memory_cycle.v)
- [pipeline/writeback_cycle.v](../pipeline/writeback_cycle.v)

---

## 2. Current Architectural Stage

### Implemented

| Area | Status | Notes |
|------|--------|-------|
| Core pipeline | Complete | IF → ID → EX → MEM → WB pipeline exists and is wired in `top.v` |
| Control decode | Complete | `Control_Unit_Top.v` decodes RV32I + SYSTEM instructions |
| Trap commit | Complete | `wb_trap_mret_commit_controller.v` commits trap/MRET at WB |
| CSR storage | Complete | `csr_regfile.v` stores `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`, counters |
| Precise exception propagation | Complete | Valid bits and exception sideband travel through pipeline registers |
| MEM-stage misalignment detection | Complete | `pipeline/memory_cycle.v` detects load/store misalignment |
| WB gating | Complete | Side effects are suppressed when `valid=0`, `exc_valid=1`, or `mret_commit=1` |
| Hazard flush plumbing | Complete | `hazard_unit.v` consumes WB redirect and exception in-flight state |

### Deferred

| Area | Status | Notes |
|------|--------|-------|
| CLIC interrupt frontend | Stubbed | `irq_valid_i` is tied low in `top.v` |
| Interrupt trap commit | Deferred | `wb_trap_mret_commit_controller.v` currently treats interrupts as inactive |
| Legacy trap FSM | Reference only | `trap_controller.v` remains in repository but is not the active architecture |

---

## 3. Module-by-Module Context

### 3.1 `core/top.v`

`top.v` is the integration point for the whole pipeline. It wires:

- stage-to-stage dataflow,
- CSR read/write paths,
- trap commit controller,
- hazard/flush controller,
- sideband exception and return signals.

Important connections observed in the current RTL:

- `fetch_cycle` receives both `PCSrcE` and `wb_trap_redirect`
- `execute_cycle` produces `PCSrcE` and propagates exception/MRET metadata
- `memory_cycle` finalizes MEM-local exceptions and carries WB-side metadata
- `wb_trap_mret_commit_controller` receives the WB instruction state and emits:
  - `wb_trap_redirect`
  - `trap_target`
  - `flush_pipeline_onehot`
  - trap CSR write bundle
  - MRET CSR write bundle
- `csr_regfile` accepts trap entry and MRET updates
- `hazard_unit` consumes branch flush, exception wake flush, and WB redirect flush

### 3.2 `pipeline/fetch_cycle.v`

Fetch currently implements:

- PC register update,
- instruction memory access,
- IF/ID pipeline register,
- trap redirect priority in the PC mux.

The PC selection order is:

1. `wb_trap_redirect ? trap_target`
2. `PCSrcE ? PCTargetE`
3. `PCPlus4F`

This makes WB trap return/entry the highest-priority redirection source.

### 3.3 `pipeline/decode_cycle.v`

Decode performs:

- instruction field extraction,
- main control generation,
- register file reads,
- immediate generation,
- ID/EX register storage,
- SYSTEM instruction detection,
- MRET detection,
- exception sideband propagation.

Decode is also where `illegal_instr`, `csr_valid`, and `is_mret` originate.

### 3.4 `pipeline/execute_cycle.v`

Execute performs:

- forwarding selection,
- ALU operations,
- branch/jump target generation,
- JAL/JALR target selection,
- CSR read-modify-write staging,
- EX/MEM register storage,
- propagation of exception metadata into the MEM stage.

The branch redirect signal is explicitly gated by valid and exception state:

- `PCSrcE = yesE & valid_E & ~exc_valid_E`

That prevents a faulting instruction from incorrectly redirecting control flow.

### 3.5 `pipeline/memory_cycle.v`

MEM performs:

- load/store formatting,
- byte strobes,
- memory access,
- MEM-local alignment checking,
- MEM/WB register storage.

This stage is responsible for catching load/store misalignment exceptions before WB commit.

### 3.6 `pipeline/writeback_cycle.v`

WB is a simple mux that selects the final writeback result:

- ALU result,
- data memory result,
- PC+4 link result,
- CSR old value.

Trap and MRET behavior are not implemented here directly. They are handled by the WB commit controller and CSR regfile.

### 3.7 `csr_regfile.v`

The CSR block is passive storage with three classes of activity:

1. combinational read path,
2. synchronous normal CSR writes,
3. synchronous trap-entry and MRET-side CSR writes.

Current CSR state includes:

- `mstatus`
- `mie`
- `mtvec`
- `mepc`
- `mcause`
- `mtval`
- `mscratch`
- `mcycle`
- `minstret`

### 3.8 `utils/wb_trap_mret_commit_controller.v`

This module decides when the WB instruction is allowed to retire as:

- a trap entry,
- an MRET return,
- or neither.

It generates:

- `wb_trap_redirect_o`
- `trap_target_o`
- `flush_pipeline_onehot_o`
- trap bundle outputs for CSR entry update
- MRET bundle outputs for CSR restore

### 3.9 `utils/hazard_unit.v`

The hazard unit handles:

- MEM→EX and WB→EX forwarding,
- load-use stalls,
- CSR RAW stall detection,
- branch flushes,
- continuous exception wake flush,
- WB redirect flushing.

It is the mechanism that keeps younger instructions from overtaking a trap-bound instruction.

### 3.10 `control/Control_Unit_Top.v`

The control unit is purely combinational. It identifies:

- instruction class,
- ALU control,
- load/store control,
- jump/branch control,
- CSR instruction class,
- MRET encoding.

This is where MRET is recognized as a distinct SYSTEM encoding rather than as a generic CSR operation.

---

## 4. Precise Trap Commit Behavior

### 4.1 Conceptual cycle behavior

The trap model is precise because the faulting instruction is allowed to advance to WB before any architectural state update occurs.

Behavior by stage:

- **IF**: can fetch speculatively
- **ID**: may detect illegal instruction or ECALL/EBREAK
- **EX**: carries metadata and suppresses branch redirection if faulted
- **MEM**: detects load/store misalignment and finalizes memory-side exception metadata
- **WB**: performs the commit and CSR write bundle generation

### 4.2 What gets written on trap entry

When `trap_commit` is asserted at WB:

- `mepc` gets the faulting instruction PC
- `mcause[31]` is cleared for exception
- `mcause[30:0]` receives the cause code
- `mtval` receives the faulting address or zero depending on validity
- `mstatus.MIE` is cleared
- `mstatus.MPIE` captures the old `MIE`
- `mstatus.MPP` is forced to machine mode

### 4.3 What gets written on MRET

When `mret_commit` is asserted at WB:

- `mstatus.MIE` is restored from `MPIE`
- `mstatus.MPIE` is set to 1
- `mstatus.MPP` remains machine mode
- the PC redirects to `mepc`

---

## 5. Cycle-Accurate Behavioral Summary

### 5.1 Trap entry timeline

1. Fault detected in an earlier stage.
2. Exception sideband travels with the instruction.
3. Younger instructions are flushed continuously.
4. Faulting instruction reaches WB with `valid_W=1` and `exc_valid_W=1`.
5. WB controller asserts trap commit.
6. CSR regfile performs atomic trap-entry writes.
7. Fetch redirects to `mtvec`.
8. Pipeline is drained by `flush_pipeline_onehot`.

### 5.2 MRET timeline

1. Decode recognizes MRET.
2. `is_mret` propagates through the pipeline.
3. WB sees a valid, non-faulting MRET instruction.
4. WB controller asserts MRET commit.
5. CSR regfile restores `mstatus`.
6. Fetch redirects to `mepc`.
7. Pipeline is flushed and then resumes execution at the return address.

### 5.3 Oldest-wins behavior

Because the pipeline is in-order and because younger instructions are flushed while an older fault is in flight, only the oldest surviving exception can commit.

This is the central correctness property of the design.

---

## 6. Signal Flow Summary

### Trap-related signals

- `exc_valid_D`, `exc_cause_D`, `exc_tval_D`, `exc_pc_D`
- `exc_valid_E`, `exc_cause_E`, `exc_tval_E`, `exc_pc_E`
- `exc_valid_M`, `exc_cause_M`, `exc_tval_M`, `exc_pc_M`
- `exc_valid_W`, `exc_cause_W`, `exc_tval_W`, `exc_pc_W`

### Commit-related signals

- `trap_commit_valid`
- `trap_commit_cause`
- `trap_commit_pc`
- `trap_commit_addr`
- `trap_commit_addr_valid`
- `trap_commit_is_interrupt`
- `mret_commit`

### CSR path signals

- `csr_write_en_mret`
- `csr_waddr_mret`
- `csr_wdata_mret`
- normal CSR write signals from WB
- trap-entry CSR port signals into `csr_regfile`

---

## 7. Diagram Index

- [Architecture overview](architecture_overview.mmd)
- [Trap commit timeline](trap_commit_timeline.mmd)
- [MRET commit timeline](mret_commit_timeline.mmd)
- [Precise exception state machine](precise_exception_state_machine.mmd)
- [CSR and flush signal map](csr_and_flush_signal_map.mmd)

---

## 8. Important Caveats

- The active architecture is **not** a multi-state registered trap FSM.
- Any FSM in this folder is only a conceptual explanation diagram.
- Interrupt handling is still a future integration point.
- The trap commit path is currently exception/MRET centric.

---

## 9. Recommended Reading Order

1. [core/top.v](../core/top.v)
2. [utils/wb_trap_mret_commit_controller.v](../wb_trap_mret_commit_controller.v)
3. [csr_regfile.v](../csr_regfile.v)
4. [pipeline/memory_cycle.v](../pipeline/memory_cycle.v)
5. [utils/hazard_unit.v](../utils/hazard_unit.v)
6. [control/Control_Unit_Top.v](../control/Control_Unit_Top.v)
7. This report’s diagrams

---

## 10. Bottom Line

The project is currently at a stage where the core pipeline is functional, precise traps are committed at WB, CSR state is updated atomically, and MRET returns are restored through the same privileged path.

The most important missing piece is external interrupt/CLIC integration. Everything else required for precise trap entry and MRET return is already present in the current RTL.
