# RISCFORGE 1TOPS — Current Stage Context

**Project**: 5-stage RV32I pipeline with precise trap commit and commit-qualified MRET

This folder captures the current architectural stage of the RTL and the important control-flow diagrams for trap entry, CSR update, and MRET return behavior.

## Current stage summary

The design is now centered on a **propagate-and-commit** exception model:

- Instructions flow through IF → ID → EX → MEM → WB
- Exception metadata rides with the instruction as pipeline sideband
- Younger instructions are continuously flushed while a faulting instruction is in flight
- Trap entry is committed at WB by `wb_trap_mret_commit_controller.v`
- CSR trap state is written in `csr_regfile.v`
- MRET is committed at WB and restores `mstatus` through CSR Port C

## Important source modules

- [core/top.v](../core/top.v)
- [pipeline/fetch_cycle.v](../pipeline/fetch_cycle.v)
- [pipeline/decode_cycle.v](../pipeline/decode_cycle.v)
- [pipeline/execute_cycle.v](../pipeline/execute_cycle.v)
- [pipeline/memory_cycle.v](../pipeline/memory_cycle.v)
- [pipeline/writeback_cycle.v](../pipeline/writeback_cycle.v)
- [csr_regfile.v](../csr_regfile.v)
- [wb_trap_mret_commit_controller.v](../wb_trap_mret_commit_controller.v)
- [utils/hazard_unit.v](../utils/hazard_unit.v)
- [control/Control_Unit_Top.v](../control/Control_Unit_Top.v)

## Design status at this stage

### Implemented and active

- Valid-bit propagation across the pipeline
- Exception sideband propagation through ID/EX, EX/MEM, and MEM/WB
- MEM-stage alignment exception detection
- Continuous younger-stage flush while an exception is in flight
- WB retirement gating for register writes and CSR writes
- Trap-entry CSR update bundle: `mepc`, `mcause`, `mtval`, `mstatus`
- Commit-qualified `mret` update of `mstatus`
- WB redirect priority into the IF-stage PC mux

### Deferred or stubbed

- External interrupt / CLIC handshake is stubbed in `core/top.v`
- `wb_trap_mret_commit_controller.v` currently receives `irq_valid_i = 1'b0`
- Legacy `trap_controller.v` exists but is not the active trap path

## Key architectural rules reflected by the RTL

1. Precise state changes occur only at WB commit.
2. Faulting instructions suppress their own normal side effects.
3. Younger pipeline stages are flushed while a trap is awaiting retirement.
4. MRET is not an exception; it is a WB-committed control transfer.
5. CSR trap-entry writes are atomic from the perspective of architectural state.

## Diagram index

- [Project stage context report](project_stage_context_report.md)
- [Architecture overview](architecture_overview.mmd)
- [Trap commit timeline](trap_commit_timeline.mmd)
- [MRET commit timeline](mret_commit_timeline.mmd)
- [Precise exception state machine](precise_exception_state_machine.mmd)
- [CSR and flush signal map](csr_and_flush_signal_map.mmd)

## Notes for review

- The RTL is currently consistent with an in-order precise exception model.
- The trap controller behavior is implemented as combinational retirement logic rather than a multi-state FSM.
- Any “FSM” shown in this folder should be read as a **conceptual architectural state diagram**, not as a literal registered FSM in the current code.

