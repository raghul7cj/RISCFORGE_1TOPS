"""
fig12 - I2C SCL/SDA byte timing waveform.

One byte on the wire is START + 8 data bits + a 9th ACK clock.
Grounded in:
  i2c_master_byte_ctrl.sv : ST_IDLE/ST_START/ST_READ/ST_WRITE/ST_ACK/ST_STOP,
                            ack_out <= core_rxd  (slave owns the 9th bit)
  i2c_master_bit_ctrl.sv  : scl_i + slave_wait (clock stretching IS implemented),
                            scl_sync, clk_cnt 16-bit prescale,
                            18-bit one-hot FSM, 4 states per SCL period.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle

TITLE = ("One byte is START + 8 data bits + a 9th ACK clock \u2014 "
         "the 9th clock is free, it only lets the slave pull SDA low")
SUBTITLE = ("SCL (serial clock) / SDA (serial data).  Read left to right on the "
            "numbered phase bar:  1 START -> 2 ADDRESS -> 3 ACK -> 4 DATA -> "
            "5 ACK -> 6 STOP")

# ---------------------------------------------------------------- geometry
X0 = 20.0                 # left edge of bit cell 0
U = 4.8                   # one bit period
NCELL = 20                # START + 8 addr + ACK + 8 data + ACK + STOP
XEND = X0 + NCELL * U     # 116.0
GAP = 7.8                 # lane pitch -> centres ph/bus/str/sda/scl

# half-phase grid: cell i high window = p (2i+0.5) .. p (2i+2.0)
SCL_LO, SCL_HI = 36.8, 41.2
SDA_LO, SDA_HI = 29.0, 33.4
ST_LO, ST_HI = 21.0, 24.6
BAND_A = (35.4, 44.4)    # shaded: every SCL-high window
BAND_B = (28.2, 35.0)    # shaded: SDA-stable-high windows
CELL_Y, CELL_H = 15.2, 6.6
PH_Y, PH_H = 2.4, 2.8
NOTE_Y, NOTE_H = 48.4, 10.0


def px(p):
    """half-phase position -> x in canvas units"""
    return X0 + p * (U / 2.0)


def wf(ax, pts, color, lw=2.0, dashed=False, z=6, lo=None, hi=None):
    """Explicit polyline: level holds until the next computed sample point.

    ``steps-post`` keeps every edge vertical and every plateau horizontal,
    which is what a 2-level open-drain bus signal actually looks like.
    """
    xs = [px(p) for p, _ in pts]
    lo = SCL_LO if lo is None else lo
    hi = SCL_HI if hi is None else hi
    ys = [(hi if v else lo) for _, v in pts]
    ax.add_line(Line2D(xs, ys, color=color, lw=lw, drawstyle="steps-post",
                       zorder=z, solid_capstyle="round",
                       solid_joinstyle="round",
                       linestyle=(0, (3.2, 2.2)) if dashed else "solid"))
    return xs, ys


# ---- SCL: 4 states per period in the RTL (wr_a low, wr_b high, wr_c high, wr_d low)
SCL_PTS = [(0.0, 0)]
for i in range(NCELL):
    SCL_PTS += [(2 * i + 0.5, 1), (2 * i + 2.0, 0)]
SCL_PTS += [(2 * NCELL + 0.9, 0)]

# ---- SDA: every edge sits in an SCL-low shoulder except START / STOP
SDA_PTS = [(0.0, 1), (1.25, 0), (2.25, 1), (4.25, 0), (6.25, 1), (8.25, 0),
           (24.25, 1), (32.25, 0), (38.75, 1), (2 * NCELL + 0.9, 1)]

# phase colours (used by BOTH the phase bar and the payload cells)
C_IDLE = "#D9D9D9"
C_START = "#F8CBAD"
C_ADDR = fs.S_ADDR
C_ACK = fs.S_RESP
C_DATA = fs.S_REQ
EC = {C_IDLE: "#A6A6A6", C_START: "#C55A11", C_ADDR: "#BF8F00",
      C_ACK: "#70AD47", C_DATA: "#2E75B6"}
TC = {C_IDLE: "#404040", C_START: "#843C0C", C_ADDR: "#7F6000",
      C_ACK: "#1E5B10", C_DATA: "#12466F"}


def main():
    fig, ax = fs.slide(TITLE, SUBTITLE)
    X, Y = fs.canvas(ax)
    print(f"canvas = {X:.2f} x {Y:.2f} units")

    rows = [("scl", "SCL", None), ("sda", "SDA", None),
            ("str", "SCL stretch", "own time base \u2014 not to scale"),
            ("bus", "cells", None),
            ("ph", "phase", None)]
    ax, ys, unit = fs.lanes(fig, rows, X0, XEND, unit=U, left_pad=1.0,
                            lane_gap=GAP)
    assert abs(unit - U) < 1e-9

    # ---------------- bit-period grid + SCL-high shading
    ax.add_patch(Rectangle((X0 - 0.7, BAND_A[0]), XEND - X0 + 1.4,
                           BAND_A[1] - BAND_A[0], facecolor="#EEF5FB",
                           edgecolor="none", zorder=1))
    fs.cycle_guides(ax, X0, NCELL, U, bottom=11.0, top=BAND_A[1])

    # ---------------- L2: SCL waveform + START + the 8 address bits
    wf(ax, SCL_PTS, fs.ACCENT)
    wf(ax, SDA_PTS, fs.MID, lo=SDA_LO, hi=SDA_HI)

    # ---------------- L3: payload cells, colour-matched to the phase bar
    cells(ax, c=0, vals=[""], col=C_START)                       # START
    cells(ax, c=1, vals=["1", "0", "1", "0", "0", "0", "0"], col=C_ADDR)
    cells(ax, c=8, vals=["0"], col=C_ADDR)                       # R/W
    cells(ax, c=9, vals=[""], col=C_ACK)                         # 9th clk #1
    cells(ax, c=10, vals=["0", "0", "1", "1", "1", "1", "0", "0"], col=C_DATA)
    cells(ax, c=18, vals=[""], col=C_ACK)                        # 9th clk #2
    cells(ax, c=19, vals=[""], col=C_START)                      # STOP

    # ---------------- L4a: PHASE bar.  Field names + step numbers only: the
    # bit digits live in the "cells" lane above (aligned to SDA) and the decode
    # lives in the two labels below, so repeating them here was pure clutter.
    fs.phase_bar(ax, X0, NCELL, PH_Y, PH_H, [
        (-0.30, 0.0, "", C_IDLE),
        (0.0, 1.0, "1  START", C_START),
        (1.0, 9.0, "2  ADDRESS", C_ADDR),
        (9.0, 10.0, "3  ACK", C_ACK),
        (10.0, 18.0, "4  DATA", C_DATA),
        (18.0, 19.0, "5  ACK", C_ACK),
        (19.0, 20.0, "6  STOP", C_START)], fs=7.4, unit=U)
    fs.label(ax, X0 - 0.72, PH_Y + PH_H / 2, "IDLE", fs=6.4, color="#404040",
             weight="bold", rot=90)

    fs.label(ax, 44.0, 7.8, "7-bit slave address 0x50 = 1010000\n"
             "R/W = 0  \u2192  write", fs=7.6, color=fs.TXT, weight="bold")
    fs.label(ax, 87.2, 7.8, "data byte = 0011 1100 = 0x3C", fs=7.6,
             color=fs.TXT, weight="bold")

    # ---------------- L4b: SDA-stable-high windows
    ax.add_patch(Rectangle((X0 - 0.1, BAND_B[0]), XEND - X0 + 0.2,
                           BAND_B[1] - BAND_B[0], facecolor="#F2F7EC",
                           edgecolor="none", zorder=1))
    for a, b in [(px(2.25), px(4.25)), (px(24.25), px(32.25))]:
        ax.add_patch(Rectangle((a, BAND_B[0] + 0.3), b - a,
                               BAND_B[1] - BAND_B[0] - 0.6,
                               facecolor="#D9E8C8", edgecolor="#A9C48A",
                               lw=0.8, zorder=2))
    fs.label(ax, (px(24.25) + px(32.25)) / 2.0, 31.5,
             "SDA stable HIGH = bit 1", fs=7.0, color="#3F5A22",
             weight="bold", ha="center")

    fs.label(ax, X0, 43.1, "SCL-high windows \u2014 SDA may only change "
             "while SCL is LOW", fs=8.0, color=fs.ACCENT, weight="bold",
             ha="left")
    fs.txn_mark(ax, px(18.5), SCL_HI,
                "9th clk: master releases SDA \u2014 slave drives ACK",
                xytext=(95, 24), fs=7.4)

    stretch(ax)

    # ---------------- L5: failure modes.  ONE quiet grey footnote, not three
    # loud red boxes: the title's subject is the byte on the wire, and three
    # saturated callouts across the top were the first thing the eye landed on.
    fs.eqbox(ax, 3.8, NOTE_Y, 24.0, NOTE_H,
             "addr byte = 1010 000 | 0\n"
             "= (0x50 << 1) | R/W\n"
             "data byte = 0011 1100 = 0x3C\n"
             "1 SCL period = 4 states x clk_cnt\n"
             "(prescale counter)   \u00b7   ACK = acknowledge",
             fs=6.8)
    fs.note(ax, 29.4, NOTE_Y, 68.0, NOTE_H,
            "FAILURE MODES \u2014 none of them is reported by any APB or I2C bus monitor\n"
            "WRONG MODE   read a byte where the register pointer was expected: no NACK and no\n"
            "APB error, so the I2C block decodes a different register and the CPU reads the wrong data\n"
            "MISSING STOP   a byte with no START\u2192STOP framing releases SDA mid-byte; every other\n"
            "master then waits forever for a STOP: bus hung\n"
            "NACK   the slave holds SDA HIGH on the 9th clock: wrong address, or device unpowered",
            fs=6.8, kind="note")

    fs.footer(fig, "START and STOP are the only SDA edges that happen while "
                   "SCL is high \u2014 and every 9 data bits must be followed "
                   "by an ACK clock, or the slave never confirms the byte.")

    fs.pad_limits(ax, 0.06)
    fs.qa_report(fig)
    fs.save(fig, "fig12_i2c_timing_waveform.png")


def cells(ax, c, vals, col):
    """shaded payload cells, colour matched to the phase bar"""
    fs.bus_cells(ax, X0 + c * U, vals, U, CELL_Y, CELL_H, fill=col,
                 ec=EC[col], color=TC[col])


# ---- clock stretching: IMPLEMENTED (bit_ctrl.sv slave_wait / scl_sync).
# Own compressed time base, deliberately separated from the byte above.
MX0, MU = 22.0, 3.4
ST_LO2, ST_HI2 = 21.1, 25.1
STRETCH = [(0.0, 0), (3.0, 0), (3.0, 1), (5.0, 1), (5.0, 0), (6.0, 0)]


def flow(ax, x, y, items, gap=2.0, f=6.6):
    """Left-align labels in a row using MEASURED widths, never guessed."""
    for s, col, wt in items:
        fs.label(ax, x, y, s, fs=f, color=col, ha="left", weight=wt)
        x += fs.text_w(ax, s, fs=f, weight=wt) + gap
    return x


def wrap(ax, s, max_w, f=7.0, weight="normal"):
    """Greedy wrap on MEASURED text width -- fs.note() does not wrap."""
    lines, cur = [], ""
    for w in s.split():
        t = (cur + " " + w).strip()
        if not cur or fs.text_w(ax, t, fs=f, weight=weight) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def stretch(ax):
    # highlight band only (no border): the strip's own trace runs through it
    ax.add_patch(Rectangle((MX0 - 0.9, 20.1), 6 * MU + 1.8, 6.2,
                           facecolor="#FBE4E4", edgecolor="none", zorder=1))
    # what the master asks for (scl_oen released)
    ax.add_line(Line2D([MX0, MX0 + 3 * MU], [ST_HI2, ST_HI2], color=fs.MID,
                       lw=1.8, ls=(0, (3.2, 2.2)), zorder=5))
    ax.add_line(Line2D([MX0, MX0], [ST_LO2, ST_HI2], color=fs.MID, lw=1.8,
                       ls=(0, (3.2, 2.2)), zorder=5))
    # what the pin actually does
    xs = [MX0 + p * MU for p, _ in STRETCH]
    ys = [(ST_HI2 if v else ST_LO2) for _, v in STRETCH]
    ax.add_line(Line2D(xs, ys, color=fs.RED, lw=2.2, drawstyle="steps-post",
                       zorder=6, solid_capstyle="round"))
    fs.label(ax, MX0 + 1.5 * MU - 0.3, 23.5, "slave holds\nSCL low", fs=6.2,
             color="#7F1010", weight="bold")
    # "oen" is output-enable: say so the first time a newcomer meets it.
    fs.label(ax, 45.0, 24.6,
             "master released SCL  (scl_oen = 1 = SCL output enable)", fs=6.6,
             ha="left", color=fs.TXT)
    fs.label(ax, 45.0, 22.6,
             "slave holds it low  →  FSM stalls in slave_wait  "
             "(clock stretching IS implemented)", fs=6.6, ha="left",
             weight="bold", color=fs.TXT)
    fs.label(ax, 45.0, 20.6,
             "cost: one full bit period", fs=6.4, ha="left", color=fs.GREY)


if __name__ == "__main__":
    main()