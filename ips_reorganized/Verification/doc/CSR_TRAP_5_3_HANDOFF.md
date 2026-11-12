# 5.3 Privileged / trap verification status

**Disposition: PENDING.** The 5.3 checklist item remains In Progress. A test pass report does not close the item until the source, run, approved expectations and closure scope are bound together.

## Current evidence and limits

- User-reported: privileged and trap tests pass. The newer run bundle/source identity has not been attached to this handoff.
- Retained CSR corner unit run (11 Nov 2026): 552 checks, 0 failures, 56 specification-pending cases. It samples 236/236 observed case-index bins; 40 collision and 16 counter cases are observations without expected-value checks. This is partial unit evidence, not 5.3 closure.
- Core `tb_core_csr_trap`: connected skeleton; reset-held run, no scenario stimulus or checks, no core coverage sampling.
- No 5.3 SoC end-to-end run/coverage evidence is recorded here.

## Closure work

1. Resolve contract decisions D1-D6 and convert pending observations into reviewed expected-value checks.
2. Add core programs and response schedules, an independent reference model/effects ledger, and coverage sampled only from checked results.
3. Run and retain exception, CSR dependency, interrupt timing, MRET, memory-wait and multi-cycle interaction cases against the approved source/configuration.
4. Decide whether SoC-level evidence is required by the 5.3 acceptance criteria; if so, run and retain it.
5. Update status only after the run bundle, checks, and coverage disposition are reviewed.

## Published references

- [CSR/trap corner test plan](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/verification_infra/ips_reorganized/Verification/doc/CSR_TRAP_CORNER_TESTPLAN.md)
- [CSR/trap testbench architecture](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/verification_infra/ips_reorganized/Verification/doc/CSR_TRAP_TESTBENCH_ARCHITECTURE.html)
- [CSR/trap skeleton README](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/verification_infra/ips_reorganized/Verification/infrastructure/tb/csr_trap/README.md)
- [SoC stimulus and coverage plan](https://github.com/raghul7cj/RISCFORGE_1TOPS/blob/verification_infra/ips_reorganized/Verification/plans/soc_testbench_framework_20261104/04_STIMULUS_AND_COVERAGE.md)

The detailed CSR unit/core bench sources and retained XSim run bundle are present in the local checkout but were not present at those paths on `verification_infra` when this handoff was prepared. Do not treat their GitHub URLs as published evidence until pushed and checked.
