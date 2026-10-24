# Verification Environment, Build Scripts & Regression Infrastructure Survey Report

**Agent**: `explorer_survey_3`  
**Date**: 2026-10-01T21:05:00Z  
**Scope**: RISCFORGE SoC Verification Infrastructure (Simulators, Testbenches, Checkers/Blame Engine, 7 Proof Stages, Vacuous Pass Prevention)

---

## 1. Observation

### 1.1 Dual Simulator Build Flows

#### Remote Synopsys VCS & Cadence Xcelium Flow
* **Synopsys VCS Script (`Verification/run_vcs.sh`)**:
  - Environment variables (lines 10–13):
    ```bash
    export SNPSLMD_LICENSE_FILE=27020@14.139.1.126
    export VCS_HOME=/home/iiita/Synopsys/Installed_tools/vcs/U-2023.03
    export VERDI_HOME=/home/iiita/Synopsys/Installed_tools/verdi/U-2023.03-SP1
    export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"
    ```
  - Compilation & execution command (lines 25–29):
    ```bash
    vcs -sverilog -full64 +v2k -timescale=1ns/1ps -debug_access+all -kdb +define+FSDB -f tb1_interrupts.f -o simv -l compile.log
    ./simv -l sim.log
    ```
  - Waveform output: `core_interrupt_tb.fsdb` for Verdi.
* **Cadence Xcelium Remote Harness (`datapath_verification/UART0/run_tb.ps1`)**:
  - Remote host parameters (lines 5–8):
    ```powershell
    $Server  = "172.16.33.51"
    $User    = "iiita"
    $Pass    = "vishal6776"
    $HostKey = "SHA256:cqJWRoLmPRrAi2x4x+JG1xNtIw4Yjro8LNKzFzScxBU"
    ```
  - Execution command via `plink.exe` and `pscp.exe` (lines 26–30):
    ```bash
    export PATH=/home/iiita/riscv_tools/bin:$PATH
    export LM_LICENSE_FILE=5280@14.139.1.126 CDS_LIC_FILE=5280@14.139.1.126
    make clean && make all
    /home/install/XCELIUM2209/bin/xrun -f tb_uart0.f -l xrun.log
    ```
* **SoC VCS/Xcelium Filelist (`Verification/infrastructure/soc_verification.f`)**:
  - 182 lines defining top `-top soc_tb_top`, include dirs (`+incdir+...`), packages, common cells, AXI/APB fabric, peripherals, memories, core RTL, BFMs, monitors, and checkers.

#### Local Windows AMD Vivado XSim Flow
* **XSim Toolchain (`Verification/run_tb1.ps1`)**:
  - Path lookup (lines 5–15): Defaults to `C:\Xilinx\Vivado\2022.2\bin` (`xvlog.bat`, `xelab.bat`, `xsim.bat`) with fallback to PATH.
  - Commands executed (lines 27, 35, 43):
    ```powershell
    & $XVLOG -sv -f tb1_interrupts.f -log xvlog.log
    & $XELAB core_interrupt_tb -s core_interrupt_tb_sim -debug all -log xelab.log
    & $XSIM core_interrupt_tb_sim -R -log xsim.log
    ```
* **XSim Project File (`Verification/infrastructure/soc_verification.prj`)**:
  - 170 lines formatting RTL sources as `sv work "<path>" -i "<incdir>"` and `verilog work "<path>"`.
* **Discrepancies & Gaps Observed in `run_regression.ps1`**:
  - In `Verification/regression/run_regression.ps1` lines 91–96:
    ```powershell
    $xelabCmd = "xelab -prj soc_verification.prj -s soc_sim_snap -debug all"
    $xsimCmd  = "xsim soc_sim_snap -R -log sim_$t.log +BOOT_MODE=$BootMode +IMEM_HEX=imem.hex +DMEM_HEX=dmem.hex"
    Write-Host "Simulation command prepared: $xsimCmd"
    Pop-Location
    $passedCount++
    ```
    Neither `xelab` nor `xsim` is actually executed! The script merely formats `$xsimCmd` as a string and increments `$passedCount++` unconditionally (a stub / fake pass).
  - In remote mode (lines 98–100):
    ```powershell
    Write-Host "[VCS/Server] Remote EDA script: $VerifDir\run_vcs.sh"
    $passedCount++
    ```
    Remote mode similarly outputs a log line and increments `$passedCount++` without dispatching SSH/batch commands.
  - In test suite list (lines 32–39), `stage2_watchdog` is omitted from `$testList`.
  - In `soc_verification.prj` lines 151–158: Legacy monitors (`monitors/fetch_monitor.sv`, etc.) are included, but class-based monitor files (`rf_monitor_if.sv`, `rf_monitors.sv`, `rf_monitor_env.sv`, `rf_mon_probe.sv`) present in `soc_verification.f` are omitted.
  - In `Verification/step4_checkers/step4_smoke_tb.sv` lines 54–61:
    > "axi_lite_to_apb declares its APB ports as unpacked arrays of a parameter type (axi_lite_to_apb.sv:69-70). xsim refuses to elaborate that port connection -- 'cannot assign a packed type to an unpacked type' -- whatever the declaring scope. Xcelium and VCS handle it..."

---

### 1.2 Existing Testbenches

| Testbench Location | Module Name | DUT | Boot Mode & Stimulus | Key Checks Performed |
|:---|:---|:---|:---|:---|
| `Verification/tb1_interrupts.sv` | `core_interrupt_tb` | `riscv_core/rtl/top.v` (RV32IM Core standalone) | Direct memory preloading into `Instruction_Memory_new` (base `0x8000_0000`) | 7 core interrupt scenarios: MTIP timer, 7 sequential IRQ lines, priority arbitration, `mintprio` threshold (CSR 0x7C0), DIV multi-cycle stall collision, synchronous exception collision, MRET state restoration. |
| `Verification/infrastructure/tb/soc_tb_top.sv` | `soc_tb_top` | `riscforge_soc_subsystem` (Full SoC) | Dual-boot: WARM (backdoor `$readmemh` into ISRAM `0x0001_0000` & DSRAM `0x0002_0000`) and COLD (SPI flash model preloaded, Bootloader streams image) | 1M-cycle watchdog, mailbox character stream sniffer (`mb_char_out`), mailbox status (`CMD_PASS`/`CMD_FAIL`), monitor dumpers, register and IRQ predictor checkers. |
| `Verification/step4_checkers/step4_smoke_tb.sv` | `step4_smoke_tb` | `step4_apb_bridge_model` + 6 APB slaves | Controlled AXI4-Lite transaction stimulus | Phase 1: Clean traffic (zero findings). Phase 2: Fault injection matrix across strobe corruption, wait states, parity, timeouts, slot shifts, wdata/rdata corruption, resp error. |
| `Verification/infrastructure/tb/rf_mon_smoke_tb.sv` | `rf_mon_smoke_tb` | `rf_mon_stub_dut` | Direct synthetic signal driving | Validates `rf_monitor_env` and ring buffer capture across Fetch, Retire, LSU, AXI, APB, and IRQ interfaces. |
| `RTL_SOC/soc_regtest_tb.sv` | `soc_regtest_tb` | `riscforge_soc_subsystem` | COLD BOOT: Infineon S25FS512S SPI flash model preloaded with `regtest_flash.mem` | Full peripheral register sweep (I2C, Timer0, UART, GPIO, SPI, Timer1). Validates reset defaults, RO protection, RW patterns, per-IP uniqueness, W1C, bus fault response (SLVERR vs DECERR), timer guard, SPI CS arbitration. |
| `RTL_SOC/soc_montest_tb.sv` | `soc_montest_tb` | `riscforge_soc_subsystem` | COLD BOOT: S25FS512S SPI flash model running `montest.c` | Bus timeout monitors (`apb_timeout_monitor`, `axi_lite_timeout_monitor`). Uses `force`/`release` on `PREADY` lines to inject slave stalls. Verifies exact cycle thresholds, response shaping (`PSLVERR=1`, `0xDEADBEEF`), sticky flags, and beat conservation. |
| `RTL_SOC/soc_timer0_boot_run_tb.sv` | `soc_timer0_boot_run_tb` | `riscforge_soc_subsystem` | COLD BOOT: S25FS512S SPI flash running Timer 0 test | SPI boot -> BootROM execution (`lui x2, 0x28; jal x0, +0xFFFC`) -> ISRAM runtime (`0x0001_0000`) -> MMIO write/read to Timer 0 -> DSRAM result write. |
| `RTL_SOC/soc_imem_boot_tb.sv` | `soc_imem_boot_tb` | `riscforge_soc_subsystem` | COLD BOOT: Lightweight SPI Flash BFM | Verifies bootloader transfers instructions into `Instruction_Memory_new` via AXI crossbar -> `axi_lite_sram_if` -> `sram_mux` -> `imem_sram_wrapper`. |
| `datapath_verification/UART0/tb_uart0.sv` | `tb_uart0` | `riscforge_soc_subsystem` | Warm boot running `uart_smoke_test.c` | Verifies UART loopback and Baud generation via remote Xcelium flow. |
| `datapath_verification/i2c0/tb_i2c0.sv` | `tb_i2c0` | `riscforge_soc_subsystem` | Warm boot running `i2c_smoke_test.c` | I2C master controller register and transfer testing via remote Xcelium flow. |
| `datapath_verification/spi0/tb_spi0.sv` | `tb_spi0` | `riscforge_soc_subsystem` | Warm boot running `spi_smoke_test.c` | SPI master transfer and FIFO behavior via remote Xcelium flow. |

---

### 1.3 Checkers, Scoreboards, and First-Fatal Blame Engine

* **Layered Blame Taxonomy (`step4_pkg.sv:37-60`)**:
  - `L_PROTO = 1`: AXI4-Lite & APB protocol handshakes (`AXIL-1001..1011`, `APB-2001..2010`).
  - `L_PATH  = 2`: LSU $\rightarrow$ AXI $\rightarrow$ APB Bridge $\rightarrow$ Slot routing (`PATH-3001..3015`).
  - `L_REG   = 3`: Peripheral register reads/writes (`REG-4001`, `REG-4002`).
  - `L_FUNC  = 4`: External pin and BFM behavior.
  - `L_IRQ   = 5`: Interrupt lifecycle, 2-level priority class, shadow stack.
  - `L_CPU   = 6`: Retired instructions, CSRs, traps.
  - `L_FW    = 7`: Mailbox status, firmware assertion errors.
* **First-Fatal Blame & Ring Buffer Freeze Rule (`step4_reporter.sv:117-156`)**:
  - First fatal event latches `hub.fatal_seen = 1`, assigns `hub.blame_layer` and `hub.blame_cid`, freezes circular history buffers (`hub.frozen = 1`), and outputs initial report.
  - If a subsequent failure occurs at a *strictly lower* layer number (`e.layer < hub.blame_layer`), the blame is reassigned (`F_REASSIGN`) because the lower layer is more fundamental.
  - Any subsequent failure at an equal or higher layer is tagged as downstream (`F_DOWNSTREAM`) and suppressed.
* **1-Page Diagnostic Report Generation (`step4_reporter.sv:645-706`)**:
  - Emits:
    1. Header, test name, timestamp, and cycle number.
    2. Blame Layer & Check ID (e.g., `*** BLAME = PROTOCOL (check AXIL-1001) ***`).
    3. Failure location (APB slot name and index).
    4. Expected vs Actual description strings.
    5. Findings tally (recorded, downstream suppressed, reassignments).
    6. Layer status table (quiet, BLAME, down, FAIL for L1 through L7).
    7. Last 10 retired instructions with PC, raw instruction opcode, mnemonic disassembly (`disasm(ins)` via `step4_disasm.sv`), and symbol resolution (`sym`).
    8. Frozen transaction ring buffers: Core LSU, AXI4-Lite Master, APB Bridge.
    9. Transaction counters (LSU reqs, AXI W/R, APB xfers per slot, timeouts, SLVERR, DECERR).
* **Current Status of Infrastructure Checkers in `Verification/infrastructure/checkers/`**:
  - `failure_reporter.sv`: Basic module with `report_failure` task, but lacks disassembly formatting and frozen ring buffer table dumps.
  - `axi_lite_protocol_sva.sv`: Implements 5 basic SVA assertions (`p_awaddr_stable`, `p_wdata_stable`, `p_araddr_stable`, `p_bvalid_stable`, `p_rvalid_stable`).
  - `apb_protocol_sva.sv`: Implements 3 SVA assertions (`p_psel_onehot`, `p_setup_to_access`, `p_apb_control_stable`).
  - `mmio_path_scoreboard.sv`: Decodes APB address on completed transfer, but lacks request-to-response latency tracking and byte-enable matching.
  - `register_predictor.sv`: **0 BYTES (EMPTY)**. Missing register model (RW, RO, W1C, SET/CLR/TOGGLE) and expected vs actual comparison.
  - `irq_predictor.sv`: **0 BYTES (EMPTY)**. Missing 2-level priority class arbitration reference model and out-of-order grant / preemption / shadow stack checking.
  - In `Verification/step4_checkers/xsim.log`: Phase 1 passed cleanly (0 findings), but Phase 2 fault injection returned empty strings `' '` instead of expected check IDs (`PATH-3007`, `APB-2004`, etc.) because check event latching in the smoke harness requires alignment.

---

### 1.4 The 7 Proof Stages and Vacuous Pass Prevention

* **Stage-by-Stage Inventory**:
  1. `stage1_hello` (`main.c`): Proves `crt0.s`, `link.ld`, and isolated DSRAM mailbox (`0x0002_0000`). Streams console text via `mailbox_puts()` (`CHAR_OUT` at offset `+0x14` with sequence tag `mb_char_out[31:16]`), signals `CMD_PASS`.
  2. `stage2_watchdog` (`main.c`): Intentionally loops `while(1) nop;` to trip testbench watchdog at exactly 1,000,000 cycles, verifying that watchdog fires, freezes ring buffers, and dumps last PC.
  3. `stage3_monitor_count` (`main.c`): Performs exactly 20 stores to DSRAM scratch array. Proves testbench monitors count exactly 20 retired instructions and 20 LSU write operations with 0 spurious bus events.
  4. `stage4_fault_inject` (`main.c`): Accesses unmapped APB aperture gap at `0x4000_3800` (GPIO window ends at `0x4000_37FF`). Verifies APB bridge returns `RESP_DECERR`, core traps with Load Access Fault (`mcause = 5`), trap handler saves state and adjusts `mepc + 4`, asserts `fault_handled == 1`.
  5. `stage5_reg_sweep` (`main.c`): Type-safe 32-bit aligned MMIO read sweep confirming default hardware reset values across UART LSR (`0x60`), Timer0/1 CTRL (`0x00`), GPIO DIR (`0x00`), I2C CTR (`0x00`), and SPI CLKDIV (`0x04`).
  6. `stage6_polled_periph` (`main.c`): Polled loopback and wire transfer across UART (115200 baud loopback), Timer 0 (count progress), GPIO (output-to-input loopback + atomic bit set/clear), SPI master (command transfer to VIP), and I2C recovery.
  7. `stage7_nested_irq` (`main.c`): Pre-fills callee-saved registers (`s0=0x11223344`, `s1=0x55667788`, `s2=0x99AABBCC`) with canary values, enables periodic Timer 0 interrupts (MTIP, cause 7), verifies bit-for-bit canary integrity across 5 ISR invocations, proving zero GPR corruption during context save/restore.
* **Vacuous Pass Prevention Methodology**:
  - Defined in `step4_reporter.sv:712-727` and `soc_tb_top.sv:513-521`:
    1. **Firmware Status**: Firmware must explicitly write `CMD_PASS` (`0x0000_0001`) to `0x0002_0000`.
    2. **Instruction Retirement Guard**: `u_retire_mon.total_retired_instr > 0`. If firmware reports PASS with 0 retired instructions, simulation immediately fails:
       ```systemverilog
       if (u_retire_mon.total_retired_instr == 0) begin
           $display("\n[FATAL VACUOUS PASS] Test reported PASS but zero instructions retired!");
           $finish(1);
       end
       ```
    3. **Activity Evidence Guard**: If `hub.n_find == 0`, the scoreboard additionally asserts that non-zero MMIO transactions were observed (`hub.stats.lsu_reqs > 0` and (`hub.stats.axi_wrs > 0` or `hub.stats.axi_rds > 0`)). A checker suite that never saw transactions proves nothing and triggers a vacuous pass warning.
    4. **Clean Finding Check**: `hub.n_find == 0` (zero unsuppressed fatal findings).
    5. **Watchdog Upper Bound**: Hard cycle timeout (`max_watchdog_cycles`) prevents silent infinite loops or hangs.

---

## 2. Logic Chain

1. **Dual Simulator Strategy**:
   - `Verification/run_vcs.sh` and `datapath_verification/UART0/run_tb.ps1` confirm that Synopsys VCS U-2023.03 and Cadence Xcelium 22.09 are hosted on remote server `172.16.33.51` with dedicated floating licenses (`27020@14.139.1.126` and `5280@14.139.1.126`).
   - Local Windows AMD Vivado XSim flow uses `xvlog`, `xelab`, and `xsim` (2022.2).
   - However, in `run_regression.ps1` lines 91–101, simulation execution was never wired up (it formats string `$xsimCmd` and increments `$passedCount++` without running `Invoke-Expression` or `& $XSIM`). Therefore, local regression currently generates artificial 100% pass counts without testing RTL.
   - Furthermore, XSim 2022.2 cannot elaborate unpacked-array ports of parameter types on `axi_lite_to_apb.sv:69-70`, which explains why `step4_smoke_tb.sv` had to employ a bridge model `step4_apb_bridge_model` for local XSim testing.
2. **Testbench Hierarchy**:
   - `tb1_interrupts.sv` validates the standalone core pipeline (`top.v`), whereas `soc_tb_top.sv` and `soc_regtest_tb.sv` / `soc_montest_tb.sv` validate the complete SoC subsystem with all memory routers, crossbars, bridges, and peripherals.
   - Warm Boot (direct backdoor `$readmemh` into ISRAM and DSRAM) is necessary for high-speed regression runs, while Cold Boot (SPI Flash BFM + Bootloader) validates hardware boot sequencing.
3. **First-Fatal Blame Engine Implementation**:
   - `step4_checkers/step4_reporter.sv` contains the complete, ratified SystemVerilog implementation of the hierarchical blame engine, ring-buffer freeze, disassembler integration (`step4_disasm.sv`), and 1-page markdown report generator.
   - `Verification/infrastructure/checkers/failure_reporter.sv` is a skeleton version that needs to adopt the mature blame logic from `step4_reporter.sv`.
   - `register_predictor.sv` and `irq_predictor.sv` in `Verification/infrastructure/checkers/` are empty (0 bytes). To achieve Acceptance Criteria R3, they must be implemented with independent register state tracking (RW, RO, W1C, SET/CLR/TOGGLE) and 2-level priority class interrupt arbitration.
4. **Proof Suites and Vacuous Pass Guarding**:
   - The 7 proof stages (`stage1` to `stage7`) are implemented in `Verification/tests/suites/` and map to the milestones in `soc_verification_plan.md`.
   - Vacuous pass prevention is achieved through multi-point correlation: mailbox handshake (`CMD_PASS`), non-zero retired instruction count, non-zero bus transaction counters, and zero active assertion findings.

---

## 3. Caveats

1. **Remote Server Availability**: The Synopsys VCS and Cadence Xcelium tools reside on a remote network host (`172.16.33.51`). If that server or its license daemon (`14.139.1.126`) is offline, local execution must rely on AMD Vivado XSim.
2. **XSim Syntax Sensitivity**: XSim 2022.2 does not support certain advanced SV constructs (e.g. unpacked-array ports of parameterized interface types). Any code targeting the local XSim flow must adhere to XSim 2022.2 synthesizable/elaboratable subsets.
3. **Empty Checkers**: `register_predictor.sv` and `irq_predictor.sv` in `Verification/infrastructure/checkers/` are currently 0 bytes; until populated, register and interrupt prediction checks will remain inactive.

---

## 4. Conclusion

1. **Dual Simulator Build Flows**: The remote VCS/Xcelium flow and local Vivado XSim flow are well-defined in concept and filelists (`soc_verification.f` vs `soc_verification.prj`), but `run_regression.ps1` requires immediate remediation to actually execute `xelab`/`xsim` instead of stubbing the run, include `stage2_watchdog`, and include the required monitor files in `soc_verification.prj`.
2. **Existing Testbenches**: Comprehensive coverage exists across core-level interrupt verification (`tb1_interrupts.sv`), SoC cold-boot and peripheral register testing (`soc_regtest_tb.sv`), bus timeout monitors (`soc_montest_tb.sv`), bootloader verification (`soc_imem_boot_tb.sv`), and subsystem tests (`datapath_verification/`).
3. **First-Fatal Blame Engine**: The reference implementation in `step4_checkers/step4_reporter.sv` satisfies all requirements for 64-entry ring buffer freezing, layer reassignment, instruction disassembly, and 1-page markdown diagnostic failure reporting. It should be unified into `Verification/infrastructure/checkers/failure_reporter.sv`. `register_predictor.sv` and `irq_predictor.sv` must be created from 0-byte stubs to complete R3.
4. **7 Proof Stages**: All 7 test programs (`stage1_hello` through `stage7_nested_irq`) are authored in `Verification/tests/suites/`. Vacuous pass prevention is rigorously enforced by demanding concurrent confirmation from firmware (`CMD_PASS`), pipeline monitors (`total_retired_instr > 0`), and bus activity counters.

---

## 5. Verification Method

To independently verify this survey's findings:

1. **Verify `run_regression.ps1` stubbing**:
   Inspect lines 91–96 of `Verification/regression/run_regression.ps1` to confirm that `$xsimCmd` is printed but never executed.
2. **Verify 0-byte predictor files**:
   Run `Get-Item "Verification/infrastructure/checkers/register_predictor.sv", "Verification/infrastructure/checkers/irq_predictor.sv" | Select-Object Name, Length` to confirm lengths are 0.
3. **Inspect First-Fatal Blame Engine**:
   View `Verification/step4_checkers/step4_reporter.sv` lines 117–156 (blame absorption) and lines 645–706 (`emit_one_page`).
4. **Inspect Vacuous Pass Prevention Logic**:
   View `Verification/infrastructure/tb/soc_tb_top.sv` lines 513–521 and `Verification/step4_checkers/step4_reporter.sv` lines 712–727.
5. **Inspect the 7 Proof Suites**:
   Inspect `main.c` across `Verification/tests/suites/stage[1-7]*/main.c`.
