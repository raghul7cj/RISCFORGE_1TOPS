# BRIEFING — 2026-10-01T21:46:00Z

## Mission
Implement 6 passive protocol & pipeline monitors with 64-entry circular ring buffers and simultaneous freeze broadcast for RISCFORGE SoC.

## 🔒 My Identity
- Archetype: worker
- Roles: implementer, qa, specialist
- Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_1
- Original parent: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Milestone: M1 (Passive Protocol & Pipeline Monitors with Circular Freeze Buffers)

## 🔒 Key Constraints
- DO NOT CHEAT. All implementations must be genuine.
- Exclusive ownership of files listed in DISPATCH.md.
- Maintain 64-entry circular ring buffers across all 6 monitors with simultaneous freeze broadcast.
- Zero backpressure and zero timing impact on RTL (#1step Preponed sampling).
- Modulo write pointer management; freeze halts write pointer advance immediately.

## Current Parent
- Conversation ID: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
- Updated: 2026-10-01T21:46:00Z

## Task Summary
- **What to build**: Implement and harden the 6 passive protocol & pipeline monitors (Fetch, Retire with shadow PC-to-instr tracking, LSU, AXI4-Lite, APB 6-Slot, IRQ) with 64-entry circular ring buffers and simultaneous freeze broadcast.
- **Success criteria**: All 6 monitors compile and execute cleanly in simulation; smoke test passes; all explorer bug fixes implemented.
- **Interface contracts**: PROJECT.md § Interface Contracts
- **Code layout**: PROJECT.md § Code Layout

## Key Decisions Made
- Use shadow PC-to-instr associative map in `tb_pkg.sv` so retire_monitor can disassemble retired instructions without RTL modification.
- Fix AXI-Lite dual completion race condition and same-cycle handshake latching.
- Add `pstrb` and pack `prdata_flat` for APB monitor to ensure XSim compatibility.
- Upgrade IRQ monitor with gateway latches, arbiter state, shadow stack, and edge-gated grant to avoid flooding.
- Connect monitors in `soc_tb_top.sv` to `u_dut.i_riscv_core.*` and probe interface.

## Artifact Index
- Verification/infrastructure/monitors/fetch_monitor.sv
- Verification/infrastructure/monitors/retire_monitor.sv
- Verification/infrastructure/monitors/lsu_monitor.sv
- Verification/infrastructure/monitors/axi_lite_monitor.sv
- Verification/infrastructure/monitors/apb_monitor.sv
- Verification/infrastructure/monitors/irq_monitor.sv
- Verification/infrastructure/tb/rf_monitor_if.sv
- Verification/infrastructure/tb/rf_mon_probe.sv
- Verification/infrastructure/tb/rf_monitors.sv
- Verification/infrastructure/tb/tb_pkg.sv
- Verification/infrastructure/tb/soc_tb_top.sv

## Change Tracker
- **Files modified**: None yet
- **Build status**: Pending
- **Pending issues**: None

## Quality Status
- **Build/test result**: Pending
- **Lint status**: Pending
- **Tests added/modified**: Pending

## Loaded Skills
- None
