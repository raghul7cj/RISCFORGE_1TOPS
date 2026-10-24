# Message 0 [user]


### Text:

You are the Lead SoC Verification Architect performing a comprehensive audit of the RISCFORGE RV32IM_Zicsr SoC Verification Infrastructure implementation.

### 1. Verification Plan:
```markdown
# RISCFORGE SoC Verification Infrastructure: Final Implementation Plan

## [Goal Description]

This document establishes the comprehensive, granular implementation and sign-off plan for the **RISCFORGE single-core RV32IM_Zicsr SoC verification infrastructure**.

The infrastructure follows the **"Firmware is Stimulus, Testbench is the Judge"** methodology specified in the [SoC Verification Infrastructure: Integration Guide](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SoC%20Verification%20Infrastructure_%20Integration%20Guide.html), enhanced with architectural insights and gap resolutions from multi-agent codebase analysis.

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
| **Stage 7** | Trap & Preemption Proof | `stage7_nested_irq/main.c` | 3-level nested preemption (Class 0 $\rightarrow$ 1 $\rightarrow$ 
... [Truncated 203 chars]
```

### 2. Integration Guide HTML Specifications:
```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>SoC Verification Infrastructure: Integration Guide</title>
<style>
:root{--bg:#fff;--fg:#1c2733;--mut:#5a6878;--ln:#c9d2dc;--ac:#1f5fa8;--ac2:#e6eef9;--ok:#2e7d4f;--box:#f5f7fa;box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#14191f;--fg:#e4e9ef;--mut:#9aa7b5;--ln:#33404d;--ac:#6ea8e6;--ac2:#1b2a3a;--ok:#5fb98a;--box:#1a2129}}
:root[data-theme="dark"]{--bg:#14191f;--fg:#e4e9ef;--mut:#9aa7b5;--ln:#33404d;--ac:#6ea8e6;--ac2:#1b2a3a;--ok:#5fb98a;--box:#1a2129}
html{scroll-padding-top:env(safe-area-inset-top,0px)}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.65 "Segoe UI",system-ui,Arial,sans-serif}
main{max-width:860px;margin:0 auto;padding:28px 20px 48px}
h1{font-size:30px;line-height:1.2;margin:0 0 6px}
h2{font-size:21px;margin:36px 0 10px;padding-bottom:4px;border-bottom:2px solid var(--ac)}
h3{font-size:16px;margin:20px 0 6px}
p{margin:8px 0}
.sub{font-size:17px;color:var(--mut);margin:0}
.meta{font-size:13px;color:var(--mut);margin:10px 0 18px;padding-bottom:12px;border-bottom:1px solid var(--ln)}
nav ol{margin:6px 0 0;padding-left:22px;columns:2}
a{color:var(--ac)}
ul,ol{padding-left:22px;margin:6px 0}
li{margin:3px 0}
figure{margin:18px 0;padding:10px;border:1px solid var(--ln);border-radius:6px;background:var(--box);overflow-x:auto}
figcaption{font-size:13px;color:var(--mut);margin-top:6px}
svg{max-width:100%;height:auto;display:block;margin:0 auto}
svg text{font:12px "Segoe UI",Arial,sans-serif;fill:var(--fg)}
svg .t{font-weight:600}
svg .s{font-size:11px}
svg .m{fill:var(--mut)}
.b{fill:var(--bg);stroke:var(--ac);stroke-width:1.4}
.a{fill:var(--ac2);stroke:var(--ac);stroke-width:1.4}
.z{fill:none;stroke:var(--mut);stroke-width:1.2;stroke-dasharray:5 4}
.l{fill:none;stroke:var(--mut);stroke-width:1.4;marker-end:url(#ar)}
.l2{marker-start:url(#ar)}
.d{stroke-dasharray:4 3}
.step{border-left:4px solid var(--ac);padding:1px 0 1px 14px;margin:16px 0}
.step h3{margin:0 0 4px}
.proof{color:var(--ok);font-size:14px}
table{border-collapse:collapse;width:100%;font-size:14px;margin:10px 0}
th,td{border:1px solid var(--ln);padding:6px 8px;text-align:left;vertical-align:top}
th{background:var(--ac2)}
.wrap{overflow-x:auto}
.note{background:var(--ac2);border:1px solid var(--ln);border-radius:6px;padding:8px 12px;margin:12px 0;font-size:14px}
code{font:13px Consolas,"Courier New",monospace;background:var(--box);padding:1px 4px;border-radius:3px}
@media print{
:root{--bg:#fff;--fg:#000;--mut:#444;--ln:#aaa;--ac:#1f5fa8;--ac2:#e6eef9;--ok:#1f6a40;--box:#fff}
@page{margin:16mm}
body{font-size:10.5pt}
main{max-width:none;padding:0}
h2{break-after:avoid}
h3{break-after:avoid}
figure,.step,table,.note{break-inside:avoid}
nav ol{columns:1}
a{color:inherit;text-decoration:none}
}
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" style="fill:var(--mut)"/></marker></defs></svg>
<main>
<header>
<h1>SoC Verification Infrastructure</h1>
<p class="sub">Integration guide: from C tests to drivers, interrupt service routines and a working SoC</p>
<p class="meta">Single-core RV32IM_Zicsr SoC, bare-metal C, machine mode. Version 1.0, infrastructure edition.</p>
</header>

<nav aria-label="Contents">
<strong>Contents</strong>
<ol>
<li><a href="#intro">Introduction</a></li>
<li><a href="#basics">Unit and peripheral testing basics</a></li>
<li><a href="#method">SoC-level methodology</a></li>
<li><a href="#build">Building the infrastructure</a></li>
<li><a href="#drivers">Developing drivers and ISRs on the infrastructure</a></li>
<li><a href="#late">Late-stage components: register model, C models, DPI-C, ISS co-simulation</a></li>
<li><a href="#debug">Debugging with the infrastructure</a></li>
<li><a href="#fpga">Carrying the infrastructure to the FPGA</a></li>
</ol>
</nav>

<h2 id="intro">1. Introduction</h2>
<p>This guide explains how to build the verification infrastructure for the SoC <em>before</em> writing the tests that use it. The order of work is C test programs first, then peripheral drivers, then interrupt service routines (ISRs), and finally a working application on the complete SoC. Test cases are deliberately out of scope: they can be derived later, or taken from your existing catalogue, once the infrastructure can run and judge them.</p>
<h3>Guiding ideas</h3>
<ul>
<li><strong>Firmware is the stimulus and the testbench is the judge.</strong> Software runs on the real core. The testbench only observes and checks.</li>
<li><strong>Checks fire by themselves.</strong> A failure should name the property that broke, not send you reading a log.</li>
<li><strong>Every check has an independent source of expected behaviour</strong>: an assertion, a register predictor, a pin model or an instruction-set simulator (ISS).</li>
<li><strong>One ELF per test</strong> runs unchanged on RTL simulation, the ISS and the FPGA.</li>
<li><strong>Build in thin slices.</strong> Prove each piece with a trivial program before adding the next.</li>
<li><strong>Add models late.</strong> The register model, C models through DPI-C and ISS co-simulation come after the basic checks work.</li>
</ul>
<p>Suggested tool roles: xsim for the daily inner loop, VCS or Xcelium for regressions, coverage and DPI-C co-simulation, Vivado for the FPGA build, and Jasper or VC Formal for small control blocks such as the interrupt arbiter. AI assistants, including the AMD Ross MCP servers for Vivado, fit well for drafting drivers, scripts and first versions of checkers. Every generated artefact must still pass the same checks and an independent review.</p>

<h2 id="basics">2. Unit and peripheral testing basics</h2>
<h3>Unit testbench</h3>
<p>A unit testbench verifies one module. Its parts are a transaction, a driver that applies it, a monitor that observes the outputs, a scoreboard that compares them with a reference function, and a covergroup that records what was exercised. Sequences come in three flavours: directed, constrained-random and corner. The strength is speed and depth on small blocks such as the ALU, hazard unit or arbiter. The weakness is that the bench trusts the interface assumptions of its own model.</p>
<h3>Peripheral testbench</h3>
<p>A peripheral testbench wraps one IP with a bus agent (an APB master), a register model that knows reset values, access types and side effects, a pin model or protocol monitor on the external side, and an interrupt monitor. These parts are reused at SoC level, so write them as reusable components from the start.</p>
<h3>What these levels cannot see</h3>
<ul>
<li>The real address decode and the bus ordering produced by the core's load/store unit.</li>
<li>Byte strobes and hidden reads generated by compiled C code.</li>
<li>Interrupts arriving at arbitrary points in the pipeline.</li>
<li>Reset and boot sequences across blocks.</li>
<li>Assumptions made in driver and ISR code.</li>
</ul>
<figure>
<svg viewBox="0 0 760 130" role="img" aria-label="Three test levels: unit, peripheral and SoC testbench">
<rect class="b" x="10" y="14" width="220" height="86" rx="5"/>
<text class="t" x="120" y="40" text-anchor="middle">Unit testbench</text>
<text x="120" y="62" text-anchor="middle">one module, reference function</text>
<text x="120" y="82" text-anchor="middle">fast, deep, near-exhaustive</text>
<rect class="a" x="270" y="14" width="220" height="86" rx="5"/>
<text class="t" x="380" y="40" text-anchor="middle">Peripheral testbench</text>
<text x="380" y="62" text-anchor="middle">IP, bus agent, pin model</text>
<text x="380" y="82" text-anchor="middle">registers, protocol, interrupt pin</text>
<rect class="b" x="530" y="14" width="220" height="86" rx="5"/>
<text class="t" x="640" y="40" text-anchor="middle">SoC testbench</text>
<text x="640" y="62" text-anchor="middle">firmware is the stimulus</text>
<text x="640" y="82" text-anchor="middle">integration, software contract</text>
<path class="l" d="M230 57H268"/><path class="l" d="M490 57H528"/>
<text class="m" x="380" y="122" text-anchor="middle">reused upward: monitors, pin models, register model</text>
</svg>
<figcaption>Figure 1. Test levels and what is carried upward.</figcaption>
</figure>

<h2 id="method">3. SoC-level methodology</h2>
<h3>Firmware as stimulus</h3>
<p>Tests are C programs compiled with GCC. The image is preloaded into ISRAM and DSRAM (warm boot) or loaded from a flash model by the bootloader (cold boot). The program runs on the real RTL and reports its result through a mailbox word in DSRAM that the testbench watches.</p>
<h3>Observe and check in layers</h3>
<p>The testbench taps the design at fixed observation points and checks each layer against an independent source. Lower layers are blamed first, because a protocol error explains many higher-level failures.</p>
<div class="wrap"><table>
<tr><th>Layer</th><th>What is observed</th><th>Expected behaviour comes from</th></tr>
<tr><td>Protocol</td><td>AXI-Lite and APB handshakes</td><td>Assertions</td></tr>
<tr><td>Path</td><td>Core access to AXI transaction to APB transfer</td><td>Scoreboard using the address map</td></tr>
<tr><td>Register</td><td>Peripheral register reads and writes</td><td>Register predictor</td></tr>
<tr><td>Peripheral function</td><td>UART, GPIO, I2C, SPI, timer behaviour at the pins</td><td>Pin models and protocol monitors</td></tr>
<tr><td>Interrupt</td><td>Source, pending, grant, accept, acknowledge</td><td>Independent interrupt predictor</td></tr>
<tr><td>CPU state</td><td>Retired instructions, CSRs, traps</td><td>ISS (Spike)</td></tr>
<tr><td>Firmware result</td><td>Mailbox status, checksum</td><td>The test itself and host-computed values</td></tr>
</table></div>
<h3>First failing check</h3>
<p>When a check fires, the failure reporter records the cycle, check ID, expected and actual values, and freezes the ring buffers that hold the last transactions of every monitor. It blames the lowest layer that failed first and marks later failures as downstream. The output is a one-page report with the last retired instructions disassembled, so a person reads one page instead of the full log.</p>
<h3>Pass rule</h3>
<p>A test passes only when the mailbox reports PASS, no checker failed, the checkers actually saw activity (no vacuous pass), no predicted event is left unobserved, and no timeout occurred.</p>
<figure>
<svg viewBox="0 0 760 340" role="img" aria-label="SoC testbench infrastructure architecture">
<rect class="b" x="10" y="16" width="130" height="38" rx="4"/><text class="t" x="75" y="39" text-anchor="middle">C sources</text>
<rect class="b" x="10" y="76" width="130" height="38" rx="4"/><text class="t" x="75" y="99" text-anchor="middle">GCC toolchain</text>
<rect class="b" x="10" y="136" width="130" height="38" rx="4"/><text class="t" x="75" y="159" text-anchor="middle">ELF</text>
<rect class="b" x="10" y="196" width="130" height="38" rx="4"/><text class="t" x="75" y="219" text-anchor="middle">Memory images</text>
<rect class="b" x="10" y="256" width="130" height="38" rx="4"/><text class="t" x="75" y="279" text-anchor="middle">Disassembly pc map</text>
<path class="l" d="M75 54V76"/><path class="l" d="M75 114V136"/><path class="l" d="M75 174V196"/><path class="l" d="M10 155H3V275H10"/>
<rect class="z" x="165" y="8" width="450" height="324" rx="6"/>
<text class="m s" x="175" y="324">Simulation top</text>
<rect class="a" x="180" y="24" width="120" height="40" rx="4"/><text class="t" x="240" y="48" text-anchor="middle">Boot and preload</text>
<rect class="b" x="330" y="24" width="270" height="84" rx="4"/>
<text class="t" x="465" y="48" text-anchor="middle">DUT: SoC</text>
<text x="465" y="68" text-anchor="middle">core, memories, fabric,</text>
<text x="465" y="86" text-anchor="middle">peripherals, IRQ gateway</text>
<path class="l" d="M140 215H152V44H180"/><path class="l" d="M300 44H330"/>
<rect class="b" x="180" y="128" width="270" height="44" rx="4"/><text class="t" x="315" y="146" text-anchor="middle">Monitors (passive taps)</text><text class="s" x="315" y="162" text-anchor="middle">fetch, retire, LSU, AXI, APB, IRQ</text>
<rect class="a" x="470" y="128" width="130" height="44" rx="4"/><text class="t" x="535" y="146" text-anchor="middle">Pin models</text><text class="s" x="535" y="162" text-anchor="middle">UART GPIO I2C SPI</text>
<path class="l d" d="M360 108V128"/><path class="l l2" d="M535 108V128"/>
<rect class="b" x="180" y="192" width="270" height="50" rx="4"/><text class="t" x="315" y="212" text-anchor="middle">Checkers</text><text class="s" x="315" y="230" text-anchor="middle">assertions, scoreboards, predictors</text>
<rect class="a" x="470" y="192" width="130" height="50" rx="4"/><text class="t" x="535" y="212" text-anchor="middle">Mailbox, watchdog</text><text class="s" x="535" y="230" text-anchor="middle">PASS, FAIL, hang</text>
<path class="l" d="M315 172V192"/>
<rect class="a" x="180" y="262" width="270" height="50" rx="4"/><text class="t" x="315" y="282" text-anchor="middle">Failure reporter</text><text class="s" x="315" y="300" text-anchor="middle">first failing check, report</text>
<path class="l" d="M315 242V262"/><path d="M535 242V287" class="l" style="marker-end:none"/><path class="l" d="M450 287H630"/>
<rect class="b" x="630" y="262" width="120" height="50" rx="4"/><text class="t" x="690" y="282" text-anchor="middle">Result</text><text class="s" x="690" y="300" text-anchor="middle">PASS/FAIL + report</text>
</svg>
<figcaption>Figure 2. Infrastructure architecture: build side on the left, simulation top in the dashed frame.</figcaption>
</figure>

<h2 id="build">4. Building the infrastructure</h2>
<p>Build the eight steps in order. Each step ends with a proof: a small program or an injected fault that shows the step works. Do not start the next step until the proof passes.</p>

<div class="step"><h3>Step 1. Toolchain, startup and mailbox</h3>
<p>Pin the GCC version and flags (<code>-march=rv32im_zicsr -mabi=ilp32</code>), and make sure no library brings compressed or atomic instructions. Write the startup file (stack, <code>.bss</code>, <code>.data</code>, trap vector, call <code>main</code>), a linker script that places <code>.text</code> in ISRAM and <code>.data</code>, <code>.bss</code>, stack and mailbox in DSRAM, and a mailbox layout with status, test ID, argument, character output and error code. Produce the listing, symbol file and a pc map (PC to function and source line) from the ELF.</p>
<p class="proof">Proof: the same hello program prints through the mailbox on Spike and on RTL.</p></div>

<div class="step"><h3>Step 2. Testbench shell and memory preload</h3>
<p>Create the top module with clock and reset, a backdoor loader for the image into ISRAM and DSRAM, the mailbox address read from the ELF symbol, a per-test watchdog, and a boot-mode switch. Warm boot is the default; cold boot through the flash model is added once the bootloader is stable.</p>
<p class="proof">Proof: a trivial PASS program ends the simulation; an infinite loop trips the watchdog and reports the last PC.</p></div>

<div class="step"><h3>Step 3. Monitors and transactions</h3>
<p>Add passive monitors for fetch, retire, load/store, AXI-Lite (AW, W, B, AR and R as separate events), APB, the interrupt lines and the pins. Each monitor emits timestamped transaction objects on one shared cycle counter and keeps a ring buffer of the most recent ones. Write them as SystemVerilog interfaces plus small classes so they can become UVM agents later without a rewrite.</p>
<p class="proof">Proof: transaction counts match a known program, for example ten stores produce ten load/store transactions.</p></div>

<div class="step"><h3>Step 4. Checkers and failure reporter</h3>
<p>Bind protocol assertions on every fabric interface and add a path scoreboard: each core MMIO access must appear as one AXI transaction and one APB transfer on the slot given by the address map, with the same data, strobes and response. Add the reporter with first-fatal logic. Give every checker a fault-injection switch (for example, force one byte strobe) so you can prove it fires.</p>
<p class="proof">Proof: each injected fault is named by the correct check ID in the report, and every assertion has a cover that is hit.</p></div>

<div class="step"><h3>Step 5. C test harness and register access layer</h3>
<p>Provide macros for 32-bit volatile register access, test begin and end with ID and PASS/FAIL, check macros that write the error code, a cycle-counter timeout helper, and a panic handler. Generate address headers from the same address map the testbench uses. Use 32-bit accesses until sub-word MMIO is verified, because compilers emit byte and halfword accesses for narrow registers.</p>
<p class="proof">Proof: a reset-value sweep of one peripheral runs and the register predictor, once present, agrees with every read.</p></div>

<div class="step"><h3>Step 6. Drivers and pin models</h3>
<p>Give each peripheral a register struct, an init function, polled operations with timeouts and error codes, and a pin model with error injection (UART monitor, GPIO driver and monitor, I2C slave model, SPI flash model). Develop each driver against its pin model so the wire is checked, not only the register read-back.</p>
<p class="proof">Proof: one polled transfer per peripheral is verified at the pins.</p></div>

<div class="step"><h3>Step 7. ISR framework and interrupt monitor</h3>
<p>Write the trap entry that saves caller-saved registers, a dispatch table keyed by cause, and an unexpected-interrupt handler that fails the test. Fix the ISR rules: acknowledge, record, return, with no blocking calls. Add the interrupt monitor that logs raise, pending, grant, accept and acknowledge, together with an interrupt predictor written from the interrupt specification, not from the RTL.</p>
<p class="proof">Proof: a register-canary test shows no corruption across an ISR, and a timer tick test produces the exact expected count.</p></div>

<div class="step"><h3>Step 8. Regression runner and triage</h3>
<p>Create a manifest with test ID, source, boot mode, timeout and seeds, and a runner that builds, simulates and collects results. Every log starts with seed, git hash, ELF hash and RTL hash. Bucket failures by signature (check ID, PC, cause) and replay a failing seed with waveforms on.</p>
<p class="proof">Proof: a nightly run completes unattended, and a seeded failure produces exactly one report.</p></div>

<figure>
<svg viewBox="0 0 760 190" role="img" aria-label="Infrastructure build roadmap">
<g>
<rect class="b" x="2" y="20" width="86" height="56" rx="4"/><text class="t s" x="45" y="44" text-anchor="middle">1 Toolchain</text><text class="s" x="45" y="60" text-anchor="middle">startup, mailbox</text>
<rect class="b" x="96" y="20" width="86" height="56" rx="4"/><text class="t s" x="139" y="44" text-anchor="middle">2 TB shell</text><text class="s" x="139" y="60" text-anchor="middle">preload</text>
<rect class="b" x="190" y="20" width="86" height="56" rx="4"/><text class="t s" x="233" y="44" text-anchor="middle">3 Monitors</text><text class="s" x="233" y="60" text-anchor="middle">transactions</text>
<rect class="b" x="284" y="20" width="86" height="56" rx="4"/><text class="t s" x="327" y="44" text-anchor="middle">4 Checkers</text><text class="s" x="327" y="60" text-anchor="middle">reporter</text>
<rect class="b" x="378" y="20" width="86" height="56" rx="4"/><text class="t s" x="421" y="44" text-anchor="middle">5 C harness</text><text class="s" x="421" y="60" text-anchor="middle">access layer</text>
<rect class="b" x="472" y="20" width="86" height="56" rx="4"/><text class="t s" x="515" y="44" text-anchor="middle">6 Drivers</text><text class="s" x="515" y="60" text-anchor="middle">pin models</text>
<rect class="b" x="566" y="20" width="86" height="56" rx="4"/><text class="t s" x="609" y="44" text-anchor="middle">7 ISR</text><text class="s" x="609" y="60" text-anchor="middle">framework</text>
<rect class="b" x="660" y="20" width="86" height="56" rx="4"/><text class="t s" x="703" y="44" text-anchor="middle">8 Regression</text><text class="s" x="703" y="60" text-anchor="middle">runner</text>
</g>
<path class="l" d="M88 48H96"/><path class="l" d="M182 48H190"/><path class="l" d="M276 48H284"/><path class="l" d="M370 48H378"/><path class="l" d="M464 48H472"/><path class="l" d="M558 48H566"/><path class="l" d="M652 48H660"/>
<path class="l" d="M703 76V98H160V120"/>
<text class="m s" x="430" y="94" text-anchor="middle">then add the late-stage components</text>
<rect class="a" x="60" y="120" width="200" height="50" rx="4"/><text class="t" x="160" y="142" text-anchor="middle">Register model</text><text class="s" x="160" y="158" text-anchor="middle">predictor table, headers</text>
<rect class="a" x="290" y="120" width="200" height="50" rx="4"/><text class="t" x="390" y="142" text-anchor="middle">C models and DPI-C</text><text class="s" x="390" y="158" text-anchor="middle">shared functional models</text>
<rect class="a" x="520" y="120" width="200" height="50" rx="4"/><text class="t" x="620" y="142" text-anchor="middle">ISS co-simulation</text><text class="s" x="620" y="158" text-anchor="middle">Spike, retire port, adapter</text>
<path class="l" d="M260 145H290"/><path class="l" d="M490 145H520"/>
</svg>
<figcaption>Figure 3. Build order: eight infrastructure steps, then the late-stage components.</figcaption>
</figure>

<h2 id="drivers">5. Developing drivers and ISRs on the infrastructure</h2>
<p>With the infrastructure in place, each new peripheral follows one loop. Write a small C test using raw register access, extract the working sequence into driver functions, and run a polled test checked at the pins. When all checks are clean, add the interrupt-driven variant with its ISR and acknowledge, and confirm the interrupt monitor and predictor agree. Only then compose the application on top of the drivers. If any check fires, use the first failing check to fix the problem and rerun.</p>
<p>For a peripheral whose driver you must write from scratch: read the RTL register list, define the register struct, write init and a polled operation with a timeout, observe the wire, add the error cases, and look at one waveform to confirm the sequence. Third-party IP often differs from its documentation, so treat the pin model as the authority. An AI assistant can draft the driver from the register description; require that it passes the pin-level test and have a second, independent reviewer compare it with the specification.</p>
<figure>
<svg viewBox="0 0 760 180" role="img" aria-label="Driver and ISR development loop">
<rect class="b" x="10" y="60" width="105" height="54" rx="4"/><text class="t" x="62" y="82" text-anchor="middle">C test</text><text class="s" x="62" y="100" text-anchor="middle">raw register access</text>
<rect class="b" x="135" y="60" width="105" height="54" rx="4"/><text class="t" x="187" y="82" text-anchor="middle">Driver</text><text class="s" x="187" y="100" text-anchor="middle">functions, timeouts</text>
<rect class="b" x="260" y="60" width="105" height="54" rx="4"/><text class="t" x="312" y="82" text-anchor="middle">Polled test</text><text class="s" x="312" y="100" text-anchor="middle">checked at the pins</text>
<polygon class="a" points="375,87 420,53 465,87 420,121"/><text class="t s" x="420" y="84" text-anchor="middle">Checks</text><text class="t s" x="420" y="98" text-anchor="middle">clean?</text>
<rect class="b" x="490" y="60" width="120" height="54" rx="4"/><text class="t" x="550" y="82" text-anchor="middle">Interrupt variant</text><text class="s" x="550" y="100" text-anchor="middle">ISR, ack, IRQ monitor</text>
<rect class="b" x="630" y="60" width="120" height="54" rx="4"/><text class="t" x="690" y="82" text-anchor="middle">Application</text><text class="s" x="690" y="100" text-anchor="middle">built on drivers</text>
<path class="l" d="M115 87H135"/><path class="l" d="M240 87H260"/><path class="l" d="M365 87H375"/><path class="l" d="M465 87H490"/><path class="l" d="M610 87H630"/>
<text class="m s" x="478" y="80">yes</text>
<path class="l" d="M420 121V160H62V114"/>
<text class="m s" x="240" y="154" text-anchor="middle">no: read the first failing check, fix, rerun</text>
</svg>
<figcaption>Figure 4. Development loop for each peripheral, from C test to application.</figcaption>
</figure>

<h2 id="late">6. Late-stage components</h2>
<p>Add these after the basic checks are stable. Each one replaces a weaker check with a stronger independent one.</p>
<h3>Register model</h3>
<p>Keep one description per peripheral: address, width, reset value, per-field access (read-write, read-only, wri
... [Truncated 5803 chars]
```

### 3. Implementation Directory & File Location Manifest:
```json
{
  "Software_BSP": {
    "path": "Verification/tests/bsp/",
    "files": [
      "mailbox.h",
      "test_harness.h",
      "soc_regs.h",
      "crt0.s",
      "link.ld",
      "trap_handler.s",
      "isr_dispatch.h",
      "isr_dispatch.c"
    ],
    "mailbox_location": "DSRAM Base 0x0002_0000 (.mailbox NOLOAD 64B)"
  },
  "Software_Drivers": {
    "path": "Verification/tests/drivers/",
    "files": [
      "uart_driver.h",
      "uart_driver.c",
      "timer_driver.h",
      "timer_driver.c",
      "gpio_driver.h",
      "gpio_driver.c",
      "i2c_driver.h",
      "i2c_driver.c",
      "spi_driver.h",
      "spi_driver.c"
    ],
    "features": "Direct register models, cycle-bounded timeouts via mcycle, dedicated recover() functions"
  },
  "VIP_BFMs": {
    "path": "Verification/infrastructure/vip/",
    "files": [
      "uart_pin_vip.sv",
      "gpio_pin_vip.sv",
      "i2c_eeprom_at24c02.sv",
      "spi_flash_s25fs512s.sv"
    ],
    "features": "Lightweight SystemVerilog BFMs without heavy UVM/VIP overhead"
  },
  "Monitors_and_Checkers": {
    "path": "Verification/infrastructure/monitors/ & checkers/",
    "files": [
      "fetch_monitor.sv",
      "retire_monitor.sv",
      "lsu_monitor.sv",
      "axi_lite_monitor.sv",
      "apb_monitor.sv",
      "irq_monitor.sv",
      "axi_lite_protocol_sva.sv",
      "apb_protocol_sva.sv",
      "mmio_path_scoreboard.sv",
      "failure_reporter.sv"
    ],
    "features": "64-entry ring buffers, SVA protocol assertions, first-fatal blame engine"
  },
  "Testbench_Top": {
    "path": "Verification/infrastructure/tb/",
    "files": [
      "soc_tb_top.sv"
    ],
    "features": "Dual boot (Warm backdoor SRAM @ t=0 & Cold SPI boot), mailbox watcher, 1M-cycle watchdog"
  },
  "Filelists_and_Build": {
    "path": "Verification/infrastructure/",
    "files": [
      "soc_verification.f",
      "soc_verification.prj"
    ],
    "features": "VCS/Xcelium filelist (.f) and Vivado XSim project (.prj)"
  },
  "Regression_Runner": {
    "path": "Verification/regression/",
    "files": [
      "run_regression.ps1",
      "elf_to_hex_clean.py"
    ],
    "features": "Dual VCS remote EDA / Vivado XSim local Windows runner with bounds-checked ELF splitter"
  },
  "Proof_Test_Suites": {
    "path": "Verification/tests/suites/",
    "suites": [
      "stage1_hello",
      "stage2_watchdog",
      "stage3_monitor_count",
      "stage4_fault_inject",
      "stage5_reg_sweep",
      "stage6_polled_periph",
      "stage7_nested_irq"
    ]
  }
}
```

### Your Audit Task:
1. **Specification Alignment**: Compare every component across all folder locations against the requirements in the Integration Guide HTML and the Verification Plan.
2. **Architecture Compliance**: Verify the 6 core architectural mandates:
   - Lightweight SystemVerilog BFMs only (no heavy UVM VIPs).
   - Warm boot primary (direct backdoor SRAM at t=0) with isolated Cold boot signoff.
   - Mailbox located at DSRAM `0x0002_0000` with character streaming without hardware UART dependency.
   - Dual simulation support: Synopsys VCS (`soc_verification.f`) and AMD Vivado XSim (`soc_verification.prj` / `run_regression.ps1`).
   - Peripheral drivers matching direct register models with cycle-bounded timeouts and illegal state recovery.
   - Passive monitors with 64-entry ring buffers and failure reporter first-fatal blame engine.
3. **Discrepancy Identification**: Flag any discrepancies, missing requirements, interface mismatches, or edge-case gaps between the implementation and the specifications.
4. **Final Verdict & Recommendations**: Provide a clear, actionable audit summary with itemized findings.



# Message 1 [assistant]


### Text:
I'll start by exploring the actual implementation on disk to compare against the specifications.


### Tool: None
Input: null


### Tool: None
Input: null


# Message 2 [assistant]


### Reasoning:
Let me explore the RISCFORGE_1TOPS-main/rtl/ips/Verification directory.


### Tool: None
Input: null


# Message 3 [assistant]


### Reasoning:
Now I have a good map. Key immediate findings:
- `gpio_pin_vip.sv` = 0 bytes (EMPTY)
- `spi_flash_s25fs512s.sv` = 0 bytes (EMPTY)
- `uart_pin_vip.sv` = 1334 bytes (small)
- `i2c_eeprom_at24c02.sv` = 3632 bytes
- Monitors are small (1.4-2.7 KB) — need to verify 64-entry ring buffers
- No `Verification/tests/bsp/` missing files? Manifest lists 8 files: mailbox.h, test_harness.h, soc_regs.h, crt0.s, link.ld, trap_handler.s, isr_dispatch.h, isr_dispatch.c — all present ✓
- Drivers: all 10 present ✓
- Suites: 7 present ✓
- Missing from manifest but present: rf_monitors.sv, rf_monitor_env.sv, rf_mon_probe.sv, rf_monitor_if.sv, launch_opencode_verifier.py, soc_verification_plan.md

Let me now do a comprehensive read. Let me set up a todo list and parallelize reading.

Let me read everything systematically. I'll launch subagents for bulk reading while I read key files myself.

Let me start byreading the critical files.


### Text:
Found the implementation. Two VIP files are **0 bytes** — noted. Let me audit systematically.


### Tool: None
Input: null


# Message 4 [assistant]


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 5 [assistant]


### Reasoning:
Already found significant bugs:

**BSP Bugs:**

1. **`crt0.s` zeroes `a0`/`a1` (`x10`, `x11`) before `.bss` clearing** — actually it does the bss clear AFTER zeroing, using `la a0, _sbss`. That's fine since it reloads. OK.

2. **`crt0.s` — `.Lmain_pass` writes CMD_PASS to mailbox but `mailbox_init` in TEST_START sets `cmd_status = RUNNING`. Order: TEST_START sets RUNNING, then TEST_PASS sets PASS. Fine.

3. **`crt0.s` line 72-78: `beqz a0, .Lmain_pass`** — `main()` returns 0 on pass. But `mailbox_fail()` spins forever, so main() only returns on pass. OK-ish. But note: crt0 writes `sw a0, 24(a1)` for error code at offset 24 = 0x18 = error_code ✓. And `sw a2, 0(a1)` = cmd_status ✓.

   **BUG: crt0 overwrites `test_id`?** No. But `main()`'s return value in `a0` is checked with `beqz`. If a test wants to return a specific error code, that path writes error_code AND cmd_status=FAIL ✓.

   **BUG: `main` is called but if `main` never returns (mailbox_fail spins), the CMD_FAIL path is dead code.** Minor.

4. **`crt0.s` writes mintprio CSR at 0x7C0** — `csrw 0x7C0, zero`. Note: 0x7C0 is a non-standard CSR. Need to verify the RTL supports it. Also this is a **custom CSR**; the assembly `csrw 0x7C0` requires Zicsr ✓.

5. **`trap_handler.s` MAJOR BUG: `addi sp, sp, -72` — 72 bytes is NOT 4-byte aligned.** 72 = 16 (regs) + 8 (CSRs) = 24 bytes of data... wait let's count: 16 caller-saved registers × 4 bytes = 64 bytes (offsets 0..60), then mepc at 64, mcause at 68 = 72 bytes total (offsets 0..71). So the frame is 72 bytes = 18 words. `addi sp, sp, -72` gives sp % 16 == ... If sp was 16-byte aligned (0x...8000), sp becomes 0x...FB8, which is 8 mod 16 — still 4-byte aligned (72 is divisible by 4) ✓. But **the RV32I psABI requires 16-byte stack alignment at all times**. Violated. Also GCC will assume 16-byte alignment and may use `sd`-like patterns (it won't on RV32 but will align spills), so this can cause misaligned access traps. **FINDING: stack frame not 16-byte aligned.**

6. **`trap_handler.s` MAJOR BUG: The spec says "Saves all 16 caller-saved registers (x1, x5-x7, x10-x17, x28-x31)".** Let's enumerate what's saved: ra(x1), t0(x5), t1(x6), t2(x7), a0-a7(x10-x17), t3-t6(x28-x31) = 1+3+8+4 = **16 registers** ✓. Good, that matches.

   **BUT: `mstatus`/`mie`/`mpp` are not saved/restored.** For nested interrupts, MPP must be handled. The hardware shadow stack handles mstatus per the RTL. Need to check.

7. **`trap_handler.s` BUG: `csrr t0, mepc` / `csrr t1, mcause` are done AFTER saving caller-saved registers — that's fine. But then `mv a0, t1; mv a1, t0; call c_trap_handler`. And restore `csrw mepc, t0` from stack 64 — the C handler's return value is ignored.** No exception-advance logic. For a synchronous access fault, `mepc` is NOT advanced, so `mret` re-executes the faulting instruction → **infinite trap loop**. The spec doesn't require it to advance, but there's no way for C to signal advance/discard. `c_trap_handler` returns void. **FINDING: no exception-forwarding mechanism (no way to advance mepc past a faulting instruction).**

8. **`isr_dispatch.c` BUG (CRITICAL): `uint32_t idx = cause & 0x1F;`** — mcause bit 31 is the interrupt flag. For **interrupt** causes, the value is e.g. 27 (SPI EOT) which fits in 5 bits ✓, but mcause values ≥ 32 for interrupts (mcause = 32 + irq_num) would be aliased. For **exceptions**, mcause = 5 (Load Access Fault), 7 (Store Access Fault) ✓. But **the spec's interrupt table lists mcause 27 for SPI EOT and mcause 19/18/17/16 for UART/SPI/I2C/GPIO.** Note: these are < 32 so `& 0x1F` preserves them ✓. However, this means **an interrupt with irq_num 0 and an exception with mcause 0 alias**, and more importantly the dispatcher cannot distinguish interrupt from exception. Also `mcause & 0x1F` **destroys the interrupt bit (bit 31)**. So `c_trap_handler` can't tell IRQ from exception. **FINDING: dispatcher masks off the interrupt bit; no interrupt-vs-exception discrimination, no per-cause aliasing protection.**

9. **`isr_dispatch.c` — `isr_table` is in `.bss`, initialized in `crt0`. OK. But `isr_register_handler` is never called by anything.**

10. **`test_harness.h` — `TEST_ASSERT(cond, err)` calls `mailbox_fail((err_code), (uint32_t)(uintptr_t)__FILE__, ...)`.** Putting a **string literal pointer** into `arg0` which the TB may interpret as an address → **nonsensical**. Also `TEST_ASSERT` passes `(uint32_t)__LINE__` as `arg1` (expected) and `0` as `got`. So exp/actual are meaningless. **FINDING: TEST_ASSERT abuses arg0 with `__FILE__` pointer and misuses exp/actual slots.** Also inconsistent with TEST_ASSERT_EQ which uses `addr = __LINE__`.

11. **`mailbox.h` — `mailbox_putc` writes to `char_out` at +0x14 with NO handshake/handshake-back.** The TB must sample it every clock; a fast `putc` loop can drop characters between TB samples. **FINDING: no ready/ack handshake on char_out → character loss.** The spec claims "zero-overhead character streaming" but this is lossy. Need to check what the TB does — if TB samples on write (posedge on addr decode) it works. Let me check.

12. **`mailbox.h` — `mailbox_fail` writes error_code, arg0/1/2, cmd_status = FAIL, then `while(1) wfi`.** The order means the TB sees cmd_status=FAIL last ✓ good.

13. **`soc_regs.h` — no peripheral register definitions at all.** The manifest says "MMIO address definitions & 32-bit access macros" and the plan says `REG32_WRITE`/`REG32_READ`. The drivers have their own register models. But per Integration Guide Step 5: "Generate address headers from the same address map the testbench uses." **Only base addresses here, no register offsets, and hand-written (not generated from a single source).** FINDING.

14. **`soc_regs.h` — `csr_read_mcycle()`**: Is `mcycle` (0xB00) actually implemented in the core RTL? Need to check. If not implemented, `csrr` returns 0 or traps → **all timeouts become infinite or immediate**. CRITICAL to verify.

15. **`link.ld` — `.mailbox (NOLOAD)` section.** This is at DSRAM base. But: **`.mailbox` is NOLOAD, and `*(.mailbox)` collects a section named `.mailbox`.** Nothing in the codebase defines a `.mailbox` section (crt0 uses raw address `0x00020000`). So `_mailbox_base = 0x20000`, then `. = _mailbox_base + 0x40`. OK, that reserves 64 bytes. ✓

    **BUG: `.rodata` follows `.mailbox` but the linker doesn't force `.rodata` to start at 0x0002_0040.** Actually it does implicitly because `.mailbox` ends at 0x20040 and `.rodata` starts at the next free address ✓.

    **BUG: `.bss (NOLOAD)` — but `_stack_top = 0x28000`.** There's no `.stack` section and no stack guard. Stack grows down from 0x28000 which is the TOP of DSRAM. `_ebss` is below. No overflow checking. FINDING (minor, typical).

    **BUG: `link.ld` has `BOOTROM (rx) : ORIGIN = 0x00000000, LENGTH = 64` declared but never used and no section maps to it.** If any code lands in BOOTROM it's an orphan-section error. Minor.

    **BUG: `/DISCARD/ : { *(.eh_frame*) }`** — fine for bare metal.

    **MAJOR: `.text` goes ONLY to ISRAM but `link.ld` doesn't handle `.init_array`/`.fini_array`** — if `--specs=nosys` newlib is used, there could be sections. Minor.

    **CRITICAL CHECK: Is DSRAM actually writable/initialized at 0x20000 by `elf_to_hex_clean.py`?** Need to check the bounds check.

16. **`link.ld` says `.data` is loaded — crt0 does NOT copy `.data` from ISRAM/ROM to DSRAM.** `.data` is `> DSRAM` (VMA in DSRAM). If `.data` has initialized content, `elf_to_hex_clean.py` must emit it at the DSRAM VMA. But the plan says "elf_to_hex.py (Bounded ISRAM / DSRAM Slices)". Need to verify it uses VMA not LMA and doesn't split incorrectly. **If the converter only handles one contiguous region per file or uses LMA, `.data` init breaks.** CRITICAL to check.

    Also note: **`.rodata` in DSRAM** — but rodata is read-only and DSRAM is fine.

17. **crt0 does NOT initialize `.data`** — with VMA==LMA in DSRAM and the hex preloaded directly into DSRAM, no copy needed ✓ (as long as elf_to_hex uses VMA).

Now let me read the drivers, VIP, monitors, checkers, tb.


### Text:
Significant findings already. Let me read the drivers and VIP/BFMs.


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 6 [assistant]


### Reasoning:
Critical finding: **GPIO register offsets are lowRISC-style (0x000, 0x004, ..., 0x580)** which are the **AXI-Lite/regfile (32-bit word-based with byte-addressed 0x4 spacing)**. But the plan explicitly says:

| **Sub-word MMIO on APB3 Peripherals** | `ls_unit.v`, `axi_lite_to_apb.sv` | Legacy APB3 IPs (UART, Timers, I2C, SPI) lack `PSTRB` port; `gpio_apb_wrap` has `PSTRB`. |

And the gap analysis says GPIO is `gpio_apb_wrap`. So GPIO uses `gpio_apb_wrap.sv` — need to check what register map `gpio_apb_wrap` exposes. The lowRISC `gpio.sv` core has the regfile at 0x00.. with 0x4 word spacing and offsets 0x00, 0x04, 0x08, 0x0C, ... 0x580. But **the lowRISC gpio is 32 bits** whereas this SoC's GPIO is likely 32-bit. Need to verify.

Hmm — actually lowRISC gpio_reg_pkg offsets: INFO=0x00, CFG=0x04, MODE_0=0x08, MODE_1=0x0c, ... IN=0x100, OUT=0x180, SET=0x200, CLEAR=0x280, TOGGLE=0x300, INTRPT_RISE_EN=0x380... INTRPT_STATUS=0x580. That's exactly right for lowRISC prim gpio. ✓ consistent.

**But `gpio_apb_wrap.sv`** — the lowRISC `gpio_apb_wrap` doesn't exist in upstream lowRISC prim; they have `gpio_cdc`. This is a custom wrapper. Need to check its address decoding — it may only expose a subset, and its INTRPT_STATUS might be at a different offset. This is a HIGH-risk finding requiring RTL cross-check.

Also **`gpio_driver.h` has no `GPIO_MODE` register write beyond MODE_0/MODE_1** — lowRISC GPIO with 32 pins only has MODE_0. MODE_1 is for 64-pin. Harmless.

**`gpio_driver.c` line 10: writes `GPIO_CFG_OFFSET = 0x00`** to set "all pins to normal GPIO mode". But CFG in lowRISC is a read-only config register in some versions. Writing to it may be a bus error or ignored. Need to check.

**`timer_driver.h` — `TIMER_CTRL_PRESC_SHIFT 3`**. The ETH Zurich `apb_timer` CTRL register: bit 0 = ENABLE, bits 3-5 = PRESCALER. Actually in the ETH `apb_timer`, CTRL is: `prescaler[5:3]` and `enable[0]`. ✓ correct.

But **`TIMER_VAL_OFFSET 0x00`, `TIMER_CTRL_OFFSET 0x04`, `TIMER_CMP_OFFSET 0x08`** — ETH `apb_timer.sv` REG_SIZE is 8 with VAL at 0x00, CTRL at 0x04, CMP at 0x08. ✓ 

**`uart_driver.h` — 16550 offsets.** The IP is `apb_uart-main/rtl/apb_uart.sv`. Standard 16550: RBR/THR 0, IER 1, IIR/FCR 2, LCR 3, MCR 4, LSR 5, MSR 6, SCR 7. With 32-bit word spacing: 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14 ✓. Need to verify against apb_uart.sv.

**`uart_init` writes FCR = 0x07 then IER = 0x00.** OK.

**`uart_driver.c` has a "BUG"**: `uart_puts` — `if (uart_putc(*s++) != 0)`. If `*s++` is evaluated once ✓.

**CRITICAL: `uart_recover()` step 2 is an UNBOUNDED loop**: `while (REG32_READ(LSR) & UART_LSR_DR) { read RBR; }`. If the DR bit never clears (which is the exact illegal-state condition recover() is meant to fix), **this hangs forever** — no cycle-bounded timeout. This directly violates the architectural mandate "cycle-bounded timeouts and illegal state recovery". **HIGH FINDING.**

**`uart_putc` timeout = 500000 cycles.** With 100 MHz clock that's 5 ms. But **`csr_read_mcycle()` — need to confirm mcycle exists in RTL.** If mcycle isn't implemented, timeout breaks entirely.

Also `uart_recover` has no mcycle-bounded loop at all.

Let me now read i2c, spi drivers andthe VIPs.


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 7 [assistant]


### Reasoning:
Major bugs found:

**I2C driver — CRITICAL BUGS:**
1. `i2c_start_addr` line 34: `REG32_WRITE(CR, I2C_CR_STA | I2C_CR_WR)` — no ACK bit set, meaning ACK=0 which is correct for the address byte. OK.
2. `i2c_read_byte` line 75: `if (!send_ack) cr |= I2C_CR_ACK;` — `I2C_CR_ACK` = (1<<3) with comment "ACK value to send (0=ACK, 1=NACK)". So `!send_ack` (i.e., send NACK) → set bit → NACK ✓. Logic correct but confusingly named.
3. **`i2c_recover` line 93: `REG32_WRITE(CR, I2C_CR_IACK)` with CTR disabled (EN=0)** — issuing a STOP while the core is disabled will not release the bus. Then it re-enables and issues STOP. Actually it does re-enable at step 4 then STOP at step 5 ✓.
4. **CRITICAL: `i2c_wait_tip()` — the driver polls SR.TIP. But the OpenCores/ETH I2C requires waiting on `SR.IF` (interrupt flag) for transfer completion, not TIP going low.** Actually TIP going low is the standard busy-poll. However: **the loop reads SR via the APB bus which takes many cycles.** With `I2C_DEFAULT_TIMEOUT_CYCLES = 500000` mcycle and the APB round trip being ~20-40 cycles, this is fine.
5. **REAL CRITICAL BUG: `i2c_start_addr` — `i2c_wait_tip()` is called immediately after writing CR. But the transfer may not have STARTED yet (TIP not yet asserted), so `i2c_wait_tip()` returns 0 IMMEDIATELY (TIP==0 before start), and then the code reads SR and checks RXACK which is still stale/0 → returns 0 (ACK) even though nothing happened.** This is a classic OpenCores I2C race: you must wait for TIP to go HIGH first, then wait for it to go LOW. **HIGH-severity bug: no "wait for TIP assert" phase.** This affects `i2c_start_addr`, `i2c_write_byte`, `i2c_read_byte`, `i2c_recover`.

**SPI driver — CRITICAL BUGS:**
1. **`spi_transfer_command` line 41: `while (REG32_READ(STATUS) & 0x1)` — status bit 0 on READ is `RXAVAIL` (RX FIFO data available), NOT "transfer in progress".** In the ETH `apb_spi_master`, STATUS read bits: [0]=RXAVAIL, [1]=TXAVAIL, [2]=RXFULL, [3]=TXEMPTY, [4]=... So polling `& 0x1` waits for RX data to be *available*, which for a WRITE-only transfer will **never** happen → guaranteed 500000-cycle timeout on every write transfer. **CRITICAL BUG.**
2. **`spi_transfer_command` — no TX FIFO fill before triggering.** The ETH SPI requires data written to TX FIFO before WR. `spi_write_tx_fifo` is never called inside `spi_transfer_command`. So `data_len_bits > 0` sends garbage/stale FIFO contents. **CRITICAL BUG.**
3. **CRITICAL: writing `STATUS_OFFSET` (0x00) is used BOTH as CS-select AND as command trigger.** In the ETH apb_spi_master, CS select bits are [12:8] in the write to STATUS ✓ and RD/WR are bits [0]/[1] ✓. That's consistent. BUT `spi_select_cs` writes CS bits only, no RD/WR — OK.
4. **`spi_recover` line 63: `REG32_WRITE(SPI_STATUS_OFFSET, SPI_CMD_SWRST)` — SWRST is bit 4 in the WRITE view.** Hmm — in ETH apb_spi_master STATUS write: bit 4 = SWRST ✓. But **bit 4 in the READ view is `RXFULL`**... actually let me not over-claim without the RTL. Need to verify against `apb_spi_master.sv`.
5. **`spi_recover` comment says "Clear interrupt status by reading INTSTA"** — reading INTSTA in the ETH SPI **sets** the interrupt status (it clears TXAVAIL/RXAVAIL/TXFULL flags on read). So this is correct behavior but the comment is confusing. Actually in ETH apb_spi_master, reading INTSTA clears the flags. OK.
6. **`spi_read_rx_fifo` has no "is data available" bound check.**

**Now let me read the VIP BFMs, which include two EMPTY files.**

Also note: `spi_driver.c` never verifies the ETH SPI reg map. Let me cross-check with RTL.

Let me read the VIPs and monitorsnow.


### Tool: None
Input: null


### Tool: None
Input: null


# Message 8 [assistant]


### Reasoning:
MAJOR BUGS in I2C VIP:

1. **`i2c_eeprom_at24c02.sv` — NO `rst_n` port.** It's missing reset entirely. Initial block handles power-on. Acceptable-ish but inconsistent.

2. **CRITICAL: `always @(posedge scl)` samples `sda` — but I2C requires SDA to be sampled on the HIGH period of SCL, ideally at the rising edge (data setup). Sampling at `posedge scl` is acceptable but the master changes SDA around the same edge; risk of metastability/mis-sampling. Standard practice is to sample at posedge SCL which is fine.

3. **CRITICAL RACE: two `always @(posedge scl)` and `always @(negedge scl)` blocks both drive `state`, `bit_idx`, `sda_en`, `sda_out`.** Non-blocking assignments from both edge blocks → the posedge and negedge blocks both assign; the negedge block assigns unconditionally (mostly). Since posedge only assigns `shift_in`, that's fine. But `shift_in` is assigned at posedge and SAMPLED at negedge in the same `bit_idx` step → this is the correct I2C pattern. OK actually.

4. **CRITICAL BUG: Address byte comparison `shift_in[7:1] == I2C_ADDR`.** `shift_in` is loaded MSB-first at `bit_idx = 7` down to 0. So `shift_in[7]` is the first bit = R/W. `shift_in[7:1]` = the 7-bit address ✓. Correct.

5. **CRITICAL BUG in `S_DEV_ACK` → `S_READ_DATA`: `shift_out <= memory[mem_addr]` and `sda_out <= memory[mem_addr][7]`.** But `mem_addr` at that point is 0 (never set, since no `S_MEM_ADDR` happened for a read). **CRITICAL: For a random-read sequence (START + devaddr+R + repeated START + devaddr+W + memaddr + repeated START + devaddr+R), the model has NO support for a repeated START.** After the first `S_DEV_ADDR` it goes to `S_DEV_ACK`, which on a *second* START (negedge sda while scl) sets `state <= S_DEV_ADDR` — actually that works since `always @(negedge sda)` fires on repeated START too. Hmm, so repeated START is handled by the negedge-sda block. OK, partial support.

   But **`is_read` is never initialized before `S_DEV_ACK`** — set in S_DEV_ADDR ✓.

6. **CRITICAL BUG: `S_READ_DATA` is completely broken.**
   - `sda_out` is only updated when `bit_idx != 0`, using `shift_out[bit_idx - 1]`. When `bit_idx == 0` it releases SDA and goes IDLE. But **the master's ACK/NACK bit is never sampled** — the model just releases the bus and goes to S_IDLE, ignoring the master ACK. So a multi-byte read (AT24C02 sequential read) **breaks after the first byte**. 
   - **Also: the model releases SDA at `negedge scl` when bit_idx==0, but never waits for the master's ACK.** For a proper sequential read the master should issue a repeated START or the slave should present the next byte.
   - **Also `mem_addr <= mem_addr + 1` happens at the END of the byte, after which state=S_IDLE. So even if ACK were handled, the FSM can't continue.**
   - **CRITICAL: the model drives `sda` from the very first negedge of `S_DEV_ACK` onwards but `S_READ_DATA`'s first data bit `memory[7]` is presented immediately — there's no issue since SDA changes on negedge SCL which is correct I2C.** ✓
   
   So: **random read of more than one byte is broken; sequential read is broken.** Only single-byte read works. **HIGH finding.**

7. **CRITICAL: `S_MEM_ADDR` reads a full 8-bit memory address, but the AT24C02 has a 6-bit address (256 bytes → 8-bit addressing, 8 bits address byte).** Actually AT24C02 = 2 Kbit = 256 bytes → needs 8-bit word address, so 1 address byte ✓. Memory array is `[0:255]` ✓. OK.

8. **`sda` is `inout wire` and the assign uses `1'bz` release ✓ but there's NO pull-up.** I2C needs pull-ups on SDA/SCL. If the DUT doesn't have internal pull-ups, the bus will be floating 'z' and the VIP's `scl` input will be 'x'. **CRITICAL: no `pullup()` on SDA.** Need to check whether the DUT enables internal pullups. HIGH finding.

9. **No `I2C_ADDR` NACK for other addresses → goes to S_IDLE and never ACKs.** But it also releases SDA mid-byte → the master's ACK check will fail. Acceptable but should hold SDA high during the remaining bits (real NACK behavior).

**UART VIP — CRITICAL BUGS:**
1. **`#(BIT_PERIOD_CYCLES * 10ns * 1.5)` — `BIT_PERIOD_CYCLES` is `int unsigned`, and `10ns` is a time literal. Multiplying an integer by a time literal requires a time-typed operand; `int * 10ns` in Verilog is ILLEGAL — you cannot multiply an integer variable by a time literal. This is a compile error: "Illegal multiply of a time literal by an integer variable" — actually Verilog allows `10ns * integer` only in some cases. Let me think: `time_literal * integer_expr` is not legal in Verilog-2001; SV allows `time * number`? No — SV time literals can be multiplied/divided by real/integer numbers only if the number is a constant... Actually IEEE 1800 allows `time_literal * integral_number`. From LRM: "time_literal ::= unsigned_number time_unit | fixed_point_number time_unit". And multiplication: `mult_expr ::= ... | mult_expr '*' expr`. For time, the LRM says time is a 64-bit unsigned number and multiply is allowed. But "unscaled" time (i.e., real-time without unit) is disallowed as a multiplier. `BIT_PERIOD_CYCLES` is an integer, `10ns` is a time literal → `int * time`. In Verilog this is generally an error: "Real/Time/integer type is not allowed here" or produces 0. **This is a high-risk compile/elaboration failure.** Also `#(delay)` requires the expression to be a time value.

   Actually more importantly: **even if it compiles, `clk` is completely unused!** The module has `input logic clk` and `input logic rst_n` but NEVER uses them. The monitor is a `forever @(negedge uart_tx)` block with absolute delays. So:
   - `rst_n` is unused → lint warning, no reset behavior.
   - The monitor is purely event-driven and will **not report errors**; it has no framing/parity/stop-bit checking, no overrun detection, no error counters, and **no comparison against an expected value**. The Integration Guide Step 6 requires "UART monitor" with "error injection". **The VIP is a $display-only decoder with zero checking and zero error injection.** FINDING.

2. **`rx_shift` is assigned in a `for` loop in a non-clocked always block with no reset; `rx_shift[i] = uart_tx;` uses blocking assignment on a `logic [7:0]` — fine.

3. **`assign uart_rx = loopback_en ? uart_tx : 1'b1;` — combinational loopback of a serial line: the DUT's TX drives uart_rx directly. This is a zero-delay digital loop which will NOT emulate a real UART framing (the DUT RX will sample at its own baud). Since both sides use the same baud and the loop is zero-delay, the DUT's RX sampler will see clean edges — acceptable for loopback. BUT this bypasses the wire entirely and thus does NOT verify "at the pins" with framing. **FINDING: loopback is a wire short, not a pin-level model.**

4. **`task automatic enable_loopback` declared inside the module but NEVER called** from soc_tb_top (need to check). Dead code unless instantiated with a control path.

5. **`initial loopback_en = 1'b0;`** → default is NOT loopback. So the DUT RX pin floats high (idle) and stage6 UART loopback test would fail unless loopback is enabled via a plusarg/force.

Now let me read the two EMPTY VIP files (0 bytes) to confirm, plus the monitors.


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 9 [assistant]


### Reasoning:
Confirmed: `gpio_pin_vip.sv` and `spi_flash_s25fs512s.sv` are **EMPTY (0 bytes)**.

More findings:
- `retire_monitor.sv` line 40: retirement detection uses `instr_w != 0` — **a legitimately retired instruction of 0x00000000 (illegal) would not be counted**. Also no bubble/valid signal is used, so **stall cycles that keep InstrW registered will be counted as multiple retirements**. Need to check how it's wired. **CRITICAL: no `valid` signal → miscounts on stalls.** Also the dump function checks `ring_buffer[idx].pc != 0 || ring_buffer[idx].trap` while the capture condition is `instr != 0` — inconsistent filtering.

- `fetch_monitor.sv` line 43: `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH` — **modulo by a non-power-of-2 is fine (64 is a power of 2) but `%` with `int unsigned` is expensive; more importantly it's fine functionally.**

- All monitors: `function automatic void dump_recent_*` — declared with a default arg `int count = 10`. **SystemVerilog does NOT allow default arguments in function declarations inside a module in a way that's portable to XSim... actually SV does support default args. But XSim/VCS support for default port/arg values is OK.**

- **CRITICAL COMPLIANCE GAP: The plan mandates each monitor "emits timestamped transaction objects on one shared cycle counter" and "Write them as SystemVerilog interfaces plus small classes so they can become UVM agents later without a rewrite" (Integration Guide Step 3). NONE of the monitors are SV interfaces; they are all plain modules with no transaction streams, no analysis ports, no classes.** This directly violates the Integration Guide's reusability mandate. **HIGH FINDING.**

- **CRITICAL: No monitor has a transaction-count *comparison* mechanism.** Stage 3's proof criterion is "number of executed stores matches LSU and AXI monitor transaction counts exactly". The monitors expose `total_writes`/`total_reads`/`total_fetches` as local variables with NO ports/outputs. They cannot be read by the testbench or scoreboard! `retire_monitor.total_retired` is an internal variable not brought out via a port. In Verilog you can hierarchical-reference, but there's no such reference in the TB. **CRITICAL FINDING: monitor counters are not observable; Stage 3 proof criterion is unimplementable as wired.**

Let me continue reading the rest.


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 10 [assistant]


### Reasoning:
Enormous findings here:

**`mmio_path_scoreboard.sv` — CRITICAL FAILURES:**
1. **It is NOT a scoreboard.** It has no expected-value queue, no data comparison, no ordering. The plan says: "each core MMIO access must appear as one AXI transaction and one APB transfer on the slot given by the address map, with the same data, strobes and response." This implementation only checks address→slot decoding on the APB side. It **never correlates with the LSU port at all** — `lsu_req`, `lsu_we`, `lsu_addr`, `lsu_wdata`, `lsu_be`, `lsu_stall` are all declared as inputs but **NEVER USED** (only used in the function? no — the function uses `paddr`). **6 of 12 input ports are dead. HIGH FINDING: no Core→AXI→APB path correlation implemented.**
2. **No data comparison** (`pwdata` is also unused!). Actually `pwdata` is an input but never referenced. So no data check.
3. **No strobe check.**
4. **`exp_slot` returns -1 for out-of-range**, and the check `if (exp_slot != s)` will fire for any unmapped hole. **That's intentional for the DECERR test.** But: for a transaction at `0x4000_3800` (unmapped APB hole), the bridge returns DECERR. Does `axi_lite_to_apb` still drive `PSEL` to a slot? If it drives PSEL to all-0 or to a default slot, the scoreboard will `$error`. Actually if PSEL=0, the loop won't fire. Need to check bridge behavior. But `$error` is called **unconditionally without first-fatal gating** — so **the scoreboard bypasses the failure_reporter's first-fatal blame engine entirely**. It just `$error`s. **CRITICAL: the scoreboard does not integrate with `failure_reporter.report_failure()`; no blame layer assigned, no freeze.**
5. **`get_expected_apb_slot` returns `0` for I2C range 0x4000_0000–0x4000_0FFF.** But the plan's gap matrix says "Unmapped APB Holes (0x4000_3800–0x4000_3FFF, 0x4000_6000–0x4FFF_FFFF) → RESP_DECERR". `0x4000_3800` is inside the GPIO range (0x4000_3000-0x4000_3FFF) so `get_expected_apb_slot` returns 3, matching. Fine. But the scoreboard has **no knowledge of the unmapped-hole → DECERR** case. Stage 4's proof criterion ("accessing unmapped APB hole 0x4000_3800 triggers RESP_DECERR and generates a 1-page failure report naming the exact check ID") — **the scoreboard would NOT report the DECERR because PSEL+PENABLE+PREADY happens and slot==3==expected**. There's no PSLVERR/RESP check at all. **CRITICAL: DECERR detection is missing.**

**`failure_reporter.sv` — CRITICAL FAILURES:**
1. **`report_failure` is a TASK that must be called explicitly.** It has no input ports for checkers. There is **no mechanism** by which an SVA assertion failure, a scoreboard error, or a monitor fault calls this task. SVA failures print to the log; they cannot call a module task. **CRITICAL: the first-fatal blame engine is architecturally orphaned — nothing invokes it.** No `bind`, no port, no analysis port.
2. **`freeze_monitors` is assigned with a blocking assignment inside a task called from... nothing.** It's a continuous `output logic` driven procedurally → OK syntactically but nothing drives the task.
3. **`fail_cycle = $time / 10;` "assuming 10ns clock" — hardcoded assumption, no parameter.** Minor.
4. **`$fopen`/`$fdisplay` to `failure_report.md` — file I/O in the middle of a simulation. XSim supports `$fopen` but `%s` with a `string` type is fine.** However: **the report does NOT include the last 10 disassembled instructions**, which is an explicit mandate: "generates a 1-page diagnostic report with the last 10 disassembled instructions" and "The output is a one-page report with the last retired instructions disassembled". The markdown report has NO instruction trace at all. **CRITICAL: mandated content missing.**
5. **No seed/git hash/ELF hash/RTL hash header.** Integration Guide Step 8 mandates: "Every log starts with seed, git hash, ELF hash and RTL hash." **MISSING.**
6. **No "vacuous pass" detection, no "no predicted event left unobserved" check** (Integration Guide "Pass rule"). **MISSING.**
7. **Layer enum is just an int passed in — no hierarchy enforcement.** The plan says "Blaming: lowest architectural layer first: Protocol(1) → Path(2) → ... → Firmware(6)" and "It blames the lowest layer that failed first and marks later failures as downstream." Implementation just takes the first caller's layer and ignores all later ones. **No downstream marking, no lowest-layer arbitration.**
8. **`failing_layer` is set but NEVER read.** Dead.
9. **`rst_n` input is NEVER used.** Dead port → lint warning.
10. **`clk` never used.** Dead port.

**`irq_monitor.sv` — CRITICAL FAILURES:**
1. **The 6 peripheral IRQ source inputs (`timer0_irq`, `timer1_irq`, ..., `spi_irq`) are NEVER USED.** Only `irq_ack` triggers capture. **HIGH: the "raise, pending, grant, accept, acknowledge" lifecycle logging mandated by Integration Guide Step 7 is NOT implemented.**
2. **`irq_txn_t` fields `asserted`, `granted`, `acked` are all hardcoded to 1'b1** — no actual detection of those events. The Integration Guide mandates "logs raise, pending, grant, accept and acknowledge, together with an interrupt predictor written from the interrupt specification". **NO predictor exists.** **CRITICAL: no independent interrupt predictor = no independent source of expected behaviour.**
3. **`irq_id <= mcause[4:0]`** — mcause for interrupts is `32 + irq_num` (bit 31 set). `mcause[4:0]` truncates to irq_num mod 32. **For mcause=27 (SPI) → 27 ✓; for mcause=19 → 19 ✓.** But the plan lists **mcause 7 = MTIP for Timer0** (machine timer interrupt), not 15. `mcause[4:0]` of 7 = 7 ✓. OK but loses the interrupt bit. **Also mcause=16 (GPIO) → 16 ✓.** Fine but lossy.
4. **No shadow-stack / preemption-level tracking at all.** Plan mandates: "irq_monitor.sv: Tracks IRQ lifecycle and shadow stack preemption levels." **MISSING — 0 of 2 responsibilities implemented.**
5. **No `nest_depth` / `class_stack` / `mepc_stack` monitoring.**

**`axi_lite_monitor.sv` — BUGS:**
1. **`latched_awaddr` / `latched_araddr` are single-deep.** AXI4-Lite allows only one outstanding, so OK, but there's no AW/W decoupling: **`ring_buffer[...].data <= wdata` uses the CURRENT `wdata`, not the data latched at the W handshake.** If W arrived before AW (legal in AXI), or if W is still valid when B arrives, the captured data is wrong. **Should latch on `wvalid && wready`. FINDING.**
2. **`ring_buffer[...].strb <= wstrb` at B time — same issue, should be latched at W.**
3. **NO `dump_recent_*` function** — the other monitors have one, this doesn't. Inconsistent; the failure reporter cannot dump AXI history.
4. **NO transaction counters at all** (no `total_axi_writes`/`total_axi_reads`). Stage 3's proof criterion ("AXI monitor transaction counts exactly") is unimplementable. **CRITICAL.**
5. **Ring buffer is 64 DEEP TOTAL, not 64 per channel.** The Integration Guide Step 3 explicitly says "AXI4-Lite (AW, W, B, AR and R as **separate events**)". The implementation merges them into a single 64-entry ring → **violates the explicit "separate events" requirement**, and a burst of 33 writes followed by 33 reads loses the first 33 writes. **HIGH FINDING.**
6. **Both write and read blocks assign `ring_buffer[head_ptr]` and `head_ptr` in the same always block → if both B and R handshakes occur in the same cycle, the second assignment wins (last-wins) → ONE transaction silently LOST.** AXI4-Lite has independent read/write channels so this IS possible. **CRITICAL BUG: simultaneous B and R handshakes lose a transaction.** Same bug exists in `apb_monitor.sv` (though APB is single-slot exclusive, so less likely) and in `lsu_monitor` (no).

**`apb_monitor.sv` — BUGS:**
1. **No `dump_recent_*` function.**
2. **No transaction counters.**
3. **The `for` loop over slots assigns `ring_buffer[head_ptr]` — if two PSELs are asserted simultaneously (shouldn't happen with one-hot PSEL but the plan says "One-hot PSEL" is a CHECKED property, not a guaranteed DUT property), multiple writes to the same entry + head_ptr. Last wins → loss.**
4. **`input logic [31:0] prdata [0:NUM_SLOTS-1]` — an unpacked array port. XSim/VCS support it, but binding to a flat `prdata` bus requires port collapsing. Need to check soc_tb_top wiring.**
5. **No PSLVERR capture issue — actually it does capture `pslverr[i]` ✓.**
6. **`total` counters missing.**

**Also `apb_monitor` has `paddr` as a single 32-bit value shared across all slots — so it cannot distinguish per-slot addresses.** If the bridge drives a common PADDR (typical), fine.

Now let me read the SVA files, soc_tb_top, tb_pkg, filelists, regression, and the suites. Let me parallelize with subagents for the bulk RTL cross-check.


### Text:
Major architectural gaps emerging. Let me read the SVA, TB top, and dispatch parallel RTL cross-checks.


### Tool: None
Input: null


### Tool: None
Input: null


### Tool: None
Input: null


# Message 11 [assistant]


### Reasoning:
Now this is very rich. Let me enumerate the findings in soc_tb_top.sv:

**CRITICAL FINDINGS in soc_tb_top.sv:**

1. **`axi_lite_monitor`, `apb_monitor`, `irq_monitor`, `axi_lite_protocol_sva`, `apb_protocol_sva` are ALL NEVER INSTANTIATED.** Only fetch_monitor, retire_monitor, lsu_monitor, mmio_path_scoreboard are instantiated. **5 of 10 mandated infrastructure components are dead code — never elaborated.** This is the single biggest finding: the AXI/APB/IRQ monitoring and protocol checking layers DO NOT EXIST in the running simulation. **CRITICAL.**

2. **`spi_flash_s25fs512s` is instantiated and `u_spi_flash_vip.preload_hex(flash_mem_path)` is called — but the module is a 0-BYTE EMPTY FILE.** → **COMPILE ERROR.** The entire simulation cannot elaborate. Same for `gpio_pin_vip` (0 bytes) instantiated at line 145. **CRITICAL: the testbench does not compile.**

3. **`gpio_pin_vip` port names (`.clk, .rst_n, .gpio_out_o, .gpio_oe_o, .gpio_in_i`)** — an empty file so no way to validate, but the manifest doesn't specify ports. Anyway it's empty.

4. **`uart_pin_vip` is instantiated with loopback DEFAULT DISABLED** (`initial loopback_en = 1'b0`), and `enable_loopback` is a task never called. **So `uart_sin` is permanently 1'b1 (idle high). Stage 6 UART loopback test can never pass.** **CRITICAL: Stage 6 proof criterion is unachievable.**

5. **CRITICAL MAILBOX SNOOPING BUG — `dut.u_dsram.mem[0..6]`:**
   - `assign mb_cmd = dut.u_dsram.mem[0]` — this is a *continuous* assignment to a memory word. Memory word index 0 ↔ byte address 0x20000 ✓.
   - `mb_char_out = mem[5]` → byte 0x20014 ✓ matches `char_out` at +0x14 ✓
   - `mb_error_code = mem[6]` → byte 0x20018 ✓ matches `error_code` at +0x18 ✓
   - So the mapping is right. BUT: **`cycle_cnt` at +0x1C (mem[7]) is not snooped** — minor.
   - **CRITICAL: `assign mb_cmd = dut.u_dsram.mem[0];` — the DSRAM `mem` array is also written by `$readmemh`.** With a continuous assign from a memory word, the simulator must re-evaluate on every write to `mem[0]`. XSim supports this. OK.

6. **CRITICAL — the character streaming monitor is LOSSY and LOSSY-BY-DESIGN:**
   ```systemverilog
   if (mb_char_out != 0 && mb_char_out != prev_char_out) begin
     $write("%c", mb_char_out[7:0]);
     prev_char_out <= mb_char_out;
   end
   ```
   - **It compares against `prev_char_out`, so repeating characters are DROPPED.** `"aaa"` prints ONE 'a'. **CRITICAL BUG.**
   - **`mb_char_out != 0` means a literal NUL character (0x00) is never printed.** Minor.
   - **Sampling at posedge clk means if firmware writes two different chars in consecutive cycles, one is lost.** `mailbox_putc` is a store; a loop of stores can easily outpace a 100 MHz sampler if the store completes in 1 cycle back-to-back. Actually each store takes ≥1 cycle through the LSU, and MMIO stores stall the core for many cycles, so back-to-back writes are unlikely. But the `prev_char_out` dedup bug is fatal regardless.
   - **NO ready/ack handshake** → this violates "zero-overhead character streaming" claim. **FINDING.**

7. **CRITICAL WATCHDOG BUG:** `sim_cycle_cnt` is declared `longint unsigned` and incremented in the watchdog `while` loop. Fine. **BUT the watchdog starts counting at time 0 — INCLUDING the reset period.** Actually more importantly: **the watchdog `while (sim_cycle_cnt < max_watchdog_cycles)` and the mailbox watcher are in a `fork...join_any`. `join_any` fires when EITHER completes.** When the mailbox watcher calls `$finish`, that's fine. But when the watchdog block's `while` loop EXITS (condition false), the block continues to `$finish(2)`. OK.
   
   **CRITICAL: `fork ... join_any` then the `initial` block ends. The other forked branch is still running.** Since `$finish` is called, the sim ends. OK.

   **REAL BUG: the watchdog's `report_failure` is called, THEN `dump_recent_retires`, THEN `$finish(2)`. But `report_failure` sets `freeze_monitors=1`, so the dumps happen on frozen data ✓ good design intent.**

   **REAL BUG: Stage 2's proof criterion — "Infinite loop trips the watchdog at the exact cycle limit".** The watchdog counts from t=0 including ~10 reset cycles and the `fork` start. So it's NOT the exact cycle limit relative to firmware execution start. Minor.

8. **CRITICAL — Stage 2 proof criterion: "dumps last PC correctly"** ✓ implemented via `dump_recent_retires`.

9. **CRITICAL — `LAYER_FIRMWARE` is used but I must check `tb_pkg.sv` for its definition.**

10. **`fetch_monitor` port `.pc_f (dut.u_core.PC_F, 2'b00)`** — hierarchical reference to `dut.u_core.PC_F`. Need to verify `u_core` is the instance name and `PC_F` is a signal in `top.v`. Per AGENTS.md, "PCSrcE1 is the only debug port from top" — so `PC_F` may be internal to `fetch_cycle.v`, not visible at `top.v` level. Hierarchical reference `dut.u_core.PC_F` will resolve only if PC_F is a signal in the `top` module scope or an intermediate. **HIGH RISK: hierarchical probe path likely wrong.**

11. **`retire_monitor` `.instr_w (dut.u_core.InstrW)`, `.rd_addr_w (dut.u_core.rd_W)`, `.rd_wdata_w (dut.u_core.ResultW)`, `.reg_we_w (dut.u_core.RegWriteW)`, `.trap_w (dut.u_core.trap_taken)`** — AGENTS.md mentions `PCSrcE1` is the only debug port. So `InstrW`, `rd_W`, `ResultW`, `RegWriteW`, `trap_taken` may be internal to `writeback_cycle.v`. **HIGH RISK.**

12. **`lsu_monitor` `.lsu_req (dut.u_core.lsu_mem_req)` etc.** — AGENTS.md says `hybrid_mem_interface.sv` and `ls_unit.v` are in `riscv_core/rtl/`. The plan says the LSU signals are `lsu_mem_addr`, `lsu_mem_wdata`, `lsu_mem_rdata`, `lsu_mem_be`, `lsu_mem_we`. Need to verify these names exist.

13. **`.pc_w (dut.u_core.PC_W)`** — again unverified.

14. **CRITICAL: `mmio_path_scoreboard` connects `.psel (dut.apb_psel)` — needs to be a `[5:0]` at the subsystem level.** Need to verify `riscforge_soc_subsystem` exposes `apb_psel`, `apb_penable`, `apb_pready`, `apb_paddr`, `apb_pwdata`, `apb_pwrite`. **Also `apb_pslverr` and per-slot `prdata` are NOT connected because the scoreboard doesn't have those ports — that's fine, but `apb_protocol_sva` needs them and isn't instantiated anyway.**

15. **CRITICAL: `NUM_DATA_WORDS(0)` and `NUM_INSTR_WORDS(64)` in the DUT instantiation!** With `NUM_INSTR_WORDS = 64` words = 256 bytes of ISRAM, but ISRAM is 32 KB! **This would truncate the instruction memory to 256 bytes**, so any real program wouldn't fit. Unless the parameter is only used for the "new" memory. **CRITICAL: need to check `riscforge_soc_subsystem.sv` parameter semantics.** Also `$readmemh` into `dut.u_imem_wrapper.Instruction_Memory_new.mem_array` requires `NUM_INSTR_WORDS(64)` to mean a 64-word array = 256 bytes, but `imem.hex` is 10240 bytes of hex text. `$readmemh` with too few words → warning, truncated program. **CRITICAL SUSPECT.**

16. **`FLASH_POWERUP_CYCLES(100)`** — fine.

17. **`import gpio_reg_pkg::GPIOCount;`** — a package import inside a module. Need to verify `gpio_reg_pkg` is compiled and in scope (declared in `soc_verification.f`). **If not in the filelist → compile error.**

18. **`string boot_mode_str = "WARM";`** — SystemVerilog variable initialization at module scope. XSim 2022.2 supports this. VCS supports it.

19. **`void'($value$plusargs(...))`** — `void'()` cast is SV; `$value$plusargs` returns int. OK.

20. **NO `+UVM_TESTNAME`/seed handling.** Integration Guide Step 8: "Every log starts with seed, git hash, ELF hash and RTL hash." **The TB banner prints only BOOT MODE and WATCHDOG LIMIT. No seed, no git hash, no ELF hash, no RTL hash.** **MANDATE MISSING.**

21. **NO "vacuous pass" detection.** Integration Guide pass rule: "a test passes only when the mailbox reports PASS, no checker failed, **the checkers actually saw activity (no vacuous pass)**, no predicted event is left unobserved, and no timeout occurred." The mailbox watcher calls `$finish(0)` on CMD_PASS with ZERO verification that any monitor/checker saw activity. **CRITICAL: vacuous pass is structurally permitted. A test that does nothing and returns 0 → PASS.** Also all checker pass/fail is ignored on `$finish(0)`.

22. **NO scoreboard/assertion failure aggregation into the pass decision.** `axi_lite_protocol_sva` uses `$error` in an `else` clause — in most simulators `$error` sets an error count and, with `-error_limit`, can terminate, but here it does NOT prevent `$finish(0)`. **So a run with protocol assertion failures can still be reported as PASS.** **CRITICAL.**

23. **`$finish(0)` then the watchdog/mailbox fork**: the mailbox watcher calls `$finish(0)` — but `join_any` means the initial block completes, and the other branch keeps running. `$finish` ends all. OK.

24. **`#500ns` before `$finish`** to let the last write settle — reasonable.

25. **COLD BOOT: `@(posedge boot_done);`** — if the bootloader never asserts boot_done, the mailbox watcher still runs. OK. But `fetch_enable = 1'b1` is set at t=0 for BOTH modes — for cold boot the core may start fetching from BOOTROM before `boot_addr` is valid. **Need to check.**

26. **`boot_addr = 32'h0001_0000;`** — for cold boot the bootloader sets it.

27. **`#100ns` reset then `#100ns` warm preload then release reset.** The warm boot path: reset asserted for 200 ns = 20 cycles, preload, then release. **"Warm boot primary... Core runs instantly at t=0"** — approximately achieved ✓.

28. **CRITICAL: There's no `$readmemh` for the mailbox clearing.** `dmem.hex` contains whatever the linker put at 0x20000. The `.mailbox` section is NOLOAD so the converter shouldn't emit it → dmem.hex[0] = 0 = CMD_RUNNING ✓. Need to verify `elf_to_hex_clean.py` skips NOLOAD.

29. **NO reset of `prev_char_out` on reset** — `initial prev_char_out = 0` only.

Now let me read tb_pkg.sv, the filelists, regression runner, elf_to_hex, and the test suites. And I need to verify the RTL signal names. Let me dispatch subagents for the RTL cross-check in parallel.


### Text:
Now let me cross-check RTL signal names and read the remaining infrastructure in parallel.


### Tool: None
Input: null


### Tool: None
Input: null

---

## Current-status addendum — 2026-10-22

This file preserves the original raw audit conversation and its findings. Do not treat it as a current status report by itself. The latest retained execution evidence is `artifacts/component_first/20261018_run01/`:

- The historical “SoC testbench cannot elaborate” finding is superseded: `soc_compile/reproducibility.json` records successful XSim compile and `soc_tb_top` elaboration. A full SoC simulation is not shown.
- The simultaneous IRQ ring-buffer loss was reproduced before a monitor change and the later stress log reports 165 checks, 0 failures. The targeted stress issue is therefore fixed in the tested configuration; broader monitor behavior is not thereby certified.
- Monitor smoke and 25 empirical challenge checks pass. Boot/reset retention passes 36 checks. GPIO direct-wrapper and I2C direct-APB suites pass 312 and 90 checks respectively.
- UART and AXI-Lite-to-APB bridge remain incomplete. UART stops advancing around reset. Bridge TC3 stalls on an unmapped address and logs arbiter assertions after TC1/TC2 basic accesses pass.
- The component-first bundle does not run firmware stages 1–7 or establish full SoC functional coverage. Other raw findings about driver recovery, register/IRQ predictors, end-to-end path checking, mailbox/reporting, and dual-simulator support remain not re-audited unless separately verified.

The dated pre-audit scope and open checkpoints are in `.agents/teamwork/auditor_gate_1/pre_audit_brief_2026-10-22.md`. The reconciled interim report is `.agents/teamwork/auditor_gate_1/audit_report.md`; neither claims the comprehensive audit is complete.
