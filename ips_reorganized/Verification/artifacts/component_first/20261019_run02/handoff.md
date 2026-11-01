# Handoff — Component-First SoC Verification

**Prepared:** 2026-10-19  
**Repository:** `C:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl`  
**Run directory:** `ips/Verification/artifacts/component_first/20261019_run02`

## User objective and constraints

Continue the authorized component-first SoC testbench validation. Establish that monitors/checkers and individual blocks work before running Stage1 firmware. The user explicitly asked to use the local Vivado MCP server for simulation/status and said no drastic infrastructure changes or RTL changes; small modular verification-only changes are allowed. Do not change RTL. The user has now asked to stop and move the work to another chat.

The user supplied these local endpoints:

- Vivado MCP: `http://127.0.0.1:18090/mcp`
- OpenCode UI: `http://127.0.0.1:4096/`

The Vivado MCP was reached by bypassing the configured proxy for localhost (`HttpClientHandler.UseProxy = $false`). MCP session id: `mcp-session-98db0f7b-49c7-477b-97bb-537b03e87588`. The active Vivado session started in this run directory has id `vivado-20261019-024344-ca5f1587`, process id `16744`, and Vivado 2022.2. The OpenCode UI exploration was aborted by the user, so no OpenCode model/subagent was invoked.

## What is done

### Existing run02 results

See [README.md](README.md) and [reproducibility.json](reproducibility.json), noting those files were not updated after the fresh checks listed below. Current recorded results include:

- SRAM: 7/7 pass.
- AXI-Lite-to-APB bridge: 28/28 pass.
- SoC APB aperture / bridge routing: 43/43 pass using synthetic APB responders.
- SPI master: 26 pass indications; TC6 EOT timeout remains unresolved despite expected PREADY recovery and data checks.
- UART: incomplete in XSim; no reliable full-suite result from current sources.
- Cold boot to Timer0 runtime smoke: 52/52 pass after removing `--override_timeunit`; this avoids stretching the flash model’s power-up time from 300 us to 300 s.

Earlier run01 evidence (not rerun this turn): monitor challenge/stress, GPIO 312/312, I2C 90/90, full SoC compile/elaboration, and cold/warm reset retention. Run01 is at `ips/Verification/artifacts/component_first/20261018_run01/`.

### Fresh monitor and timer checks

- Fresh XSim monitor smoke/challenge/stress results are in `monitor/smoke`, `monitor/challenge`, and `monitor/stress`. The smoke showed nonzero activity for fetch (396), retire (412), LSU (2), AXI-Lite (14), APB (8), IRQ (4), and pin (2); it ends with `SMOKE TEST PASSED` and an LSU→AXI-Lite→APB cross-layer join.
- A second monitor smoke compile/sim was run through the local Vivado MCP. It passed; evidence is isolated under `monitor/smoke/mcp_run/` (`mcp_compile_retry.log`, `mcp_elab.log`, `mcp_sim.log`). The first MCP compile attempt failed because the isolated filelist omitted `-i ../../inputs`; its log is preserved as `mcp_compile.log`. This was a run-command issue, corrected on retry.
- `timers/timer_component_tb.sv` directly instantiates two timer blocks to represent Timer0 and Timer1. It checks reset values, independent counting/stopping, compare/overflow IRQs, invalid register read, and APB response. Result: `TIMER_COMPONENT_RESULT pass=9 fail=0`. Logs are `timers/compile.log`, `timers/elab.log`, and `timers/sim.log`.

### UART XSim diagnosis

Controlled benches under `uart/` reproduce a no-time-advance stall at `PSEL`:

- A no-DUT control advances and finishes.
- A minimal UART APB read reproduces the stall.
- Disabling OBI assertions does not fix it.
- Forcing only OBI `gnt` low lets time advance.
- An adapter-only `apb_to_obi` test with synthetic `gnt = req` reproduces it, so UART serial behavior is not implicated by this failure.

This localizes the observed issue to XSim scheduling/handling of the combinational APB-to-OBI grant path. Do **not** label it a confirmed RTL defect or a confirmed XSim bug until another simulator or a cycle-based workaround establishes that. Relevant source references are `ips/SOC_FILES/include/obi/apb_to_obi.sv` (`obi_req_o.req = apb_req_i.psel`, request/grant transition) and `ips/SOC_FILES/include/obi/obi_uart_register.sv` (`obi_rsp_o.gnt = obi_req_i.req`). Diagnostic files and logs are under `uart/debug/`.

## What remains

1. Update `README.md` and `reproducibility.json` to include the fresh monitor runs, timer 9/9 result, Vivado MCP version/session, and UART controlled diagnosis. Correct the stale statements that MCP was unavailable and that direct timer checks remain incomplete.
2. Keep UART status as incomplete until a trustworthy full directed test runs. Consider an independent simulator or a strictly verification-only cycle/handshake adaptation; do not change RTL without user instruction.
3. Resolve SPI TC6 EOT or retain `PASS_WITH_CAVEAT` and explicitly track it.
4. Finish monitor negative/timeout injections and demonstrate non-vacuous scoreboard accounting on real traffic if not already covered by the run01 challenge evidence.
5. External pin behavior still needs full UART/SPI/GPIO confirmation; I2C evidence exists in prior run01 only.
6. Stage1 firmware remains **DEFERRED** until the required component/monitor gates pass.

## Vivado MCP details

The local server was initialized directly over HTTP JSON-RPC; the listed Vivado tools are accessible. A Tcl Vivado session was successfully created and queried: `Vivado v2022.2 (64-bit)`, working directory is this run folder. The monitor smoke was compiled/elaborated/run through this session (MCP command selected XSim executables under `C:/Xilinx/Vivado/2022.2/bin/unwrapped/win64.o/`). The server’s three-item todo plan exists; item 1 (“Run remaining component checks through Vivado MCP”) was active when the user stopped the work. Before closing that session, either mark the item done with the smoke rerun summary and advance/complete the plan, or leave it intact and tell the next chat its state. Check `vivado_status` before reusing or stopping the session.

The prior failed MCP compile used a missing include path; the successful compile included `-i ../../inputs`. Compile and elaboration both succeeded, then XSim returned exit code 0 and wrote the smoke log. Pass summary is in `mcp_sim.log`; the visible terminal output ends `SMOKE TEST PASSED`, includes event counts, and writes a post-mortem.

## Scope / change record

No RTL source was changed. Verification artifacts were added under this run folder, including the direct timer testbench, UART diagnostic benches/logs, and the Vivado MCP smoke subdirectory. The intended next change is only to update this run’s documentation/manifest after review.
