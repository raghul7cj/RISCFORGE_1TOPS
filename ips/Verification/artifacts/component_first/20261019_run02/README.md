# Component-first SoC verification — run 02

**Date:** 2026-10-19  
**Simulator:** Vivado XSim 2022.2 (local Windows installation)  
**MCP status:** Local Vivado MCP server `2026.9.1` is responsive at `http://127.0.0.1:18090/mcp`. Session `vivado-20261019-024344-ca5f1587` (PID 16744, Vivado 2022.2) is alive and idle with an empty queue; its last Tcl command, `current_project`, returned “No projects are currently open” (exit 1). The preserved `monitor/smoke/mcp_run/` run was completed through MCP; the newer isolated follow-ups used the local XSim CLI.  
**Design scope:** No SoC or peripheral RTL was changed. Verification monitor and testbench sources were updated where noted, with run snapshots preserved in this artifact tree.

## Results

| Area | Status | Result and evidence |
|---|---|---|
| SRAM single-port block | PASS | 7/7 checks: first/last word, byte lanes, zero mask, read-first behavior, subsequent read, and chip-select hold. `sram/sim.log`. |
| AXI-Lite-to-APB bridge | PASS | 28/28 checks. BFM now samples handshakes at the active edge and waits for responses without consuming them early. `bridge/sim.log`; adapted bench snapshot in `bridge/tb_axi_lite_to_apb.sv`. |
| SoC APB aperture and bridge slot routing | PASS | 43/43 checks across all six APB slots, reads/writes, selected-slot mask, and GPIO alias/gap/unmapped cases. Uses the real bridge with APB responders; not the actual peripheral RTL. `gpio_aperture/sim.log`. |
| SPI master component | PASS (follow-up) | Follow-up XSim run passes 26/26 checks with `TEST_PASS`; nine EOT events were captured, including TC6. The original timeout was a testbench sampling issue: TC6 waited for a one-cycle EOT event after the APB read had already completed. `spi/eot_retry/sim.log`. |
| UART component | INCOMPLETE | XSim compiles and elaborates; simulation stops progressing after reset checks. Current log: `uart/sim.log`. Historical Xcelium run reported 69/69 pass, but source identity was not captured, so it is not accepted as current evidence. |
| Cold boot to Timer0 runtime smoke | PASS (corrected XSim time-unit setup) | **52/52 checks pass.** Flash model power-up, SPI command/address, MISO, RXFIFO APB data, all 11 ISRAM words, Timer0 MMIO, and DSRAM result store were observed. Final log: `timer0_integration/sim_timescale_preserved.log`. |
| Direct Timer0/Timer1 component checks | PASS | **9/9 checks pass** using two timer instances: reset values, independent counting/stopping, compare/overflow IRQs, invalid-register read, and APB response. `timers/sim.log`; testbench: `timers/timer_component_tb.sv`. |
| Monitor smoke (local XSim) | PASS | Nonzero fetch (396), retire (412), LSU (2), AXI-Lite (14), APB (8), IRQ (4), and pin (2) activity; includes an LSU→AXI-Lite→APB cross-layer join. `monitor/smoke/sim.log`, `monitor/smoke/monitor_postmortem.txt`. |
| Monitor exact path follow-up | PASS | Strengthened the synthetic monitor smoke to require exactly one UART store at each layer with matching address, data, byte enables/strobes, slot, and ordered timestamps. XSim passes `J4.exact_uart_path`; post-mortem shows LSU/AXI/APB byte enables all `1111`. Atomic transaction construction fixed a monitor capture that had recorded LSU byte enables as zero. `monitor/exact_join_fixed/simulation.stdout.log`, `monitor/exact_join_fixed/monitor_postmortem.txt`. This validates the monitor harness, not the real SoC firmware traffic path. |
| APB timeout monitor component | PASS | **14/14 checks** against the actual `apb_timeout_monitor` RTL: transparent response, completion before threshold, timeout pulse/SLVERR/sentinel response, sticky status, pulse clear after access, and reset recovery. `monitor/apb_timeout_unit/simulation.log`. |
| Step4 checker self-proof | PASS | Clean traffic was non-vacuous (LSU=17, AXI writes=8, reads=9, APB=14); the disassembler passed 31/31 and all **11/11 injected faults** produced the expected check IDs, including APB wait timeout. This is checker-path evidence using the Step4 bridge model, not the real SoC bridge. `monitor/step4_selfproof/xsim.log`, `monitor/step4_selfproof/step4_report.txt`. |
| Monitor smoke (Vivado MCP) | PASS | Separate MCP compile, elaboration, and simulation succeeded; final log ends `SMOKE TEST PASSED` and contains event counts and a cross-layer join. Initial compile omitted `-i ../../inputs` and failed; corrected retry is preserved. `monitor/smoke/mcp_run/`. |
| Monitor empirical challenge | PASS (challenge model only) | All 25 challenges passed with 0 errors, including freeze stability and 442-cycle monitored/golden DUT non-intrusiveness checks. Its post-mortem has zero LSU and APB events, so this is not evidence for timeout/violation reporting or real-traffic MMIO accounting. `monitor/challenge/sim.log`. |
| Monitor freeze-buffer stress | PASS | 165 checks, 0 failures. `monitor/stress/sim.log`. These results do not by themselves close monitor violation/timeout injection or real-traffic scoreboard accounting for Stage1. |

## Previously completed component checks

The preceding checkpoint, [run 01](../20261018_run01/README.md), records passing monitor smoke/challenge/stress, full SoC compile/elaboration, cold boot plus warm-reset retention, direct GPIO checks (312/312), and I2C APB/pin-model checks (90/90). Its run manifest and source hashes are in `../20261018_run01/reproducibility.json`. These results are prior-run evidence, not reruns from this date.

## SPI EOT follow-up

The original `spi/sim.log` remains unchanged as the initial result. In `spi/eot_retry/`, the testbench now counts the public `events_o[1]` EOT pulse so it remains observable when an APB FIFO read completes later. The rerun used the same SPI RTL source snapshot, Vivado XSim 2022.2, behavioral mode, and the complete TC1–TC6 bench; it ended at 90.665 us with `TEST_PASS checks=26 eot_events=9`. The only simulation warnings are the bench's unsupported `$shm_open`/`$shm_probe` calls; no functional checks were skipped. A focused, non-empty VCD was captured at `spi/eot_retry/spi_focused.vcd`.

## Monitor path and timeout follow-up

The initial run02 monitor smoke had two LSU UART writes but only one corresponding APB UART write, and its LSU record showed `be=0000` against AXI/APB `1111`. The stronger follow-up reduced the structural stub to one known UART store and checks exact one-to-one capture at LSU, AXI-Lite, and APB. It first failed on the zero LSU byte enable, exposing sequential packed-struct member assignments that XSim 2022.2 silently dropped. `lsu_monitor` now constructs the packed record atomically; the isolated rerun passes all smoke checks, including `J4.exact_uart_path`, and the post-mortem shows identical `1111` strobes at all three layers. This is monitor-harness evidence only; Stage1 firmware accounting still needs a real SoC run.

The actual `apb_timeout_monitor` module also passes a new standalone component bench (`TEST_PASS checks=14`) covering normal response pass-through, a slave completing before the timeout threshold, injected timeout response fields, sticky status and recovery. This does not yet prove end-to-end timeout injection through the SoC bridge/core or Stage1 accounting.

## UART and firmware gate diagnosis

The minimal UART adapter replay reaches `FATAL_ERROR: Vivado Simulator kernel has discovered an exceptional condition` at 60 ns, iteration 0, in `apb_to_obi.sv`'s combinational process with a synthetic `gnt=req` responder. The saved XSim log reports 8.5 GB peak memory. No-DUT and grant-low controls advance, while disabling OBI assertions does not resolve the failure. Fresh replays with `-maxdeltaid 1000` plus process tracing, then `-maxdeltaid 10` without tracing, also stalled at the PSEL edge; both were manually stopped, and the second run's transcript stops at `ADAPTER before PSEL 60000`. The original complete fatal is in `uart/debug/sim_adapter.log`; the replay details are in `uart/debug/delta_replay_notes.txt`. AMD UG900 explains delta-cycle scheduling, but the documentation search found no matching 2022.2 Answer Record or verified workaround. This remains an XSim environment/tool failure pending a controlled VCS comparison; it does not establish a DUT defect. The local VCS command is unavailable and `SYNOPSYS_SSH_PASSWORD` is unset, so no remote comparison was run.

Stage1 is not simply pending: the saved local XSim attempt watchdogs at PC `0x00010008` with two retired instructions and no AXI/APB traffic; its post-mortem also reports a missing boot-ROM monitor image. The saved remote Xcelium attempt fails firmware activity error `0x1002` because verified MMIO reads are 4 versus the declared minimum of 6, and its AXI/APB counts disagree. Stage1 and Stage3 remain unverified until those accounting and boot-path issues are resolved.

## Tool and reproduction notes

- Vivado 2022.2 is installed locally at `C:\Xilinx\Vivado\2022.2\bin`; its XSim tools were used. The local Vivado MCP server (`2026.9.1`) was directly queried at `http://127.0.0.1:18090/mcp`. Its active session `vivado-20261019-024344-ca5f1587` is alive and idle with queue length 0. The last Tcl command, `current_project`, returned “No projects are currently open” (exit 1); these follow-up simulations used XSim CLI. The earlier MCP monitor smoke retry succeeded with `-i ../../inputs`; its first compile failure was a missing include path, not a design failure.
- UART controlled benches localize the no-time-advance stall to the APB-to-OBI combinational grant path: minimal UART APB read and adapter-only `apb_to_obi` with synthetic `gnt=req` reproduce it; no-DUT control advances; forcing `gnt` low advances; disabling OBI assertions does not resolve it. This does not confirm an RTL defect or an XSim bug. See `uart/debug/`.
- Each test has its compile, elaboration, and simulation logs, and a copy of its testbench/filelist where applicable. The Timer0 test required a temporary XSim-compatible staging copy because the checked-in filelist references stale paths/ports and includes assertions unsupported by XSim without compatibility defines. Temporary edits were limited to the staged testbench/filelist; no RTL was changed.
- The first Timer0 attempt used `xelab --timescale 1ns/1ps --override_timeunit`. That option overrode the vendor flash model's declared `1 ps/1 ps` time unit, turning its `#tdevice_PU` 300 µs delay into 300 seconds. The model was still unpowered at the first SPI read, so MISO, RXFIFO data, and ISRAM image writes were `Z`. The corrected run removed `--override_timeunit`; the model reported `PoweredUp=1`, decoded READ (`0x03`), drove data on MISO, and returned `0xb7100040` from RXFIFO (bootloader byte-swapped it to `0x400010b7`). Compare `timer0_integration/sim_override_timeunit_z_failure.log` and `timer0_integration/sim_timescale_preserved.log`.
- The first no-override diagnostic run reached the program's park PC before the final SRAM write committed. The staged bench now waits separately for `DSRAM[0] == 1`, then confirms the commit. This corrected diagnostic run passes all 52 checks; the wait adjustment is testbench-only.
- The bridge bench edit is verification-only. It corrects testbench handshake timing and adds a timeout guard; the source snapshot is preserved in `bridge/tb_axi_lite_to_apb.sv`.
- The GPIO aperture test's responders are synthetic. Its PASS verifies address selection and response routing through the actual bridge, not the functional behavior of the six peripheral RTL blocks.
- Stage1 is still deferred while the UART simulator failure, external pin checks for UART/SPI/GPIO, and monitor negative/timeout and real-traffic scoreboard gates remain open. SPI TC6 EOT now passes in the follow-up run. Direct Timer0/Timer1 checks pass 9/9.

## Remaining work before Stage1

1. Rotate credentials, set `SYNOPSYS_SSH_PASSWORD`, run the controlled UART XSim/VCS comparison, and complete UART directed/pin checks.
2. Complete SoC pin-level coverage for UART/SPI/GPIO; retain the prior I2C APB/pin-model 90/90 evidence.
3. Verify timeout/violation injection through the real SoC path and retain non-vacuous matched LSU/AXI/APB evidence for firmware traffic. Step4 checker injection, the exact monitor-harness join, and standalone APB timeout RTL now pass, but none substitutes for this SoC-level gate.
4. Resolve the boot-path and accounting failures, then run Stage1 and Stage3 against the independent monitor counts.
