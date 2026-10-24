# BRIEFING — 2026-10-01T21:40:00Z

## Mission
Investigate bus monitors (AXI4-Lite and APB 6-Slot), analyze interfaces, decoding, ring buffers, and freeze input to provide a complete implementation plan and recommendations for Worker in handoff.md.

## 🔒 My Identity
- Archetype: explorer
- Roles: explorer, analyst
- Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2
- Original parent: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Milestone: Milestone 1: Bus Monitors (AXI4-Lite & APB 6-Slot)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement (do NOT modify RTL/testbench files directly)
- Write only to working directory: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2`
- Follow AGENTS.md rules: no mass ingestion (max 1-2 files at once, targeted views), pinpoint searches, use filelists first

## Current Parent
- Conversation ID: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `Verification/infrastructure/monitors/axi_lite_monitor.sv`
  - `Verification/infrastructure/monitors/apb_monitor.sv`
  - `Verification/infrastructure/monitors/rf_monitors.sv`
  - `Verification/infrastructure/tb/tb_pkg.sv`
  - `Verification/infrastructure/tb/rf_monitor_if.sv`
  - `Verification/infrastructure/tb/rf_mon_probe.sv`
  - `Verification/infrastructure/tb/soc_tb_top.sv`
  - `Verification/infrastructure/checkers/mmio_path_scoreboard.sv`
  - `Verification/infrastructure/checkers/failure_reporter.sv`
  - `Verification/infrastructure/checkers/axi_lite_protocol_sva.sv`
  - `Verification/infrastructure/checkers/apb_protocol_sva.sv`
  - `RTL_SOC/riscforge_soc_subsystem.sv`
  - `bus_monitors/axi_lite_timeout_monitor.sv`
  - `Verification/infrastructure/soc_verification.prj` & `soc_verification.f`
- **Key findings**:
  1. Packed Structs: `axi_req_t` (111b), `axi_resp_t` (41b), `apb_req_t` (74b), `apb_resp_t` (34b) are in `riscforge_soc_subsystem.sv`. Flat signals were removed.
  2. Tap Points: Core AXI port (`core_axi_req/resp`) vs Crossbar port 0 (`xbar_slv_req[0]/resp[0]`). Timeout monitor sits between them; on timeout, it injects SLVERR to core while draining downstream. Probing `core_axi_req/resp` is essential for 1:1 LSU CPU transaction correlation.
  3. APB 6-Slot Decoding: GPIO is strictly 2 KB (`0x4000_3000` - `0x4000_37FF`). Gap `0x4000_3800` - `0x4000_3FFF` is unmapped (generates DECERR). Discovered bug in `mmio_path_scoreboard.sv` line 35 which incorrectly decoded full 4 KB for GPIO.
  4. Ring Buffer Deficiencies: `axi_lite_monitor.sv` has simultaneous R+B pointer write race, single-cycle latching race, and missing `axi_txn_t` fields. `apb_monitor.sv` has unpacked array port (XSim incompatible), missing `pstrb`, and missing `wait_states`.
  5. Dual Framework Coexistence: Class-based monitors in `rf_monitors.sv` + `rf_mon_probe.sv` vs module-based monitors in `axi_lite_monitor.sv` / `apb_monitor.sv`. `soc_tb_top.sv` currently attempts to connect non-existent flat signals (`dut.m0_*`, `dut.apb_*`).
- **Unexplored areas**: None for M1 bus monitors scope.

## Key Decisions Made
- Recommending concrete patch plans for the Worker:
  1. Fix `axi_lite_monitor.sv` and `apb_monitor.sv` standalone modules.
  2. Align `soc_tb_top.sv` wiring with packed structs (`dut.core_axi_req`, `dut.core_axi_resp`, `dut.apb_req`, `dut.apb_resp`).
  3. Fix the GPIO 2 KB decode and unmapped gap in `mmio_path_scoreboard.sv`.
  4. Align `soc_verification.prj` and `soc_verification.f`.

## Artifact Index
- `BRIEFING.md` — Persistent awareness & state
- `DISPATCH.md` — Task dispatches
- `progress.md` — Heartbeat and step tracking
- `handoff.md` — Complete 5-component handoff report for Worker
