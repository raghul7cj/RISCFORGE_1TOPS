# RISCFORGE — Parallel Track F Brief (Targeted Formal)

**Goal:** Learn formal reasoning by proving or disproving a **small set of high-risk RTL properties** without blocking ordinary directed verification. This is **parallel work**, not Stage 9.

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§18, 21.4–21.5. Rev B specifies property registration, covers, viability/vacuity evidence, proofs, and triage across core, interrupt, and fabric structures. This brief selects a narrow subset.

## Scope

1. **Check actual tool availability.** Identify the supported formal engine, language subset, and simplest synthesizable target. If unavailable, record BLOCKED and demonstrate the property as a simulation assertion instead; do not invent proof outcomes.
2. **Select 2–3 local invariants.** Prioritize an SRAM mux exclusivity/priority claim, an interrupt gateway/arbiter gating claim, or a reset/trap transition invariant. Specify assumptions and bound explicitly; avoid trying to prove full RV32IM execution.
3. **Show non-vacuity.** For each assertion, add a reachable antecedent/cover or negative control. A property that never activates does not establish the target behavior.
4. **Inspect counterexamples.** Classify failures as actual RTL defect, bad environment assumption, incorrect property, or inconclusive proof. Preserve minimal waveforms and inputs. Never alter assumptions simply to force PASS.
5. **Relate to simulation.** Add a directed reproducer for one counterexample or an assertion usable in the Stage 5–7 simulation regression.

## Done when

- [ ] Two or more precisely scoped claims have a documented property, assumptions, and result (PROVED / FAILED / INCONCLUSIVE / BLOCKED).
- [ ] Each attempted claim has activation/cover evidence or is explicitly marked unverified.
- [ ] At least one result changes the simulation test plan or resolves a concrete risk.

## Deliverables (only these)

- Small property file(s) and reproducible proof/simulation commands.
- `formal_findings.md`: properties, assumptions, bounds, results, counterexamples, follow-up tests.

## Not in Track F

No complete proof of the CPU, blanket formal sign-off, automated vacuity platform, or requirement that P3/P4 implementation stop until every formal obligation closes. Full Rev B Track F closure remains a distinct later goal.

## Codex instruction

> Discover the available formal/simulation tool first. Suggest at most three RTL properties with independent assumptions and explicit covers. Report PROVED/FAILED/INCONCLUSIVE/BLOCKED from actual logs; do not claim proof from assertion compilation or simulation-only passing.
