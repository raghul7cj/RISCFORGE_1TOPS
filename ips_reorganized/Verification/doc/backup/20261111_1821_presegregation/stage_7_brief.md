# RISCFORGE — Stage 7 Brief (P5: Stress & Convergence)

**Goal:** Determine whether the Stage 6 baseline remains stable under **repetition, varied seeds, boot/reset cycling, and controlled errors**. Increase test volume only when the added tests provide new evidence.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§6–7, 11, 20–21. Rev B proposes a formal convergence rule plus **provisional** floors (20 nightly seeds, 1,000 cold boots, 24-hour soak); those are *not automatically required* for this reduced learning milestone.

## Scope

1. **Choose a candidate identity.** Reuse the Stage 6 regression manifest. Freeze RTL and tool inputs for the campaign; log environment differences and treat any RTL edit as a new candidate.
2. **Repeat stable tests.** Rerun representative boot, MMIO, device, interrupt, and error scenarios. Add a small seed sweep where randomized stimulus already exists; do not create a new constrained-random framework solely to produce more seeds.
3. **Stress observable boundaries.** Exercise cold versus warm boot, reset during one transaction, varying legal bus wait times, and a controlled timeout or error response. Check progress, data/response correctness, outstanding-transaction drain, and recovery.
4. **Measure convergence.** Track newly hit coverage cases per batch, repeated failure signatures, timeout counts, and non-deterministic outcomes. Expand seeds or iterations only if important bins or instability remain; never interpret 'no new coverage' as proof of correctness by itself.
5. **Triage before changing anything.** Minimize each newly found failure to its first discriminating test and preserve the failing seed/log. Report whether the issue is DUT, checker, simulator, or unresolved; avoid masking intermittent failures with longer timeouts.

## Done when

- [ ] Selected repeated runs have identical expected outcomes, or every divergence is logged with a reproducer.
- [ ] Boot/reset and at least one bus wait/error/timeout scenario have checked results.
- [ ] Campaign report includes runs, seeds, iteration counts, new coverage hits, unique failures, and remaining gaps.
- [ ] All queued transactions are accounted for at termination; unexpected hangs and drops fail.
- [ ] No 'soak passed' or silicon-release claim is made for unexecuted Rev B scenarios.

## Deliverables (only these)

- A reusable bounded stress command or batch manifest and raw logs.
- `convergence_summary.md`: exact run counts, coverage progression, failure signature index, and unexecuted Rev B floors.
- `p5_findings.md`: instability, demonstrated recovery behavior, and next priority fix/test.

## Not in Stage 7

No mandated 24-hour/1,000-cycle campaign unless separately justified, all-7-timeout-monitor closure, FPGA soak, unsupported scenario permutations, or final compliance/formal sign-off.

## Next stage

**Stage 8 / P6:** freeze a demonstrated verification snapshot and publish an evidence-backed engineering status, explicitly separate from tapeout sign-off.

## Codex instruction

> Reuse the Stage 6 manifest and fixed RTL identity. Propose a bounded campaign with observable convergence metrics, then execute what the tools support. Preserve failing seeds and do not increase thresholds, skip cases, or claim a soak without direct evidence.
