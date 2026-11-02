# I2C Register Test — `ips/RTL_SOC/mem/i2c_regtest`

Self-contained firmware + memory images for a **register-level test of the APB
I2C master** (`ips/apb_i2c-master/apb_i2c.sv`), run on the real RV32 core after a
cold boot from the Infineon S25FS512S flash model.

Every access goes through the complete path:

```
core LSU -> hybrid_mem_interface -> axi_lite_xbar -> axi_lite_to_apb -> apb_i2c
```

This is one peripheral only. The naming convention for the folders that follow is
`<peripheral>_regtest`, so the register tests stay separable and a folder name
says exactly which IP its `.mem` files belong to:

| folder                       | scope                                      |
|------------------------------|--------------------------------------------|
| `i2c_regtest/`               | I2C registers (this folder)                |
| `regtest/`                   | all six peripherals in one program (legacy) |
| `montest/`                   | bus timeout monitors                       |
| `uart_regtest/` *(planned)*  | UART registers                             |
| `gpio_regtest/` *(planned)*  | GPIO registers                             |
| `spi_regtest/` *(planned)*   | SPI master registers                       |
| `timer_regtest/` *(planned)* | Timer 0 / Timer 1 registers                |

---

## Contents

### Sources (checked in, edit these)

| file            | role                                                                   |
|-----------------|------------------------------------------------------------------------|
| `i2c_regtest.c` | the test program: 9 phases, ~130 checks                                |
| `startup.S`     | reset entry, `.bss` clear, `mtvec` trap handler writing `g_trap`        |
| `link.ld`       | `.text` to ISRAM; `.results`/`.rodata`/`.data`/`.bss`/stack to DSRAM    |
| `build.py`      | compile, instruction-mix check, split into the memory images            |
| `README.md`     | this file                                                              |

Unlike `montest/`, this folder does **not** share `startup.S` / `link.ld` with
`regtest/`. It carries its own copies so the folder can be moved or archived on
its own.

### Generated (by `build.py`, do not edit)

| file                      | what it is                                                            |
|---------------------------|-----------------------------------------------------------------------|
| `i2c_regtest_imem.hex`    | **instruction SRAM** image, one 32-bit word per line, from `0x0001_0000` |
| `i2c_regtest_dmem.hex`    | **data SRAM** image, one 32-bit word per line, from `0x0002_0000`        |
| `i2c_regtest_flash.mem`   | flash byte stream (little-endian, ISRAM words then DSRAM words)        |
| `fw_params.svh`           | `FW_NUM_INSTR_WORDS` / `FW_NUM_DATA_WORDS` / `FW_RESULT_ADDR` + image paths |
| `i2c_regtest.elf`         | linked ELF                                                            |
| `i2c_regtest.dump`        | disassembly (`objdump -d -M no-aliases`)                              |
| `i2c_regtest.map`         | linker map                                                            |

`_dmem.hex` starts at the DSRAM base and includes the 64 zero-filled `.results`
bytes, so it can be loaded straight into the DSRAM array. `_flash.mem` is the
same format as `gen_flash_image.py` output and is what the bootloader's `0x03`
read plus RX byte swap expects.

---

## Build

```bash
cd ips/RTL_SOC/mem/i2c_regtest && python build.py
```

The toolchain is found on `PATH`, from `$RISCV_TOOLCHAIN_BIN`, from
`--toolchain <bin>`, or from the default
`D:/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin`.

Current output:

```
ISRAM words (NUM_INSTR_WORDS) : 1125   (4500 B of 32 KB)
DSRAM words (NUM_DATA_WORDS)  :  493   (1972 B of 32 KB)
Flash bytes                   : 6472
```

`build.py` fails the build, rather than producing a bad image, if the compiler
emits any of:

* **M-extension** instructions (`mul`/`div`/`rem`) — `rv32m_unit.v` is not
  signed off, and the image is built `-march=rv32i_zicsr`
* **sub-word** loads or stores (`lb`/`lh`/`lbu`/`lhu`/`sb`/`sh`) — APB has no
  byte strobes and `apb_i2c.sv` ties `PSLVERR` low, so a sub-word MMIO store
  would silently write all 32 bits of `PWDATA`
* **compressed** (16-bit) instructions — the trap handler resumes at `mepc + 4`
* any loadable byte outside ISRAM/DSRAM

The current image passes with **1125 instructions, RV32I + Zicsr only,
128 `lw` / 135 `sw`, all 32-bit**.

---

## Register map under test

APB slot 0, `apb_addr_map[0]` = `0x4000_0000 – 0x4000_0FFF` (full 4 KB).

| offset | name | kind | reset  | reads back | notes |
|--------|------|------|--------|------------|-------|
| `0x00` | PRE  | RW   | 0x0000 | `[15:0]`   | clock prescale, 16 bit; upper 16 must not store |
| `0x04` | CTR  | RW   | 0x00   | `[7:0]`    | bit 7 EN, bit 6 IEN, `[5:0]` plain storage |
| `0x08` | RXR  | RO   | 0x00   | `[7:0]`    | shift-register output, hardware driven |
| `0x0C` | SR   | RO   | 0x00   | `[7:0]`    | 7 RXACK, 6 BUSY, 5 AL, `[4:2]` reserved, 1 TIP, 0 IF |
| `0x10` | TXR  | RW   | 0x00   | `[7:0]`    | byte to transmit |
| `0x14` | CR   | CMD  | 0x00   | `[7:0]`    | 7 STA, 6 STO, 5 RD, 4 WR, 3 ACK, `[2:1]` reserved, 0 IACK |
| `0x18`–`0x3C` | — | — | 0 | — | ten unmapped slots (`s_apb_addr` 6…15): read 0, writes ignored |

**Decode:** `s_apb_addr = PADDR[5:2]`. `PADDR[11:6]` is not decoded, so the
16-slot block **repeats 64 times** across the 4 KB window. `PREADY` is tied 1
and `PSLVERR` is tied 0, so **no** access in this test may fault or stall.

### Why CR cannot be pattern-swept

Taken from the RTL, not from a datasheet:

* a CR write only lands while `CTR.EN` (bit 7) is 1; otherwise CR keeps its
  previous contents and a write can neither set nor clear it
* bits `[2:1]` are reserved and bit 0 (IACK) is a self-clearing pulse — any
  later APB cycle clears them, so they always read back 0
* bits `[7:4]` (STA/STO/RD/WR) are cleared by hardware on transfer done or on
  arbitration loss; bit 3 (ACK) is plain storage and holds
* writing bits `[7:4]` starts real I2C traffic

Phase 5 therefore checks each of those rules individually, touching only ACK,
IACK and the reserved bits, so the I2C bus stays idle for the whole run.

---

## Test phases

| # | phase | what it proves |
|---|-------|----------------|
| 1 | reset values | all 6 registers read their reset value before anything is written; SR checked field by field (RXACK/BUSY/AL = 0, TIP/IF = 0, reserved `[4:2]` = 0) |
| 2 | read-only | RXR and SR ignore four write patterns each and answer OKAY; PRE/CTR/TXR/CR do not change |
| 3 | unmapped slots | the ten slots `0x18`–`0x3C` read 0 and swallow a write; no mapped register changes |
| 4 | RW pattern sweep | 36 patterns per RW register (0, all-ones, `0xAAAA_AAAA`, `0x5555_5555`, walking one over all 32 bits) read back through the implemented-bit mask — PRE, CTR, TXR. Also: the CTR sweep sets `EN`, so SR must still be idle and CR must still be 0 afterwards |
| 5 | CR semantics | write ignored while `EN=0`; ACK holds with `EN=1`; reserved `[2:1]` and IACK read 0 even when written 1; IACK self-clears; CR is **frozen not cleared** when `EN` goes away (a write can neither set nor clear it); IEN is storage and does not set IF |
| 6 | uniqueness | a distinct value in every writable register at once, then all read back, twice with swapped values — catches two offsets decoding to the same storage |
| 7 | aliasing + full window | named alias spot checks (`+0x040`, `+0x7C0`, `+0xFC0`, `+0x810`, `+0xFD0`, `+0x898`), a write landing through a high alias, then **all 1024 word addresses** in the 4 KB window read and matched against their slot value (16 slots × 64 aliases) |
| 8 | no faults | `g_trap.total == 0`: not one access in the run faulted, and none stalled |
| 9 | final state | all 6 registers are back at their reset value |

### Deliberately out of scope

The **RXR data path** and the hardware-driven **SR bits** (RXACK, BUSY, AL, TIP,
IF) only change as a result of real I2C traffic, which needs a slave on the bus.
That is protocol behaviour, not register behaviour, and it is covered by
`ips/apb_i2c-master/directed_tb.sv` and `i2c_thorough_tb.sv`. This test verifies
their reset state, that they are read-only, that they decode correctly across the
whole window, and that nothing it does disturbs them.

### Why the firmware avoids table-driven addressing

Every MMIO address that reaches a load or store is a compile-time constant or
pure register arithmetic on a loop variable. No base/offset pair is fetched from
a table and no address passes through a function pointer or jump table.

This is deliberate. REG-VERIF-v1.0 §3 traced all 37 failing registers of the
all-peripheral `regtest` to address corruption in the core on exactly that code
shape (`lw base` / `lw off` / `add` / `jalr`, behind a load-use hazard feeding a
branch). Keeping addresses out of memory means a FAIL reported here is an I2C
defect and not that core defect. The generated code confirms it: the whole
program contains **three** `add` instructions, none of them in an MMIO address
path — every I2C access is `lw`/`sw rd, imm(rs)` off a register loaded by `lui`.

---

## Results

### Mailbox — DSRAM `0x0002_0000`, words 0–6

Identical to `regtest.c`, so a testbench that already understands `regtest.c`
understands this program. The testbench acts on the store to `MB_CMD`, which is
always the last store of a post.

| word | field | meaning |
|------|-------|---------|
| `+0x00` | CMD  | `1` PASS, `2` FAIL, `3` SECTION, `4` BUSRESP (reserved, unused), `0xD0` DONE |
| `+0x04` | IP   | pointer to `"I2C"` |
| `+0x08` | NAME | pointer to the register name (`"PRE"`, `"CR"`, `"hole"`, `"window"`, `"bus"`) |
| `+0x0C` | SUB  | pointer to the check description |
| `+0x10` | ADDR | address under test (phase number for SECTION, pass count for DONE) |
| `+0x14` | EXP  | expected value (fail count for DONE) |
| `+0x18` | GOT  | observed value (total traps for DONE) |

### Summary block — DSRAM `0x0002_0020`, words 8–15

Lets a run be graded **with no testbench support at all**: dump 16 words at
`0x0002_0000` and read words 8–15.

| word | field | meaning |
|------|-------|---------|
| `+0x20` | MAGIC | `0x49324352` (`"I2CR"`), written first thing in `main` |
| `+0x24` | PASS  | checks passed |
| `+0x28` | FAIL  | checks failed |
| `+0x2C` | CHECKS| checks made |
| `+0x30` | TRAPS | `g_trap.total`, must be 0 |
| `+0x34` | FIRSTFAIL | address of the first failing check, 0 if none |
| `+0x38` | PHASE | phase currently running — localises a hang |
| `+0x3C` | DONE  | `0xD09ED09E` once `main` reached the end |

**PASS** = `DONE == 0xD09ED09E` **and** `FAIL == 0` **and** `TRAPS == 0`.

Example, from a simulator prompt:

```tcl
value -radix hex dut.i_dsram.mem[8:15]
```

---

## Running it in simulation

This firmware has its **own** testbench in `ips/RTL_SOC/tb/` — one bench per
firmware, so `soc_regtest_tb.sv` (all peripherals) and `soc_montest_tb.sv`
(bus monitors) are left untouched:

| file | role |
|------|------|
| `ips/RTL_SOC/tb/soc_i2c_regtest_tb.sv` | testbench: boot, mailbox scoreboard, independent APB / bus checks |
| `ips/RTL_SOC/run.f`                    | run filelist: select this TB and `+incdir+../mem/i2c_regtest` in its SELECT TEST block |

```bash
cd ips/RTL_SOC/mem/i2c_regtest && python build.py
```

then set the SELECT TEST block of `ips/RTL_SOC/run.f` to:

```
+incdir+../mem/i2c_regtest
../tb/soc_i2c_regtest_tb.sv
-top soc_i2c_regtest_tb
```

and run from `ips/RTL_SOC/sim/`:

```bash
xrun -f ../run.f -l logs/i2c_regtest.log
```

```bash
xrun -f ../run.f -l logs/i2c_regtest.log +VERBOSE
```

`+VERBOSE` also prints every PASS and every APB access on slot 0. Waveforms go
to `soc_i2c_regtest_tb.shm` on every run.

### What the testbench checks on its own

Besides filing the firmware's ~130 checks against a golden I2C map (so a
register the firmware skips prints as **NOT EXERCISED**), the bench verifies
independently of anything the firmware reports:

| phase | check |
|-------|-------|
| A–C | flash preload; the image lands correctly in ISRAM and DSRAM |
| D   | I2C block reset state by backdoor, at the edge the core is released |
| E   | **read-mux shadow**: on every APB read, PRDATA is recomputed from `r_pre` / `r_ctrl` / `s_rx` / `s_status` / `r_tx` / `r_cmd` and compared with what the slave drove |
| E   | **APB protocol**: `PREADY` high in every ACCESS phase, `PSLVERR` never, `paddr` always inside the 4 KB window |
| E   | **I2C bus idle**: SCL/SDA output enables stay released, `CR[7:4]` stays 0, `SR` stays 0x00, `i2c_interrupt_o` stays low — every clock |
| F   | all 16 decode slots read, **all 1024 word addresses** of the window touched |
| F   | AXI read/write counts equal APB slot-0 counts one for one; no other APB slot selected; no bus error; no timeout monitor fired |
| F   | firmware totals match the mailbox tally; the summary block at `0x0002_0020` agrees with both |
| F   | final register state equals reset state |

### Expected numbers for a passing run

From replaying the firmware sequence against a model of `apb_i2c.sv`:

* 123 firmware checks, 0 failed
* 1407 APB accesses on slot 0: 1233 reads, 174 writes
* 1024 of 1024 window word addresses touched, all 16 slots read
* 0 traps, 0 bus errors, 0 cycles with the I2C bus driven

The last line of the log is `*** I2C REGISTER TEST PASSED ***` or
`*** I2C REGISTER TEST FAILED ***`.
