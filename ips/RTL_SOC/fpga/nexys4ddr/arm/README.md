# Board test "arm": WidowX-200 robotic arm from the RISCFORGE SoC

The SoC drives the lab's WidowX-200 arm (Dynamixel Protocol 2.0: IDs 1–5
XM430-W350, IDs 6–7 XL430-W250) itself: it builds every servo packet, reads
the USB keyboard and the board's switches and buttons, and runs the poses.
No STM32 is needed.

| | |
|---|---|
| Board top | `top_arm.sv` (this folder) |
| Constraints | `arm.xdc` |
| Firmware | `ips/RTL_SOC/mem/arm/arm.c`, built by `mem/arm/build.py` |
| SoC clock | **32 MHz** (MMCM 100 MHz x 8 / 25) |
| Servo bus | SoC UART at **1 Mbps** (divisor 2), laptop relay or Pmod JA (SW13) |
| Servo settings | 1 Mbps, IDs 1–7, **Operating Mode 3 (position)**, set once through the U2D2 on 2026-11-04 (they were in velocity mode). The firmware writes no EEPROM. |
| Gripper | ID 7 is optional: used only if it answers (offline since 2026-11-04) |
| Keyboard | USB keyboard → Nexys PIC24 → PS/2 on pins F4/B2 → GPIO[21]/[22]; decoded in `arm.c` |
| Block diagram | `arm_block_diagram.png` / `.svg` |
| RTL | needs the core fix on `malay` (PR #11, `51a09f8`): load lost when a flush meets a memory stall |
| Status | **tested on the arm 2026-11-05 (laptop relay mode):** keyboard, torque on/off, jogging, C pose and rest pose. Direct mode (Pmod JA) not tried yet. |

## Three ways to run it

| Mode | SW13 | Servo link | Laptop needed while running? |
|---|---|---|---|
| **A. Laptop relay** (tested) | **on** | SoC UART → Nexys USB-UART → laptop `dxl_relay.py` → U2D2 → servos | **yes**, the relay must keep running |
| **B. Direct** | off | SoC UART → Pmod JA → level shifter → servos | no, but a laptop is handy for the console |
| **C. Standalone** | off | same as B | **no**: program once, then unplug the laptop |

In every mode the SoC makes every decision and builds every packet; the relay
only copies bytes. **Set SW13 before pressing CPU_RESET and do not touch it
while running:** the firmware reads it at reset (answer timeout), and the
board top switches the UART pins with it live, so moving it mid-run cuts the
servo link.

Programming always uses the laptop (Vivado, over the same PROG/UART cable,
JTAG channel). The bitstream and firmware are stored in the board's QSPI
flash, so after `program.bat` the board boots the arm demo by itself at every
power-on (jumper JP1 on QSPI).

## Quick start, mode A (laptop relay)

```
 USB keyboard ─► Nexys USB HOST ─► (PIC24, PS/2) ─► GPIO ─► SoC
 SoC UART ─► Nexys PROG/UART USB ─► laptop: dxl_relay.py ─► U2D2 ─► power hub ─► servos
```

1. **Wiring:** U2D2 3-pin cable in the power hub, its USB to the laptop.
   Nexys PROG/UART micro-USB to the same laptop. USB keyboard in the Nexys
   **USB HOST** port. 12 V on the power hub, hub switch on.
2. **Program** (only after a new build), from this folder: `program.bat`
   (jumper JP1 on QSPI).
3. **Switches:** SW13 **on**, SW15 **off**, all others off.
4. **Relay** (from the `arm_teleop/` folder here); close `arm_teleop.py`, Dynamixel
   Wizard and terminals on those ports first:

   ```bash
   python dxl_relay.py
   ```

   It finds both ports by USB ID and prints the SoC's console as `[SoC] ...`.
5. **CPU_RESET.** Expect `link: laptop relay (SW13 on)` and
   `ping: 1=ok 2=ok 3=ok 4=ok 5=ok 6=ok 7=--`.
6. Press `P`: every joint must read **0–4095** (see "Joint positions" below).
7. **SW15 on**: `torque ON`, the arm stiffens where it is.
8. Press a joint number, then hold `W` / `S`. Try `C` and `R`.

For short servo round trips set the FTDI **Latency Timer to 1 ms** on both
COM ports (Device Manager → port → Port Settings → Advanced), then replug.

## All controls

### Board switches and buttons

| Control | Action |
|---|---|
| **SW15** | **Master torque switch.** Off → on: reads every joint and makes that the goal (no jump), then torque on. On → off: torque off, the arm goes limp. Always wins over the keyboard. If SW15 is already on at power-up, switch it off and on again. |
| **SW14** | fast jog for the buttons: 30 ticks per 20 ms (~132 °/s) instead of 10 (~44 °/s) |
| **SW13** | servo link: **on = laptop relay**, off = direct (Pmod JA). Set before reset, never change while running. |
| SW0 | select waist (ID 1) for the buttons |
| SW1 | select shoulder (ID 2, with ID 3 mirrored) |
| SW2 | select elbow (ID 4) |
| SW3 | select wrist angle (ID 5) |
| SW4 | select wrist rotate (ID 6) |
| SW5 | select gripper (ID 7) |
| SW6–SW12 | not used |
| **BTNU / BTND** | while held: move the switch-selected joints up / down (several at once allowed) |
| **BTNC** | go to the **C pose** (one joint at a time) |
| **BTNL** | print all joint positions on the console |
| **BTNR** | ping IDs 1–7 again (LD8–LD14) |
| **CPU_RESET** | reboot the SoC from flash. Torque stays as the servos have it; switch SW15 off and on. |
| JP1 jumper | must be on **QSPI** (boot from flash) |

### USB keyboard (Nexys USB HOST port)

| Key | Action |
|---|---|
| `1` | select **waist** (ID 1) |
| `2` | select **shoulder** (ID 2 + ID 3 together) |
| `3` | select **elbow** (ID 4) |
| `4` | select **wrist angle** (ID 5) |
| `5` | select **wrist rotate** (ID 6) |
| `6` | select **gripper** (ID 7; ignored while it is offline) |
| `W` or `↑` | hold: move the selected joint up (position increases) |
| `S` or `↓` | hold: move the selected joint down |
| `A` / `D` | step smaller / bigger: 5 / **10** / 20 / 30 ticks per 20 ms |
| `Z` / `X` | speed slower / faster: profile velocity 30 / 60 / **100** / 200 |
| `C` | **C pose** (one joint at a time, shoulder first) |
| `R` | **balanced rest pose** (shoulder lowered last) |
| `Esc` | stop a pose move and hold where it is; also releases every key |
| `P` | print all joint positions |
| `T` | torque on (works only while SW15 is on) |
| `O` then `Y` | torque off: the arm goes limp |
| `H` | print the key help |

Defaults at power-up are in bold. The selected joint is printed as
`kb joint: ...`; **press the joint number first**, the last selection stays
active. The keyboard moves its own selected joint; the buttons move the
switch-selected joints; both work together.

### Poses (raw ticks, this arm)

| Pose | waist | shoulder (ID 2) | elbow | wrist angle | wrist rotate | order |
|---|---|---|---|---|---|---|
| C | 3974 | 1160 | 1963 | 834 | 2008 | shoulder, elbow, wrist angle, waist, wrist rotate |
| rest (balanced) | 3887 | 760 (742 is the stop) | 928 | 1442 | 2000 | wrist angle, elbow, waist, wrist rotate, shoulder |

Each joint finishes (servo reports stopped, within 80 ticks) before the next
starts. A joint that does not settle in 8 s stops the move and the arm holds.
ID 3 always follows ID 2 mirrored, keeping the offset measured at torque-on.
The poses include the waist: if the base was turned away from ~3900, a pose
turns it back (slowly, the direct way within 0–4095).

## Safety notes (read before use)

- **Emergency stop:** SW15 off makes the arm limp, but in **mode A** that
  command travels through the relay. If the relay is not running or the USB
  is unplugged, **SW15 cannot reach the servos**: the arm holds its last pose
  and the only stop is the **power hub switch** (the arm drops, support it).
- **Joint positions (multi-turn):** while torque is off, the servos keep
  counting whole turns if a joint is turned by hand past 4095 or 0 (you see
  values like 6990 or negative numbers). The servos only accept goals in
  0–4095, so turning torque on in that state can make the joint swing.
  **Press `P` before SW15. If any joint is outside 0–4095, switch the power
  hub off and on** (resets the count), then check again.
- Keep a hand on SW15 (or the hub switch) for the first moves after any
  change. Keep the gripper end clear of the table.
- Stuck keys: a held move key that stops sending auto-repeat for 1.2 s counts
  as released; with a keyboard that never repeats, one press moves at most
  3 s. A PS/2 data error, a full key queue, `Esc` or any torque change
  releases every key, so the arm never moves on its own.
- Torque stays off if any of IDs 1–6 does not answer, or if the shoulder pair
  disagrees (ID 3 not within 100 ticks of 4095 − ID 2).

## Power

| Part | Supply |
|---|---|
| **Nexys 4 DDR** | PROG/UART micro-USB (laptop or a **5 V USB charger**), or an external **4.5–5.5 V, ≥ 1 A** supply on the power jack (center-positive, 2.1 mm), selected with jumper **JP3**. **Never connect 12 V to the Nexys.** |
| **Servos** | **12 V** supply into the power hub's barrel jack (the arm's supply). The 12 V never goes to the Nexys. |
| Level shifter (modes B/C) | 3.3 V side from Pmod JA6, **5 V** side from a separate 5 V source (USB 5 V breakout or a small regulator), common ground |

## Mode B / C: direct link on Pmod JA (SW13 off)

The Dynamixel bus is a single DATA wire that both sides drive in turn
(half-duplex), at 5 V TTL levels. The Artix-7 pins are 3.3 V only and **not
5 V tolerant**, so the FPGA must never be connected straight to the servos.
Put a direction-controlled level shifter between them, such as a
**74LVC1T45** breakout (or a 74LVC2T45 / SN74LVC1T45 module).

```
 Nexys 4 DDR Pmod JA                74LVC1T45                 Servo bus (any free 3-pin port)
 ───────────────────                ─────────                 ──────────────────────────────
 JA1  DXL_DATA  ─────────────────── A        B  ───────────── DATA   (hub pin 3)
 JA2  DXL_DIR   ─────────────────── DIR
 JA6  3.3 V     ─────────────────── VCCA
                     5 V supply ─── VCCB
 JA5  GND       ─────────────────── GND ──────────────────── GND    (hub pin 1)
                                       hub pin 2 = 12 V: NOT connected to anything here
```

Pmod JA pins (Digilent 12-pin Pmod): 1–4 and 7–10 signals, 5 and 11 GND,
6 and 12 3.3 V. Pin 1 is marked on the silkscreen.

- **DIR:** 1 = A to B (FPGA transmits), 0 = B to A (servos answer); GPIO[16].
  GPIO resets to 0, so the FPGA never drives the bus before the firmware runs.
- **Measure first:** with the servos powered and nothing else on the line, the
  idle DATA voltage is about 5 V, which is why the shifter is needed.
- **One controller only:** unplug the U2D2's cable from the power hub (the hub
  stays: it powers the servos), and keep the STM32 off the bus.
- In direct mode servo answers take < 3 ms, and SW15 always reaches the
  servos (no relay in the path).

### Mode C: standalone, no laptop

1. With the laptop: build, `program.bat` (JP1 on QSPI). This writes the
   bitstream and firmware into the board's flash; it survives power-off.
2. Unplug the laptop. Power the Nexys from a **5 V USB charger** on the
   PROG/UART micro-USB (or a 5 V supply on the power jack with JP3 set).
3. Wire the level shifter to Pmod JA as above, U2D2 unplugged from the hub,
   12 V on the hub.
4. USB keyboard in the USB HOST port. SW13 **off**, SW15 off.
5. Power on (or CPU_RESET). LD0 lights, LD4 blinks, LD8–LD13 light when the
   servos answer the ping.
6. Without a laptop there is no console text: use the LEDs below. `P` and
   BTNL print to the console only, so if a joint was turned by hand, power-cycle
   the hub before SW15 on (that always brings every joint back into 0–4095).

## LEDs

| LED | Meaning |
|---|---|
| LD0 | `boot_done`: firmware loaded, core running |
| LD1 | pre-boot flash clocks done |
| LD2 | a bus-timeout monitor fired (should stay off) |
| LD3 | UART TX activity (servo packets and console text) |
| LD4 | heartbeat, toggles every 0.5 s (firmware alive) |
| LD5 | a servo read/write failed (timeout, CRC or status error) since the last ping scan |
| LD6 | fast jog (SW14) |
| LD7 | a move or pose command is running |
| LD8–LD14 | ID 1–7 answered the last ping |
| LD15 | torque on |

## Console

Mode A: `dxl_relay.py` prints it as `[SoC] ...`. Modes B/C: open the Nexys COM
port at **1000000 baud 8N1** (PuTTY: Speed 1000000; servo packets show as a
few garbage characters). You see the boot banner, ping results,
`torque on` / `REFUSED` / `torque OFF`, positions, pose progress and keyboard
messages.

## Why 32 MHz

The SoC UART oversamples 16x, so its baud rate is `clk / (16 x divisor)`,
with divisor >= 2. At 40 MHz (the Pong build), 1 Mbps would need a divisor of
2.5. At 32 MHz the divisor is exactly 2, so the SoC talks to the servos at
their 1 Mbps without any RTL change.

## Build and program

Firmware first, then the bitstream:

```bash
cd ips/RTL_SOC/mem/arm
python build.py
cd ../../fpga/nexys4ddr/arm
build.bat
program.bat
```

Results are in `out/`: `top_arm.bit`, `nexys4ddr_arm.mcs`, `arm.bin`, reports.
Rebuild the bitstream whenever the firmware size changes (the word counts in
`mem/arm/fw_params.svh` are built into it). Last build: WNS +1.065 ns.

## Not done yet

- Direct and standalone modes (Pmod JA + level shifter) not tried on the arm.
- Gripper (ID 7) offline: check its cable, then set it to position mode.
- Firmware does not yet refuse torque when a joint reads outside 0–4095
  (see the multi-turn note); `dxl_relay.py` exits on a USB unplug.
- Mouse not in this build (the firmware must send PS/2 command 0xF4; GPIO[18]
  is already wired for it).
- No simulation model of the servos or the PS/2 keyboard yet.
- Core RTL item still open with the team: `PCSrcE` is not gated during a
  memory stall (`execute_cycle.v`, `FlushE`).
