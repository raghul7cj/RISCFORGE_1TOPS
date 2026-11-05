# Board test "pong": Pong on the RISCFORGE SoC

Pong runs entirely on the RV32 core. The laptop is only the screen and
keyboard: it talks to the SoC over the Nexys's own USB-UART cable.

| | |
|---|---|
| Board top | `top_pong.sv` (this folder) |
| Constraints | `pong.xdc` |
| Firmware | `ips/RTL_SOC/mem/pong/pong.c`, built by `mem/pong/build.py` |
| SoC clock | **40 MHz** (MMCM 100 MHz x 10 / 25) |
| Link | SoC UART at **115200 baud 8N1** (113 636 actual) over the board's USB-UART |
| Block diagram | `pong_block_diagram.png` / `.svg` |
| Status | runs on the board (checked over COM5, 2026-11-02) |

## Quick start

1. **Board setup:** jumper **JP1 (MODE) on QSPI**. Connect the **PROG/UART**
   micro-USB to the laptop. That cable powers the board, programs it and
   carries the game.
2. **Program** (once; the game stays in flash after power-off), from this
   folder:

   ```bash
   program.bat
   ```

3. **Open a terminal** on the board's COM port (COM5 on this PC) at
   **115200 8N1**: PuTTY → Serial → Speed 115200. Or use the graphical viewer:

   ```bash
   python ../../../mem/pong/pong_viewer.py COM5
   ```

4. **Press CPU_RESET** (the red button) to see the title screen, then
   **SPACE** to serve.

## All controls

### Laptop keyboard (in the terminal or viewer window)

| Key | Action |
|---|---|
| `W` / `S` | LEFT paddle up / down |
| `I` / `K` | RIGHT paddle up / down (the first press takes it over from the CPU) |
| `A` | give the RIGHT paddle back to the CPU (AI) |
| SPACE | serve |
| `P` | pause / continue |
| `R` | restart (after a win, or at any time) |

The first side to 7 points wins. A side scores when the ball goes past the
**other** side's paddle.

`pong_viewer.py` switches the game to its binary display by itself (control
byte `0x02`) and back to the terminal display when it exits (`0x01`). These
are not printable keys, so typing in a terminal never changes the mode.

### Board

| Control | Action |
|---|---|
| **CPU_RESET** (red button) | reboot the SoC: cold boot from flash, title screen again |
| JP1 jumper | must be on **QSPI**, so the board boots Pong from flash at power-on |
| Switches SW0–SW15, buttons BTNC/U/D/L/R | **not used** by Pong |

There is no USB keyboard on the board in this build: the keys come from the
laptop over the USB-UART.

### LEDs

| LED | Meaning |
|---|---|
| LD0 | `boot_done`: firmware loaded from flash, core running |
| LD1 | pre-boot flash clocks done |
| LD2 | a bus-timeout monitor fired (should stay off) |
| LD3 | UART TX activity (the game screen being sent) |
| LD8–LD15 | `gpio_out[7:0]` (wired, but Pong does not use GPIO: off) |

## Power

The Nexys 4 DDR runs from the **PROG/UART micro-USB** (laptop or a 5 V USB
charger), or from an external **4.5–5.5 V** supply on its power jack
(center-positive, 2.1 mm), selected with jumper **JP3**. Never connect 12 V
to the Nexys.

## Build

See `../README.md` for the full flow (C code → build.py → simulation → board
top → Vivado). In short:

```bash
cd ips/RTL_SOC/mem/pong
python build.py
cd ../../fpga/nexys4ddr/pong
build.bat
program.bat
```

Rebuild the bitstream (`build.bat`) whenever the firmware size changes: the
bootloader's word counts in `mem/pong/fw_params.svh` are built into it.
