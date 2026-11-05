# RISCFORGE SoC on FPGA: from board top to bitstream

How the complete RISCFORGE SoC was brought up on the Digilent Nexys 4 DDR
(XC7A100T-1CSG324C), from the top-level file and constraints to the final
output and a running board.

**The approach in one line:** the full SoC runs as designed. Its memories start
empty, and its own bootloader loads the firmware from an external SPI flash
through the SPI master at every reset, exactly as a fabricated chip would. No
firmware is hardcoded into the memories.

**Final outputs:**

| File | What it is | Used for |
|---|---|---|
| **Bitstream** (`top_<test>.bit`) | The FPGA configuration: the SoC hardware | Configures the FPGA |
| **Configuration memory file** (`nexys4ddr_<fw>.mcs`) | Flash image: bitstream at `0x000000`, firmware at `0x400000` | Programmed into the QSPI flash; the board boots from it at every power-on |

---

## 1. Why the firmware is not hardcoded

One way to get firmware running quickly on an FPGA is to preload it: `$readmemh`
fills the instruction and data memories at synthesis, so the program is part of
the bitstream. Another bring-up of this SoC used that method. It is a valid
shortcut for FPGA-only experiments, but it does not represent the hardware being
designed. On silicon, SRAM has no initial contents at power-up, so the program
has to be brought in from outside the chip.

| | Preloaded memory (hardcoded) | This flow (bootloader + SPI flash) |
|---|---|---|
| Where the firmware lives | Inside the bitstream, as memory initial values | External SPI flash, separate from the hardware |
| SRAM at power-up | Already holds the program; not possible on silicon | Empty, then written by the bootloader, as on silicon |
| Bootloader | Not exercised for loading | Runs on every cold boot |
| SPI master, flash read path | Not exercised for booting | Exercised on every boot |
| SRAM write path over AXI-Lite | Not exercised for loading | Carries the whole image |
| Reset sequence | Not fully exercised | Full sequence: hold, clear, load, clean-slate reset, run |
| Firmware change | Bitstream must be regenerated | New flash image; a full build is needed only if the firmware size changes |

This SoC's bootloader also **clears both SRAMs on a cold boot** (`S_CLEAR_SRAM`),
so a preloaded image would not survive one. The design expects to be loaded.

---

## 2. System overview

```
 Laptop (Vivado) ─ USB, JTAG ─► FPGA configuration logic ─► QSPI flash
                                                             │  0x000000 bitstream
                                                             │  0x400000 firmware
                      at power-on: bitstream ◄───────────────┤
                                                             │ firmware, over SPI
 ┌─ FPGA ─────────────────────────────────────────────────── │ ───────────────┐
 │  Board top: MMCM clock, STARTUPE2 flash clock, pin wiring │                │
 │  ┌─ riscforge_soc_subsystem ──────────────────────────────▼─────────────┐  │
 │  │  Bootloader ─► SPI master                                            │  │
 │  │      │ writes firmware                                               │  │
 │  │      ▼                                                               │  │
 │  │  ISRAM + DSRAM ◄─ memory interface ◄─ RV32 core ◄─ boot ROM          │  │
 │  │                         │                                            │  │
 │  │                         ▼                                            │  │
 │  │       AXI-Lite crossbar ─► AXI-to-APB bridge ─► UART, GPIO, timers,  │  │
 │  │                                                 I2C, SPI             │  │
 │  └──────────────────────────────────────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────────────────────┘
```

Each test has its own folder with its own top, constraints, scripts and results,
plus a block diagram of how everything connects: `pong/pong_block_diagram.png`
and `arm/arm_block_diagram.png`.

---

## 3. The flow, step by step

```
 1 Firmware        C → ELF → hex → flash image + fw_params.svh
 2 Board top       top_<test>.sv wraps the complete SoC
 3 Constraints     <test>.xdc: pins, clock, configuration
 4 Sources         SoC RTL file list + the board top
 5 Synthesis       RTL → netlist
 6 Implementation  optimise → place → route
 7 Reports         timing, utilisation, DRC
 8 Final outputs   bitstream (.bit) → configuration memory file (.mcs)
 9 Programming     .mcs into the QSPI flash over JTAG
10 Boot and run    FPGA configures, bootloader loads, core runs
```

### Step 1: Firmware (`ips/RTL_SOC/mem/<fw>/`)

`build.py` turns the C program into the flash image:

| Stage | Tool | Output |
|---|---|---|
| Compile + link | `riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -Os`, with `startup.S` and `link.ld` | `.elf`, `.map` |
| Disassemble + check | `objdump`; the build fails on any `mul`/`div` or sub-word access | `.dump` |
| Split by address | `objcopy -O verilog` | `_imem.hex` (ISRAM `0x0001_0000`), `_dmem.hex` (DSRAM `0x0002_0000`) |
| Flash image | Little-endian bytes, ISRAM then DSRAM | `_flash.mem` |
| Build parameters | Word counts of both sections | `fw_params.svh` |

`fw_params.svh` is what ties firmware to hardware: the top passes
`FW_NUM_INSTR_WORDS` and `FW_NUM_DATA_WORDS` to the bootloader, so it knows how
much to copy.

### Step 2: Board top (`top_pong.sv`, `top_arm.sv`)

The top instantiates the **complete** `riscforge_soc_subsystem`, with the
bootloader and SPI master, and adds only what the board needs (section 4 explains
how to decide on and write one):

| Block | Purpose |
|---|---|
| **MMCM** (`MMCME2_BASE`) | Makes the SoC clock from the 100 MHz oscillator (see below) |
| **STARTUPE2** | The flash clock pin (CCLK, E9) is a dedicated configuration pin. User logic can only drive it through `STARTUPE2.USRCCLKO`. |
| **Pre-boot sequencer** | STARTUPE2 drops the first 3 clocks after configuration, so the top sends 8 dummy clocks with the flash deselected before releasing the SoC from reset. Without this, the bootloader's first read command would be corrupted. |
| **Board overrides** (`defparam`) | Bootloader `FLASH_START_ADDR = 0x400000`, because the bitstream occupies the start of the flash; boot ROM hex path |
| **Flash pins** | `QSPI_CSN`, `DQ0` (MOSI), `DQ1` (MISO); `DQ2`/`DQ3` held high (WP#, HOLD#), because the SoC uses standard SPI |
| **Status LEDs** | LD0 `boot_done`, LD1 pre-boot done, LD2 bus timeout, LD3 UART activity |
| **Test wiring** | UART and GPIO to board pins, per test |

**Clock choice.** The SoC does not close timing at the oscillator's 100 MHz: the
worst path (core MMIO address → `hybrid_mem_interface` → AXI-Lite crossbar →
`axi_lite_to_apb` → response → core stall → next PC → ISRAM address) takes about
21.6 ns.

| Test | MMCM | SoC clock | Why |
|---|---|---|---|
| Pong | 100 MHz × 10 / 25 | **40 MHz** | Meets timing |
| Arm | 100 MHz × 8 / 25 | **32 MHz** | UART reaches exactly 1 Mbps for the servos: 32 MHz / (16 × 2) |

**RTL change for FPGA.** One change was needed for BRAM mapping: the reset was
removed from `raddr_q` in `Instruction_Memory.v`, so ISRAM maps to block RAM. The
`$readmemh` in that file stays under `` `ifndef SYNTHESIS ``, so it is simulation
only and no firmware enters the bitstream.

### Step 3: Constraints (`pong.xdc`, `arm.xdc`)

Vivado uses XDC, its constraints format based on SDC.

| Constraint | Content |
|---|---|
| Clock | `create_clock -period 10.000` on `CLK100MHZ` (E3). The MMCM output clock is derived automatically. |
| Pins | `PACKAGE_PIN` + `IOSTANDARD` for reset, USB-UART, QSPI, LEDs, plus switches, buttons, PS/2 and Pmod for the arm |
| False paths | Slow or asynchronous I/O synchronised inside the SoC: reset, UART RX, switches, LEDs, flash pins. The flash runs far below the clock period. |
| Configuration | `CFGBVS VCCO`, `CONFIG_VOLTAGE 3.3`, `SPI_BUSWIDTH 1`, `CONFIGRATE 33`, `BITSTREAM.GENERAL.COMPRESS TRUE` |

### Steps 4–8: Build (`build.bat` → `build.tcl`)

A Vivado non-project batch flow:

```tcl
read_verilog -sv  ...              ;# win_sources.f (or filelists/ on Linux), then the top
read_xdc          <test>.xdc
synth_design      -top top_<test> -part xc7a100tcsg324-1 -include_dirs ... \
                  -generic BOOTROM_HEX=...
opt_design
place_design
phys_opt_design
route_design
report_utilization; report_timing_summary; report_drc
write_bitstream   out/top_<test>.bit
write_cfgmem      -format mcs -size 16 -interface SPIx1 \
                  -loadbit  "up 0x00000000 out/top_<test>.bit" \
                  -loaddata "up 0x00400000 out/<fw>.bin" \
                  -file     out/nexys4ddr_<fw>.mcs
```

Checks after every build:
- `work/vivado_build.log`: `FLASH_START_ADDR bound to: 24'b010000000000000000000000` (`0x400000`), and the expected `NUM_INSTR_WORDS` / `NUM_DATA_WORDS`.
- `out/timing_summary.rpt`: "All user specified timing constraints are met".

### Step 9: Programming (`program.bat` → `program.tcl`)

The USB cable carries two separate channels through the board's FT2232 chip:
**JTAG**, used here, and **UART**, used at runtime.

1. Set jumper JP1 to QSPI.
2. Vivado loads a temporary flash-programmer design into the FPGA over JTAG.
3. It erases the flash, writes the `.mcs`, and verifies it.
4. It reboots the FPGA from flash.

From then on the board needs no laptop to boot: the flash keeps its contents when
powered off.

### Step 10: Boot and run

What happens at every power-on or press of CPU_RESET:

| # | Stage | What happens |
|---|---|---|
| 1 | FPGA configuration | The FPGA's configuration logic reads the bitstream from flash address 0 (on power-on; not on CPU_RESET) |
| 2 | Pre-boot | The top waits for end of configuration and MMCM lock, sends 8 dummy flash clocks, and releases the SoC. LD1 turns on. |
| 3 | Clear | Bootloader writes zeros to every ISRAM and DSRAM word over AXI-Lite (`S_CLEAR_SRAM`) |
| 4 | Flash wait | Waits for the flash power-up time (`S_FLASH_WAIT`) |
| 5 | SPI setup | Programs the SPI master: clock divider 4 (SoC clock / 10), read command `0x03` |
| 6 | Load | Reads the firmware from `0x400000` in chunks of up to 1024 words. Each word goes from the SPI RX FIFO to ISRAM, then DSRAM (`S_READ_FIFO` → `S_WRITE_SRAM`). |
| 7 | Clean-slate reset | Pulses reset to core, peripherals and SPI (`S_CLEAN_*`), so no boot configuration leaks into runtime |
| 8 | Hand-over | `boot_done` goes high (LD0). The APB path to SPI passes through to the core (`S_DONE`). |
| 9 | Boot ROM | The core starts at `0x0000_0000`: `lui x2, 0x28` sets the stack, `jal` jumps to ISRAM at `0x0001_0000` |
| 10 | Firmware | `startup.S` runs, then `main()` |

---

## 4. How to decide on and write a top file

The SoC (`riscforge_soc_subsystem`) knows nothing about any board. The top file is
the adapter between the two: it gives the SoC a clock and a reset, connects its
ports to real pins, and handles whatever is special about the board. **It holds no
application logic.** What the demo does belongs in firmware.

Each test gets its own top, because each test connects different things to the
SoC. Pong and the arm share the same SoC and boot method and differ only in clock
and I/O.

### Decide

Answer these questions, in this order, before writing anything:

| # | Question | How to decide | Pong | Arm |
|---|---|---|---|---|
| 1 | What does the demo connect to? | List the external devices, then the SoC peripheral each one uses | Terminal on UART | Servos on UART; keyboard, switches, buttons, LEDs on GPIO |
| 2 | What SoC clock? | Period must be longer than the ~21.6 ns worst path, and the real test is WNS ≥ 0 after implementation. If a peripheral needs an exact rate, choose a clock that divides to it. | 40 MHz | 32 MHz: UART exactly 1 Mbps |
| 3 | Where does the firmware come from? | Always the bootloader and SPI flash | QSPI flash, `0x400000` | Same |
| 4 | Which pins? | Take each from the board's master XDC. Check bank voltage and connector limits. | C4/D4 UART, LEDs | Also SW, BTN, F4/B2 PS/2, Pmod JA |
| 5 | Any voltage or direction issues? | Check every external signal: FPGA pins are 3.3 V, and shared lines need a tri-state | None | Servo bus needs a level shifter; DATA tri-state; PS/2 open drain |
| 6 | What about unused ports? | Every SoC input must have a defined value (see below) | I2C, GPIO inputs tied | I2C tied |

**Choosing the clock.** The MMCM output is `100 MHz × M / (D × O)`, and the VCO
(`100 MHz × M / D`) must stay in its 600–1200 MHz range. Pong uses M=10, O=25 (VCO
1000 MHz, 40 MHz). The arm uses M=8, O=25 (VCO 800 MHz, 32 MHz). UART baud is
`clk / (16 × divisor)`, with divisor ≥ 2. At 40 MHz, 1 Mbps would need a divisor of
2.5, which is why the arm has a different clock.

### Connect every SoC port

Go through the SoC's port list one by one. Every port falls into one of these:

| Treatment | Ports | Connection |
|---|---|---|
| Clock | `clk_i` | MMCM output, through a `BUFG` |
| Reset | `hard_rst_ni` | `CPU_RESETN & preboot_done`: held in reset until the flash is ready |
| Tie to a fixed value | `soft_rst_ni`, `fetch_enable_i` | `1'b1` |
| | `test_mode_i` | `1'b0` |
| | `boot_addr_i` | `32'h0000_0000` |
| | `i2c_scl_i`, `i2c_sda_i` when unused | `1'b1` (the idle level of an I2C line) |
| | `gpio_in_i` when unused | `'0` |
| Flash | `spi_clk_o`, `spi_csn0_o`, `spi_sdo0_o`, `spi_sdi1_i` | Flash pins; the clock goes through STARTUPE2 |
| To board pins | `uart_sout_o`, `uart_sin_i`, `gpio_*` | As the demo needs |
| Status | `boot_done_o`, bus-timeout sticky outputs | LEDs |
| Left unused | interrupts, `spi_csn1_o`, `gpio_tx_en_o`, ... | Wire with no load |

### Write it

Build the file in this order. `pong/top_pong.sv` is the reference.

**1. Header and ports.** Name the module `top_<test>` and use the board's signal
names. Every port needs a pin in `<test>.xdc`, or the bitstream step fails.

```systemverilog
module top_pong
  import gpio_reg_pkg::GPIOCount;
#(
  parameter string       BOOTROM_HEX      = "../mem/common/riscforge_bootrom.hex",
  parameter logic [23:0] FLASH_IMAGE_ADDR = 24'h40_0000,  // must clear the bitstream
  parameter int unsigned PREBOOT_CLKS     = 8             // >= 3
)(
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,
  input  logic        UART_TXD_IN,
  output logic        UART_RXD_OUT,
  output logic        QSPI_CSN,
  output logic        QSPI_DQ0,
  input  logic        QSPI_DQ1,
  output logic        QSPI_DQ2,
  output logic        QSPI_DQ3,
  output logic [15:0] LED
);
  `include "fw_params.svh"   // FW_NUM_INSTR_WORDS, FW_NUM_DATA_WORDS
```

**2. Clock.** Put the MMCM and BUFGs under `` `ifdef SYNTHESIS ``, because Vivado
defines that macro. In simulation the clock passes straight through.

```systemverilog
`ifdef SYNTHESIS
  MMCME2_BASE #(.CLKIN1_PERIOD(10.000), .DIVCLK_DIVIDE(1),
                .CLKFBOUT_MULT_F(10.000), .CLKOUT0_DIVIDE_F(25.000))
    u_mmcm (.CLKIN1(CLK100MHZ), .CLKFBIN(clkfb_buf), .CLKFBOUT(clkfb_mmcm),
            .CLKOUT0(clk_mmcm), .LOCKED(clk_locked), .PWRDWN(1'b0), .RST(1'b0));
  BUFG u_bufg_fb  (.I(clkfb_mmcm), .O(clkfb_buf));
  BUFG u_bufg_clk (.I(clk_mmcm),   .O(clk));
`else
  assign clk        = CLK100MHZ;
  assign clk_locked = 1'b1;
`endif
```

**3. Flash clock (STARTUPE2).** The Nexys flash clock is the dedicated CCLK pin,
which has no normal I/O path, so this block is required on this board.

```systemverilog
`ifdef SYNTHESIS
  STARTUPE2 #(.PROG_USR("FALSE"), .SIM_CCLK_FREQ(0.0))
    u_startup (.EOS(eos), .USRCCLKO(flash_sck), .USRCCLKTS(1'b0),
               .USRDONEO(1'b1), .USRDONETS(1'b1), .CLK(1'b0), .GSR(1'b0),
               .GTS(1'b0), .KEYCLEARB(1'b1), .PACK(1'b0));
`else
  assign eos = 1'b1;
`endif
```

**4. Pre-boot sequencer.** A small state machine: wait for end of startup (`eos`)
and `clk_locked`, send `PREBOOT_CLKS` clocks with the flash deselected, then set
`preboot_done`. STARTUPE2 drops the first 3 clocks, so without this the
bootloader's first read command would be corrupted.

**5. SoC instance.** Connect every port from the table above and pass the firmware
word counts. Set `FLASH_POWERUP_CYCLES` so that the wait is longer than the flash's
power-up time: 30,000 cycles is 750 µs at 40 MHz and 940 µs at 32 MHz, against
300 µs for the S25FL128S.

```systemverilog
  riscforge_soc_subsystem #(
    .NUM_INSTR_WORDS      ( FW_NUM_INSTR_WORDS ),
    .NUM_DATA_WORDS       ( FW_NUM_DATA_WORDS  ),
    .FLASH_POWERUP_CYCLES ( 30_000             )
  ) u_soc (
    .clk_i        ( clk                       ),
    .hard_rst_ni  ( CPU_RESETN & preboot_done ),
    .soft_rst_ni  ( 1'b1                      ),
    // ... every other port
  );
```

**6. Board overrides.** Use `defparam` for the two parameters the SoC doesn't
expose, so the SoC RTL stays unchanged.

```systemverilog
  defparam u_soc.i_bootloader.FLASH_START_ADDR = FLASH_IMAGE_ADDR;
  defparam u_soc.i_boot_rom.HEX_FILE           = BOOTROM_HEX;
```

**7. Pins.** The flash clock and chip select stay under the pre-boot sequencer's
control until `preboot_done`. WP# and HOLD# are held high for standard SPI.

```systemverilog
  assign flash_sck    = preboot_done ? spi_clk  : pb_sck_q;
  assign QSPI_CSN     = preboot_done ? spi_csn0 : 1'b1;
  assign QSPI_DQ0     = spi_sdo0;
  assign QSPI_DQ2     = 1'b1;
  assign QSPI_DQ3     = 1'b1;
  assign UART_RXD_OUT = uart_sout;
```

Test-specific wiring goes here too. For example, the arm drives its shared lines as
tri-states and open drains:

```systemverilog
  assign DXL_DATA = dxl_dir ? uart_sout : 1'bz;
  assign PS2_CLK  = gpio_out[GPIO_PS2_CLK_LOW] ? 1'b0 : 1'bz;
```

**8. Status LEDs.** Connect `boot_done`, `preboot_done`, the bus-timeout flags and
UART activity first. They show how far boot got when nothing else is visible.

**9. Connect it to the build.** Give the test its own folder, then:

- Add each top-level port to `<test>.xdc`, copying the lines from the board's master
  XDC and renaming them to match. Add `PULLUP TRUE` on open-drain inputs such as
  PS/2.
- Set the names in `build.tcl`: `set top top_<test>`, which `synth_design -top` uses,
  and the test name that selects `$test.xdc`.
- Point the firmware paths in `build.tcl` and the include path to the test's firmware
  folder, so that `` `include "fw_params.svh" `` finds its word counts.
- Add any new source files to `win_sources.f`.

### Rules

- **Don't edit the SoC to fit a board.** Use ports, parameters and `defparam`.
- **Keep one clock domain.** Everything in the SoC runs on the MMCM output.
- **Leave no input undriven.** Tie off each unused SoC input to its idle value.
- **Wire, don't decode.** Protocols such as PS/2 belong in firmware; the top only
  connects the pins.
- **Keep firmware and clock in step.** If the MMCM changes, change `CLK_HZ` in the
  firmware as well, or UART and timers will run at the wrong rate.
- **Reserve the bitstream's flash space.** `FLASH_IMAGE_ADDR` must lie beyond the
  bitstream, and must match `write_cfgmem` in `build.tcl`.

### Bring-up order on the board

Use the LEDs to find where a new top stops working:

| Symptom | Stopped at | Check |
|---|---|---|
| LD1 off | Pre-boot | MMCM lock, `eos` |
| LD1 on, LD0 off | Bootloader | Flash image at `0x400000`, JP1 on QSPI, word counts, `FLASH_START_ADDR` |
| LD0 on, no UART output | Firmware start | `CLK_HZ` and baud, UART pins |
| LD2 on | Bus hang | Which peripheral access timed out |

---

## 5. Results

| | Pong | Robotic arm |
|---|---|---|
| Board top | `pong/top_pong.sv` | `arm/top_arm.sv` |
| SoC clock | 40 MHz | 32 MHz |
| Worst setup slack | +0.629 ns | +1.065 ns |
| Timing | All constraints met | All constraints met |
| Slice LUTs (of 63,400) | 9,215 | 9,349 |
| Slice registers (of 126,800) | 7,292 | 7,426 |
| Block RAM tiles (of 135) | 16 | 16 |
| Bitstream (compressed) | 1.30 MB | 1.38 MB |
| Firmware in flash | 4,356 bytes | 9,572 bytes |
| Tested on the board | Game runs, played over the USB-UART | Keyboard, torque on/off, joint jogging, C pose and rest pose on the WidowX-200 |

These figures are from the bitstreams currently in `pong/out/` and `arm/out/`. The
two builds were made on different dates, so they don't carry the same RTL: the
Pong build predates the core and UART fixes on `malay`, and the arm build includes
those fixes (PR #11).

---

## 6. How to reproduce

Tools: Vivado 2023.2, xPack `riscv-none-elf-gcc`, Python 3.

```bash
# 1. firmware
cd ips/RTL_SOC/mem/pong
python build.py

# 2. bitstream and flash image
cd ../../fpga/nexys4ddr/pong
build.bat

# 3. program the flash (jumper JP1 on QSPI)
program.bat
```

Use `mem/arm` and `fpga/nexys4ddr/arm` for the robotic arm. Rebuild the bitstream
whenever the firmware size changes, because the word counts are built into it.
How to operate each demo is in `pong/README.md` and `arm/README.md`.

---

## 7. Minimum files

### To run a demo on the board

Only one file is needed: the `.mcs`. It already contains the bitstream (at
`0x000000`) and the firmware (at `0x400000`).

| Demo | File | Size |
|---|---|---|
| Pong | `pong/out/nexys4ddr_pong.mcs` | 3.7 MB |
| Arm | `arm/out/nexys4ddr_arm.mcs` | 3.9 MB |

To write it to the board:

- **Tool:** Vivado or Vivado Lab.
- **Scripts:** `program.bat` and `program.tcl` are optional, but save doing it by
  hand in Hardware Manager. They expect the `.mcs` in `out/` next to them, so copy
  the `out/` folder as well.
- **Jumper:** set JP1 to QSPI so the board boots from flash at power-on.

The arm's relay mode (SW13 on) also needs `arm/arm_teleop/dxl_relay.py` on the laptop.

Not needed to run:

| File | Why |
|---|---|
| `.prm` | `program.tcl` never reads it |
| `.bit` | Not needed once you have the `.mcs`. Not enough on its own either, because the SoC always loads its program from flash, so the firmware must already be there. Only useful for a quick reload over JTAG (`program.bat jtag`) when the firmware hasn't changed. |
| `.bin` | Already merged into the `.mcs` |
| `.rpt` | Reports only |

### To rebuild the `.mcs`

| What | Files |
|---|---|
| Board files | `top_<test>.sv`, `<test>.xdc` |
| Build scripts | `build.bat`, `build.tcl`, `win_sources.f` |
| Firmware source | `mem/<test>/<test>.c`, `build.py` |
| Boot ROM | `mem/common/riscforge_bootrom.hex` |
| SoC RTL | Everything listed in `win_sources.f` |
| Tools | Vivado and `riscv-none-elf-gcc` |

`build.py` generates the other files in `mem/<test>/`, such as `fw_params.svh` and
`<test>_flash.mem`, so they don't need to be copied.
