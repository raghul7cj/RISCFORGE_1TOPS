# Dispatch — m1_reviewer_1

## Milestone 1 Review: Pipeline & Bus Monitors Correctness & Interface Conformance
Examine files modified by `m1_worker_2`:
- `Verification/infrastructure/monitors/fetch_monitor.sv`
- `Verification/infrastructure/monitors/retire_monitor.sv`
- `Verification/infrastructure/monitors/lsu_monitor.sv`
- `Verification/infrastructure/monitors/axi_lite_monitor.sv`
- `Verification/infrastructure/monitors/apb_monitor.sv`
- `Verification/infrastructure/monitors/irq_monitor.sv`
- `Verification/infrastructure/tb/rf_monitor_if.sv`
- `Verification/infrastructure/tb/rf_mon_probe.sv`
- `Verification/infrastructure/tb/rf_monitors.sv`
- `Verification/infrastructure/tb/tb_pkg.sv`
- `Verification/infrastructure/tb/soc_tb_top.sv`

Requirements to verify:
1. All 6 monitors implement 64-entry circular ring buffers with modulo pointer increment.
2. Retirement condition strictly checks `valid_W & ~exc_valid_W`.
3. Shadow PC-to-instruction tracking accurately recovers instruction opcodes at retirement without modifying RTL.
4. Non-intrusiveness: monitors use `#1step` Preponed clocking blocks, never drive DUT signals, no backpressure or timing modifications.
5. Synchronous freeze: all 6 monitors freeze simultaneously when `freeze` is asserted.
6. Run verification commands (compile via xvlog/xelab or run smoke test `run_rf_mon_smoke.ps1`).

Deliver verdict (APPROVE or REQUEST_CHANGES) with full evidence in `handoff.md`.
Input: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md`, `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md`, `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_2\handoff.md`.

## 2026-10-02T00:07:43Z
From: f600a31f-7502-4e6a-baf5-5e32a55d3d3e
Content:
You are m1_reviewer_1.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_reviewer_1
Read DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md.
Also read m1_worker_2's handoff report at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_2\handoff.md.
Review pipeline & bus monitors for correctness, completeness, and interface conformance. Run builds/tests to verify.
Deliver your review verdict (APPROVE or REQUEST_CHANGES) in handoff.md in your working directory, update progress.md, and send a message back.
