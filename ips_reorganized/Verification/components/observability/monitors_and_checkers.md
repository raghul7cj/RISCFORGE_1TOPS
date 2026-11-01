# Passive Monitors and Checker Evidence Record

## Identity and test basis

- Master-plan reference: Sections 4, 8, 9, and 19 of RISCFORGE_Verification_Plan_RevB.docx.
- Infrastructure: passive fetch, retire, LSU, AXI-Lite, APB, IRQ, and pin monitors; protocol checks; path scoreboard; failure reporting.
- Test levels: monitor harness self-tests, standalone checker tests, and eventual real-SoC observation. These are different evidence classes.

## Retained execution evidence

- Monitor smoke: PASS with nonzero activity from all listed monitor layers and an LSU-to-AXI-to-APB join. See the [smoke log](../../artifacts/component_first/20261019_run02/monitor/smoke/sim.log) and [post-mortem](../../artifacts/component_first/20261019_run02/monitor/smoke/monitor_postmortem.txt).
- Exact path follow-up: PASS for one synthetic UART store matched across LSU, AXI-Lite, and APB with address/data/strobes and ordered timestamps. See the [simulation output](../../artifacts/component_first/20261019_run02/monitor/exact_join_fixed/simulation.stdout.log) and [post-mortem](../../artifacts/component_first/20261019_run02/monitor/exact_join_fixed/monitor_postmortem.txt).
- Freeze stress: PASS, 165 checks. Challenge model: PASS, 25 checks. See the [stress log](../../artifacts/component_first/20261019_run02/monitor/stress/sim.log) and [challenge log](../../artifacts/component_first/20261019_run02/monitor/challenge/sim.log).
- APB timeout monitor: PASS, 14/14 against actual timeout RTL. See the [timeout unit result](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/simulation.log).
- Step4 checker self-proof: PASS, 31/31 disassembler checks and 11/11 injected fault IDs. See the [runner output](../../artifacts/component_first/20261019_run02/monitor/step4_selfproof/runner.stdout.log), [checker report](../../artifacts/component_first/20261019_run02/monitor/step4_selfproof/step4_report.txt), and [simulation log](../../artifacts/component_first/20261019_run02/monitor/step4_selfproof/xsim.log).
- Run identity and source hashes: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json).
- Stage 2 Watchdog & Freeze Proof: PASS (cycle 50,000 watchdog fire, 31,734 retired instructions, 10 APB transfers captured in freeze buffers, attestation word `0x00010004`). See [Stage 2 artifact README](../../artifacts/stage_proofs/20261024_stage2_watchdog/README.md) and [manifest](../../artifacts/stage_proofs/20261024_stage2_watchdog/manifest.json).
- Stage 3 Exact Bus Count & Monitor Observation: Hardware 100% verified (14 AXI RD, 4 AXI WR, 18 APB transfers, 0 PSLVERR across I2C, Timer 0, Timer 1). See [Stage 3 artifact README](../../artifacts/stage_proofs/20261024_stage3_monitor_count/README.md) and [manifest](../../artifacts/stage_proofs/20261024_stage3_monitor_count/manifest.json). Firmware anti-vacuity accounting under triage.

## What the results establish

They establish monitor activity, selected harness joins, freeze behavior, standalone timeout-monitor behavior, and checker fault-path behavior under their stated test models.

## Limitations and open obligations

The exact join uses a structural stub; Step4 uses a bridge model rather than the real bridge. These results do not yet establish matched Stage1 firmware traffic, real SoC timeout propagation, or SoC-level negative/violation coverage. Preserve those as open obligations.
