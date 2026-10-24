# BRIEFING — 2026-10-01T21:30:00Z

## Mission
Survey RISCFORGE RTL architecture, core pipeline, memory interfaces, AXI/APB bus hierarchy, and testbenches to identify exact signal taps and architecture for 6 passive protocol & pipeline monitors with circular freeze buffers.

## 🔒 My Identity
- Archetype: explorer
- Roles: survey, analysis, architectural signal tap mapping
- Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\explorer_survey_1
- Original parent: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Milestone: Survey & Tap Identification

## 🔒 Key Constraints
- Read-only investigation — do NOT implement or modify RTL
- No mass ingestion (inspect only targeted files/lines)
- Output only metadata to .agents/teamwork/

## Current Parent
- Conversation ID: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Updated: 2026-10-01T21:00:09Z

## Investigation State
- **Explored paths**:
  - `RTL_SOC/soc_subsystem.f`, `RTL_SOC/riscforge_soc_subsystem.sv`
  - `riscv_core/rtl/top.v`, `fetch_cycle.v`, `decode_cycle.v`, `execute_cycle.v`, `memory_cycle.v`, `writeback_cycle.v`, `wb_trap_mret_commit_controller.v`, `csr_regfile.v`, `irq_gateway.v`, `irq_arbiter.v`, `hybrid_mem_interface.sv`
  - `axi_lite_xbar/axi_lite_xbar.sv`, `axi_lite_to_apb/rtl/axi_lite_to_apb.sv`
  - `bus_monitors/axi_lite_timeout_monitor.sv`, `bus_monitors/apb_timeout_monitor.sv`
  - `Verification/infrastructure/` (`tb/soc_tb_top.sv`, `tb/rf_mon_probe.sv`, `tb/rf_monitor_if.sv`, `tb/tb_pkg.sv`, `monitors/*.sv`, `checkers/*.sv`)
- **Key findings**:
  - Exact signal taps identified for all 6 monitors (Fetch, Retire, LSU, AXI4-Lite, APB 6-Slot, IRQ).
  - RTL uses packed structs (`axi_req_t`, `axi_resp_t`, `apb_req_t`, `apb_resp_t`) rather than flat nets.
  - Core instance in top is named `dut.i_riscv_core` (not `dut.u_core` as in `soc_tb_top.sv`).
  - Core lacks raw instruction word in WB stage; non-intrusive solution is PC-to-instruction shadow lookup.
  - Core lacks physical `irq_ack` pin; architectural commit is `trap_commit_valid && trap_commit_is_interrupt`.
  - Simultaneous freeze is achieved via `failure_reporter.freeze_monitors` broadcasting to all 6 circular buffers.
- **Unexplored areas**: None for survey scope.

## Key Decisions Made
- Fully documented all hierarchical signal paths, widths, timing conditions, and structs in `handoff.md`.
- Flagged integration fixes for `soc_tb_top.sv` to ensure clean elaboration in Vivado XSim.

## Artifact Index
- DISPATCH.md — Task assignment and instructions
- BRIEFING.md — Persistent agent state and memory
- progress.md — Liveness heartbeat and progress tracking
- handoff.md — 5-component handoff report
