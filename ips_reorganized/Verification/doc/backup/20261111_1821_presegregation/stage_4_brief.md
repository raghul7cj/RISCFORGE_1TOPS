# RISCFORGE — Stage 4 Brief (P2: Register & Device Models)

**Goal:** Move beyond bus-transaction correspondence: check whether a selected APB peripheral returns the **right register values and observable device behavior**. Extend Stage 3 incrementally; do not build all six device environments at once.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§8–9, 15, 20–21. This is a **reduced P2 milestone**, not Rev B's full six-device, three-oracle sign-off.

## Scope

1. **Choose one verified path.** Reuse the Stage 3 peripheral (prefer GPIO or a timer). Inventory implemented registers, access permissions, reset values, byte enables, aliases, holes, and observable side effects. Distinguish *specified behavior* from current RTL behavior; flag spec gaps rather than copying the DUT as the oracle.
2. **Build a small independent register model.** Track expected state across reset, reads, writes, partial writes, read-only fields, and relevant write-one-to-clear or side-effect behavior. Compare against actual APB completion data, not a duplicate of internal DUT signals.
3. **Add one device-level observable effect.** For GPIO, exercise output/pin state; for a timer, exercise count/compare/interrupt timing. Reuse an existing external model if suitable. Check that a firmware-issued MMIO operation produces the intended effect.
4. **Exercise legal and negative cases.** Run a compact directed table: reset read, normal write/readback, byte strobe, reserved/invalid address, and one device side effect where supported. State the expected error policy; do not silently assume every access must raise `PSLVERR`.
5. **Verify the oracle itself.** Deliberately corrupt a model expectation or inject a safe read-data mismatch and observe an attributed **FAIL**. Then extend to **one additional peripheral or register class**, only if the first model is reliable.

## Done when

- [ ] A named peripheral has a checked register map and an independent expected-state model.
- [ ] Legal, partial-write, reset, and applicable invalid-access cases have reproducible verdicts.
- [ ] One externally observable device effect is checked, not only readback.
- [ ] A deliberately wrong expected value produces FAIL; all unfinished devices are labeled NOT TESTED.
- [ ] Stages 1–3 still run with no unexplained regressions.

## Deliverables (only these)

- A small model/spec table for selected registers; reuse existing Stage 3 monitor transactions.
- Directed register/device test(s) plus a checker, with one negative-case log.
- `p2_findings.md`: tested identities, model-vs-RTL mismatches, untested modes, and the next device to add.

## Not in Stage 4

No complete UVM RAL build-out, six-device sign-off, full-offset sweep, generated-all-from-RTL oracle, new bus framework, dashboards, or coverage closure. Full P2 remains open until all in-scope integrated devices and required oracles are checked.

## Next stage

**Stage 5 / selective P3:** verify reset/boot timing, interrupt entry and clearing, and a non-happy-path fabric response using the established models.

## Codex instruction

> Read Stages 1–3 evidence. Inspect one peripheral specification and its RTL bindings; report OBSERVED / EXPECTED / UNKNOWN and up to five small tasks. Reuse existing monitors. Implement one independent model and one real device-effect check, demonstrate a negative checker case, and preserve all failing traces.
