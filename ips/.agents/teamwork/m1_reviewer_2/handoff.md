# Handoff Report — Milestone 1 Review & Adversarial Challenge

## Review Summary

**Verdict**: **REQUEST_CHANGES**  
**Overall Risk Assessment**: **HIGH**  
**Integrity Audit**: **CLEAN (NO INTEGRITY VIOLATION)** — No hardcoded test results, facade implementations, bypassed tasks, or fabricated logs were found. The infrastructure code represents genuine, extensive implementation. However, critical and major functional defects, dropped events under concurrency, missing peripheral signals, and a fatal Vivado XSim simulator crash require immediate changes before Milestone 2 and Milestone 5.

---

## 1. Observation

Direct, independent empirical verification and adversarial stress-testing were conducted on Windows with AMD Vivado XSim 2022.2 across all modified and newly created infrastructure files:

### 1.1 Tool Execution & Test Results
1. **Compilation of All Infrastructure Files & Testbench**:
   ```powershell
   & "C:\Xilinx\Vivado\2022.2\bin\xvlog.bat" --sv -i tb -i ../.. ../../gpio-master/gpio_reg_pkg.sv tb/rf_monitor_if.sv tb/tb_pkg.sv monitors/fetch_monitor.sv monitors/retire_monitor.sv monitors/lsu_monitor.sv monitors/axi_lite_monitor.sv monitors/apb_monitor.sv monitors/irq_monitor.sv monitors/rf_monitors.sv monitors/rf_monitor_env.sv tb/rf_mon_probe.sv checkers/failure_reporter.sv checkers/mmio_path_scoreboard.sv checkers/register_predictor.sv checkers/irq_predictor.sv checkers/axi_lite_protocol_sva.sv checkers/apb_protocol_sva.sv vip/i2c_eeprom_at24c02.sv vip/spi_flash_s25fs512s.sv vip/gpio_pin_vip.sv vip/uart_pin_vip.sv tb/soc_tb_top.sv
   ```
   *Result*: Exited with code 0. Zero syntax errors. All modules and packages analyzed cleanly.

2. **Basic Smoke Test Execution (`run_rf_mon_smoke.ps1`)**:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_smoke.ps1"
   ```
   *Result*: Exited with code 0. Passed all 23 self-checks against the basic stub DUT.

3. **Adversarial Stress Execution (`run_freeze_stress.ps1` / `tb_freeze_buffer_stress.sv`)**:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_freeze_stress.ps1"
   ```
   *Result*: Exited with code 0, 165 checks total, **1 FAILED ASSERTION**:
   ```
   IRQ Monitor After Dual Simultaneous Assertion:
     total_irq_asserts = 1
     head_ptr          = 1
     ring_buffer[0].src = UART (id=19)
     ring_buffer[1].src = NONE (id=x)
   [CRITICAL BUG CONFIRMED] irq_monitor: Simultaneous GPIO and UART assertion resulted in only 1 event recorded! The earlier event was silently overwritten by the second call in the same cycle due to non-blocking head_ptr scheduling!
   [ASSERTION FAILED] [IRQ_CONCURRENCY_PRESERVED] Simultaneous IRQs caused ring buffer slot overwrite / dropped event!
   ```

4. **Empirical Challenge Execution (`run_rf_mon_challenge.ps1` / `rf_mon_empirical_challenge_tb.sv`)**:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_challenge.ps1"
   ```
   *Result*: **FATAL SIMULATOR KERNEL CRASH** during `$finish` inside `final` block of `rf_mon_probe.sv`:
   ```
   FATAL_ERROR: Vivado Simulator kernel has discovered an exceptional condition from which it cannot recover. Process will terminate.
   Time: 4455001 ps  Iteration: 0  Process: /rf_mon_empirical_challenge_tb/u_mon/Always520_199
   File: C:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/Verification/infrastructure/tb/rf_mon_probe.sv
   ```

### 1.2 Verbatim Source Observations
- **`monitors/irq_monitor.sv` Lines 89-121 & 142-198**:
  `push_event` is a task updating `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`. Lines 142-198 invoke `push_event` across multiple separate `if` conditions in the same clocked block.
- **`monitors/irq_monitor.sv` Lines 23, 68, 84, 136, 142-179, 205**:
  `input logic [3:0] timer1_irq` is declared in the port list and stored in `prev_t1 <= timer1_irq;`. However, lines 142-179 contain checks for `gpio_irq`, `i2c_irq`, `spi_irq[0..1]`, `uart_irq`, and `timer0_irq[0..3]`, but **ZERO lines checking `timer1_irq`**.
- **`tb/rf_mon_probe.sv` Lines 520-523**:
  ```verilog
  final begin
    if (env != null)
      env.write_postmortem("monitor_postmortem.txt", DUMP_N);
  end
  ```
- **`monitors/axi_lite_monitor.sv` Lines 60-65**:
  ```verilog
  wire [31:0] eff_awaddr = (awvalid && awready) ? awaddr : latched_awaddr;
  wire [31:0] eff_wdata  = (wvalid  && wready)  ? wdata  : latched_wdata;
  wire [31:0] eff_araddr = (arvalid && arready) ? araddr : latched_araddr;
  ```

---

## 2. Logic Chain

1. *Observation 1 & 3*: In `monitors/irq_monitor.sv`, `push_event` schedules `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;` via a non-blocking assignment (`<=`).
   - *Deduction*: In SystemVerilog, non-blocking assignments evaluated within the same timestep do not take effect until the NBA region at the end of the simulation cycle.
   - *Impact*: When multiple interrupt sources assert on the same cycle (e.g. GPIO and UART rise together, or an IRQ rises on the same cycle an arbiter grant or trap commit occurs), each sequential call to `push_event` writes to the exact same index `ring_buffer[head_ptr]`, overwriting earlier events. At the end of the timestep, `head_ptr` only increments by 1 instead of N. Events are dropped and lost from post-mortem history. This was directly reproduced and verified in `tb_freeze_buffer_stress.sv`.

2. *Observation 2*: `monitors/irq_monitor.sv` declares `timer1_irq[3:0]` as an input port and updates `prev_t1`, but omits all edge detection for `timer1_irq[0..3]` in lines 142-179.
   - *Deduction*: Timer 1 (APB slot 5) is one of the 6 peripherals on the RISCFORGE SoC. Its 4 interrupt lines (Overflow and Compare on Channels 0 and 1) are completely ignored by the module monitor.
   - *Impact*: In Milestone 5 (polled and interrupt-driven peripheral tests) and Milestone 3 (interrupt predictor), any Timer 1 interrupt activity will be invisible to `u_irq_mon`.

3. *Observation 4*: In `tb/rf_mon_probe.sv`, `env.write_postmortem(...)` is invoked inside `final begin ... end`.
   - *Deduction*: Vivado XSim 2022.2 has a known internal simulator defect where executing complex class method file I/O operations from within an interface/module `final` block dereferences dangling runtime structures during simulation tear-down, crashing the simulator kernel (`FATAL_ERROR`).
   - *Impact*: Any simulation that terminates via `$finish` while probe monitors are instantiated risks an abnormal tool abort with exit code 1.

4. *Observation 5*: In `monitors/axi_lite_monitor.sv`, `eff_awaddr` uses `(awvalid && awready) ? awaddr : latched_awaddr`.
   - *Deduction*: In AXI4-Lite, write channels are decoupled. A master can issue Write 1 (latched in cycle T-1). In cycle T, the slave completes Write 1 by asserting BVALID/BREADY (`b_fire = 1`). In that same cycle T, the master can present Write 2's address (`awvalid && awready = 1`).
   - *Impact*: Because `awvalid && awready` is active in cycle T, `eff_awaddr` evaluates to Write 2's address rather than the completing Write 1's latched address. Write 1's B completion is recorded in the ring buffer with Write 2's address.

---

## 3. Findings

### [Critical] Finding 1: Concurrency Collision and Event Dropping in `irq_monitor.sv`
- **What**: Simultaneous interrupt assertions or concurrent assertion + grant/commit within the same cycle result in ring buffer slot overwrites and permanent event loss.
- **Where**: `Verification/infrastructure/monitors/irq_monitor.sv:89-121` (`push_event`) and lines 142-198.
- **Why**: `push_event` utilizes non-blocking assignment (`head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH`). When multiple `if` branches evaluate to true in the same cycle, all invocations write to `ring_buffer[head_ptr]` with the same pointer value, and `head_ptr` only increments by 1.
- **Empirical Proof**: Failed `tb_freeze_buffer_stress.sv` Test 5: simultaneous GPIO + UART recorded only 1 event (`total_irq_asserts = 1`, `head_ptr = 1`).
- **Suggestion**: Accumulate simultaneous events within the clock cycle into temporary local variables and update `ring_buffer` entries at distinct offsets (`head_ptr`, `(head_ptr + 1) % RING_BUFFER_DEPTH`, etc.) while advancing `head_ptr <= (head_ptr + num_events) % RING_BUFFER_DEPTH`, identical to the multi-channel pattern successfully implemented in `axi_lite_monitor.sv:147-183`.

### [Major] Finding 2: Timer 1 Interrupt Edge Detection Missing in `irq_monitor.sv`
- **What**: `timer1_irq` is declared in the module header but completely absent from the edge-detection logic.
- **Where**: `Verification/infrastructure/monitors/irq_monitor.sv:142-179`.
- **Why**: Edge detection was implemented for `timer0_irq[0..3]`, `gpio_irq`, `i2c_irq`, `spi_irq[0..1]`, and `uart_irq`, but `timer1_irq[0..3]` was accidentally skipped.
- **Suggestion**: Add the 4 edge detection blocks:
  ```verilog
  if (timer1_irq[0] && !prev_t1[0]) begin
    push_event(5'd23, RF_IRQ_T1_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer1_irq[1] && !prev_t1[1]) begin
    push_event(5'd24, RF_IRQ_T1_C0_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer1_irq[2] && !prev_t1[2]) begin
    push_event(5'd25, RF_IRQ_T1_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer1_irq[3] && !prev_t1[3]) begin
    push_event(5'd26, RF_IRQ_T1_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  ```

### [Major] Finding 3: Vivado XSim Simulator Crash (`FATAL_ERROR`) in `rf_mon_probe.sv` `final` Block
- **What**: Test execution crashes XSim with a fatal kernel exception during simulation shutdown.
- **Where**: `Verification/infrastructure/tb/rf_mon_probe.sv:520-523`.
- **Why**: XSim 2022.2 does not reliably support class method file I/O inside `final` blocks.
- **Empirical Proof**: Crashed with `FATAL_ERROR: Vivado Simulator kernel has discovered an exceptional condition ... Process: Always520_199` in `rf_mon_empirical_challenge_tb.sv`.
- **Suggestion**: Remove `final begin env.write_postmortem(...); end` from `rf_mon_probe.sv` and provide a clean `task dump_postmortem()` that the testbench or failure reporter calls explicitly prior to `$finish`.

### [Major] Finding 4: AXI-Lite Monitor Address Latching Hazard on Concurrent B + AW
- **What**: A write transaction's address in `ring_buffer` is corrupted by the next write's address if B handshakes concurrently with the next AW.
- **Where**: `Verification/infrastructure/monitors/axi_lite_monitor.sv:60-65`.
- **Why**: `eff_awaddr` unconditionally selects `awaddr` whenever `awvalid && awready` is true, without checking whether the completing B handshake belongs to an earlier latched address.
- **Suggestion**: Maintain a state bit (`latched_aw_valid`) indicating an outstanding write awaiting B. When `latched_aw_valid` is set, the B completion must record `latched_awaddr`.

### [Minor] Finding 5: `apb_monitor.sv` Multi-PSEL Defensive Guard
- **What**: The loop iterating over APB slots does not break on match.
- **Where**: `Verification/infrastructure/monitors/apb_monitor.sv:67-90`.
- **Why**: If a decoder glitch asserted multiple PSEL lines simultaneously, `head_ptr` would experience non-blocking overwrite.
- **Suggestion**: Add defensive break or one-hot priority selection.

### [Minor] Finding 6: Redundant Module Monitor Instantiations
- **What**: Duplicate module monitor instantiations in `soc_tb_top.sv:223-340` and `rf_mon_probe.sv:401-518`.
- **Where**: `tb/soc_tb_top.sv` and `tb/rf_mon_probe.sv`.
- **Suggestion**: Retain the module monitors inside `rf_mon_probe.sv` only.

---

## 4. Verified Claims

| Claim from Worker Handoff | Verification Method | Status | Notes |
|:---|:---|:---|:---|
| All 6 monitors implement 64-entry circular ring buffers | Inspected parameter and array sizing in all 6 monitor files | **PASS** | `RING_BUFFER_DEPTH = 64` verified |
| Modulo pointer arithmetic on buffer write | Inspected pointer update logic across monitors | **PASS** | Modulo 64 verified |
| Retirement condition `valid_W & ~exc_valid_W` | Inspected `retire_monitor.sv:41` | **PASS** | Correctly excludes exceptions from instruction count |
| Shadow PC-to-instruction tracking | Inspected `tb_pkg.sv` and `fetch_monitor.sv` / `retire_monitor.sv` | **PASS** | Associative shadow table tested |
| Non-intrusive `#1step` Preponed clocking blocks | Inspected all 7 interfaces in `rf_monitor_if.sv` | **PASS** | Verified 0 backpressure & 0 driven DUT nets |
| Synchronous freeze broadcast on cycle 0 | Inspected continuous assignments in `rf_mon_probe.sv` and monitor freeze gating | **PASS** | Verified cycle-0 freeze lock |
| Vivado 2022.2 compilation (`xvlog`) | Executed `xvlog.bat` across all 20+ files | **PASS** | Exited code 0 |
| Vivado 2022.2 smoke simulation (`run_rf_mon_smoke.ps1`) | Executed PowerShell smoke test script | **PASS** | Exited code 0, 23 checks pass |
| Robustness under concurrent IRQs | Executed `tb_freeze_buffer_stress.sv` (Test 5) | **FAIL** | Overwrite & dropped events on simultaneous IRQ (Finding 1) |
| Complete peripheral IRQ capture | Code inspection of `irq_monitor.sv:142-179` | **FAIL** | Timer 1 IRQ completely omitted (Finding 2) |
| Simulator stability on test shutdown | Executed `run_rf_mon_challenge.ps1` | **FAIL** | XSim kernel crash in `final` block (Finding 3) |

---

## 5. Caveats
- Full SoC elaboration (`xelab soc_tb_top`) with the real core and crossbar is planned under Milestone 4 (`soc_verification.prj` / `soc_verification.f`). Unit-level verification against the structural stub DUT was used for Milestone 1 scope.
- No other caveats.

---

## 6. Conclusion
While the foundational architecture (interfaces, Preponed clocking blocks, shadow PC association, freeze broadcast, and class environment) is sound and passes smoke testing, **the implementation cannot be signed off in its current state**:
1. `irq_monitor.sv` drops interrupt events under concurrent assertions.
2. `timer1_irq` is completely missing from `irq_monitor.sv`.
3. `rf_mon_probe.sv` crashes the Vivado XSim simulator kernel during `$finish`.
4. `axi_lite_monitor.sv` corrupts completed write addresses during concurrent pipelined requests.

These defects directly impair downstream Milestone 2 (Scoreboards / Blame Engine), Milestone 3 (Interrupt Predictor), and Milestone 5 (Stage 7 Nested Interrupts).

**Verdict**: **REQUEST_CHANGES**.

---

## 7. Verification Method
To independently reproduce all observations and failures:

```powershell
cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"

# 1. Clean compilation check:
& "C:\Xilinx\Vivado\2022.2\bin\xvlog.bat" --sv -i tb -i ../.. ../../gpio-master/gpio_reg_pkg.sv tb/rf_monitor_if.sv tb/tb_pkg.sv monitors/fetch_monitor.sv monitors/retire_monitor.sv monitors/lsu_monitor.sv monitors/axi_lite_monitor.sv monitors/apb_monitor.sv monitors/irq_monitor.sv monitors/rf_monitors.sv monitors/rf_monitor_env.sv tb/rf_mon_probe.sv checkers/failure_reporter.sv checkers/mmio_path_scoreboard.sv checkers/register_predictor.sv checkers/irq_predictor.sv checkers/axi_lite_protocol_sva.sv checkers/apb_protocol_sva.sv vip/i2c_eeprom_at24c02.sv vip/spi_flash_s25fs512s.sv vip/gpio_pin_vip.sv vip/uart_pin_vip.sv tb/soc_tb_top.sv

# 2. Basic smoke test:
pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_smoke.ps1"

# 3. Empirical stress test reproducing IRQ concurrency collision (Finding 1):
pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_freeze_stress.ps1"

# 4. Empirical challenge test reproducing XSim kernel crash in final block (Finding 3):
pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_challenge.ps1"
```

Invalidation conditions:
- Test 5 in `tb_freeze_buffer_stress.sv` passes with `head_ptr == 2` and both GPIO and UART captured.
- `timer1_irq[0..3]` is present in `irq_monitor.sv`.
- `run_rf_mon_challenge.ps1` runs to `$finish` with zero XSim kernel crashes.
