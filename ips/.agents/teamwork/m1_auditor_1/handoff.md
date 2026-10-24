# Forensic Audit Report & Handoff — Milestone 1: Passive Protocol & Pipeline Monitors

## Forensic Audit Report

**Work Product**: Milestone 1 Verification Infrastructure (Monitors, Probe Interfaces, Circular Freeze Buffers, Shadow PC Tracker)  
**Profile**: General Project / Hardware SystemVerilog Verification  
**Verdict**: CLEAN  

### Phase Results
- **Hardcoded Test Results Check**: PASS — No pre-canned PASS/FAIL strings or bypass shortcuts detected in any monitor.
- **Facade Implementation Check**: PASS — All 6 monitors implement genuine parameterized 64-entry circular ring buffers with wrap-around write pointer advancement and full transaction capture.
- **Freeze Gating Check**: PASS — Synchronous continuous `freeze` broadcast verified; `freeze == 1` halts all buffer writes and pointer advancement across all 6 monitors.
- **Shadow PC Tracking Check**: PASS — Dynamic associative table `shadow_pc_imem [logic [31:0]]` populated at Fetch time and queried at Writeback retirement for disassembly without RTL modification.
- **DUT Tap Authenticity Check**: PASS — Probe interfaces bind directly to real structural signals (`u_dut.i_riscv_core.*`, `u_dut.core_axi_req.*`, `u_dut.apb_req.*`, `u_dut.*` pins) with zero intrusive overrides.
- **Independent Compilation Check**: PASS — Vivado 2022.2 `xvlog` compiles all infrastructure and top files with 0 errors.
- **Behavioral Simulation Check**: PASS — Vivado XSim smoke regression passes 39 deterministic assertions with exit code 0 and produces authentic post-mortem history dump.

---

## 1. Observation

### 1.1 Source Code Static Audit
- **`Verification/infrastructure/monitors/fetch_monitor.sv`**:
  - Line 26: `fetch_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];` (Parameter `RING_BUFFER_DEPTH = 64`).
  - Lines 44-65: Write gating:
    ```systemverilog
    if (imem_en && !stall_f && !freeze) begin
      ...
      shadow_record_fetch(pc_f, instr_f);
      head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
      total_fetches <= total_fetches + 1;
    end
    ```
  - When `freeze == 1`, ring buffer mutation and `head_ptr` increment are completely blocked.

- **`Verification/infrastructure/monitors/retire_monitor.sv`**:
  - Line 32: `retire_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];` (Parameter `RING_BUFFER_DEPTH = 64`).
  - Line 41: `wire retire_fire = valid_w && ~exc_valid_w;`
  - Line 63: `if ((retire_fire || trap_fire) && !freeze) begin`
  - Line 66: Instruction opcode resolution via shadow table:
    ```systemverilog
    resolved_instr = (instr_w != 32'h0000_0000) ? instr_w : shadow_lookup_instr(pc_w);
    ```
  - Line 87: `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`
  - Lines 89-92: `total_retired_instr` increments strictly on valid architectural commit.

- **`Verification/infrastructure/monitors/lsu_monitor.sv`**:
  - Line 29: `lsu_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];`
  - Line 51: `if (lsu_req && !lsu_stall && !freeze) begin`
  - Line 70: `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`
  - Genuinely sniffs `lsu_addr`, `lsu_wdata`, `lsu_rdata`, `lsu_be`, `lsu_we`, `lsu_err`, `pc_m`, `lsunit_m`.

- **`Verification/infrastructure/monitors/axi_lite_monitor.sv`**:
  - Line 47: `axi_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];`
  - Lines 67-68: `wire b_fire = bvalid && bready && !freeze; wire r_fire = rvalid && rready && !freeze;`
  - Lines 109-186: Single or simultaneous handshake race handling. In case of simultaneous B and R response in same clock, allocates two consecutive ring slots:
    ```systemverilog
    next_idx = (head_ptr + 1) % RING_BUFFER_DEPTH;
    head_ptr <= (head_ptr + 2) % RING_BUFFER_DEPTH;
    ```
  - Gated by `!freeze`.

- **`Verification/infrastructure/monitors/apb_monitor.sv`**:
  - Line 30: `apb_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];`
  - Line 69: `if (psel[i] && penable && pready[i] && !freeze) begin`
  - Lines 60-65: Protocol wait state accumulator `ws_cnt[s] <= ws_cnt[s] + 1;`.
  - Line 86: `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`
  - Flat bit-vector unpacking `prdata_flat[i*32 +: 32]` ensures XSim compatibility.

- **`Verification/infrastructure/monitors/irq_monitor.sv`**:
  - Line 52: `irq_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];`
  - Line 97: `task automatic push_event(...) if (!freeze) begin ... head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH; end`
  - Lines 143-198: Edge-gated pulse detection preventing buffer flooding across GPIO, I2C, SPI, UART, Timer0, Arbiter grant, Trap commit, and MRET context pop.

- **`Verification/infrastructure/tb/tb_pkg.sv`**:
  - Lines 409-423: Genuine shadow PC tracking implementation:
    ```systemverilog
    logic [31:0] shadow_pc_imem [logic [31:0]];
    function automatic void shadow_record_fetch(logic [31:0] pc, logic [31:0] instr);
      shadow_pc_imem[pc] = instr;
    endfunction
    function automatic logic [31:0] shadow_lookup_instr(logic [31:0] pc);
      if (shadow_pc_imem.exists(pc)) return shadow_pc_imem[pc];
      return 32'h0000_0000;
    endfunction
    ```

- **`Verification/infrastructure/tb/rf_mon_probe.sv` & `soc_tb_top.sv`**:
  - Probe nets wired to genuine DUT paths: `u_dut.i_riscv_core.Fetch.PCF`, `u_dut.i_riscv_core.valid_W`, `u_dut.core_axi_req.*`, `u_dut.apb_req.*`.
  - Continuous freeze fan-out: `assign fetch_if.freeze = freeze;`, etc.
  - Instantiates 6 module monitors with `RING_BUFFER_DEPTH(64)`.

### 1.2 Independent Empirical Verification
1. **Compilation Command**:
   ```powershell
   & "C:\Xilinx\Vivado\2022.2\bin\xvlog.bat" --sv -i tb -i ../.. ../../gpio-master/gpio_reg_pkg.sv tb/rf_monitor_if.sv tb/tb_pkg.sv monitors/fetch_monitor.sv monitors/retire_monitor.sv monitors/lsu_monitor.sv monitors/axi_lite_monitor.sv monitors/apb_monitor.sv monitors/irq_monitor.sv monitors/rf_monitors.sv monitors/rf_monitor_env.sv tb/rf_mon_probe.sv checkers/failure_reporter.sv checkers/mmio_path_scoreboard.sv checkers/register_predictor.sv checkers/irq_predictor.sv checkers/axi_lite_protocol_sva.sv checkers/apb_protocol_sva.sv vip/i2c_eeprom_at24c02.sv vip/spi_flash_s25fs512s.sv vip/gpio_pin_vip.sv vip/uart_pin_vip.sv tb/soc_tb_top.sv
   ```
   *Result*: Exited with code 0. Zero errors.

2. **Simulation Command**:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_smoke.ps1"
   ```
   *Result*: Exited with code 0. 39 assertions evaluated, all passed (`[SMOKE] pass M1.fetch .. F2.cycle`). Generated `monitor_postmortem.txt` with verified dynamic timestamps, accurate cross-layer joins, and zero vacuous entries.

---

## 2. Logic Chain

1. *Premise*: An integrity violation occurs if verification checks are hardcoded, buffers are facades, `freeze` is non-functional, or transactions are fabricated constants.
2. *Observation*: Every monitor file declares a real array of size `RING_BUFFER_DEPTH = 64` and advances `head_ptr` using modulo arithmetic (`(head_ptr + 1) % RING_BUFFER_DEPTH`). No hardcoded return values exist.
3. *Observation*: All ring buffer update blocks explicitly check `!freeze`. In `rf_mon_probe.sv`, `freeze` is distributed via continuous assignment (`assign *_if.freeze = freeze;`).
4. *Observation*: `tb_pkg.sv` implements an associative table `shadow_pc_imem[logic [31:0]]` storing instructions dynamically recorded by `fetch_monitor` and looked up by `retire_monitor`.
5. *Observation*: The testbench probe taps in `rf_mon_probe.sv` and `soc_tb_top.sv` are connected directly to hierarchical nets of `u_dut` (`u_dut.i_riscv_core`, `u_dut.core_axi_req`, etc.).
6. *Observation*: Independent compilation of the entire infrastructure suite and top testbench succeeded with exit code 0.
7. *Observation*: Independent simulation of the smoke test suite completed with 39 passing checks and 0 failures, producing authentic post-mortem output.
8. *Conclusion*: Milestone 1 deliverables are authentic, functionally complete, and strictly adhere to all integrity constraints.

---

## 3. Caveats

- No caveats. All 6 passive monitors, structural probes, clocking blocks, circular ring buffers, and testbenches were directly audited and verified in simulation.

---

## 4. Conclusion

The Milestone 1 work product passes all forensic criteria. There are no facade implementations, no hardcoded passes, no fabricated outputs, and no shortcuts. All 6 monitors genuinely implement 64-entry circular ring buffers with synchronous freeze gating, `#1step` non-intrusive sampling, and shadow PC instruction tracking.

**Forensic Verdict**: **CLEAN**.

---

## 5. Verification Method

To independently reproduce this audit:

1. **Static Analysis of Circular Ring Buffers & Freeze**:
   ```powershell
   Select-String -Path "Verification/infrastructure/monitors/*.sv" -Pattern "RING_BUFFER_DEPTH|freeze|head_ptr"
   ```
   Verify that all 6 monitors declare `ring_buffer`, check `!freeze`, and advance `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH`.

2. **Compilation Verification**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   & "C:\Xilinx\Vivado\2022.2\bin\xvlog.bat" --sv -i tb -i ../.. ../../gpio-master/gpio_reg_pkg.sv tb/rf_monitor_if.sv tb/tb_pkg.sv monitors/fetch_monitor.sv monitors/retire_monitor.sv monitors/lsu_monitor.sv monitors/axi_lite_monitor.sv monitors/apb_monitor.sv monitors/irq_monitor.sv monitors/rf_monitors.sv monitors/rf_monitor_env.sv tb/rf_mon_probe.sv checkers/failure_reporter.sv checkers/mmio_path_scoreboard.sv checkers/register_predictor.sv checkers/irq_predictor.sv checkers/axi_lite_protocol_sva.sv checkers/apb_protocol_sva.sv vip/i2c_eeprom_at24c02.sv vip/spi_flash_s25fs512s.sv vip/gpio_pin_vip.sv vip/uart_pin_vip.sv tb/soc_tb_top.sv
   ```
   Verify exit code 0 and 0 errors.

3. **Smoke Simulation Regression**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_smoke.ps1"
   ```
   Verify exit code 0 and that all 39 smoke checks pass.
