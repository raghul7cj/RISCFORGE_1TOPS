# Dispatch — explorer_survey_1

## Task
Survey RISCFORGE RTL architecture, core pipeline, memory interfaces, AXI/APB bus hierarchy, and existing testbenches.
Determine exact signal taps for the 6 passive protocol & pipeline monitors:
1. Fetch stage
2. Retire stage (RVFI or commit signals)
3. LSU (Load/Store Unit)
4. AXI4-Lite bus
5. APB 6-Slot peripheral bus
6. IRQ lines / Interrupt controller interface

Analyze how to tap these signals non-intrusively (no backpressure, no timing changes) and how freeze triggers (assertions/traps) can be routed to circular freeze buffers.
Input: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md
Output: Write structured handoff report to handoff.md in your working directory.

## 2026-10-01T21:00:09Z
You are explorer_survey_1.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\explorer_survey_1
Read your task in DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md.
Also inspect c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\AGENTS.md for the fast routing map.
Do not mass ingest files. Inspect only relevant files/lines in RTL_SOC/, riscv_core/rtl/, axi_lite_xbar/, axi_lite_to_apb/, bus_monitors/.
Survey the RTL architecture, core pipeline, memory interfaces, AXI/APB bus hierarchy, and existing testbenches.
Identify the exact signal taps for the 6 passive protocol & pipeline monitors:
1. Fetch stage
2. Retire stage (RVFI or commit signals)
3. LSU (Load/Store Unit)
4. AXI4-Lite bus
5. APB 6-Slot peripheral bus
6. IRQ lines / Interrupt controller interface
Explain how to tap non-intrusively without backpressure or timing changes, and how circular freeze buffers (64 entries) can freeze simultaneously on first assertion or trap.
Deliver your full findings in handoff.md in your working directory, update progress.md, and send a completion message back.
