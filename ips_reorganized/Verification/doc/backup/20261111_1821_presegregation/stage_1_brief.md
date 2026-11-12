# RISCFORGE — Stage 1 Brief (P0: Bring-up)

**Goal:** Prove that the *current integrated SoC* can execute one meaningful, repeatable firmware smoke test. **Do not build a verification framework yet.**

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§5–6, 20–21. This is a *reduced implementation plan*, not a claim that any check already exists or passes.

## Scope

1. **Find the working path.** Inspect the repository for the SoC top, resolved RTL filelist, simulator command, firmware/image build, SPI/boot setup, SRAM initialization, and existing result mechanism. Record gaps; do not assume the document matches the tree.
2. **Make one command work.** Run a single cold-boot scenario from the actual boot/image source through bootloader, SRAM, core release, and firmware completion. Reuse existing scripts; patch only what's required for this scenario.
3. **Prove useful activity.** Observe nonzero instruction retirement, AXI-Lite transfers, APB transfers, and a firmware result/attestation. The firmware must check an expected outcome, not merely print `PASS`.
4. **Make the result reproducible.** Save the exact invocation and a machine-readable record with: RTL hash, filelist hash, simulator/version, plusargs, seed (or `none`), scenario, verdict, and artifact/log location.
5. **Prove failures are visible.** Deliberately run one harmless negative harness case (e.g. incorrect expected firmware signature) and confirm it exits **FAIL**, never **PASS**. Restore the correct expectation afterward.

## Done when

- [ ] One documented command reruns the same SoC smoke test on the same RTL identity.
- [ ] Cold boot reaches firmware and a checked result; instruction/AXI/APB/attestation counters are nonzero.
- [ ] The run stores its command, inputs, hashes, simulator identity, logs, and **PASS/FAIL/TIMEOUT** verdict.
- [ ] A deliberate negative case is detected; missing activity or timeouts fail rather than silently pass.
- [ ] Any unresolved issue is labeled **BLOCKED** with evidence and a next experiment.

## Deliverables (only these)

- `run_smoke` entry point (script or existing command), with minimal documented prerequisites.
- One small self-checking firmware image or a reused existing equivalent.
- Log + run metadata + concise PASS/FAIL summary for the positive and negative runs.
- `p0_findings.md`: observed results, remaining blockers, and the next smallest test.

## Not in Stage 1

No full UVM/cocotb port, generic agents, full AXI/APB scoreboards, ISS lock-step, coverage closure, formal sign-off, dashboards, generated register models, or extensive governance. These belong to later stages, if justified.

## Next stage

**Stage 2 / P1a:** establish core confidence on the *current* RTL using RISCOF, focused CSR/trap/MRET tests, and targeted assertions; then **P1b:** verify one independent core → AXI → APB round trip with a monitor and scoreboard. Keep core-only tests separate from SoC activity gates.

## Codex instruction

> Inspect first; report **OBSERVED / EXPECTED / UNKNOWN**, actual repository paths, and a maximum five-step P0 task list. Reuse the existing harness. Make no broad RTL refactor or test weakening. Implement only the next smallest agreed step and attach its commands, logs, diffs, and verdict.
