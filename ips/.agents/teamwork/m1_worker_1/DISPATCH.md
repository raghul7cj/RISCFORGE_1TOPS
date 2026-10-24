# Dispatch — m1_worker_1

## Milestone 1: Passive Protocol & Pipeline Monitors with Circular Freeze Buffers

### Scope & Exclusive File Ownership
You exclusively own and will modify/create:
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

### Context & Findings
Carefully read the authoritative reports:
1. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1\handoff.md` (Pipeline monitors & shadow PC tracking)
4. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2\handoff.md` (Bus monitors, packed structs, race conditions)
5. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_3\handoff.md` (IRQ monitor, probe binding, #1step clocking, freeze)

### Implementation Requirements
1. Implement 64-entry circular ring buffers in all 6 monitors with modulo write pointer management.
2. In `fetch_monitor.sv`: Sniff PCF, PCPlus4F, PC_next, InstrF, imem_sram_en, StallF non-intrusively.
3. In `retire_monitor.sv`: Sniff `valid_W & ~exc_valid_W`, `PC_W`, `RDW`, `ResultW`, `RegWriteW_gated`. Implement shadow PC-to-instruction lookup so instruction words are available at retirement for disassembly without modifying RTL. Track `total_retired_instr`. Sniff trap commit and MRET commit.
4. In `lsu_monitor.sv`: Sniff `lsu_mem_*`, `PC_M`, `lsunitM`. Record completed transfers (`lsu_mem_req && !lsu_mem_stall`).
5. In `axi_lite_monitor.sv`: Fix concurrent B and R handshake race condition on `head_ptr`. Fix same-cycle AW/W/B address latching. Unpack from `axi_req_t` / `axi_resp_t`.
6. In `apb_monitor.sv`: Add `pstrb` support. Fix unpacked-array port issue for XSim. Map all 6 APB slots cleanly.
7. In `irq_monitor.sv`: Full 64-entry buffer. Sniff raw lines, gateway latches, arbiter grants, shadow stack. Add edge detection on `irq_pending` to prevent flooding. Fix enum casts.
8. In `rf_mon_probe.sv`, `rf_monitor_if.sv`, `soc_tb_top.sv`:
   - Point hierarchy to `u_dut.i_riscv_core.*` (not `dut.u_core.*`).
   - Use `#1step` Preponed clocking blocks to ensure zero backpressure and zero timing impact.
   - Wire synchronous `freeze_monitors` broadcast so that all 6 buffers halt immediately on cycle 0 of assertion/trap.
9. Verification:
   - Run compilation and simulation smoke tests (e.g. using Vivado `xvlog`/`xelab`/`xsim` on the testbench or smoke harness) to prove that all 6 monitors instantiate and log transactions without errors or warnings.
   - Document commands executed and exact test results in your `handoff.md`.

MANDATORY INTEGRITY WARNING:

## 2026-10-01T21:12:49Z
[Message] timestamp=2026-10-01T21:12:49Z sender=f600a31f-7502-4e6a-baf5-5e32a55d3d3e priority=MESSAGE_PRIORITY_HIGH content=You are m1_worker_1.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_1
Read your task in DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md.
Also read the 3 explorer reports:
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1\handoff.md
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2\handoff.md
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_3\handoff.md

Implement the 6 passive protocol & pipeline monitors (Fetch, Retire with shadow PC-to-instr tracking, LSU, AXI4-Lite, APB 6-Slot, IRQ) with 64-entry circular ring buffers and simultaneous freeze broadcast.
Exclusively own and edit the files listed in DISPATCH.md.
Follow the exact guidelines and bug fixes identified by the explorers.
Run build/test commands to verify all 6 monitors compile and execute cleanly in simulation.
Document your changes, build/simulation commands, and pass results in handoff.md in your working directory, update progress.md, and send a completion message back.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
