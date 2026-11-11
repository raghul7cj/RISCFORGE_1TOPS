# SoC Firmware Rules

Rules for anyone writing bare-metal firmware for `riscforge_soc_subsystem`. Each rule
says what to do, what goes wrong otherwise, and where in the RTL it comes from.
Breaking most of them does not give a clean error: the SoC hangs until a bus
timeout fires, silently corrupts a register, or takes an access-fault trap.

Working examples that follow every rule: `mem/regtest/` (register test),
`mem/pong/` and `mem/arm/` (board firmware).

---

## 1. Build settings

| Rule | Why |
|---|---|
| Compile with `-march=rv32i_zicsr -mabi=ilp32` | All current firmware and board builds use RV32I. The M extension is implemented, but the multiplier still reports port-width warnings at elaboration (`rv32m_mul.v`); use `M` only once it is signed off for your use. |
| No compressed (`C`) instructions | The core is RV32IM, no C extension. Trap handlers that return to `mepc + 4` rely on this. |
| No byte or half-word loads/stores (`lb/lh/lbu/lhu/sb/sh`) to peripherals | See section 4. `mem/regtest/build.py` and `mem/pong/build.py` scan the disassembly and fail the build if they find them. |

## 2. Memory map and where things must live

| Region | Range | Firmware access |
|---|---|---|
| Boot ROM | `0x0000_0000 - 0x0000_003F` (64 B) | **Instruction fetch only.** A load/store faults. |
| ISRAM | `0x0001_0000 - 0x0001_7FFF` (32 KB) | **Instruction fetch only.** A load/store faults (`hybrid_mem_interface.sv:72`, `addr_fault`). |
| DSRAM | `0x0002_0000 - 0x0002_7FFF` (32 KB) | Loads and stores, 1 stall cycle per load. |
| Peripherals | `0x4000_0000 - 0x4FFF_FFFF` | 32-bit loads and stores only (section 4). |
| Anything else | - | Load/store access fault (mcause 5/7), instruction fetch access fault (mcause 1). |

**Rules:**

1. **Put everything the program reads in DSRAM**: `.rodata`, `.data`, `.bss`, stack. Constants, string tables and lookup tables left in ISRAM fault the first time they are read. Use `mem/regtest/link.ld` as the template (`.text > ISRAM`, `.rodata/.data/.bss > DSRAM`).
   - Do **not** use a linker script that places `.rodata` in ISRAM or copies `.data` from an ISRAM load address (for example the older `D:\riscv-toolchain\link.ld`): the copy loop itself loads from ISRAM and faults.
2. **`_start` must be the first word of `.text`.** The boot ROM sets `sp = 0x0002_8000` and jumps to `0x0001_0000` (`mem/common/riscforge_bootrom.hex`).
3. **Image size:** at most 8192 instruction words and 8192 data words. The bootloader copies exactly `NUM_INSTR_WORDS` + `NUM_DATA_WORDS` from flash (`fw_params.svh`). On the FPGA these counts are built into the bitstream: if the firmware size changes, rebuild the bitstream too.

## 3. Address map of the peripherals

| Slot | Peripheral | Base | Window |
|---|---|---|---|
| APB[0] | I2C | `0x4000_0000` | 4 KB |
| APB[1] | Timer 0 | `0x4000_1000` | 4 KB |
| APB[2] | UART | `0x4000_2000` | 4 KB |
| APB[3] | GPIO | `0x4000_3000` | **2 KB** |
| APB[4] | SPI master | `0x4000_4000` | 4 KB |
| APB[5] | Timer 1 | `0x4000_5000` | 4 KB |

- An address inside `0x4000_0000-0x4FFF_FFFF` that is in no slot (for example `0x4000_3800`, `0x4000_6000`) returns DECERR and the core takes an access fault.
- Most peripherals decode only a few address bits, so their registers **repeat** through the window (I2C every `0x40`, timers and UART every `0x20`, SPI every `0x40`). Use the base offsets only.

## 4. All peripheral accesses: 32-bit only

| Rule | What goes wrong otherwise |
|---|---|
| Use 32-bit `lw`/`sw` for every peripheral register | Timer, SPI and I2C ignore the byte strobes: a byte/half-word store writes the whole register with the other bytes garbled. GPIO rejects sub-word stores with SLVERR, so the core takes a store access fault. |
| Use `volatile uint32_t *` for every MMIO pointer | Without `volatile` the compiler may merge, reorder or drop accesses. |
| Write registers with a full value, not read-modify-write on bits you do not own | Several registers have side effects on write (SPI STATUS, timer CMP, UART LCR), see below. |

## 5. Timer 0 / Timer 1

Two channels per timer; channel `n` registers at `+0x10*n`: `VAL +0x0`, `CTRL +0x4`, `CMP +0x8`.

| Rule | Why |
|---|---|
| **Writing CMP also clears VAL to 0** | `timer.sv`: the CMP write path resets `REG_TIMER`. Program CMP first, then VAL if you need a start value. |
| With `CTRL.EN = 1`, VAL counts to CMP and then resets to 0 | Use this for a fixed period (pong frame tick). CMP = 0 disables the compare match. |
| Disable (`CTRL.EN = 0`) before reprogramming | A disabled timer raises no IRQ and does not auto-clear VAL. |
| Prescaler is `CTRL[5:3]`; 0 = count every clock | |
| Compute periods from the real clock: 40 MHz (pong board build), 32 MHz (arm board build), 100 MHz (simulation) | |

## 6. UART (16550-style, plain TX/RX)

Registers: `RBR/THR/DLL +0x00`, `IER/DLM +0x04`, `IIR/FCR +0x08`, `LCR +0x0C`, `MCR +0x10`, `LSR +0x14`.

| Rule | Why |
|---|---|
| Divisor `{DLM,DLL}` must be **>= 2** | `obi_uart_baudgen.sv`: divisor 1 is treated as invalid and the baud generator stops. |
| Divisor = `round(CLK_HZ / (16 * BAUD))` | One oversample tick every divisor clocks, 16 ticks per bit. Example: 40 MHz, 115200 baud -> 22. |
| Set the divisor with `LCR = 0x80` (DLAB), write DLL/DLM, then write LCR with the full frame format (e.g. `0x03` = 8N1) | Write LCR with a full value, not read-modify-write. |
| Poll `LSR` bit 5 (THRE) before writing THR, bit 0 (DR) before reading RBR | Writing THR while it is full overwrites a character (FIFO off). |
| Use the UART as plain TX/RX: leave IER bit 3 (EDSSI) = 0 and do not use MSR | The modem lines are not used in this SoC. Known issue: MSR reads `0x0F` after reset instead of `0x00` (`obi_uart_modem.sv` synchronizer reset values); enabling EDSSI would give one false modem interrupt. |
| LSR and MSR are read-only: a write returns SLVERR (access fault) | |
| SCR (`+0x1C`) is not implemented: reads 0, writes ignored | |
| With DLAB = 1, offsets `0x08-0x1C` can be read (current RTL). Older firmware that avoided this is still correct. | |

## 7. GPIO (32 pins, 2 KB window)

**Use the offsets from `gpio_reg_pkg.sv`. They are spaced `0x80` apart, not `0x4`:**

| Register | Offset | Register | Offset |
|---|---|---|---|
| INFO | `0x000` | INTRPT_RISE_EN | `0x380` |
| CFG | `0x004` | INTRPT_FALL_EN | `0x400` |
| GPIO_MODE_0 | `0x008` | INTRPT_LVL_HIGH_EN | `0x480` |
| GPIO_MODE_1 | `0x00C` | INTRPT_LVL_LOW_EN | `0x500` |
| GPIO_EN | `0x080` | INTRPT_STATUS (W1C) | `0x580` |
| GPIO_IN | `0x100` | INTRPT_RISE_STATUS (W1C) | `0x600` |
| GPIO_OUT | `0x180` | INTRPT_FALL_STATUS (W1C) | `0x680` |
| GPIO_SET | `0x200` | INTRPT_LVL_HIGH_STATUS | `0x700` |
| GPIO_CLEAR | `0x280` | INTRPT_LVL_LOW_STATUS | `0x780` |
| GPIO_TOGGLE | `0x300` | | |

The register table in the `riscforge_soc_subsystem.sv` header comment and in
`core_soc_integration_v5.pdf` lists these 4 bytes apart (e.g. GPIO_EN at `0x010`).
That table is wrong; `0x010` is an unmapped offset and faults.

| Rule | Why |
|---|---|
| Set the pin's bit in `GPIO_EN` before reading it in `GPIO_IN` | GPIO_IN is frozen for pins whose GPIO_EN bit is 0. |
| Unmapped offsets inside the 2 KB window return SLVERR (access fault) | reggen register block. |
| Clear interrupt status by writing 1 (W1C); writing 0 does nothing | For level interrupts, remove the cause before clearing. |

## 8. SPI master

Registers: `STATUS +0x00`, `CLKDIV +0x04`, `SPICMD +0x08`, `SPIADR +0x0C`, `SPILEN +0x10`, `SPIDUM +0x14`, `TXFIFO +0x18`, `RXFIFO +0x20`, `INTCFG +0x24`, `INTSTA +0x28`.

| Rule | What goes wrong otherwise |
|---|---|
| **Read RXFIFO only when `STATUS[20:16]` (RX count) != 0** | Reading an empty RXFIFO holds the APB bus (PREADY low) until the SPI bus-timeout monitor fires after 65536 cycles, then the core takes a load access fault. |
| **Write TXFIFO only when `STATUS[28:24]` (TX count) < 10** | Same stall on a full FIFO (depth 10). |
| **CLKDIV >= 2 for reads** | `spi_master_clkgen.sv`: below 2 the MISO round trip (pad, board, slave output delay) has no timing margin on silicon. Simulation has no delays, so it still passes there - do not rely on that. |
| SPICMD and SPIADR are **MSB-aligned** | The TX shifter always starts at bit 31: an 8-bit command goes in `[31:24]`, a 24-bit address in `[31:8]`. |
| Writing STATUS starts a transfer (or a soft reset with bit 4) | It is a command register: do not read-modify-write it. |
| Chip select 0 is the boot flash, chip select 1 the external device | Do not select CS0 at runtime unless you mean to talk to the flash. |
| Only standard (1-bit) SPI is pinned out: MOSI = `sdo0`, MISO = `sdi1` | Quad mode has no pins in this SoC. |
| The SPI interrupt state machine arms only after a read of INTSTA | `uvm/README.md` notes. |

## 9. I2C master

| Rule | Why |
|---|---|
| Set `CTR.EN = 1` (`0x80`) before writing CR | CR writes are ignored while the core is disabled. |
| SCL = clk / (5 * (PRE + 1)) | Compute PRE from the real clock. |
| Single master only | Arbitration loss cannot happen on this SoC's bus. |

## 10. Bus errors, timeouts and traps

| Rule | Why |
|---|---|
| Install a trap handler (`mtvec`) even if you do not use interrupts | Any rule above that is broken ends in an access-fault trap; without a handler the core jumps to `mtvec = 0` (boot ROM) and restarts. |
| A peripheral that never answers is aborted by the bus timeout monitors | APB slots time out after 16 cycles (SPI: 65536). The access then faults (mcause 5/7, `mtval` = address) instead of hanging the SoC. |
| Misaligned loads/stores trap (mcause 4/6) | Keep all accesses naturally aligned. |

## 11. Interrupts

| Source | mip / mcause | Notes |
|---|---|---|
| Timer 0 ch0 compare | 7 (MTIP) | |
| GPIO global | 16 | |
| I2C | 17 | |
| SPI event 0 | 18 | |
| UART | 19 | |
| Timer 0 ch0 overflow, ch1 overflow, ch1 compare | 20, 21, 22 | |
| Timer 1 ch0 overflow, ch0 compare, ch1 overflow, ch1 compare | 23, 24, 25, 26 | |
| SPI end of transfer | 27 | |
| External (MEIP), software (MSIP) | 11, 3 | Tied off: no PLIC or CLINT in this SoC. |

- An interrupt is taken only when `mstatus.MIE = 1` and the matching `mie` bit is set.
- One-cycle interrupt pulses are latched by the core until taken or disabled.
- The board firmware (pong, arm) runs with interrupts off and polls instead.

## 12. Boot and reset

| Rule | Why |
|---|---|
| Cold boot (hard reset) clears both SRAMs, then loads the image from SPI flash | The bootloader has no image check and no timeout: a blank or wrong flash image is loaded and run as-is. |
| Warm boot (soft reset) keeps ISRAM and DSRAM and restarts the core | `.bss` is zeroed again by startup code; `.data` is **not** reloaded, so initialised variables keep their last runtime values. |
| On the FPGA the image sits at flash `0x400000`; in simulation at `0x000000` | Set by the board top (`FLASH_START_ADDR`). |
