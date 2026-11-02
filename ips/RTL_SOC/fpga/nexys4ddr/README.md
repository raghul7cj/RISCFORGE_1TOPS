# RISCFORGE 1TOPS on the Nexys 4 DDR

Board top, constraints and Vivado scripts for running the SoC on a Digilent
Nexys 4 DDR (XC7A100T-1CSG324C). The SoC RTL is not modified.

```
fpga/nexys4ddr/
├── nexys4ddr_top.sv        board top: SoC + MMCM + STARTUPE2 + pre-boot clocks + LEDs
├── nexys4ddr.xdc           pins (clock, reset, USB-UART, QSPI flash, LEDs)
├── win_sources.f           RTL file list for the Windows checkout
├── build.bat / build.tcl   Vivado batch: synth -> impl -> .bit -> .mcs
├── program.bat / program.tcl  write the .mcs to the flash (or .bit over JTAG)
├── tb/
│   ├── soc_nexys4ddr_tb.sv board-top simulation (Xcelium)
│   └── make_sim_flash.py   flash preload with the image at 0x400000
├── out/                    RESULTS (kept): .mcs, .bit, .prm, <fw>.bin, reports
└── work/                   Vivado run files (git-ignored, safe to delete):
                            logs, journals, .Xil cache, crash dumps, .dcp checkpoints
```

`build.bat` and `program.bat` start Vivado inside `work/`, so nothing but
`out/` changes in this folder. Delete `work/` at any time; it is recreated.

## Clock

The SoC runs at **40 MHz** from an MMCM (100 MHz oscillator x 10 / 25). At
100 MHz the design does not close: the worst path, core MMIO address ->
`hybrid_mem_interface` -> AXI-Lite crossbar -> `axi_lite_to_apb` -> response ->
core stall -> next PC -> ISRAM address, is ~21.6 ns in one cycle. At 40 MHz
the routed design meets timing (WNS +0.52 ns). Firmware for the board must be
built with `CLK_HZ = 40 MHz` (the default in `mem/pong/build.py`): UART
divisor 22, i.e. 113 636 baud, which a terminal set to 115200 reads fine.

## How it boots

The SoC loads its program from the on-board QSPI flash (S25FL128S, 16 MB),
the same chip the FPGA configures from:

| Flash address | Contents |
|---|---|
| `0x000000` | FPGA bitstream (~3.8 MB) |
| `0x400000` | firmware image (`pong_flash.mem` as raw bytes) |

`nexys4ddr_top.sv` sets the bootloader's `FLASH_START_ADDR` to `0x400000`
and the boot ROM's `HEX_FILE` with `defparam`. The flash clock is CCLK, driven
through `STARTUPE2.USRCCLKO`. STARTUPE2 drops the first 3 clocks after
configuration, so the top sends 8 dummy clocks (flash deselected) before
releasing the SoC from reset.

| LED | Meaning |
|---|---|
| LD0 | `boot_done`: image loaded, core running |
| LD1 | pre-boot dummy clocks done |
| LD2 | a bus-timeout monitor fired (should stay off) |
| LD3 | UART TX activity |
| LD8–LD15 | `gpio_out_o[7:0]` |

CPU_RESET (the red button) re-runs the cold boot from flash.

## 1. Simulate the board top (Linux, Xcelium)

```bash
cd ips/RTL_SOC/mem/pong
python build.py --sim
python ../../fpga/nexys4ddr/tb/make_sim_flash.py
```

In `ips/RTL_SOC/run.f`, set the SELECT TEST block to:

```
+incdir+../mem/pong/sim_build
../fpga/nexys4ddr/nexys4ddr_top.sv
../fpga/nexys4ddr/tb/soc_nexys4ddr_tb.sv
-top soc_nexys4ddr_tb
```

```bash
cd ips/RTL_SOC/sim
xrun -f ../run.f -l logs/nexys4ddr.log
```

Expected: `*** NEXYS4DDR BOARD TOP TEST PASSED ***`. The test checks the
dummy clocks, the boot from `0x400000`, the Pong title on `UART_RXD_OUT`, and
a reset-button re-boot.

## 2. Build the bitstream and flash image (Vivado)

Build the **board** firmware (40 MHz, 115200 baud, 30 fps), not the `--sim` one:

```bash
cd ips/RTL_SOC/mem/pong
python build.py
cd ../../fpga/nexys4ddr
build.bat
```

On Linux `build.tcl` reads the same filelists as Xcelium (`filelists/inc.f`,
`ip.f`, `core.f`, `soc_rtl.f`). On Windows it reads `win_sources.f`: the same
files in the same order at this checkout's paths (the IP layout differs from
the Linux tree). Paths in both are relative to `ips/RTL_SOC/sim/`.

After the first build, check:

- `work/vivado_build.log`: under `Synthesizing module 'bootloader'`,
  `FLASH_START_ADDR bound to: 24'b010000000000000000000000` (= 0x400000).
  If it shows 0, the `defparam` was not applied.
- `out/timing_summary.rpt`: WNS >= 0 ("All user specified timing constraints
  are met"). If you change the MMCM frequency, the firmware's `CLK_HZ`
  (pong.c, build.py) must change with it.

## 3. Program the board

1. Set jumper **JP1 (MODE) to QSPI**.
2. Connect the PROG/UART micro-USB and power on.
3. Run:

```bash
program.bat
```

This writes `out/nexys4ddr_pong.mcs` (bitstream + Pong), verifies it, and
reconfigures the FPGA from flash. From then on the board boots into Pong at
every power-up.

4. Open a terminal on the board's COM port at **115200 8N1** (PuTTY, Tera
   Term), then press CPU_RESET to watch it boot. For the graphical viewer:

```bash
python ../../mem/pong/pong_viewer.py COM5
```
