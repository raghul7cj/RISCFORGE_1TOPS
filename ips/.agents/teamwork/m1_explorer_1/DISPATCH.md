# Dispatch — m1_explorer_1

## Task
Milestone 1: Pipeline Monitors Exploration (Fetch, Retire, LSU).
Examine:
- Existing implementations in `Verification/infrastructure/monitors/` (`fetch_monitor.sv`, `retire_monitor.sv`, `lsu_monitor.sv`).
- Pipeline taps in `riscv_core/rtl/top.v`, `fetch_cycle.v`, `memory_cycle.v`, `wb_trap_mret_commit_controller.v`.
- Instruction retirement detection: `valid_W & ~exc_valid_W`.
- Shadow PC-to-Instruction tracking to resolve `InstrW` at retirement without modifying RTL.
- 64-entry circular ring buffer implementation, pointer management, and synchronous freeze input.
Input paths:
- `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md`
- `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md`
Output: Detailed recommendations for Worker in `handoff.md` in your working directory.

## 2026-10-01T21:06:43Z
[Message from f600a31f-7502-4e6a-baf5-5e32a55d3d3e]
You are m1_explorer_1.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1
Read DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md.
Investigate the pipeline monitors (Fetch, Retire, LSU) in Verification/infrastructure/monitors/.
Analyze the exact signals, shadow PC-to-instruction mapping, 64-entry circular ring buffer structure, and freeze input.
Deliver a complete implementation plan and recommendations for the Worker in handoff.md in your working directory, update progress.md, and send a completion message back.

