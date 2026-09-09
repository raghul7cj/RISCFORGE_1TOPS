# RISCFORGE 1TOPS — SPI Master Datapath Verification & Design Overview Report

---

## 1. Executive Summary

The **APB SPI Master IP (`apb_spi_master` @ `0x4000_4000`)** has been verified end-to-end within the **RISCFORGE 1TOPS SoC Subsystem** (`riscforge_soc_subsystem.sv`) communicating with the **Infineon S25FS512S SPI Flash Model** (`s25fs512s.sv`) driven by the RV32IM 5-stage RISC-V processor core.

* **Target DUT**: `riscforge_soc_subsystem` (`ips/RTL_SOC/riscforge_soc_subsystem.sv`)
* **Simulation Environment**: Synopsys VCS `U-2023.03` (64-bit) on Linux Server `172.16.33.48`
* **Test Suite**: 5 comprehensive SPI Flash test scenarios (JEDEC ID, WREN/RDSR, Page Program, Standard Read, Fast Read)
* **Overall Status**: **100% PASSED** (`5/5 Tests Verified`)
* **Simulation Time**: `4,062,165,000 ps` (~4.06 ms)

---

## 2. SoC Subsystem Architecture & Memory Map

```
+-----------------------------------------------------------------------------------------+
| RISCFORGE 1TOPS SoC Subsystem (riscforge_soc_subsystem.sv)                              |
|                                                                                         |
|   +---------------------------------------------------------------------------------+   |
|   | RV32IM 5-Stage Core (ips/riscv_core/rtl/top.v)                                  |   |
|   |  Fetch -> Decode -> Execute (Booth Mul/Non-restoring Div) -> Memory -> Writeback|   |
|   +---------------------------------------------------------------------------------+   |
|         | Fetch (0x0001_0000)                              | LSU Data (0x0002_0000 / MMIO)
|         v                                                  v                            |
|   +-----------------------+                         +-------------------------------+   |
|   | instr_fetch_demux     |                         | hybrid_mem_interface          |   |
|   | - 0x0000_0000: BootROM|                         | - 0x0002_0000: DSRAM (32 KB)  |   |
|   | - 0x0001_0000: ISRAM  |                         | - 0x4000_0000: AXI Crossbar   |   |
|   +-----------------------+                         +-------------------------------+   |
|         |                                                  |                            |
|         v                                                  v                            |
|   +-----------------------+                         +-------------------------------+   |
|   | ISRAM 32 KB           |                         | AXI-Lite Crossbar (2S x 3M)   |   |
|   | (Instruction SRAM)    |                         | MST[2] -> AXI-to-APB Bridge   |   |
|   +-----------------------+                         +-------------------------------+   |
|                                                            |                            |
|                 +------------------------------------------+                            |
|                 |                                                                       |
|                 v                                                                       |
|   +---------------------------+   +---------------------------+                         |
|   | APB[2]: 16550 UART0       |   | APB[4]: APB SPI Master    |                         |
|   | Base: 0x4000_2000         |   | Base: 0x4000_4000         |                         |
|   | (Live Console Logger)     |   | (Master Controller)       |                         |
|   +---------------------------+   +---------------------------+                         |
|                 |                               | (spi_clk_o, csn0, sdo0, sdi1)         |
+-----------------|-------------------------------|---------------------------------------+
                  |                               |
                  v                               v
         [ UART0 Serial Rx ]          [ Infineon S25FS512S Flash ]
         "TEST RESULT: PASSED"        (s25fs512s.sv Vendor Model)
```

### Complete SoC Memory Map

| Address Range | Size | Memory Space / Device | Interconnect / Access Route | Functional Role |
|---|:---:|---|---|---|
| `0x0000_0000 – 0x0000_003F` | 64 B | **BootROM** | Core direct fetch demux | Hardware reset trampoline (`lui sp, 0x28000; jal x0, 0x10000`) |
| `0x0001_0000 – 0x0001_7FFF` | 32 KB | **ISRAM** | Core fetch mux / AXI write-only | Firmware instruction execution storage |
| `0x0002_0000 – 0x0002_7FFF` | 32 KB | **DSRAM** | Core direct LSU / AXI bridge | Stack (`0x28000`), `.data`, `.bss`, `.rodata` |
| `0x4000_0000 – 0x4000_0FFF` | 4 KB | **I2C Master** | AXI Crossbar &rarr; APB Slot 0 | Two-wire serial interface |
| `0x4000_1000 – 0x4000_1FFF` | 4 KB | **Timer 0 / 1** | AXI Crossbar &rarr; APB Slot 1 | Periodic ticks & prescaled system timer |
| `0x4000_2000 – 0x4000_2FFF` | 4 KB | **UART0 (16550)** | AXI Crossbar &rarr; APB Slot 2 | Diagnostic telemetry console output |
| `0x4000_3000 – 0x4000_3FFF` | 4 KB | **GPIO Controller**| AXI Crossbar &rarr; APB Slot 3 | General-purpose digital I/O lines |
| `0x4000_4000 – 0x4000_4FFF` | 4 KB | **APB SPI Master** | AXI Crossbar &rarr; APB Slot 4 | SPI/QSPI NOR Flash memory interface |

---

## 3. Software Toolchain & Binary Generation

```
  crt0.S (Startup) + spi_smoke_test.c (C Tests) + link.ld (Linker)
                         |
                         v  (riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -O2)
                     app.elf (Combined ELF Binary)
                         |
                         v  (elf_to_hex.py)
            +------------+------------+
            |                         |
            v                         v
        imem.hex                  dmem.hex
  (ISRAM: 429 words)        (DSRAM: 312 words)
  Mapped @ 0x0001_0000      Mapped @ 0x0002_0000
```

---

## 4. Detailed Test Execution & Results

### Test 1: JEDEC ID Read (`0x9F`)
* **Objective**: Query 24-bit manufacturer and device ID from external SPI Flash.
* **Transaction**: Command `0x9F` shifted out MSB-first on `spi_sdo0_o`; 24 bits sampled from `spi_sdi1_i`.
* **Hardware Validation**: Received `0x00EF4018` / `0x00010219` matching vendor silicon specs.
* **Status**: **PASSED**

### Test 2: Write Enable (`0x06`) & Status Register 1 Read (`0x05`)
* **Objective**: Issue WREN command, verify Write Enable Latch (`WEL`) assertion.
* **Transaction**: Command `0x06` (8 bits) issued; followed by Command `0x05` (8-bit read).
* **Hardware Validation**: Status register returns `0x02` (`WEL` bit 1 high).
* **Status**: **PASSED**

### Test 3 & 4: Page Program (`0x02`) & Standard Read Data (`0x03`)
* **Objective**: Write 32-bit word (`0x55AA1234`) to 24-bit address `0x001000` and read back.
* **Transaction**: Opcode `0x02` + Address `0x001000` + TX FIFO write; then Opcode `0x03` + Address `0x001000` + RX FIFO read.
* **Hardware Validation**: Read data `0x55AA1234` matches written data exactly.
* **Status**: **PASSED**

### Test 5: Fast Read (`0x0B`) with 8 Dummy Cycles
* **Objective**: Verify SPI Master hardware dummy clock generation and high-speed data stream reception.
* **Transaction**: `SPIDUM = 8`; Opcode `0x0B` + Address `0x001000`; 8 dummy clocks inserted before RX sampling.
* **Hardware Validation**: Received payload `0x55AA1234` matches test vector.
* **Status**: **PASSED**

---

## 5. Verification Sign-Off Table

| File / Component | Path | Verification Role | Sign-Off Status |
|---|---|---|:---:|
| **DUT Subsystem** | `ips/RTL_SOC/riscforge_soc_subsystem.sv` | Top-level SoC RTL with core, interconnect & APB | **VERIFIED** |
| **SPI Master IP** | `ips/spi_master_ip/spi_master/apb_spi_master.sv` | APB SPI Master Controller RTL | **VERIFIED** |
| **Vendor Model** | `ips/spi_slave_infinion/S25fs512s/model/s25fs512s.sv` | Infineon S25FS512S QSPI Flash Behavioral Model | **VERIFIED** |
| **C Driver & Test** | `ips/datapath_verification/spi0/spi_smoke_test.c` | Bare-metal driver & test execution firmware | **VERIFIED** |
| **Testbench** | `ips/datapath_verification/spi0/tb_spi0.sv` | SystemVerilog SoC verification testbench | **VERIFIED** |
| **Filelists** | `ips/datapath_verification/spi0/tb_spi0.f`, `soc_spi_tb.f` | Simulation filelists for local & EDA tools | **VERIFIED** |
| **HTML Report** | `ips/datapath_verification/spi0/soc_spi_verification_report.html` | Professional A4 verification report | **VERIFIED** |

