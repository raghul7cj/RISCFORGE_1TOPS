#!/usr/bin/env python3
"""Laptop relay between the Nexys 4 DDR (RISCFORGE SoC, arm build) and a U2D2.

The SoC builds every Dynamixel packet itself; this script only passes them on:

    SoC UART --USB-UART (Nexys)--> laptop --USB--> U2D2 --> servo bus
    SoC UART <--USB-UART (Nexys)-- laptop <--USB-- U2D2 <-- servo answers

The SoC's status text arrives on the same link. It is printed here and not
sent to the servos: from the Nexys stream, only complete Protocol 2.0 packets
(FF FF FD 00 ...) go to the U2D2; every other byte is console text.

Runs on Windows, Linux and macOS (Python 3.8+, pyserial). Ports are found by
USB ID (Nexys FT2232 0403:6010, U2D2 FT232H 0403:6014), or given by hand.

    python dxl_relay.py
    python dxl_relay.py --nexys COM5 --u2d2 COM6
    python dxl_relay.py --list
    python dxl_relay.py -v              # also print every forwarded packet

Board side: arm bitstream with SW13 ON (laptop-relay link), then reset.
Close arm_teleop.py / Dynamixel Wizard first: the U2D2 port must be free.
For short round trips set both ports' FTDI Latency Timer to 1 ms
(Windows: Device Manager > port > Port Settings > Advanced).
Stop with Ctrl+C.
"""
import argparse
import sys
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing: pip install pyserial")

BAUD = 1_000_000
NEXYS_IDS = {(0x0403, 0x6010)}      # FT2232: the Nexys USB-UART (interface B)
U2D2_IDS = {(0x0403, 0x6014)}       # FT232H: ROBOTIS U2D2


def list_serial_ports():
    for p in list_ports.comports():
        ids = f"{p.vid:04X}:{p.pid:04X}" if p.vid is not None else "----:----"
        tag = ""
        if (p.vid, p.pid) in NEXYS_IDS:
            tag = "  <- Nexys USB-UART"
        elif (p.vid, p.pid) in U2D2_IDS:
            tag = "  <- U2D2"
        print(f"  {p.device:<16} {ids}  {p.description}{tag}")


def find(ids, what, flag):
    hits = [p.device for p in list_ports.comports() if (p.vid, p.pid) in ids]
    if len(hits) == 1:
        return hits[0]
    print(f"Could not pick the {what} port automatically ({len(hits)} candidates). Serial ports:")
    list_serial_ports()
    sys.exit(f"Run again with {flag} <port>")


def open_port(dev, what):
    try:
        return serial.Serial(dev, BAUD, timeout=0.001)
    except serial.SerialException as e:
        sys.exit(f"cannot open {what} port {dev}: {e}\n"
                 f"(close arm_teleop.py / Dynamixel Wizard / terminals using it)")


class NexysStream:
    """Splits the byte stream from the SoC into Dynamixel packets and text."""

    def __init__(self, on_packet, on_text):
        self.on_packet = on_packet
        self.on_text = on_text
        self.pkt = bytearray()
        self.text = bytearray()

    def feed(self, data):
        for b in data:
            p = self.pkt
            if p:
                p.append(b)
                n = len(p)
                if n <= 4:                                   # header FF FF FD 00
                    if b != (0xFF, 0xFF, 0xFD, 0x00)[n - 1]:
                        self._flush_partial()
                    continue
                if n >= 7 and n == 7 + (p[5] | (p[6] << 8)):
                    self.on_packet(bytes(p))
                    p.clear()
                continue
            if b == 0xFF:
                p.append(b)
                continue
            self._text_byte(b)

    def _flush_partial(self):
        # Not a packet after all: the first byte (FF) is dropped as text, and
        # the rest is scanned again, since a real header may start inside it.
        rest = bytes(self.pkt[1:])
        self.pkt.clear()
        self.feed(rest)

    def _text_byte(self, b):
        if b == 0x0A:
            self.on_text(self.text.decode("ascii", "replace").rstrip("\r"))
            self.text.clear()
        elif 0x20 <= b < 0x7F or b == 0x0D:
            self.text.append(b)


def main():
    ap = argparse.ArgumentParser(description="Relay between the Nexys SoC and a U2D2.")
    ap.add_argument("--nexys", help="Nexys USB-UART port (default: found by USB ID)")
    ap.add_argument("--u2d2", help="U2D2 port (default: found by USB ID)")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("-v", "--verbose", action="store_true", help="print forwarded packets")
    args = ap.parse_args()
    if args.list:
        list_serial_ports()
        return

    nexys_dev = args.nexys or find(NEXYS_IDS, "Nexys", "--nexys")
    u2d2_dev = args.u2d2 or find(U2D2_IDS, "U2D2", "--u2d2")
    nexys = open_port(nexys_dev, "Nexys")
    u2d2 = open_port(u2d2_dev, "U2D2")
    print(f"relay: Nexys {nexys_dev} <-> U2D2 {u2d2_dev} at {BAUD} baud. Ctrl+C to stop.")
    print("Board: SW13 on (laptop relay), then press CPU_RESET to see the banner.\n")

    stats = {"to_servo": 0, "to_soc": 0}
    stop = threading.Event()

    def to_servo(pkt):
        u2d2.write(pkt)
        stats["to_servo"] += 1
        if args.verbose:
            print(f"  SoC->servo {pkt.hex(' ').upper()}")

    def text(line):
        if line:
            print(f"[SoC] {line}", flush=True)

    stream = NexysStream(to_servo, text)

    def servo_to_soc():
        while not stop.is_set():
            data = u2d2.read(u2d2.in_waiting or 1)
            if data:
                nexys.write(data)
                stats["to_soc"] += len(data)
                if args.verbose:
                    print(f"  servo->SoC {data.hex(' ').upper()}")

    t = threading.Thread(target=servo_to_soc, daemon=True)
    t.start()
    try:
        while True:
            data = nexys.read(nexys.in_waiting or 1)
            if data:
                stream.feed(data)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        t.join(timeout=0.5)
        print(f"\nrelay stopped: {stats['to_servo']} packets to the servos, "
              f"{stats['to_soc']} bytes back to the SoC")
        nexys.close()
        u2d2.close()


if __name__ == "__main__":
    main()
