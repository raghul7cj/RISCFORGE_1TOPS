# RISCFORGE 1TOPS — I2C Master Datapath Verification & Design Overview Report

---

## 1. Executive Summary

The **APB I2C Master IP (`apb_i2c` @ `0x4000_0000`)** has been verified end-to-end within the **RISCFORGE 1TOPS SoC Subsystem** (`riscforge_soc_subsystem.sv`) communicating with the **AT24C02 2Kb I2C EEPROM Slave Model** (`i2c_at24c02.sv`) driven by the RV32IM 5-stage RISC-V processor core.

* **Target DUT**: `riscforge_soc_subsystem` (`ips/RTL_SOC/riscforge_soc_subsystem.sv`)
* **Simulation Environment**: Synopsys VCS `U-2023.03` (64-bit) on Linux Server `172.16.33.48`
* **Test Suite**: 3 comprehensive I2C EEPROM test scenarios (Byte Write, Random Read & Compare, Multi-Location Write/Read)
* **Overall Status**: **100% PASSED** (`3/3 Tests Verified`)
* **Simulation Time**: `3,287,465,000 ps` (~3.29 ms)

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
|   | APB[2]: 16550 UART0       |   | APB[0]: APB I2C Master    |                         |
|   | Base: 0x4000_2000         |   | Base: 0x4000_0000         |                         |
|   | (Live Console Logger)     |   | (Master Controller)       |                         |
|   +---------------------------+   +---------------------------+                         |
|                 |                               | (i2c_scl, i2c_sda open-drain)         |
+-----------------|-------------------------------|---------------------------------------+
                  |                               |
                  v                               v
         [ UART0 Serial Rx ]             [ AT24C02 I2C EEPROM ]
         "TEST RESULT: PASSED"           (i2c_at24c02.sv @ 0x50)
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
  crt0.S (Startup) + i2c_smoke_test.c (C Tests) + link.ld (Linker)
                         |
                         v  (riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -O2)
                     app.elf (Combined ELF Binary)
                         |
                         v  (elf_to_hex.py)
            +------------+------------+
            |                         |
            v                         v
        imem.hex                  dmem.hex
  (ISRAM: 432 words)        (DSRAM: 2308 words)
  Mapped @ 0x0001_0000      Mapped @ 0x0002_0000
```

---

## 4. Detailed Test Execution & Results

### Test 1: EEPROM Byte Write (`0x10` &larr; `0xA5`)
* **Objective**: Perform single-byte write to address `0x10` of AT24C02 EEPROM.
* **Transaction**: START &rarr; Device Address `0x50` (Write: `0xA0`) &rarr; Word Address `0x10` &rarr; Data `0xA5` &rarr; STOP.
* **Hardware Validation**: Slave acknowledges all 3 phases (`RxACK == 0`).
* **Status**: **PASSED**

### Test 2: EEPROM Random Read & Compare (`0x10` &rarr; `0xA5`)
* **Objective**: Perform random byte read from address `0x10` and verify data integrity against written value.
* **Transaction**: Dummy Write (`0xA0` + `0x10`) &rarr; Repeated START (`0xA1`) &rarr; Read Byte + Master NACK + STOP.
* **Hardware Validation**: Read data byte matches expected value `0xA5`.
* **Status**: **PASSED**

### Test 3: Multi-Location Verification (`0x20` &larr; `0x5A`, `0x30` &larr; `0x3C`)
* **Objective**: Write multiple non-contiguous memory locations and perform subsequent random reads.
* **Transaction**: Write `0x5A` to `0x20` and `0x3C` to `0x30`. Read back and verify both locations.
* **Hardware Validation**: Read values `0x5A` and `0x3C` match expected constants.
* **Status**: **PASSED**

---

## 5. Verification Sign-Off Table

| Test Suite | Subsystem Interface | Tested Hardware / IP | Target Model | Result |
|---|---|---|---|:---:|
| **Test 1** | APB &rarr; I2C Core &rarr; Open-Drain Bus | APB I2C Master (`0x4000_0000`) | AT24C02 EEPROM (`0x50`) | <span style="color:green;font-weight:bold;">PASSED</span> |
| **Test 2** | APB &rarr; I2C Core &rarr; Open-Drain Bus | APB I2C Master (`0x4000_0000`) | AT24C02 EEPROM (`0x50`) | <span style="color:green;font-weight:bold;">PASSED</span> |
| **Test 3** | APB &rarr; I2C Core &rarr; Open-Drain Bus | APB I2C Master (`0x4000_0000`) | AT24C02 EEPROM (`0x50`) | <span style="color:green;font-weight:bold;">PASSED</span> |
| **Telemetry** | APB &rarr; OBI UART &rarr; Serial Pin | 16550 UART0 (`0x4000_2000`) | TB UART Receiver Monitor | <span style="color:green;font-weight:bold;">PASSED</span> |

---

## 6. Raw Synopsys VCS Simulation Log

```text
===============================================================
    RISCFORGE 1TOPS — I2C MASTER & AT24C02 SIMULATION         
===============================================================
[TB-DIAG] @0 Bootloader State -> S_RESET
[TB] Loading ISRAM from '../datapath_verification/i2c0/imem.hex'...
[TB] Loading DSRAM from '../datapath_verification/i2c0/dmem.hex'...
[TB] Warm reset de-asserted at t = 195000 ns

[TB-DIAG] @205000 Bootloader State -> S_CLEAN_ASSERT
[TB-DIAG] @215000 Bootloader State -> S_CLEAN_HOLD
[TB-DIAG] @255000 Bootloader State -> S_CLEAN_RELEASE
[TB-DIAG] @255000 Core Reset Released! boot_done=0, PC=0x00000000
[TB-DIAG] @265000 Bootloader State -> S_DONE

=======================================================
   RISCFORGE 1TOPS - I2C Master & AT24C02 Smoke Test   
=======================================================
[INFO] Initializing I2C Master Controller (Prescaler=20)...
[INFO] I2C Master Initialized.

[TEST 1] EEPROM Byte Write...
  Slave Addr : 0x50
  Mem Offset : 0x00000010
  Write Data : 0x000000A5
  --> [TEST 1 PASSED: Byte Write ACKed by Slave]

[TEST 2] EEPROM Byte Read & Compare...
  Read Data  : 0x000000A5
  --> [TEST 2 PASSED: Read data matches written data 0xA5]

[TEST 3] Multi-Location Write & Read Verification...
  Addr 0x20 -> Exp: 0x5A, Got: 0x0000005A
  Addr 0x30 -> Exp: 0x3C, Got: 0x0000003C
  --> [TEST 3 PASSED: Both locations verified successfully]

=======================================================
>>> TEST RESULT: [ PASSED ] <<<
=======================================================

===============================================================
 [SIMULATION SUCCESS] All I2C Master tests verified successfully!
===============================================================
           V C S   S i m u l a t i o n   R e p o r t 
Time: 3287465000 ps
```
