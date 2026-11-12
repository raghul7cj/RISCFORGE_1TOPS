# RISCFORGE SoC Verification Infrastructure: Final Implementation Plan

## [Goal Description]

This document establishes the comprehensive, granular implementation and sign-off plan for the **RISCFORGE single-core RV32IM_Zicsr SoC verification infrastructure**.

The infrastructure follows the **"Firmware is Stimulus, Testbench is the Judge"** methodology specified in the SoC Verification Infrastructure: Integration Guide, enhanced with architectural insights and gap resolutions from multi-agent codebase analysis.

```mermaid
flowchart TB
    subgraph Toolchain_Harness ["Stage 1 & 5: Bare-Metal C Toolchain & Mailbox"]
        direction TB
        C_Tests["C / ASM Test Programs"] --> GCC["RISC-V GCC (-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -mno-relax)"]
        GCC --> Linker["link.ld (Isolated .mailbox @ 0x0002_0000)"]
        Linker --> ELF["Target ELF"]
        ELF --> HexGen["elf_to_hex.py (Bounded ISRAM / DSRAM Slices)"]
        HexGen --> HexFiles["imem.hex / dmem.hex"]
        ELF --> DisGen["Disassembly & PC Symbol Map"]
    end

    subgraph Simulation_Harness ["Stage 2 & 8: Dual-Runner Simulation Harness"]
        direction TB
        subgraph Simulators ["Dual Simulation Targets"]
            VCS["Server Mode: Synopsys VCS / Cadence Xcelium (run_vcs.sh)"]
            XSim["Local Windows Mode: AMD Vivado XSim (xvlog / xelab / xsim)"]
        end
        HexFiles --> BackdoorLoader["Warm Boot: Backdoor SRAM Preloader ($readmemh)"]
        BackdoorLoader --> SimTop["Unified Testbench Shell (soc_tb_top.sv)"]
        Simulators --> SimTop
    end

    subgraph DUT_Subsystem ["DUT: riscforge_soc_subsystem (RV32IM_Zicsr)"]
        direction TB
        Core["RV32IM_Zicsr Core (5-Stage Pipeline)"]
        MemRouter["hybrid_mem_interface.sv"]
        ISRAM["32 KB ISRAM (0x0001_0000)"]
        DSRAM["32 KB DSRAM (0x0002_0000)"]
        XBAR["2x3 AXI4-Lite Crossbar (axi_lite_xbar.sv)"]
        Bridge["AXI-to-APB Bridge (axi_lite_to_apb.sv)"]
        Peripherals["APB Peripherals (I2C, Timer0/1, UART, GPIO, SPI)"]
        TimeoutMon["Bus Timeout Monitors (apb_timeout / axi_timeout)"]

        Core -->|Fetch| ISRAM
        Core -->|LSU Direct| MemRouter -->|DSRAM Direct (1-cyc read / 0-cyc write)| DSRAM
        MemRouter -->|MMIO (0x4000_0000 - 0x4FFF_FFFF)| XBAR
        XBAR --> Bridge --> Peripherals
        Bridge --> TimeoutMon
    end

    subgraph Monitors_Checkers ["Stage 3, 4 & 7: Layered Passive Monitors & Checkers"]
        direction TB
        FetchMon["Fetch Monitor"]
        RetireMon["Retire Monitor (RVFI)"]
        LSUMon["LSU Monitor"]
        AXIMon["AXI4-Lite Monitor"]
        APBMon["APB 6-Slot Monitor"]
        IRQMon["Interrupt Lifecycle Monitor"]
        PinBFMs["Lightweight SV BFMs (UART, I2C EEPROM, SPI Flash, GPIO)"]

        SVA["Protocol Assertions (AXI / APB SVA)"]
        Scoreboard["MMIO Path Scoreboard (Core -> AXI -> APB Slot)"]
        PreemptCheck["2-Level Preemption & Shadow Stack Checker"]
        BlameEngine["First-Fatal Blame Engine & Ring-Buffer Freeze"]
        Reporter["1-Page Diagnostic Markdown Reporter"]

        FetchMon & RetireMon & LSUMon & AXIMon & APBMon & IRQMon & PinBFMs --> SVA & Scoreboard & PreemptCheck
        SVA & Scoreboard & PreemptCheck --> BlameEngine --> Reporter
    end

    SimTop --> DUT_Subsystem
    DUT_Subsystem --> Monitors_Checkers
```

---

## User Review Required & Alignment Summary

> [!IMPORTANT]
> **Key Architectural Decisions Finalized via /grill-me Alignment**:
> 1. **Lightweight SystemVerilog BFMs**: External peripheral responders are built strictly as lightweight SystemVerilog BFMs (e.g. `spi_flash_s25fs512s.sv`, `i2c_eeprom_at24c02.sv`, `uart_pin_vip.sv`, `gpio_pin_vip.sv`), avoiding heavy VIP frameworks.
> 2. **Warm Boot Primary**: All peripheral, driver, memory, and interrupt test suites run under **Warm Boot** (direct SRAM preloading at $t=0$), bypassing the SPI bootloader for maximum simulation speed. Cold boot is retained as an independent bootloader sign-off suite.
> 3. **Isolated DSRAM Mailbox (`0x0002_0000`)**: The mailbox layout is isolated in DSRAM via a dedicated `(NOLOAD)` linker section, preventing `.rodata`/`.data` clobbering while providing zero-overhead character streaming (`CHAR_OUT`).
> 4. **Layered Monitors & 64-Deep History Ring Buffers**: Passive taps capture transactions across all layers. On any failure, all ring buffers freeze simultaneously, generating a 1-page diagnostic report with the last 10 disassembled instructions.
> 5. **Two-Phase Driver / ISR Validation**: Peripheral drivers are validated first via polled loopback at the pins, followed by interrupt-driven suites with register canary tests proving zero GPR corruption across nested traps.
> 6. **Dual Simulation Target**: Synopsys VCS (`run_vcs.sh`) / Cadence Xcelium (`soc_regtest.f`) when connected to the remote EDA server; AMD Vivado XSim (`run_tb1.ps1` / `/vivado` flow) locally on Windows when the server is down.

---

## Multi-Agent Gap Analysis & Subsystem Specifications

The following gap matrix captures the architectural findings from the parallel subagent audits:

### 1. Memory Routing & Bus Error Mapping

| Subsystem / Region | Decoding Component | Response Behavior | Verification Checkpoint |
|:---|:---|:---|:---|
| **Direct DSRAM** (`0x0002_0000–0x0002_7FFF`) | `hybrid_mem_interface` | Direct connection to `sram_mux` Port 0. 1-cycle stall on read; 0-cycle stall on write. | Verify back-to-back load/store pipeline forwarding without bubbles. |
| **MMIO Aperture** (`0x4000_0000–0x4FFF_FFFF`) | `hybrid_mem_interface` | Generates AXI4-Lite transaction to `axi_lite_xbar`. Stalls core until `BVALID`/`RVALID`. | Verify core stall holds IF/ID/EX/MEM cleanly until completion. |
| **Unmapped Internal Holes** (`0x0000_0000–0x0001_FFFF`, `0x0002_8000–0x3FFF_FFFF`, `0x5000_0000–0xFFFF_FFFF`) | `hybrid_mem_interface` | Combinational `addr_fault = 1`, `mem_err = 1` (0 AXI cycles). | Core traps immediately with Load/Store Access Fault (`mcause=5/7`), `mtval = fault_addr`. |
| **Unmapped APB Holes** (`0x4000_3800–0x4000_3FFF`, `0x4000_6000–0x4FFF_FFFF`) | `axi_lite_to_apb` | APB Bridge returns AXI `RESP_DECERR` (`rdata = 0xDEA110C8`). | Core traps with `mcause=5/7`; verifies bridge error conversion. |
| **Bus Timeout Injection** (`PREADY=0 > Timeout`) | `apb_timeout_monitor` | Synthetic `PSLVERR=1`, `rdata = 0xDEADBEEF`, sticky flag asserted. | Core traps with `mcause=5/7`; monitor enters `StDrain` to swallow late response safely. |
| **Sub-word MMIO on APB3 Peripherals** | `ls_unit.v`, `axi_lite_to_apb.sv` | Legacy APB3 IPs (UART, Timers, I2C, SPI) lack `PSTRB` port; `gpio_apb_wrap` has `PSTRB`. | Firmware must use strict 32-bit aligned accesses (`REG32_WRITE`/`REG32_READ`). |

---

### 2. Interrupt Architecture, Preemption & Shadow Stack

The core implements a **Two-Level Priority Class Preemption Architecture** with a 2-deep hardware shadow stack:

```
+-------------------------------------------------------------------------------------------------------+
| Priority Order: Class 2 (Real-Time) > Class 1 (Streaming) > Class 0 (Background)                     |
+---------+--------------------+---------------+---------+-----------+----------------------------------+
| Class   | Peripheral Source  | Fast IRQ Pin  | mcause  | mip Bit   | Arbitration & Preemption Rule    |
+---------+--------------------+---------------+---------+-----------+----------------------------------+
| Class 2 | SPI EOT / Watchdog | fast_irq_i[11]| 27      | mip[27]   | Priority 1 (Strict Fixed)        |
| Class 2 | Timer 0 (Ch0 Match)| timer_irq_i   | 7 (MTIP)| mip[7]    | Priority 2 (Strict Fixed)        |
+---------+--------------------+---------------+---------+-----------+----------------------------------+
| Class 1 | UART Rx/Tx         | fast_irq_i[3] | 19      | mip[19]   | Round-Robin (rr_ptr_c1 on commit)|
| Class 1 | SPI Rx Threshold   | fast_irq_i[2] | 18      | mip[18]   | Round-Robin (rr_ptr_c1 on commit)|
+---------+--------------------+---------------+---------+-----------+----------------------------------+
| Class 0 | I2C Byte Done      | fast_irq_i[1] | 17      | mip[17]   | Round-Robin (rr_ptr_c0 on commit)|
| Class 0 | GPIO Pin / Global  | fast_irq_i[0] | 16      | mip[16]   | Round-Robin (rr_ptr_c0 on commit)|
+---------+--------------------+---------------+---------+-----------+----------------------------------+
```

- **Hardware Shadow Stack**: `mepc_stack[1:0]`, `mcause_stack[1:0]`, `mpie_stack[1:0]`, `class_stack[1:0]`.
- **Preemption Rule**: Allowed only if `raw_winner_class > cur_class_i` and `nest_depth < 2`.
- **RTL Port Note**: In `top.v`, pins `fast_irq_i[10:4]` (Timer 1 lines and Timer 0 secondary lines) are unmapped in the current core top wrapper; Timer 0 primary (`timer_irq_i`), UART (`fast_irq_i[3]`), SPI (`fast_irq_i[2]`), I2C (`fast_irq_i[1]`), and GPIO (`fast_irq_i[0]`) are fully active.

---

## Stage-by-Stage Granular Verification Plan

```
rtl/ips/
├── Verification/
│   ├── infrastructure/
│   │   ├── tb/
│   │   │   ├── soc_tb_top.sv           # Unified SystemVerilog top-level testbench
│   │   │   └── tb_pkg.sv               # Constants, structs, and transaction definitions
│   │   ├── monitors/
│   │   │   ├── fetch_monitor.sv        # IF stage sniffer with 64-entry ring buffer
│   │   │   ├── retire_monitor.sv       # WB stage / RVFI sniffer with ring buffer
│   │   │   ├── lsu_monitor.sv          # LSU load/store sniffer with ring buffer
│   │   │   ├── axi_lite_monitor.sv     # 5-channel AXI4-Lite monitor
│   │   │   ├── apb_monitor.sv          # 6-slot APB transfer monitor
│   │   │   └── irq_monitor.sv          # Interrupt lifecycle & shadow stack monitor
│   │   ├── checkers/
│   │   │   ├── axi_lite_protocol_sva.sv# AXI4-Lite protocol formal assertions
│   │   │   ├── apb_protocol_sva.sv     # APB protocol formal assertions
│   │   │   ├── mmio_path_scoreboard.sv # Core LSU -> AXI -> APB path scoreboard
│   │   │   └── failure_reporter.sv     # First-fatal blame engine & markdown reporter
│   │   ├── vip/
│   │   │   ├── uart_pin_vip.sv         # Lightweight UART BFM (framing & loopback)
│   │   │   ├── gpio_pin_vip.sv         # Lightweight GPIO BFM (pin loopback)
│   │   │   ├── i2c_eeprom_at24c02.sv   # AT24C02 I2C EEPROM slave BFM
│   │   │   └── spi_flash_s25fs512s.sv  # S25FS512S SPI Flash BFM
│   │   └── soc_verification.f         # Multi-simulator compilation filelist
│   ├── tests/
│   │   ├── bsp/
│   │   │   ├── crt0.s                  # Clean C runtime startup with exit handling
│   │   │   ├── link.ld                 # Linker script with isolated .mailbox (0x0002_0000)
│   │   │   ├── mailbox.h               # Mailbox struct & streaming char API
│   │   │   ├── soc_regs.h              # MMIO address definitions & 32-bit access macros
│   │   │   ├── test_harness.h          # TEST_START, TEST_ASSERT, TEST_PASS macros
│   │   │   ├── trap_handler.s          # Context-saving machine-mode trap handler
│   │   │   └── isr_dispatch.c/.h       # C ISR dispatch table
│   │   ├── drivers/
│   │   │   ├── uart_driver.c/.h        # 16550 APB UART driver
│   │   │   ├── timer_driver.c/.h       # APB Timer 0/1 driver
│   │   │   ├── i2c_driver.c/.h         # APB I2C Master driver
│   │   │   ├── gpio_driver.c/.h        # 32-bit GPIO driver
│   │   │   └── spi_driver.c/.h         # APB SPI Master driver
│   │   └── suites/
│   │       ├── stage1_hello/           # Stage 1: Hello mailbox proof test
│   │       ├── stage2_watchdog/        # Stage 2: Watchdog timeout & trap test
│   │       ├── stage3_monitor_count/   # Stage 3: LSU & AXI transaction count test
│   │       ├── stage4_fault_inject/    # Stage 4: DECERR & bus fault injection test
│   │       ├── stage5_reg_sweep/       # Stage 5: All peripheral register reset sweep
│   │       ├── stage6_polled_periph/   # Stage 6: Polled wire loopback tests
│   │       └── stage7_nested_irq/      # Stage 7: Register canary & 3-level preemption
│   └── regression/
│       ├── run_regression.ps1          # Automated regression runner (VCS & Vivado)
│       └── elf_to_hex_clean.py         # Bounds-checked ELF to hex memory converter
```

---

### Stage 1: Toolchain, Startup Code (`crt0.s`), Linker Script (`link.ld`), and Mailbox Protocol

- **Linker Script (`link.ld`)**:
  - `ISRAM (rx) : ORIGIN = 0x00010000, LENGTH = 32K`
  - `DSRAM (rwx) : ORIGIN = 0x00020000, LENGTH = 32K`
  - `.mailbox (NOLOAD)` at `0x0002_0000`–`0x0002_003F` (64 bytes reserved).
  - `.rodata` and `.data` placed starting at `0x0002_0040`.
- **Startup (`crt0.s`)**:
  - Sets `sp = 0x0002_8000`, zeroes `.bss` without touching `.mailbox`, sets `mtvec = trap_entry`, calls `main()`.
  - Writes return value from `main()` to mailbox (`CMD_PASS` or `CMD_FAIL`) and enters `wfi`.
- **Proof Criteria**: `stage1_hello/main.c` streams characters through `CHAR_OUT` and sets `CMD_PASS`. Simulation ends with code 0.

---

### Stage 2: SoC Testbench Shell, Memory Preload & Dual-Boot Manager

- **Testbench Top (`soc_tb_top.sv`)**:
  - Drives `clk_i` (100 MHz, 10ns period) and active-low resets (`hard_rst_ni`, `soft_rst_ni`).
  - Warm Boot: Backdoors `imem.hex` into `Instruction_Memory_new.mem_array` and `dmem.hex` into `u_dsram.mem`. Core runs instantly at $t=0$.
  - Watchdog timer: Configurable max cycles (default 1,000,000). On expiration, dumps last 10 retired instructions and raises `ERR_TIMEOUT`.
- **Proof Criteria**: Minimal PASS test exits cleanly; an intentional infinite loop `while(1);` trips the watchdog at the exact cycle limit.

---

### Stage 3: Passive Protocol & Pipeline Monitors with Cyclic Ring Buffers

- **Monitors**:
  - `fetch_monitor.sv`: Samples `imem_sram_addr`, `imem_sram_rdata`, `imem_sram_en`, `stall_f`.
  - `retire_monitor.sv`: Samples `PC_W`, `InstrW`, `rd_W`, `ResultW`, `RegWriteW`, `trap_taken`.
  - `lsu_monitor.sv`: Samples `lsu_mem_addr`, `lsu_mem_wdata`, `lsu_mem_rdata`, `lsu_mem_be`, `lsu_mem_we`.
  - `axi_lite_monitor.sv`: Tracks 5-channel AXI4-Lite handshakes.
  - `apb_monitor.sv`: Tracks all 6 APB peripheral slots.
  - `irq_monitor.sv`: Tracks IRQ lifecycle and shadow stack preemption levels.
- **64-Entry Ring Buffers**: Each monitor maintains circular history buffers that freeze simultaneously on any failure.
- **Proof Criteria**: A known loop of 20 stores produces exactly 20 LSU write transactions and 0 spurious bus events.

---

### Stage 4: Protocol Checkers (SVA), End-to-End MMIO Path Scoreboard & Failure Reporter

- **SVA Checkers**:
  - `axi_lite_protocol_sva.sv`: `AWVALID`, `WVALID`, `ARVALID`, `BVALID`, `RVALID` stability and handshake rules.
  - `apb_protocol_sva.sv`: One-hot `PSEL`, setup $\rightarrow$ access phase transitions, control stability.
- **MMIO Path Scoreboard (`mmio_path_scoreboard.sv`)**:
  - Verifies that Core LSU store $\rightarrow$ `hybrid_mem_interface` $\rightarrow$ AXI crossbar $\rightarrow$ APB bridge maps to the exact APB slot [0..5] per the address map.
- **Hierarchical Blame Failure Reporter (`failure_reporter.sv`)**:
  - Blames the lowest architectural layer first: **Protocol (1) $\rightarrow$ Path (2) $\rightarrow$ Register (3) $\rightarrow$ Pin (4) $\rightarrow$ IRQ (5) $\rightarrow$ Firmware (6)**.
  - Generates a 1-page markdown diagnostic report (`failure_report.md`).
- **Proof Criteria**: Accessing unmapped APB hole `0x4000_3800` triggers `RESP_DECERR` and generates a 1-page failure report naming the exact check ID.

---

### Stage 5: Bare-Metal C Test Harness & Type-Safe Register Access Layer (RAL)

- **Test Harness (`test_harness.h`)**:
  - `REG32_WRITE(addr, val)` / `REG32_READ(addr)` enforcing 32-bit volatile accesses.
  - `TEST_START(id, name)`, `TEST_ASSERT(cond, err)`, `TEST_ASSERT_EQ(exp, got, err)`, `TEST_PASS()`, `TEST_FAIL(err)`.
- **Proof Criteria**: Reset value sweep test (`stage5_reg_sweep/main.c`) reads every peripheral register and confirms hardware defaults.

---

### Stage 6: Peripheral C Drivers & External BFM Models

- **C Drivers (`Verification/tests/drivers/`)**:
  - `uart_driver.c/.h`: Baud divisor, 8N1, polled TX, polled RX with cycle timeout.
  - `timer_driver.c/.h`: Prescaler, counter, compare, start/stop, interrupt clear.
  - `i2c_driver.c/.h`: Prescaler, START/STOP, byte write/read with ACK polling.
  - `gpio_driver.c/.h`: Direction, data in/out, interrupt type/polarity.
  - `spi_driver.c/.h`: Clock divider, CS select, TX/RX FIFO access, command transfer.
- **Lightweight SystemVerilog BFMs**:
  - `uart_pin_vip.sv`: Passive framing monitor and configurable loopback.
  - `gpio_pin_vip.sv`: Output-to-input loopback and external pulse drive.
  - `i2c_eeprom_at24c02.sv`: 2Kbit I2C EEPROM slave BFM at address `0x50`.
  - `spi_flash_s25fs512s.sv`: SPI NOR flash BFM with memory preloading.
- **Proof Criteria**: `stage6_polled_periph/main.c` completes polled loopback and transfer verification across all peripherals at the physical pins.

---

### Stage 7: Machine-Mode Trap/ISR Framework & Preemption Verification

- **Trap Handler (`trap_handler.s`)**:
  - Saves all 16 caller-saved registers (`x1`, `x5-x7`, `x10-x17`, `x28-x31`), `mepc`, and `mcause`.
  - Calls `c_trap_handler()` in `isr_dispatch.c`.
  - Restores registers and executes `mret`.
- **Hardware Preemption & Canary Verification**:
  - **Register Canary Test**: Pre-fills `x1..x31` with unique bitmasks before IRQ trigger, verifying bit-for-bit restoration after ISR return.
  - **3-Level Preemption Stress Test**: Triggers Class 0 (GPIO) $\rightarrow$ Preempts with Class 1 (UART) $\rightarrow$ Preempts with Class 2 (Timer 0) $\rightarrow$ Pops via 3 sequential `mret`s to Main thread.
  - **Pipeline Hazard Tests**: High-priority IRQ asserting during multi-cycle `DIV` (verifying abort in $\le 3$ cycles and clean re-execution post-`mret`), and IRQ during branch misprediction.
- **Proof Criteria**: Multi-level preemption and register canary tests pass with zero register corruption.

---

### Stage 8: Dual-Runner Regression, Triage, and Late-Stage Models

- **Regression Runner (`run_regression.ps1`)**:
  - Compiles test source with GCC using `elf_to_hex_clean.py`.
  - Remote Server Mode: Dispatches `run_vcs.sh` / Cadence `xrun`.
  - Local Windows Mode: Executes AMD Vivado XSim (`xvlog`, `xelab`, `xsim`).
  - Aggregates PASS/FAIL status from mailbox memory.
- **Late-Stage Golden Models**:
  - Single-source register schema generating C headers, SV predictor tables, and UVM RAL.
  - **Spike ISS Lockstep Co-Simulation**: Instruments `top.v` with `Instr_W` pipeline propagation for `rvfi_insn`, utilizing a DPI-C memory plugin to dynamically feed MMIO read data from RTL LSU into Spike.

---

## Complete Verification Matrix & Pass/Fail Criteria

| Stage | Milestone | Test Program | Pass Criteria |
|:---|:---|:---|:---|
| **Stage 1** | Toolchain & Mailbox Proof | `stage1_hello/main.c` | Mailbox outputs characters and `CMD_PASS`; simulation ends with status 0. |
| **Stage 2** | TB Shell & Watchdog Proof | `stage2_watchdog/main.c` | Infinite loop trips watchdog at exact cycle limit; dumps last PC correctly. |
| **Stage 3** | Monitor Transaction Proof | `stage3_monitor_count/main.c` | Number of executed stores matches LSU and AXI monitor transaction counts exactly. |
| **Stage 4** | SVA & Blame Engine Proof | `stage4_fault_inject/main.c` | Unmapped MMIO hole access triggers `RESP_DECERR`; Failure Reporter outputs 1-page markdown report. |
| **Stage 5** | Register Access Layer Proof | `stage5_reg_sweep/main.c` | All peripheral register banks read back default reset values without bus fault. |
| **Stage 6** | Drivers & BFM Pin Proof | `stage6_polled_periph/main.c`| Polled TX/RX across UART, Timer, I2C, GPIO, and SPI verified at pins. |
| **Stage 7** | Trap & Preemption Proof | `stage7_nested_irq/main.c` | 3-level nested preemption (Class 0 $\rightarrow$ 1 $\rightarrow$ 2) and register canary tests pass without corruption. |
| **Stage 8** | Regression & Triage Proof | `run_regression.ps1` | Full test regression passes unattended across both VCS and Vivado XSim flows. |

