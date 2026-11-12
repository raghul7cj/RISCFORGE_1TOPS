# RISCFORGE — Stage 6 Brief (P4: Coverage & Regression Closure)

**Goal:** Turn Stages 1–5 into a **measured, reproducible verification baseline**: know what ran, what was checked, which checkers can fail, and which important behaviors remain untested.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§6, 10, 19–21 (P4.1–P4.5). This is **learning-project closure**, not Rev B's complete G2/G4/G6 candidate sign-off.

## Scope

1. **Build a small regression manifest.** Enumerate existing smoke, core/RISCOF, MMIO path, register/device, reset, interrupt, and fabric-error tests. Record scenario, configuration, RTL/filelist identity, seed, command, verdict, and artifact location. Reuse the existing runner.
2. **Define useful coverage only.** Capture executed tests and a concise functional matrix: targeted address/device, read/write/partial access, normal/error response, reset type, interrupt masked/taken, and core trap type. Use native simulator coverage if available; otherwise report explicit event counters rather than inventing percentages.
3. **Check for vacuous success.** For each important checker, demonstrate both (a) that its watched condition occurred and (b) that a deliberate negative case is reported. Keep negative tests distinct from normal DUT regression results.
4. **Map important requirements to evidence.** Maintain a short requirement → test/check → result table for the selected milestone, with UNKNOWN/NOT RUN entries. Do not generate an enterprise-wide traceability database.
5. **Rerun on one frozen snapshot.** Execute the chosen regression without changing RTL between tests. Summarize failure signatures, uncovered scenarios, test instability, and which failures reproduce with the saved command and seed.

## Done when

- [ ] One command or manifest executes the selected tests on the same recorded RTL identity.
- [ ] Every reported PASS has meaningful activity and a checked expected outcome.
- [ ] High-value checkers have a retained negative-case demonstration; missing evidence is OPEN.
- [ ] A coverage table distinguishes HIT / NOT HIT / NOT APPLICABLE / UNKNOWN with reasons.
- [ ] All failures and missing tests remain visible; the report makes no full sign-off claim.

## Deliverables (only these)

- Minimal regression manifest and combined machine-readable test summary.
- `coverage_matrix.md` (small, requirement-driven) and checker-negative evidence index.
- `p4_findings.md`: demonstrated confidence, unresolved defects, and next high-value coverage gaps.

## Not in Stage 6

No mandated 100% coverage target, giant check-ID registry, automated waiver policy, arbitrary seed-volume target, full commercial coverage merge, or organizational signatories. Rev B's G2/G4/G6 remain separate, stricter objectives.

## Next stage

**Stage 7 / selective P5:** rerun the stable candidate with incremental stress, repeat boot/reset cases, and test error/timeout paths for convergence rather than using a fixed impressive-looking count.

## Codex instruction

> Inventory existing test evidence, not planned checks. Propose a minimal regression manifest and a compact coverage matrix. Run it against a single RTL identity, show actual coverage counts and negative-checker evidence, and leave every incomplete check explicitly OPEN.
