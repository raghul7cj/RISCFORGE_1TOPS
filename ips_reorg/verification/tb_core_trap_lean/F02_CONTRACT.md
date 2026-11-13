# F0.2 pipeline contract for precise trap verification

Status: checkers and directed infrastructure implemented. Clean acceptance is open
because F02-WB-01 detects repeated physical GPR write-enable during a memory stall.
This is a core test, with IRQ inputs tied low and no trap/CSR instructions yet.
Diagram: [validated current architecture](docs/diagrams/core_trap_architecture.md).

## Location and ownership

| Location | Responsibility |
|---|---|
| Verification/lib/core/core_pipeline_if.sv | Common observation shape: D/E/M/W registered payloads, effective holds/flushes, redirects, physical memory and commit controls |
| Verification/lib/core/sva/core_stage_sva.sv | One implementation of reset, flush and hold temporal rules, instantiated four times |
| Verification/lib/core/sva/core_pipeline_sva.sv | Common fetch, request-stability, stall-control, commit-eligibility and WB-redirect checks |
| Verification/lib/memory/lsu_dmem_responder.sv | Bounded WAIT_CYCLES responder; zero is the backward-compatible default |
| core_trap_observe.sv | Only DUT hierarchy mappings; effective controls and registered payload packing; opt-in monitor-copy self-tests |
| tb_core_trap_lean.sv | Use-case programs, independent prediction, physical observations, activation requirements and watchdog |

No assertion module contains the DUT instance name or program constants. A future
SoC bench can connect the same core observation interface through its own adapter.
There is no SoC event source, interrupt-controller path or ISR loop in this milestone.

## Sampling and priority

Drive/preload on falling edges. Native SRAM responses update using NBA at rising
edges. Assertions sample preponed values. If flush/hold is sampled at T, |=> checks
the resulting registered state at T+1 before that edge's NBA. Reset > flush > hold
is the source-backed priority in fetch_cycle, decode_cycle, execute_cycle and
memory_cycle. PC updates override holds on branch or WB redirect.

Adapter D hold includes fetch's imem_stall_raw; D/E flush includes irq_flush_frontend.
E/M/W payloads contain registered operands, controls, CSR bundles and exception
bundles; combinational forwarded values are excluded. The 512-bit interface slots
are padded; field identity is explicit in the adapter. Not every unconnected/internal
register is claimed to be checked. No trap PC or cause expectation is derived from
an observed redirect or exception bundle.

| Contract | Checker | Activation in F0.2 |
|---|---|---|
| Reset clears valid at the next sample | stage a_reset | All four stages |
| Flush clears valid at the next sample | stage a_flush | D/E exercised by JAL; M/W pending F1 |
| Hold without flush preserves valid and registered payload | stage a_hold | All four stages with 1- and 3-cycle waits |
| Fetch hold preserves PC unless redirected | a_pc_hold | Wait/drain windows |
| Branch redirect reaches registered PC on the next sample | a_branch_redirect | Forward JAL |
| WB redirect reaches registered target and flushes all stages | a_wb_redirect, a_wb_flush | Present, not activated until F1 |
| WB redirect accepts no younger memory request on that edge | a_wb_kills_memory | Present, not activated until F1 |
| Waiting request remains stable unless WB cancels | a_request_hold | Wait/release exercised |
| Memory wait propagates hold controls | a_memory_stall_controls | Wait fixtures |
| Invalid/faulted stage produces no forbidden RF/CSR/memory event | eligibility assertions | Positive valid traffic exercised; fault antecedents require F1 |
| Controls/payload are defined when used | a_controls_known, a_request_known | Positive traffic |

Local redirect properties check implementation edge timing against the sampled
observed target. The independent reference model checks architectural program flow;
these are different checks. There are 26 assert-property instances and 19 cover-property
instances (including two scenario covers), not 45 independently proven invariants.
Cover callbacks can stop after the first hit in Xcelium. Reported reset/hold/flush
and protocol values are activation witnesses (>0), not exhaustive attempt counts.
Explicit sequence covers avoid counting vacuous implication success. Required witnesses
are enforced at completion; M/W flush and WB redirect zeroes remain visible.

## Memory environment and decisive experiments

A request completes at a rising edge with req && !stall; a successful write also
requires !err. The responder writes only enabled lanes and records each completion.
It never uses flush, valid, PC or scoreboard state to mask writes. Each request waits
exactly WAIT_CYCLES sampled edges; the fixture checks this against configuration.
No artificial acceptance de-duplication is applied. Address errors are returned only
on completion; error recovery is not exercised in F0.2.

The isolation program places an architectural NOP before SW so WB carries x0 work
during the wait. It then executes a forward JAL over poison RF/store instructions.
This isolates hold, request, redirect and squash plumbing. A separate unmodified
F0 stream intentionally retains the preceding nonzero GPR write and exposes
F02-WB-01. The isolation pass is not a waiver for that failure.

No claim is made for mepc/mcause/mstatus, interrupt acceptance/priority, nested
handlers, MRET or precise exception squashing. Those need independent F1 predictions.
