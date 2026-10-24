# Project: RISCFORGE SoC Verification Infrastructure

## Architecture
The RISCFORGE RV32IM_Zicsr verification infrastructure deploys an opaque, non-intrusive verification fabric wrapped around `riscforge_soc_subsystem`. It provides 6 passive protocol & pipeline monitors with synchronous 64-entry circular freeze buffers, formal protocol SVAs, an end-to-end MMIO path scoreboard, independent peripheral register and interrupt arbitration reference models, a hierarchical first-fatal blame engine producing 1-page markdown diagnostic failure reports, dual-simulator build harnesses (remote VCS/Xcelium and local Vivado XSim), and 7 bare-metal C proof stages with vacuous pass prevention.

```
       ┌────────────────────────────────────────────────────────┐
       │                riscforge_soc_subsystem                 │
       │                                                        │
       │   Fetch ──► Decode ──► Execute ──► Memory ──► Writeback │
       │     │                                │           │     │
       │     ▼                                ▼           ▼     │
       │  [Fetch Mon]                      [LSU Mon]  [Retire Mon]
       │                                      │           │     │
       │                                      ▼           ▼     │
       │      [Core AXI-Lite] ────────► [AXI Monitor]     │     │
       │             │                                    │     │
       │             ▼                                    │     │
       │      [AXI-to-APB Bridge] ────► [APB 6-Slot Mon]  │     │
       │             │                                    │     │
       │             ▼                                    │     │
       │      [Peripherals 0..5] ─────► [IRQ Monitor] ────┘     │
       └──────┬──────────────┬──────────────┬─────────────┬─────┘
              │              │              │             │
              ▼              ▼              ▼             ▼
       ┌────────────────────────────────────────────────────────┐
       │             Verification & Checking Fabric             │
       │                                                        │
       │  [AXI/APB SVAs]      [MMIO Path Scoreboard]            │
       │  [Register Predictor] [Interrupt Predictor]            │
       │                                                        │
       │  ──► [First-Fatal Blame Engine & Failure Reporter] ◄── │
       │       • 7-Layer Blame Absorption & Reassignment        │
       │       • Simultaneous Freeze Broadcast to all 6 Rings   │
       │       • 1-Page Markdown Report with Disassembly (PC-10)│
       └────────────────────────────────────────────────────────┘
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Fetch Stage Monitor | Sniffs PCF, InstrF, imem_sram_en, StallF, PC_next non-intrusively into 64-entry ring buffer | M1 | explorer_survey_1 |
| 2 | Retire Stage Monitor | Sniffs instruction retirement (valid_W & ~exc_valid_W), PC_W, RDW, ResultW, RegWriteW into 64-entry ring buffer | M1 | explorer_survey_1 |
| 3 | Shadow PC-to-Instr WB Tracker | Shadow table associating instruction opcodes with PC from Fetch/Decode to WB for retire disassembly without altering RTL | M1 | explorer_survey_1 |
| 4 | LSU Passive Monitor | Sniffs lsu_mem_req, we, addr, wdata, be, rdata, stall, err, PC_M, lsunitM into 64-entry ring buffer | M1 | explorer_survey_1 |
| 5 | AXI4-Lite Passive Monitor | Sniffs packed struct axi_req_t / axi_resp_t handshakes at core master port into 64-entry ring buffer | M1 | explorer_survey_1 |
| 6 | APB 6-Slot Passive Monitor | Sniffs packed struct apb_req_t / apb_resp_t across APB[0..5] into 64-entry ring buffer | M1 | explorer_survey_1 |
| 7 | IRQ Lines Passive Monitor | Sniffs raw peripheral IRQs, gateway pend_q, arbiter state, and shadow stack into 64-entry ring buffer | M1 | explorer_survey_1 |
| 8 | Non-Intrusive Sniffing Engine | SystemVerilog clocking blocks with #1step Preponed sampling, 0 added cycles, zero backpressure | M1 | explorer_survey_1 |
| 9 | Simultaneous Freeze Broadcast | failure_reporter.freeze_monitors simultaneously freezes all 6 ring buffers on first assertion/trap | M1 | explorer_survey_1 |
| 10 | I2C Register & Auto-Clear Model | Models APB[0] PRE, CTR, RXR, SR, TXR, CR with auto-clearing command bits and IACK IRQ clear | M3 | spec_miner_survey_2 |
| 11 | Timer 0/1 Dual 32-bit Model | Models APB[1,5] Timer 0/1, CMP-write-zeroes-timer, overflow/compare 1-cycle IRQ pulses | M3 | spec_miner_survey_2 |
| 12 | UART 16550 DLAB Model | Models APB[2] UART word-aligned decode and DLAB bit 7 banking for DLL/DLM vs RBR/THR/IER | M3 | spec_miner_survey_2 |
| 13 | GPIO Atomic Aliases Model | Models APB[3] GPIO_SET (0x200), GPIO_CLEAR (0x280), GPIO_TOGGLE (0x300) WO side-effects on gpio_out | M3 | spec_miner_survey_2 |
| 14 | GPIO Sub-word Write Blocker | Models PSLVERR generation and register write suppression on non-word writes (pstrb != 4'b1111) | M3 | spec_miner_survey_2 |
| 15 | GPIO W1C Hardware-Set-Wins | Models INTRPT_STATUS W1C clearing with incoming edge precedence | M3 | spec_miner_survey_2 |
| 16 | SPI Master Backpressure Model | Models PREADY=0 wait states on TX full / RX empty, auto-clearing command strobes | M3 | spec_miner_survey_2 |
| 17 | AON Timer Watchdog Model | Models WDOG_REGWEN write-0 lockout and watchdog counter thresholds | M3 | spec_miner_survey_2 |
| 18 | Gateway Pulse Capture Model | Models irq_gateway pulse-to-level capture with pulse-wins latch precedence | M3 | spec_miner_survey_2 |
| 19 | Two-Level Priority Class Arbiter | Models Class 2 (Fixed) > Class 1 (RR) > Class 0 (RR) arbitration with zero latency bubbles | M3 | spec_miner_survey_2 |
| 20 | Non-Speculative RR Token Rotation | Models rr_ptr_c1 and rr_ptr_c0 rotation strictly on Writeback commit of winning cause | M3 | spec_miner_survey_2 |
| 21 | Preemption Gating Model | Models preemption allowance: (nest_depth == 0) || (winner_class > cur_class) | M3 | spec_miner_survey_2 |
| 22 | 2-Deep Hardware Shadow Stack Model | Models mepc, mcause, MIE, cur_class push on trap commit and pop on MRET commit | M3 | spec_miner_survey_2 |
| 23 | Trap Redirection & MRET Semantics | Models vectored mtvec (base + cause*4) vs direct mtvec (base) and MRET context restore | M3 | spec_miner_survey_2 |
| 24 | Peripheral Register Predictor | Independent register state checker flagging unexpected MMIO read values with expected vs actual | M3 | spec_miner_survey_2 |
| 25 | Interrupt Predictor | Independent interrupt checker flagging out-of-order grants, illegal preemption, shadow stack overflow | M3 | spec_miner_survey_2 |
| 26 | AXI4-Lite Protocol SVAs | Formal SVAs checking AW/W/B/AR/R handshakes, stability during stall, and address alignment | M2 | explorer_survey_3 |
| 27 | APB Protocol SVAs | Formal SVAs checking PSEL one-hot, setup-to-access 2-phase timing, and control stability | M2 | explorer_survey_3 |
| 28 | End-to-End MMIO Path Scoreboard | Matches LSU reqs to AXI beats and APB slot transfers, verifying addr translation, strobe, latency | M2 | explorer_survey_3 |
| 29 | First-Fatal Blame Engine | 7-layer hierarchy (L1..L7), blame absorption, lower-layer reassignment, downstream suppression | M2 | explorer_survey_3 |
| 30 | 1-Page Markdown Failure Report | Structured diagnostic report: blame layer, check ID, APB slot, exp vs act, last 10 disasm instrs, ring buffers | M2 | explorer_survey_3 |
| 31 | RV32IM_Zicsr Disassembler | Disassembly decoder (step4_disasm.sv) converting raw instruction words to assembly mnemonics & symbols | M2 | explorer_survey_3 |
| 32 | Remote VCS/Xcelium Flow Setup | Filelists and environment alignment for remote VCS U-2023.03 and Xcelium 22.09 (soc_verification.f, run_vcs.sh) | M4 | explorer_survey_3 |
| 33 | Local Vivado XSim Flow Fix | Genuine execution in run_regression.ps1 (xvlog, xelab, xsim), updated soc_verification.prj with monitors | M4 | explorer_survey_3 |
| 34 | Stage 1 Proof: Hello World | Proves crt0.s, link.ld, isolated DSRAM mailbox console streaming, and CMD_PASS | M5 | explorer_survey_3 |
| 35 | Stage 2 Proof: Watchdog & Freeze | Proves 1M-cycle timeout, buffer freeze, last PC capture, and blame engine report | M5 | explorer_survey_3 |
| 36 | Stage 3 Proof: Monitor Count | Proves exact count of 20 retired instructions and 20 LSU stores with 0 spurious bus events | M5 | explorer_survey_3 |
| 37 | Stage 4 Proof: Fault Injection | Proves unmapped APB gap access (0x4000_3800), DECERR, Load Access Fault trap, handler adjustment | M5 | explorer_survey_3 |
| 38 | Stage 5 Proof: Register Sweep | Proves 32-bit aligned MMIO read sweep confirming default hardware reset values across all APB IPs | M5 | explorer_survey_3 |
| 39 | Stage 6 Proof: Polled Peripherals | Proves UART loopback, Timer 0 progress, GPIO atomic bit ops, SPI transfer, and I2C recovery | M5 | explorer_survey_3 |
| 40 | Stage 7 Proof: Nested Interrupts | Proves 2-level preemption, canary register integrity across 5 ISR invocations, 0 GPR corruption | M5 | explorer_survey_3 |
| 41 | Vacuous Pass Prevention Guard | Multi-point check: CMD_PASS + retired_instr > 0 + bus transaction activity > 0 + n_find == 0 | M5 | explorer_survey_3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Passive Protocol & Pipeline Monitors with Circular Freeze Buffers | Features 1–9: 6 monitors, 64-entry ring buffers, #1step clocking, simultaneous freeze broadcast | none | PLANNED |
| M2 | Protocol SVAs, MMIO Scoreboard & First-Fatal Blame Engine | Features 26–31: AXI/APB SVAs, MMIO scoreboard, failure reporter, 1-page markdown report, disassembler | M1 | PLANNED |
| M3 | Peripheral Register Predictor & Interrupt Predictor Models | Features 10–25: register_predictor.sv, irq_predictor.sv independent reference models | M1, M2 | PLANNED |
| M4 | Dual-Simulator Build & Regression Automation | Features 32–33: soc_verification.f, soc_verification.prj, run_regression.ps1 execution fix | M1, M2, M3 | PLANNED |
| M5 | 7-Stage Proof Suite Regression & Sign-Off Verification | Features 34–41: Execute stages 1..7, vacuous pass prevention, adversarial coverage hardening | M1, M2, M3, M4 | PLANNED |

## Interface Contracts
### Monitor Fabric ↔ Failure Reporter
- Signal `freeze_monitors`: Driven by `failure_reporter.freeze_monitors`. Active-high synchronous strobe. Freezes write pointers of all 6 ring buffers (`head_ptr <= head_ptr`).
- Signal `rf_timebase_if.cycle`: 64-bit monotonically incrementing cycle counter shared across all monitors for synchronized timestamping.

### Checkers ↔ Failure Reporter
- Function `report_failure(layer, check_id, msg, pc, slot_idx, exp_str, act_str)`:
  - `layer`: 1=PROTO, 2=PATH, 3=REG, 4=FUNC, 5=IRQ, 6=CPU, 7=FW.
  - `check_id`: string (e.g. "AXIL-1001", "PATH-3007", "REG-4001", "IRQ-5002").
  - `pc`: 32-bit PC where failure or trigger occurred.
  - Behavior: If `layer < blame_layer`, blame is reassigned; if `layer >= blame_layer`, finding is tagged downstream and suppressed. Asserts `freeze_monitors = 1`.

### Predictors ↔ Scoreboard
- `register_predictor`: Sniffs LSU and APB transactions. On MMIO read completion, compares actual read data with predicted register state. Calls `report_failure(L_REG, "REG-4001", ...)` on mismatch.
- `irq_predictor`: Sniffs raw IRQ lines, `pend_q`, and trap commits. Predicts winning interrupt and class. Calls `report_failure(L_IRQ, ...)` on out-of-order grant, illegal preemption, or stack overflow.

## Code Layout
- `Verification/infrastructure/monitors/`:
  - `fetch_monitor.sv`: Fetch stage monitor with 64-entry buffer
  - `retire_monitor.sv`: Retire stage monitor with shadow PC-to-instr tracking
  - `lsu_monitor.sv`: LSU monitor with 64-entry buffer
  - `axi_lite_monitor.sv`: AXI4-Lite monitor with 64-entry buffer
  - `apb_monitor.sv`: APB 6-slot monitor with 64-entry buffer
  - `irq_monitor.sv`: IRQ monitor with 64-entry buffer
- `Verification/infrastructure/tb/`:
  - `rf_monitor_if.sv`: Passive probe interfaces with `#1step` clocking blocks
  - `rf_mon_probe.sv`: Structural probe binding taps to DUT hierarchy
  - `soc_tb_top.sv`: Top-level verification harness
- `Verification/infrastructure/checkers/`:
  - `axi_lite_protocol_sva.sv`: AXI4-Lite protocol assertions
  - `apb_protocol_sva.sv`: APB protocol assertions
  - `mmio_path_scoreboard.sv`: LSU -> AXI -> APB slot path checker
  - `register_predictor.sv`: Independent peripheral register state model
  - `irq_predictor.sv`: Independent 2-level priority class interrupt model
  - `failure_reporter.sv`: First-fatal blame engine and 1-page markdown reporter
  - `step4_disasm.sv`: RV32IM_Zicsr instruction disassembler
- `Verification/regression/`:
  - `run_regression.ps1`: Automated regression execution script
- `Verification/tests/suites/`:
  - `stage1_hello/`: Stage 1 proof suite
  - `stage2_watchdog/`: Stage 2 proof suite
  - `stage3_monitor_count/`: Stage 3 proof suite
  - `stage4_fault_inject/`: Stage 4 proof suite
  - `stage5_reg_sweep/`: Stage 5 proof suite
  - `stage6_polled_periph/`: Stage 6 proof suite
  - `stage7_nested_irq/`: Stage 7 proof suite
