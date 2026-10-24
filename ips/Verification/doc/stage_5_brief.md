# RISCFORGE — Stage 5 Brief (P3: Architectural Scenarios)

**Goal:** Prove a small set of **cross-block behaviors** that cannot be established by register readback alone: reset/boot ordering, interrupt delivery, and fabric error propagation.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§11–14, 20–21 (P3.1–P3.4). This is a **representative P3 milestone**, not closure of all reset, interrupt, fabric, and firmware-oracle requirements.

## Scope

1. **Reset and boot (P3.1).** Capture current reset-domain assertion/deassertion behavior and SPI/core/peripheral release ordering. Verify one cold boot and one warm reset with a self-checking firmware outcome. Inspect behavior when reset occurs during an active transaction; begin with one safely reproducible case.
2. **Interrupt path (P3.2).** Select one **actually software-visible, routed** source. Check enable/pending/claim-or-clear behavior, trap entry, `mepc`/`mcause`/`mstatus` effects, handler execution, and `mret`. Include one masked-interrupt negative case. Do not count unconnected timer lines or the unintegrated AON watchdog as tested.
3. **Fabric response (P3.3).** Select one negative bus condition (unmapped address, a controlled slave error, or an available timeout). Check accepted request, correct error response, no duplicate completion, and the CPU access-fault behavior when architecturally expected.
4. **Firmware oracle (P3.4).** Make firmware check an observable value or peripheral effect, and cross-check its reported result against passive monitor/model evidence. A mailbox `PASS` by itself is insufficient.
5. **Keep faults separable.** Run one scenario at a time; identify expected cycle/order and terminal state. Distinguish RTL failure, test error, and unresolved architectural assumptions before changing any implementation.

## Done when

- [ ] Cold and warm reset scenarios complete with checked results and captured release order.
- [ ] One routed interrupt is checked from device/source through handler and return, including a masked case.
- [ ] One bus-error or timeout scenario produces the expected protocol/CPU outcome, or is BLOCKED with a specific missing mechanism.
- [ ] Firmware and external checker agree on at least one observable effect.
- [ ] New tests have reproducible commands, PASS/FAIL/TIMEOUT outcomes, and no implicit waivers.

## Deliverables (only these)

- Three or four focused directed scenarios; reuse existing smoke, firmware, observers, and reference models.
- A compact state/timing trace for reset, interrupt, and error behavior.
- `p3_findings.md`: outcomes, missing source wiring, untested scenario families, and next discriminating experiments.

## Not in Stage 5

No exhaustive reset-domain crossing methodology, all-source interrupt nesting, full 16-state boot-FSM coverage, formal closure, integration of specified-only hardware, or complete fabric matrix. Track those as open Rev B obligations.

## Next stage

**Stage 6 / selective P4:** define focused coverage and checker-viability evidence over tests built so far, then run a fixed regression candidate.

## Codex instruction

> Pick the smallest existing reset, routed-interrupt, and error-path hooks. Confirm real SoC wiring before naming expectations. Propose at most five experiments; run directed tests independently, preserve traces and mismatches, and do not silently modify RTL or soften failure predicates.
