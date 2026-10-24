# RISCFORGE — Stage 8 Brief (P6: Engineering Baseline & Handoff)

**Goal:** Produce a **defensible engineering release snapshot** of RISCFORGE: exactly what was built, tested, found, and left open. This is a learning-project handoff, **not tapeout authorization**.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§19–22 and Annexes A–D. Rev B's real P6 requires a frozen candidate, full G5 compliance/formal closure, soaked campaign evidence, and organizational sign-off; this file intentionally uses a smaller status-reporting target.

## Scope

1. **Freeze and identify the deliverable.** Record the RTL/filelist and tool versions, firmware images, run commands, hashes, and Stage 6–7 manifest. Clearly label which configuration (core-only, SoC, selected APB device) each result applies to.
2. **Execute a clean replay.** Rerun the core applicable-test inventory and the selected SoC regression on that identity. Report PASS, FAIL, NOT RUN, NOT APPLICABLE, and BLOCKED separately; do not copy prior green results across RTL changes.
3. **Summarize verification evidence.** Include demonstrated functionality, checker-negative cases, executed coverage, stress stability, and meaningful independent oracles. State which full Rev B obligations (six-device models, comprehensive coverage, ISS lock-step, formal proofs, etc.) remain incomplete.
4. **Create a defect and risk ledger.** For each open defect, record observed behavior, expected behavior, reproducer, suspected area, impact, and owner/next experiment. Distinguish design bugs from unimplemented or unintegrated features.
5. **Create the next-phase handoff.** Prioritize a small actionable queue (highest-risk RTL failures first, missing independent checker second, training-value UVM/cocotb experiment third). Keep the original Rev B plan as the expanded backlog, not as a claim of release readiness.

## Done when

- [ ] One canonical snapshot and commands reproduce the reported results.
- [ ] A summary distinguishes all executed and unexecuted checks, tool gaps, and unexpected failures.
- [ ] Every known critical problem has a reproducer or explicit blocker; none is silently waived.
- [ ] Coverage and checker-viability claims are limited to retained evidence.
- [ ] The handoff gives a reviewer the next three concrete engineering actions.

## Deliverables (only these)

- `verification_baseline.md`: snapshot identity, tests/coverage, major findings, and open obligations.
- Minimal indexed evidence bundle: manifests, verdicts, logs, and key failure reproducers.
- `next_actions.md`: prioritized RTL/DV backlog for continued work or job training.

## Not in Stage 8

No tapeout-readiness claim, corporate sign-off process, guaranteed zero defects, invented 100% coverage, automatic pass for waived tests, or release-level G5 declaration without the actual Rev B evidence.

## Next stage

Continue the highest-risk open RTL/DV work or start a **bounded UVM CSR block testbench** as a separate practical training project; keep existing working SoC regressions intact.

## Codex instruction

> Use only executed artifacts on one recorded RTL identity. Build an auditable status report with PASS/FAIL/NOT RUN/BLOCKED distinctions and a concise next-action queue. Do not invent sign-off, fill absent evidence, or rewrite failing expectations.
