# RISCFORGE 1TOPS on the Nexys 4 DDR

Board tops, constraints and Vivado scripts for running the SoC on a Digilent
Nexys 4 DDR (XC7A100T-1CSG324C). The SoC RTL is not modified.

Every board test lives in **its own self-contained folder**. A folder holds its
top, its constraints, its own copy of the build/program scripts, its
testbench, and its own results. Copy one folder and you have everything for
that test; building or changing one test never touches another.

```
fpga/nexys4ddr/
├── README.md                this file
├── pong/                    board test "pong" (see pong/README.md)
│   ├── README.md            quick start, all controls, LEDs, power
│   ├── pong_block_diagram.png / .svg
│   ├── build.bat            synth -> impl -> .bit -> .mcs   (no arguments needed)
│   ├── build.tcl
│   ├── program.bat          write the .mcs to the flash (or .bit over JTAG)
│   ├── program.tcl
│   ├── win_sources.f        SoC RTL file list for the Windows checkout
│   ├── top_pong.sv          board top: SoC + MMCM + STARTUPE2 + pre-boot clocks + LEDs
│   ├── pong.xdc             all pins and constraints for top_pong
│   ├── tb/
│   │   ├── soc_nexys4ddr_tb.sv   board-top simulation (Xcelium)
│   │   └── make_sim_flash.py     flash preload with the image at 0x400000
│   ├── out/                 RESULTS (kept): top_pong.bit, nexys4ddr_pong.mcs, pong.bin, reports
│   └── work/                Vivado run files (git-ignored, safe to delete)
└── arm/                     board test "arm": WidowX-200 robotic arm (see arm/README.md)
    ├── build.bat, build.tcl, program.bat, program.tcl, win_sources.f
    ├── top_arm.sv           32 MHz SoC, servo bus via laptop relay or Pmod JA (SW13), keyboard + switches on GPIO
    ├── arm.xdc
    ├── README.md            modes, quick start, all controls, safety, power, wiring, LEDs
    ├── arm_block_diagram.png / .svg
    ├── arm_teleop/          laptop tools: dxl_relay.py (relay mode), arm_teleop.py (U2D2 keyboard control)
    ├── out/                 top_arm.bit, nexys4ddr_arm.mcs, arm.bin, reports
    └── work/
```

Firmware is kept separately, one folder per program, in `ips/RTL_SOC/mem/`:

```
ips/RTL_SOC/mem/
├── common/riscforge_bootrom.hex   boot ROM image (shared, used by every build)
├── regtest/startup.S, link.ld     start-up code and linker script (shared)
├── arm/                           robotic arm firmware: arm.c, build.py (+ generated files)
└── pong/                          Pong firmware
    ├── pong.c                     the program
    ├── build.py                   C -> ELF -> hex -> flash image
    ├── pong_viewer.py             PC-side graphical viewer
    └── (generated) pong.elf, pong.dump, pong.map, pong_imem.hex, pong_dmem.hex,
                    pong_flash.mem, fw_params.svh, sim_build/
```

The board folder and the firmware folder are tied together only by name:
`pong/build.tcl` reads its firmware from `ips/RTL_SOC/mem/pong`. The SoC RTL
itself comes from the `ips/` tree through `win_sources.f` (Windows) or the
shared `filelists/` (Linux).

---

## The whole flow, idea to running board

```
 1 Idea / spec        what the program does, which peripherals it uses
 2 C code             mem/<fw>/<fw>.c
 3 Compile            build.py:  C -> ELF -> dump (assembly) -> hex -> flash image
 4 Verify (SoC sim)   tests/<fw>.f + tb/soc_<fw>_tb.sv  (Xcelium, bare SoC)
 5 Board top + XDC    fpga/nexys4ddr/<fw>/top_<fw>.sv, <fw>.xdc
 6 Verify (board sim) fpga/nexys4ddr/<fw>/tb/soc_nexys4ddr_tb.sv
 7 Implement          build.bat:  synth -> place -> route -> .bit -> .mcs
 8 Program            program.bat: .mcs into the QSPI flash
 9 Run                power on / CPU_RESET, terminal at 115200 8N1
```

Pong has been through every step: SoC simulation (`soc_pong_tb`), board-top
simulation (`soc_nexys4ddr_tb`), and on the board (checked over COM5,
2026-11-02).

### 1. Idea / spec

Decide what the program does and which SoC peripherals it needs (UART, timer,
GPIO, SPI, I2C). Pong uses the UART for the screen and key input, and
TIMER0 for a fixed frame rate. Keep the firmware rules of this SoC in mind
from the start:

- 32-bit loads and stores only to MMIO (byte/half-word stores corrupt or fault).
- UART: write LCR with a full value; with LCR.DLAB=1 only DLL/DLM may be read;
  the divisor must be >= 2.
- SPI: read RXFIFO only when STATUS says it has data, write TXFIFO only when
  it has room, or the bus hangs.

### 2. C code

Write `mem/<fw>/<fw>.c`. It runs bare-metal: no OS, no C library. Start-up
(`mem/regtest/startup.S`) sets the stack and calls `main`; the linker script
(`mem/regtest/link.ld`) places code in ISRAM (`0x0001_0000`, 32 KB) and data
in DSRAM (`0x0002_0000`, 32 KB). The clock is **40 MHz** on the board, so
baud divisors and timer periods are computed from `CLK_HZ = 40 MHz`.

### 3. Compile: C -> assembly -> hex -> flash image

```bash
cd ips/RTL_SOC/mem/pong
python build.py          # board image (115200 baud, 30 fps at 40 MHz)
python build.py --sim    # simulation image (fast UART/frames) -> sim_build/
```

`build.py` uses the xPack RISC-V GCC (`riscv-none-elf-*`, found on PATH or in
`D:/riscv-toolchain/...`, or `--toolchain <bin>`), and does:

| Step | Tool | Output |
|---|---|---|
| compile + link | `gcc -march=rv32i_zicsr -mabi=ilp32 -Os` with `startup.S` + `link.ld` | `pong.elf`, `pong.map` |
| disassemble | `objdump` | `pong.dump` (the assembly; checked for no `mul/div` and no byte/half-word loads/stores) |
| to hex | `objcopy -O verilog`, split by address | `pong_imem.hex` (ISRAM words), `pong_dmem.hex` (DSRAM words) |
| flash image | little-endian byte stream, ISRAM then DSRAM | `pong_flash.mem` |
| parameters | word counts, UART divisor, frame period | `fw_params.svh` |

`fw_params.svh` matters for the board: the word counts in it set how many
words the bootloader copies from flash, and they are **built into the
bitstream**. So when the firmware size changes, the bitstream must be rebuilt
(step 7), not only the flash image.

### 4. Verify on the bare SoC (Xcelium, Linux)

Simulates `riscforge_soc_subsystem` with the S25FS512S flash model holding
the image. The testbench boots it, then drives and checks the UART like the
PC would. Use the `--sim` firmware build.

```bash
cd ips/RTL_SOC/mem/pong && python build.py --sim
cd ../../sim
xrun -f ../tests/pong.f -l logs/pong.log
```

`tests/pong.f` selects `+incdir+../mem/pong/sim_build`, `tb/soc_pong_tb.sv`
and `-top soc_pong_tb`. It checks cold boot, image placement, the first
screen, frame timing on TIMER0, key presses, serve, binary viewer packets,
and that no bus error or bus-timeout monitor fired.

### 5. Board top and constraints

`top_<fw>.sv` wraps the SoC for the board. For Pong (`top_pong.sv`):

- **Clock:** MMCM, 100 MHz oscillator x 10 / 25 = **40 MHz**. At 100 MHz the
  worst path (core MMIO address -> `hybrid_mem_interface` -> AXI-Lite
  crossbar -> `axi_lite_to_apb` -> response -> core stall -> next PC -> ISRAM
  address, ~21.6 ns) does not fit.
- **Boot flash:** the on-board QSPI configuration flash (S25FL128S, 16 MB).
  Its clock pin is CCLK, which user logic can only drive through
  `STARTUPE2.USRCCLKO`. STARTUPE2 drops the first 3 clocks after
  configuration, so the top sends 8 dummy clocks (flash deselected) before
  releasing the SoC from reset.
- **defparams:** the bootloader's `FLASH_START_ADDR` = `0x400000` and the
  boot ROM's `HEX_FILE`.
- **LEDs:**

| LED | Meaning |
|---|---|
| LD0 | `boot_done`: image loaded, core running |
| LD1 | pre-boot dummy clocks done |
| LD2 | a bus-timeout monitor fired (should stay off) |
| LD3 | UART TX activity |
| LD8–LD15 | `gpio_out_o[7:0]` |

`<fw>.xdc` holds every pin (clock E3, CPU_RESETN, USB-UART C4/D4, QSPI flash,
LEDs), the 100 MHz clock constraint (the 40 MHz clock is derived from it),
false paths for the slow I/O, and the configuration settings (3.3 V, SPI x1).

Flash layout written by the build:

| Flash address | Contents |
|---|---|
| `0x000000` | FPGA bitstream (~3.8 MB) |
| `0x400000` | firmware image (`pong_flash.mem` as raw bytes) |

### 6. Verify the board top (Xcelium, Linux)

Simulates `top_pong` itself (MMCM and STARTUPE2 are left out under
simulation; the flash model is clocked from the internal `flash_sck`).

```bash
cd ips/RTL_SOC/mem/pong
python build.py --sim
python ../../fpga/nexys4ddr/pong/tb/make_sim_flash.py
```

Compile with a filelist holding (from `ips/RTL_SOC/sim/`):

```
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/pong/sim_build
../fpga/nexys4ddr/pong/top_pong.sv
../fpga/nexys4ddr/pong/tb/soc_nexys4ddr_tb.sv
-top soc_nexys4ddr_tb
```

```bash
cd ips/RTL_SOC/sim
xrun -f <that filelist> -l logs/nexys4ddr.log
```

Expected: `*** NEXYS4DDR BOARD TOP TEST PASSED ***`. It checks the dummy
clocks, the boot from `0x400000`, the Pong title on `UART_RXD_OUT`, and a
reset-button re-boot.

### 7. Implement: bitstream and flash image (Vivado, Windows)

Build the **board** firmware first (not `--sim`), then:

```bash
cd ips/RTL_SOC/mem/pong
python build.py
cd ../../fpga/nexys4ddr/pong
build.bat
```

`build.bat` starts Vivado 2023.2 (from PATH, or `F:\Xilinx\Vivado\2023.2`) in
batch mode inside `work/`. `build.tcl` reads the RTL (`win_sources.f` on
Windows, the shared `filelists/` on Linux), `top_pong.sv`, `pong.xdc`, runs
synthesis, place, route, writes the bitstream, and merges bitstream +
firmware into one `.mcs`. About 10–20 minutes.

Results in `out/`:

| File | What |
|---|---|
| `top_pong.bit` | bitstream (JTAG load, lost at power-off) |
| `pong.bin` | firmware as raw bytes |
| `nexys4ddr_pong.mcs` | flash image: bitstream @0x0, firmware @0x400000 |
| `timing_summary.rpt`, `utilization*.rpt`, `drc.rpt` | reports |

Check after a build:

- `work/vivado_build.log`: under `Synthesizing module 'bootloader'`,
  `FLASH_START_ADDR bound to: 24'b010000000000000000000000` (= 0x400000).
- `out/timing_summary.rpt`: "All user specified timing constraints are met"
  (last build: WNS +0.629 ns at 40 MHz).

`build.bat <fw_dir>` builds the same top with other firmware from
`ips/RTL_SOC/mem/<fw_dir>`.

### 8. Program the board

1. Set jumper **JP1 (MODE) to QSPI**.
2. Connect the PROG/UART micro-USB and power on.
3. From `fpga/nexys4ddr/pong/`:

```bash
program.bat
```

This writes `out/nexys4ddr_pong.mcs` to the flash, verifies it, and
reconfigures the FPGA from flash. From then on the board boots Pong at every
power-up.

Other modes: `program.bat jtag` loads only `out/top_pong.bit` (lost at
power-off; the firmware must already be in flash), and
`program.bat flash <fw>` writes `out/nexys4ddr_<fw>.mcs`.

### 9. Run

Open a terminal on the board's COM port (COM5 on this PC) at **115200 8N1**
(PuTTY, Tera Term) and press CPU_RESET to watch it boot. LD0 lights when the
image is loaded.

Keys: `w`/`s` left paddle, `i`/`k` right paddle (takes it over from the AI),
`a` gives the right paddle back to the AI, SPACE serves, `p` pauses, `r`
restarts after a win.

For the graphical viewer instead of the terminal:

```bash
python ../../../mem/pong/pong_viewer.py COM5
```

CPU_RESET (the red button) re-runs the cold boot from flash at any time.

---

## Adding a new board test

1. Copy `pong/` to `<name>/` and delete its `out/` and `work/`.
2. Rename `top_pong.sv` -> `top_<name>.sv` (and the module inside),
   `pong.xdc` -> `<name>.xdc`. Add any new pins to the top and the XDC.
3. In `build.tcl` set `test`/`top` and the default firmware to `<name>`; in
   `program.tcl` set `top` and the default `fw`. Update the comments in the
   `.bat` files.
4. Put the firmware in `ips/RTL_SOC/mem/<name>/` (a copy of `mem/pong/`'s
   `build.py` is a good start), then follow steps 3–9 above.
