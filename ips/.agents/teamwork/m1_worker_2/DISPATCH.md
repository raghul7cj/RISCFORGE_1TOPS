# Dispatch — m1_worker_2

## Milestone 1: Passive Protocol & Pipeline Monitors with Circular Freeze Buffers (Replacement for m1_worker_1)

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

### Context & Prior Findings
Read:
1. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1\handoff.md` (Pipeline monitors & shadow PC tracking)
4. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2\handoff.md` (Bus monitors, packed structs, race conditions)
5. `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_3\handoff.md` (IRQ monitor, probe binding, #1step clocking, freeze)
6. Partial progress checklist in `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_1\progress.md`

### Implementation Checklist
1. `tb_pkg.sv`: Add shadow PC-to-instruction lookup mechanism `shadow_record_fetch(pc, instr)` and `shadow_lookup_retire(pc)` so instruction words can be disassembled at retirement without altering RTL. Enrich `axi_txn_t` and `apb_txn_t` with transaction metrics.
2. `rf_monitor_if.sv`: Ensure `#1step` Preponed-region clocking blocks on all monitor probes. Add probe signals for gateway latches, arbiter state, and shadow stack.
3. `rf_mon_probe.sv`: Rebind hierarchical taps to `u_dut.i_riscv_core.*` (not `dut.u_core.*`). Connect `freeze` directly (continuous assign) for cycle-0 synchronous freezing.
4. `fetch_monitor.sv`: Implement 64-entry circular ring buffer. Log `PCF`, `InstrF`, `imem_sram_en`, `StallF`, `PC_next`. Call shadow PC record on valid fetch. Synchronous freeze on `freeze`.
5. `retire_monitor.sv`: Implement 64-entry circular ring buffer. Detect retirement strictly on `valid_W & ~exc_valid_W`. Query shadow PC table for retired `instr_w`. Log `PC_W`, `RDW`, `ResultW`, `RegWriteW_gated`. Sniff trap commit and MRET commit. Track `total_retired_instr`. Synchronous freeze on `freeze`.
6. `lsu_monitor.sv`: Implement 64-entry circular ring buffer. Sniff `lsu_mem_*`, `PC_M`, `lsunitM`. Record completed transactions on `lsu_mem_req && !lsu_mem_stall`. Synchronous freeze on `freeze`.
7. `axi_lite_monitor.sv`: Implement 64-entry circular ring buffer. Fix concurrent B and R handshake race condition on `head_ptr` (advance by 2 or evaluate with priority). Fix same-cycle AW/W/B address latching. Synchronous freeze on `freeze`.
8. `apb_monitor.sv`: Implement 64-entry circular ring buffer. Add `pstrb` input port. Use packed vectors or flat buses for `prdata` to avoid XSim unpacked-array port elaboration crashes. Map all 6 APB slots cleanly. Synchronous freeze on `freeze`.
9. `irq_monitor.sv`: Implement 64-entry circular ring buffer. Sniff raw peripheral interrupts, gateway `pend_q`, arbiter state, and shadow stack. Add edge detection on `irq_pending` to prevent flooding the buffer. Fix enum casting in `rf_monitors.sv`. Synchronous freeze on `freeze`.
10. `soc_tb_top.sv`: Update DUT instance references (`u_dut.i_riscv_core.*`), remove obsolete flat `dut.m0_awaddr` references, connect monitor probes and `freeze_monitors`.
11. Verification:
    - Compile with Vivado `xvlog`/`xelab` (e.g. `Verification/infrastructure/run_rf_mon_smoke.ps1` or `xvlog -sv -f ...`).
    - Run simulation to prove all 6 monitors log transactions cleanly without errors or backpressure.
    - Document exact commands and passing output in `handoff.md`.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.


## 2026-10-01T23:50:22Z
You are m1_worker_2, replacing m1_worker_1 who was interrupted by quota limits.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_2
Read DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\orchestrator_1\PROJECT.md.
Also read the 3 explorer reports:
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1\handoff.md
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_2\handoff.md
- c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_3\handoff.md
And check partial progress in c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_worker_1\progress.md.

Implement the complete set of 6 passive protocol & pipeline monitors (Fetch, Retire with shadow PC tracking, LSU, AXI4-Lite, APB 6-Slot, IRQ) with 64-entry circular ring buffers and synchronous simultaneous freeze broadcast.
Exclusively own and edit the files listed in DISPATCH.md.
Run build/test commands (e.g. Vivado xvlog/xelab or run_rf_mon_smoke.ps1) to verify all 6 monitors compile and execute cleanly in simulation.
Document your changes, build/simulation commands, and pass results in handoff.md in your working directory, update progress.md, and send a completion message back.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
