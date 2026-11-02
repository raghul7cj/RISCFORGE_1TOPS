#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - Pong viewer. Draws the game state streamed by pong.c.

    pip install pygame pyserial
    python pong_viewer.py COM5                 # 115200 baud by default
    python pong_viewer.py COM5 --baud 115200

All game logic runs on the SoC. This script only:
  - sends 0x02 to switch the firmware to binary mode (and 0x01 on exit, back to
    terminal mode),
  - forwards held keys (w/s, i/k, a, p, r, space),
  - draws each 16-byte state packet:
      0xA5 0x5A | bx(2) by(2) | p1 p2 | s1 s2 | state | last | rsvd(3) | sum
    bx/by are little-endian with 4 fractional bits; s1/s2 are the LEFT/RIGHT
    scores; last is the side that won the last point (0 none, 1 LEFT,
    2 RIGHT); sum is the low byte of the sum of the 13 bytes between the sync
    word and the checksum.
"""

import argparse
import sys

import pygame
import serial

# Must match pong.c
FW, FH, PH = 80, 22, 4
P1X, P2X = 2, 77
ST_NAMES = {0: "", 1: "PAUSED", 2: "SPACE to serve", 3: "LEFT WINS - r to restart",
            4: "RIGHT WINS - r to restart"}
SCORER = {1: "LEFT scores!", 2: "RIGHT scores!"}

CELL = 12                       # pixels per field cell
TOP = 60                        # score bar height
W, H = FW * CELL, FH * CELL + TOP + 30

BG, FG, DIM, ACC, BALL = (12, 14, 20), (230, 235, 240), (70, 80, 95), (80, 220, 140), (255, 210, 60)

HOLD_KEYS = {pygame.K_w: b"w", pygame.K_s: b"s", pygame.K_UP: b"i", pygame.K_DOWN: b"k",
             pygame.K_i: b"i", pygame.K_k: b"k"}
TAP_KEYS = {pygame.K_p: b"p", pygame.K_r: b"r", pygame.K_SPACE: b" ", pygame.K_a: b"a"}
MODE_TERM, MODE_BIN = b"\x01", b"\x02"   # pong.c display-mode control bytes
KEY_REPEAT_FRAMES = 2           # send a held key every 2nd frame (~30 cells/s at 60 fps)


class PacketReader:
    def __init__(self):
        self.buf = bytearray()
        self.bad = 0

    def feed(self, data):
        """Return the newest valid packet in data, or None."""
        self.buf += data
        latest = None
        while True:
            i = self.buf.find(b"\xA5\x5A")
            if i < 0:
                del self.buf[:-1]
                return latest
            if len(self.buf) - i < 16:
                del self.buf[:i]
                return latest
            body = self.buf[i + 2:i + 15]
            if (sum(body) & 0xFF) == self.buf[i + 15]:
                latest = bytes(body)
                del self.buf[:i + 16]
            else:
                self.bad += 1
                del self.buf[:i + 1]


def decode(body):
    bx = int.from_bytes(body[0:2], "little", signed=True) / 16.0
    by = int.from_bytes(body[2:4], "little", signed=True) / 16.0
    return dict(bx=bx, by=by, p1=body[4], p2=body[5], s1=body[6], s2=body[7],
                state=body[8] & 0x0F, ai=(body[8] >> 4) & 1, last=body[9])


def draw(screen, fonts, st, stats):
    big, small = fonts
    screen.fill(BG)

    # score bar
    s = big.render(f"{st['s1']}", True, FG)
    screen.blit(s, (W // 2 - 60 - s.get_width(), 8))
    s = big.render(f"{st['s2']}", True, FG)
    screen.blit(s, (W // 2 + 60, 8))
    screen.blit(small.render("RISCFORGE PONG", True, ACC), (12, 10))
    screen.blit(small.render("LEFT (w/s)  vs  RIGHT " + ("(CPU)" if st["ai"] else "(i/k)"),
                             True, DIM), (12, 32))

    # field
    pygame.draw.rect(screen, DIM, (0, TOP - 2, W, FH * CELL + 4), 2)
    for y in range(0, FH, 2):
        pygame.draw.rect(screen, DIM, (W // 2 - 2, TOP + y * CELL + 2, 4, CELL - 4))
    for x, top in ((P1X, st["p1"]), (P2X, st["p2"])):
        pygame.draw.rect(screen, ACC, (x * CELL + 2, TOP + top * CELL, CELL - 4, PH * CELL),
                         border_radius=3)
    if 0 <= st["bx"] < FW:
        pygame.draw.circle(screen, BALL, (int(st["bx"] * CELL), int(TOP + st["by"] * CELL)),
                           CELL // 2)

    # status line
    msg = ST_NAMES.get(st["state"], "")
    if st["state"] == 2 and st["last"] in SCORER:
        msg = SCORER[st["last"]] + "  SPACE to serve"
    if msg:
        t = big.render(msg, True, FG)
        screen.blit(t, ((W - t.get_width()) // 2, TOP + FH * CELL // 2 - 60))
    info = f"w/s  i/k (up/down)  a=CPU  p pause  r restart    pkts {stats['ok']}  bad {stats['bad']}"
    screen.blit(small.render(info, True, DIM), (12, H - 24))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("port", help="serial port, e.g. COM5 or /dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=115200)
    args = ap.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0)
    except serial.SerialException as e:
        sys.exit(f"Error: {e}")

    pygame.init()
    screen = pygame.display.set_mode((W, H))
    pygame.display.set_caption("RISCFORGE Pong - running on RV32I")
    fonts = (pygame.font.SysFont("consolas", 32, bold=True), pygame.font.SysFont("consolas", 16))
    clock = pygame.time.Clock()

    ser.write(MODE_BIN)
    reader = PacketReader()
    st = dict(bx=FW / 2, by=FH / 2, p1=(FH - PH) // 2, p2=(FH - PH) // 2,
              s1=0, s2=0, state=2, ai=1, last=0)
    stats = dict(ok=0, bad=0)
    frame = 0

    running = True
    while running:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT or (ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE):
                running = False
            elif ev.type == pygame.KEYDOWN and ev.key in TAP_KEYS:
                ser.write(TAP_KEYS[ev.key])

        if frame % KEY_REPEAT_FRAMES == 0:
            held = pygame.key.get_pressed()
            out = b"".join(c for k, c in HOLD_KEYS.items() if held[k])
            if out:
                ser.write(out)

        data = ser.read(4096)
        if data:
            pkt = reader.feed(data)
            if pkt is not None:
                st = decode(pkt)
                stats["ok"] += 1
            stats["bad"] = reader.bad
        elif frame % 60 == 0:
            ser.write(MODE_BIN)             # SoC was reset or in terminal mode

        draw(screen, fonts, st, stats)
        pygame.display.flip()
        clock.tick(60)
        frame += 1

    ser.write(MODE_TERM)                    # leave the firmware in terminal mode
    ser.close()
    pygame.quit()


if __name__ == "__main__":
    main()
