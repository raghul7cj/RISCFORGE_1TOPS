#!/usr/bin/env python3
"""Keyboard control of the lab WidowX-200 arm through a ROBOTIS U2D2.

Runs on Windows, Linux and macOS. Needs Python 3.8+ and pyserial
(pip install pyserial). The U2D2 port is found automatically.

    python arm_teleop.py                 # find the U2D2, start keyboard control
    python arm_teleop.py --port COM7     # use this port   (Linux: /dev/ttyUSB0)
    python arm_teleop.py --list          # list serial ports and exit
    python arm_teleop.py --check         # connect, print servo status, exit (no motion)

Keys
  1..6        select joint: 1 waist, 2 shoulder (ID 2 + ID 3 together),
              3 elbow, 4 wrist angle, 5 wrist rotate, 6 gripper (ID 7)
  w / s       move the selected joint + / -   (also Up / Down arrows)
  a / d       step size smaller / bigger: 10, 25, 50, 100 ticks (~1..9 deg)
  z / x       speed slower / faster (profile velocity)
  c           go to the C pose        r   go to the rest pose
  p           print all positions     h   help
  t           torque ON (goal = present first, so nothing jumps)
  o           torque OFF - asks for 'y' first: the arm DROPS
  q / Esc     quit (torque is left as it is)

Bus: Dynamixel Protocol 2.0, 1 Mbps, IDs 1..7, servos in position mode
(Operating Mode 3). On start, torque is switched on for every answering servo
with Goal = present position, so the arm holds where it is. Each key press
moves the goal by one step from the last goal. ID 3 always mirrors ID 2
(ID3 = 4095 - ID2 + the offset measured at torque-on). Goals stay inside
0..4095. Emergency stop: the power hub switch (the arm drops).
"""
import argparse
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing: pip install pyserial")

BAUD = 1_000_000

# U2D2 = FTDI FT232H. Other FTDI adapters are only used if they are the only one.
U2D2_VID_PID = {(0x0403, 0x6014)}
FTDI_VID = 0x0403

# key -> (name, ID)
JOINTS = {"1": ("waist", 1), "2": ("shoulder", 2), "3": ("elbow", 4),
          "4": ("wrist angle", 5), "5": ("wrist rotate", 6), "6": ("gripper", 7)}
ALL_IDS = [1, 2, 3, 4, 5, 6, 7]
STEPS = [10, 25, 50, 100]
SPEEDS = [10, 20, 40, 80, 150]           # profile velocity, 0.229 rpm units

# Raw tick poses of this arm (taught by hand / measured 2026-11-04).
# ID 3 is never listed: it always follows ID 2.
C_POSE = {1: 3974, 2: 1160, 4: 1963, 5: 834, 6: 2008}
REST_POSE = {1: 3887, 2: 760, 4: 928, 5: 1442, 6: 2000}    # balanced rest; shoulder just above its stop (742)
C_ORDER = [2, 4, 5, 1, 6]                 # lift the shoulder first
REST_ORDER = [5, 4, 1, 6, 2]              # lower the shoulder last


# ---------------------------------------------------------------------------
#  Keyboard: one key at a time, no Enter, on Windows and POSIX
# ---------------------------------------------------------------------------
if sys.platform == "win32":
    import msvcrt

    class Keys:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def get(self):
            k = msvcrt.getwch()
            if k in ("\x00", "\xe0"):             # arrow / function keys
                return {"H": "up", "P": "down"}.get(msvcrt.getwch(), "")
            return k
else:
    import select
    import termios
    import tty

    class Keys:
        def __enter__(self):
            self.fd = sys.stdin.fileno()
            self.old = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
            return self

        def __exit__(self, *exc):
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old)
            return False

        def get(self):
            k = sys.stdin.read(1)
            if k == "\x1b":                       # Esc alone, or an arrow sequence
                if select.select([sys.stdin], [], [], 0.05)[0]:
                    seq = sys.stdin.read(2)
                    return {"[A": "up", "[B": "down"}.get(seq, "")
            return k


# ---------------------------------------------------------------------------
#  Port selection
# ---------------------------------------------------------------------------
def list_serial_ports():
    ports = list(list_ports.comports())
    if not ports:
        print("no serial ports found")
    for p in ports:
        ids = f"{p.vid:04X}:{p.pid:04X}" if p.vid is not None else "----:----"
        tag = "  <- U2D2 (FT232H)" if (p.vid, p.pid) in U2D2_VID_PID else ""
        print(f"  {p.device:<16} {ids}  {p.description}{tag}")
    return ports


def find_port():
    ports = list(list_ports.comports())
    u2d2 = [p for p in ports if (p.vid, p.pid) in U2D2_VID_PID]
    if len(u2d2) == 1:
        return u2d2[0].device
    ftdi = [p for p in ports if p.vid == FTDI_VID]
    if not u2d2 and len(ftdi) == 1:
        return ftdi[0].device
    print("Could not pick the U2D2 port automatically. Serial ports:")
    list_serial_ports()
    sys.exit("Run again with --port <port> (e.g. --port COM6 or --port /dev/ttyUSB0)")


# ---------------------------------------------------------------------------
#  Dynamixel Protocol 2.0
# ---------------------------------------------------------------------------
def crc16(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x8005) if crc & 0x8000 else (crc << 1)
        crc &= 0xFFFF
    return crc


class Bus:
    def __init__(self, port):
        try:
            self.ser = serial.Serial(port, BAUD, timeout=0.005)
        except serial.SerialException as e:
            hint = ""
            if sys.platform.startswith("linux"):
                hint = "\n(Linux: add yourself to the 'dialout' group, then log in again)"
            sys.exit(f"cannot open {port}: {e}\n(Is another program using it? "
                     f"Close Dynamixel Wizard / other scripts.){hint}")

    # 60 ms reply window: covers the FTDI driver's default 16 ms latency timer.
    def transact(self, dxl_id, inst, params=(), wait=0.06):
        n = len(params) + 3
        body = [0xFF, 0xFF, 0xFD, 0x00, dxl_id, n & 0xFF, n >> 8, inst, *params]
        c = crc16(body)
        self.ser.reset_input_buffer()
        self.ser.write(bytes(body + [c & 0xFF, c >> 8]))
        self.ser.flush()
        t_end = time.time() + wait
        buf = b""
        while time.time() < t_end:
            buf += self.ser.read(self.ser.in_waiting or 1)
            i = buf.find(b"\xFF\xFF\xFD\x00")
            if i >= 0 and len(buf) >= i + 7:
                m = buf[i + 5] | (buf[i + 6] << 8)
                if len(buf) >= i + 7 + m:
                    p = buf[i:i + 7 + m]
                    if crc16(p[:-2]) == (p[-2] | (p[-1] << 8)) and p[4] == dxl_id and p[7] == 0x55:
                        return p[8], p[9:-2]
                    return None, None
        return None, None

    def read(self, dxl_id, addr, size):
        for _ in range(3):
            err, data = self.transact(dxl_id, 0x02, [addr & 0xFF, addr >> 8, size, 0])
            if data is not None and len(data) == size:
                v = int.from_bytes(data, "little")
                return v - (1 << 32) if size == 4 and v >= 1 << 31 else v
        return None

    def write(self, dxl_id, addr, size, val):
        params = [addr & 0xFF, addr >> 8] + list((val & 0xFFFFFFFF).to_bytes(size, "little"))
        for _ in range(3):
            err, _ = self.transact(dxl_id, 0x03, params)
            if err == 0:
                return True
        return False


# ---------------------------------------------------------------------------
#  Arm
# ---------------------------------------------------------------------------
class Arm:
    def __init__(self, bus):
        self.bus = bus
        self.ids = [i for i in ALL_IDS if bus.read(i, 132, 4) is not None]
        self.goal = {}
        self.off3 = 0
        self.speed_i = 1
        self.step_i = 1
        self.sel = "1"

    def present(self, i):
        return self.bus.read(i, 132, 4)

    def status(self):
        out = []
        for i in self.ids:
            out.append(f"  ID{i}: pos={self.present(i)} torque={self.bus.read(i, 64, 1)} "
                       f"mode={self.bus.read(i, 11, 1)} hw_err={self.bus.read(i, 70, 1)} "
                       f"temp={self.bus.read(i, 146, 1)}C")
        return "\n".join(out)

    def set_speed(self):
        for i in self.ids:
            self.bus.write(i, 112, 4, SPEEDS[self.speed_i])
            self.bus.write(i, 108, 4, 10)

    def torque_on(self):
        for i in self.ids:
            if self.bus.read(i, 11, 1) not in (3, 4, 5):
                print(f"  ID{i} is not in a position mode - left OFF")
                continue
            p = self.present(i)
            self.goal[i] = p
            self.bus.write(i, 116, 4, p)          # goal = present: no jump
        if 2 in self.goal and 3 in self.goal:
            self.off3 = self.goal[3] - (4095 - self.goal[2])
        self.set_speed()
        for i in self.goal:
            self.bus.write(i, 64, 1, 1)
        print(f"  torque ON for IDs {sorted(self.goal)}, holding")

    def torque_off(self):
        for i in self.ids:
            self.bus.write(i, 64, 1, 0)
        self.goal = {}
        print("  torque OFF - arm is limp")

    def set_goal(self, i, g):
        g = max(0, min(4095, g))
        self.goal[i] = g
        self.bus.write(i, 116, 4, g)
        if i == 2 and 3 in self.goal:
            g3 = max(0, min(4095, 4095 - g + self.off3))
            self.goal[3] = g3
            self.bus.write(3, 116, 4, g3)

    def jog(self, sign):
        name, i = JOINTS[self.sel]
        if i not in self.goal:
            print(f"  {name} (ID{i}) not available / torque off")
            return
        self.set_goal(i, self.goal[i] + sign * STEPS[self.step_i])
        print(f"  {name:<12} goal={self.goal[i]:5d}  ({(self.goal[i] - 2048) * 360 / 4096:+6.1f} deg)")

    def wait_still(self, ids, timeout=8.0):
        t0 = time.time()
        time.sleep(0.2)
        while time.time() - t0 < timeout:
            if not any(self.bus.read(i, 122, 1) for i in ids):
                return
            time.sleep(0.1)

    def go_pose(self, pose, order, name):
        if not self.goal:
            print("  torque is off - press t first")
            return
        print(f"  going to {name} pose (one joint at a time)")
        for i in order:
            if i in pose and i in self.goal:
                self.set_goal(i, pose[i])
                self.wait_still([i, 3] if i == 2 else [i])
                print(f"    ID{i} -> {self.present(i)}")
        print(f"  at {name} pose")


def help_line(arm):
    name, i = JOINTS[arm.sel]
    return (f"  joint={name} (ID{i})  step={STEPS[arm.step_i]} ticks  "
            f"speed={SPEEDS[arm.speed_i]}  |  1-6 joint  w/s move  a/d step  z/x speed  "
            f"c C-pose  r rest  p positions  t torque on  o torque off  h help  q quit")


def run(arm):
    arm.torque_on()
    print(help_line(arm))
    with Keys() as keys:
        while True:
            k = keys.get()
            k = {"up": "w", "down": "s"}.get(k, k).lower()
            if k in JOINTS:
                arm.sel = k
                print(help_line(arm))
            elif k == "w":
                arm.jog(+1)
            elif k == "s":
                arm.jog(-1)
            elif k in ("a", "d"):
                arm.step_i = max(0, min(len(STEPS) - 1, arm.step_i + (1 if k == "d" else -1)))
                print(f"  step = {STEPS[arm.step_i]} ticks")
            elif k in ("z", "x"):
                arm.speed_i = max(0, min(len(SPEEDS) - 1, arm.speed_i + (1 if k == "x" else -1)))
                arm.set_speed()
                print(f"  speed = {SPEEDS[arm.speed_i]}")
            elif k == "c":
                arm.go_pose(C_POSE, C_ORDER, "C")
            elif k == "r":
                arm.go_pose(REST_POSE, REST_ORDER, "rest")
            elif k == "p":
                print("  " + "  ".join(f"ID{i}={arm.present(i)}" for i in arm.ids))
            elif k == "t":
                arm.torque_on()
            elif k == "o":
                print("  torque OFF makes the arm DROP. Press y to confirm, any other key to cancel")
                if keys.get().lower() == "y":
                    arm.torque_off()
                else:
                    print("  cancelled")
            elif k == "h":
                print(__doc__)
            elif k in ("q", "\x1b"):
                print("  quit - torque left as it is")
                break


def main():
    ap = argparse.ArgumentParser(description="Keyboard control of the WidowX-200 via a U2D2.")
    ap.add_argument("--port", help="serial port of the U2D2 (default: found automatically)")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--check", action="store_true", help="print servo status and exit (no motion)")
    args = ap.parse_args()

    if args.list:
        list_serial_ports()
        return
    port = args.port or find_port()
    arm = Arm(Bus(port))
    print(f"port {port}: servos answering {arm.ids or 'none'}")
    if not arm.ids:
        sys.exit("no servo answered - is the power hub switched on? (U2D2 does not power the servos)")
    if args.check:
        print(arm.status())
        return
    run(arm)


if __name__ == "__main__":
    main()
