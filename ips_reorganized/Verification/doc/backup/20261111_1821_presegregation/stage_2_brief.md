# RISCFORGE — Stage 2 Brief (P1a: Core Confidence)

**Goal:** Establish evidence that the *current RV32IM_Zicsr core* executes instructions, CSR operations, and traps correctly before relying on firmware-driven SoC tests. **Do not claim full core sign-off from a smoke test.**

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§13, 16–18, 21.2–21.3. This is a *reduced execution milestone* for P1a; Rev B's full CT-1–CT-5 obligations remain tracked separately.

## Scope

1. **Identify the executable core configuration.** Inspect the existing core-only RISCOF wrapper, RTL filelist, ISA declaration, test inventory, and simulator. Reuse the current core RTL. Keep core-only tests independent of the SoC boot/AXI/APB activity gate.
2. **Establish an ISA baseline.** Run a representative subset of the *applicable* RISCOF tests covering RV32I and M; retain per-test PASS/FAIL/SKIP and reasons. Then run the complete applicable set if the existing toolchain supports it. Rev B names **69 applicable tests** in its vendored snapshot; verify that count against the repository rather than assuming it is current.
3. **Target risky architectural behavior.** Reuse or add small self-checking programs for CSR reads/writes and illegal CSR access, ECALL/EBREAK, exception entry, `mepc`/`mcause`/`mtval`, `mret`, and at least one MUL/DIV case. Include observed versus expected register/PC effects.
4. **Add independent checking.** Prefer an existing ISS/architectural model for a short retirement trace if available; otherwise label lock-step **PENDING** rather than writing a new ISS. Add 2–3 targeted assertions/checks for reset, retire validity, or trap/return invariants, with at least one deliberate checker-negative test.
5. **Separate evidence from open work.** Link every failure to a minimal reproducer, RTL identity, simulator command, and suspected layer (core RTL, testbench, tool, or specification). Do not change expected results to make failures pass. Record warm-boot, full lock-step, and formal status explicitly; do not silently mark CT-2/CT-4/CT-5 complete.

## Done when

- [ ] Core-only test flow reproduces results on a recorded RTL/filelist identity.
- [ ] Representative RV32I, M, CSR, trap, and `mret` tests execute with checked outcomes and per-test verdicts.
- [ ] Applicable RISCOF results are reported honestly: counts for PASS/FAIL/NOT-RUN/OUT-OF-SCOPE; remaining gaps are visible.
- [ ] At least one independently checked retire/trap effect and one negative checker test are demonstrated, or unavailable tools are documented as blockers.
- [ ] No unexplained failure is converted to a pass or waived implicitly.

## Deliverables (only these)

- `run_core_tests` entry point using the existing core wrapper and simulator.
- Small directed core test(s) and targeted checker(s), reusing existing code where practical.
- Machine-readable test results, reproducible logs, and one failure reproducer if defects exist.
- `p1a_findings.md`: evidence, unresolved CT-1–CT-5 obligations, and next experiments.

## Not in Stage 2

No new ISS from scratch, complete UVM core environment, SoC bus scoreboard, full assertion library, mandated formal closure, broad RTL restructuring, dashboards, or sign-off claims.

## Next stage

**Stage 3 / P1b:** bind an independent transaction observer/checker to one core → AXI-Lite → APB peripheral path; expand only after the first read/write round trip is proven.

## Codex instruction

> Inspect the actual RISCOF/core test setup first. Report **OBSERVED / EXPECTED / UNKNOWN**, runnable commands, and up to five smallest tasks. Preserve failing evidence and architectural expectations. Do not port frameworks, rewrite the ISS, or weaken tests. Implement the next minimal test/checker and show reproducible verdicts.
