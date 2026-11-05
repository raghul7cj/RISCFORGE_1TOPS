# arm_teleop: laptop tools for the WidowX-200 and a U2D2

| Program | What it does |
|---|---|
| `arm_teleop.py` | keyboard control of the arm from the laptop (below) |
| `dxl_relay.py` | relay for the FPGA arm build: the RISCFORGE SoC on the Nexys controls the arm, the laptop only passes its packets to the U2D2 (see `../README.md`, SW13) |

`dxl_relay.py`: `python dxl_relay.py` (finds the Nexys USB-UART 0403:6010
and the U2D2 0403:6014), `--nexys COMx --u2d2 COMy` to choose, `--list`,
`-v` to print every packet. Only complete servo packets go to the U2D2; the
SoC's text is printed as `[SoC] ...`. Only one of the two programs can use
the U2D2 at a time.

## arm_teleop.py: keyboard control through a U2D2

One file, `arm_teleop.py`. It runs on Windows, Linux and macOS, finds the
U2D2's port by itself, and needs only Python 3.8+ and pyserial.

## Setup on a new computer

1. Install Python 3 and pyserial:

   ```bash
   pip install -r requirements.txt
   ```

2. Driver: the U2D2 is an FTDI FT232H. Windows 10/11, Linux and macOS
   normally have the driver already. If no port appears, install the FTDI
   VCP driver.
3. Linux only: allow access to the port, then log out and in again:

   ```bash
   sudo usermod -aG dialout $USER
   ```

## Hardware

- U2D2 **3-pin TTL** port -> U2D2 power hub -> the arm's servo chain.
- 12 V supply into the hub's barrel jack, and the **hub switch ON**. The U2D2
  does not power the servos. At power-on each servo's red LED blinks once.
- Servos: Protocol 2.0, **1 Mbps**, IDs 1–7, Operating Mode 3 (position).
  ID 1 waist, 2+3 shoulder pair (ID3 = 4095 − ID2), 4 elbow, 5 wrist angle,
  6 wrist rotate, 7 gripper.
- Only one program may use the port. Close Dynamixel Wizard before starting.

## Run

```bash
python arm_teleop.py --list      # show serial ports; the U2D2 is marked
python arm_teleop.py --check     # servo status, nothing moves
python arm_teleop.py             # keyboard control
python arm_teleop.py --port COM7          # if auto-detect picks wrong / finds none
python arm_teleop.py --port /dev/ttyUSB0  # Linux
```

On start, torque goes on with every goal = current position, so the arm holds
where it is and nothing jumps.

| Key | Action |
|---|---|
| `1`–`6` | select joint: 1 waist, 2 shoulder (both motors), 3 elbow, 4 wrist angle, 5 wrist rotate, 6 gripper |
| `w` / `s`, ↑ / ↓ | move the selected joint + / − one step |
| `a` / `d` | step 10 / 25 / 50 / 100 ticks (~1 / 2 / 4 / 9 deg) |
| `z` / `x` | slower / faster |
| `c` | go to the C pose (one joint at a time, shoulder first) |
| `r` | go to the rest pose (shoulder lowered last) |
| `p` | print positions |
| `t` | torque on |
| `o` | torque off; asks for `y`, because the arm drops |
| `h` | help |
| `q` / Esc | quit; torque is left as it is |

To finish: `r` (rest), then `o` `y` (torque off), then `q`.
Emergency stop: the hub power switch (the arm drops).

## Notes

- Goals are only clamped to 0..4095. There are no joint limits beyond that,
  so use small steps near the table and the base.
- The C and rest poses are raw tick values of this arm, set at the top of
  `arm_teleop.py` (`C_POSE`, `REST_POSE`).
- The program writes only RAM registers: Goal Position, Torque Enable,
  Profile Velocity and Acceleration. It never changes IDs, baud rate or modes.
