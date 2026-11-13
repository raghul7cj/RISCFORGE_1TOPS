# F3 asynchronous interrupt verification contract

Status: requested policy retained. Timer and selected fast-source service is tested;
MEIP/MSIP routing and requested MEIP > MTIP > MSIP selection are failing requirements,
not exclusions or checker self-tests. No RTL change is authorized by this document.
Diagram: [current architecture](docs/diagrams/core_trap_architecture.md).

## Requested intent versus active implementation

The engineer explicitly selected retaining MEIP > MTIP > MSIP as an F3 requirement,
even when it fails against the current RTL. Source inspection of top/irq_arbiter
shows only {fast_irq_i[11:0],timer_irq_i} feeding the gateway/arbiter. ext_irq_i and
sw_irq_i feed mip, but not IRQ arbitration. The custom arbiter's class-2 table puts
timer first; class-1/0 round-robin behavior and mintprio exist but are not redefined
as the requested standard-source policy. Do not infer a universal ISA requirement
from this test's user-selected policy or claim custom arbitration signoff instead.

| Case | Asynchronous input | Required first interrupt cause |
|---|---|---|
| timer | One clock-wide timer pulse while MIE=0 | 0x80000007 |
| timer-late | Timer pulse later in an enabled dependent-ALU stream | 0x80000007 |
| fast0 | Rising-edge fast_irq_i[0] pulse | 0x80000010 |
| fast6 | Event fast_irq_i[6] pulse | 0x80000016 |
| external | ext_irq_i level, held through requested service | 0x8000000b |
| software | sw_irq_i level, held through requested service | 0x80000003 |
| priority | Timer pulse plus simultaneous external/software levels | 0x8000000b (MEIP first) |

The real top ports are timer_irq_i, ext_irq_i, sw_irq_i and fast_irq_i; the bench
maps user-level source names to these physical pins. Fast causes 16 and 22 exercise
an edge source and an event source in different custom classes individually. No
claim is made for all fast bits, class-to-class priority, round-robin fairness or
mintprio threshold races. Upper fast inputs [15:12] do not feed the active gateway.

## Stimulus, pending retention and prompt service

Software configures mtvec and the selected mie bits while global MIE remains zero.
A ready instruction retires, then the fixture drives pins 2 ns after a falling edge.
Timer and fast pins remain high for 10 ns (one sampled source cycle), then deassert;
the gateway must retain their pending bits while masked. External/software remain
asserted as level sources. After the capture allowance, actual mip is checked
against the independently selected required mask throughout the software mask window.
No trap or EX IRQ acceptance is allowed during that window. At least three samples
and a nonvacuous masking witness are required in the early-source cases.

Software subsequently commits MIE=1. The common IRQ monitor requires a pending
enabled source to commit within six sampled cycles of the ready expectation. This
is a directed pipeline service bound, not a same-edge commit requirement or a
universal ISA latency. Timer/fast early runs show enable at 265 ns and IRQ commit
at 295 ns (three core clocks later). The late case independently exercises arrival
after enabling. Off-edge stimulus is logical asynchronous-input simulation; it does
not establish metastability immunity, CDC correctness or physical timing closure.

## Independent mepc frontier and effect accounting

The model initially predicts the application from its own instruction image, with
only x0 initially known. It saves pre-instruction GPR/CSR snapshots and expected
physical-effect counts. Every observed ordinary retirement PC is checked against
the expected sequence BEFORE the reference retirement cursor advances. The expected
interrupt PC is the NEXT expected retirement PC. DUT PCE, accepted-IRQ PC and saved
mepc are never used to construct this oracle.

At the observed trap boundary, the fixture inserts architecturally expected handler
execution at that independent frontier. Before replacing any unconsumed prediction,
the common scoreboard requires already-observed RF/store counts to match the model
snapshot. It never drops an observed ghost effect or resets consumption counters.
The snapshot is copied from predicted state, not physical DUT GPR values. The model
enters the expected interrupt (cause high bit set, mepc=frontier, mtval=0, MIE->MPIE,
MIE cleared), predicts the handler and recomputes the remaining application trace.

This fixture supports one interrupt before application stores: the explicit guard
rejects a reference prefix containing stores rather than inventing memory rollback.
The handler records mepc/mcause/status and executes MRET WITHOUT adding four to mepc.
Resumption must replay the interrupted instruction exactly once. The application
performs 24 dependent increments and writes 24/25 signatures; a skipped or repeated
instruction changes those results or violates the independent effect stream.
Handler-clobbered registers are reserved from application work. The late case must
save a different independently calculated PC; both saved CSR state and handler
readback/store evidence are checked. Completion requires one trap, one MRET, drained
streams, status-transition/masking witnesses and the checked terminal instruction.

## Components and source ownership

| Component | Location and role |
|---|---|
| Architectural entry and mie CSR semantics | Verification/lib/core/rv32/rv32_machine_reference_pkg.sv |
| Validated frontier and guarded future-trace revision | Verification/lib/core/core_scoreboard_pkg.sv |
| Shared synchronous/asynchronous trap/MRET SVA | Verification/lib/core/sva/core_sync_trap_sva.sv; generalized by expected_interrupt, not copied |
| Mask, pending and prompt-service SVA | Verification/lib/core/sva/core_irq_mask_sva.sv |
| Physical observations | Common core_pipeline_if and DUT-specific core_trap_observe.sv |
| Hardware coverage | Verification/lib/core/trap_functional_cov.sv |
| Program/handler construction | Local programs/core_trap_programs.svh |
| Snapshot/driver orchestration | Local f3_scenario.svh |
| Case setup/runner | core-trap-f3-*.json and run_f3.ps1 |

SV headers are runner inputs, not duplicate compilation sources. The existing F1/F2
handler builder is reused; synchronous faults still add four, while IRQ handlers
preserve mepc. Source policy and expected cause are chosen before stimulus, not from
the DUT winner. MIP visibility checks and cause selection checks remain separate.

## Coverage and limits

Cause coverpoints now include timer/external/software and individual fast causes
16..27, plus prior synchronous bins. Mode bins and cause-by-mode crosses remain.
A second hardware-event-qualified covergroup samples before/after MIE and MPIE for
trap entry and MRET; software's initial MIE enable is not counted as a return.
MIE 1->0 on IRQ entry and 0->1 on MRET have independent hardware counters required
for F3 completion. All status observations come from real CSR transitions.

Unserved external/software bins must remain unhit; vectored mode remains unhit on
the direct-only current CSR. No bins are waived or manufactured. Reports are per
run; the F2 signed-off directed evidence remains historical evidence for that scope,
not a claim of closure of the expanded F3 coverage denominator.

Application interruption and replay are exercised. Nested IRQ-on-ISR preemption,
multiple sequential sources in one handler session, full custom RR/threshold policy,
interrupts during memory waits or RV32M operations, SoC event routing and an ISR-level
system loop are not covered. Requested simultaneous-source policy fails before
broader preemption can be signed off. F1-EXC-01 and F02-WB-01 remain open.

## Replay

`pwsh -NoProfile -File Verification/tb_core_trap_lean/run_f3.ps1 -Case all -NoThrow`

Default mode is lightweight iteration. Add -Final to selected accepted/debug cases
for detailed IMC and waveforms. The all runner retains all case results and throws
at the end unless -NoThrow is selected; that switch never upgrades failed verdicts.
Case negative-mepc changes only the PC oracle supplied to SVA by +4 and must fail.
