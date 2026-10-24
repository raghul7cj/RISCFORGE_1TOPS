"""fig22 -- the APB timeout monitor on its own (apb_timeout_monitor.sv).

Split out of d_monitors.py (fig05), panel 2.  The parent stays frozen.
Deliberately much smaller than fig21: this monitor really is simpler.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

# ------------------------------------------------------------------ real RTL
TC_APB = 16                       # TimeoutCycles
CNT_APB = 4                       # CntWidth = $clog2(16)

fig, ax = fs.slide(
    "The APB monitor bounds a single access at TimeoutCycles = 16 and then "
    "fails the slot open with PREADY = 1, PSLVERR = 1",
    "apb_timeout_monitor.sv: one 4-bit counter, one sticky flag, no state "
    "machine \u2014 the whole design is six boxes, and that simplicity is "
    "the point",
)
XW, YH = fs.canvas(ax)

COL = [(2.5, 36.0), (44.5, 36.0), (86.5, 36.0)]      # three data columns
LD = [c[0] + 2.5 for c in COL]                      # left-edge drop points
RX = [c[0] + c[1] - 2.0 for c in COL]                # right-edge drop points
RH = 5.4                                             # every logic row height
FY, FH = 8.2, 5.4                                    # the two flag panels


def B(col, y, h, text, kind="ctrl", f=6.9):
    """block placed in one of the three column slots, auto-shrunk to fit."""
    f = fs.fit_fs(ax, text, COL[col][1] - 1.7, fs=f)
    return fs.block(ax, COL[col][0], y, COL[col][1], h, text, kind=kind, fs=f)


def head(y, n, txt, right=False):
    """numbered panel header with a badge, the way the improved parents do."""
    if right:
        fs.badge(ax, 121.2, y, n, r=1.05, fs=7.0)
        fs.label(ax, 117.4, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="right")
    else:
        fs.badge(ax, 3.6, y, n, r=1.05, fs=7.0)
        fs.label(ax, 6.2, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="left")


# ------------------------------------------------------------- reading order
fs.label(ax, 2.5, 57.2,
         "START HERE \u2193   read TOP to BOTTOM, LEFT to RIGHT:   "
         "1 WHERE IT SITS   \u2192   2 PROGRESS   \u2192   3 COUNTER + FLAG   "
         "\u2192   4 FIRE + ANSWER   \u2192   5 NO STATE MACHINE   \u2192   "
         "6 CONTRAST WITH fig21",
         fs=7.4, color=fs.ACCENT, weight="bold", ha="left")

# ------------------------------------------- 1  placement strip (own context)
head(54.4, 1, "WHERE IT SITS \u2014 one instance per APB slot, in-line "
              "on the response path")
SY, SH = 47.4, 5.4
NODES = [
    (16.0, 30.0, "axi_lite_\nto_apb", "bus", "the bridge"),
    (54.0, 32.0, "apb_timeout_\nmonitor", "alarm", f"{TC_APB} cyc"),
    (94.0, 26.0, "APB slave\nUART/TIMER/I2C", "periph", "one register"),
]
anchors = []
for x, w, txt, kind, sub in NODES:
    anchors.append(fs.block(ax, x, SY, w, SH, txt, kind=kind, fs=7.3, sub=sub,
                            sub_fs=6.2))
for a, b in zip(anchors, anchors[1:]):
    fs.wire(ax, a["e"], b["w"], color=fs.ACCENT, lw=1.9)
fs.label(ax, 70.0, 46.0, "\u2190 this figure: the monitor", fs=6.8,
         color=fs.RED, weight="bold")

# ------------------------------------- 2  what counts as progress (row A)
head(44.2, 2, "WHAT COUNTS AS PROGRESS \u2014 the slave's PREADY, nothing else")
fs.label(ax, 122.5, 44.2, "no address decode here", fs=6.8, color=fs.GREY,
         ha="right")
B(0, 37.0, RH, "PROGRESS = PREADY\n!waiting \u2192 cnt_q \u2264 '0\n"
               "= !PSEL & PENABLE & PREADY", "resp")
B(1, 37.0, RH, "NO ANSWER\npsel & penable & ~pready\n"
               "\u2192 cnt_q \u2264 cnt_q + 1", "write")
B(2, 37.0, RH, "NO REGION SPLIT\none threshold for every\n"
               "slot, no address decode", "addr")

# ------------------------------------- 3  the counter, the flag (row B)
head(34.8, 3, "THE COUNTER \u2014 4 bits, saturating at 15")
B(0, 27.8, RH, "cnt_q\n4 bit = $clog2(TimeoutCycles)\n"
               "saturates at 15, never wraps", "addr")
B(1, 27.8, RH, "expired\n= (cnt_q == TimeoutCycles-1)\n"
               "= (cnt_q == 15)", "ctrl")
B(2, 27.8, RH, "blocked_q\nsticky slot block\n"
               "set on every fire", "ctrl")

for i in range(3):
    fs.wire(ax, (LD[i], 37.0), (LD[i], 33.2))
for a, b in ((0, 1), (1, 2)):
    fs.wire(ax, (COL[a][0] + COL[a][1], 30.5), (COL[b][0], 30.5))

# ------------------------------------- 4  the fire condition + the answer
head(24.6, 4, "FIRE + THE ANSWER")
fire = fs.block(ax, 2.5, 18.0, 78.0, RH,
                "fire = waiting & (expired | blocked_q)\n"
                "qualified with waiting  \u2192  \u201creal PREADY wins\u201d",
                kind="alarm", fs=7.2)
err = B(2, 18.0, RH, "apb_resp_mst_o\nPREADY = 1\nPSLVERR = 1\n"
                    "prdata = 0xDEAD_BEEF", "alarm")
fs.wire(ax, fire["e"], err["w"])

# `waiting` runs from the progress detect straight down the right edge of
# column 0 into the fire box, because it is not a register like the others.
fs.wire(ax, (RX[0], 37.0), (RX[0], 23.4), color=fs.ACCENT, lw=1.6)
fs.onwire(ax, RX[0], 36.0, "waiting", color=fs.ACCENT, fs=6.6)
# both alarm terms take the red branch lane under the counter row
for i in (1, 2):
    fs.wire(ax, (RX[i], 27.8), (RX[i], 25.9), arrow=False, color=fs.RED,
            lw=1.6)
fs.wire(ax, (RX[2], 25.9), (41.5, 25.9), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (RX[1], 25.9), (41.5, 25.9), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (41.5, 25.9), (41.5, 23.4), arrow=True, color=fs.RED, lw=1.6)
fs.onwire(ax, 60.0, 25.9, "expired", color=fs.RED, fs=6.6)
fs.onwire(ax, 100.0, 25.9, "blocked_q", color=fs.RED, fs=6.6)

# fire -> the two flag panels, in its own lane under the fire box
fs.wire(ax, (41.5, 18.0), (41.5, 16.4), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (41.5, 16.4), (100.0, 16.4), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (100.0, 16.4), (100.0, FY + FH), arrow=True, color=fs.ACCENT,
        lw=1.6)

# --------------------------- 5  the "FSM": one sticky flag, no state enum
head(15.0, 5, "NO STATE MACHINE \u2014 one flag, blocked_q, does the same job")
sb0 = fs.block(ax, 2.5, FY, 57.0, FH, "blocked_q = 0   TRANSPARENT",
               kind="plain", fs=7.4, sub="the slave owns the response\n"
                                         "exit: fire = waiting & expired",
               sub_fs=6.2)
sb1 = fs.block(ax, 66.0, FY, 56.5, FH, "blocked_q = 1   SLOT BLOCKED",
               kind="alarm", fs=7.4, sub="answer later accesses at once\n"
                                         "clear: !psel & pready",
               sub_fs=6.2)
fs.wire(ax, sb0["e"], sb1["w"])
fs.wire(ax, sb1["s"], sb0["s"], via=[(94.0, 7.6), (31.0, 7.6)],
        color=fs.GREY, lw=1.5)
fs.onwire(ax, 62.0, 7.6, "the slave shows PREADY while deselected",
          color=fs.GREY, fs=6.4)

# ------------------------------- 6  threshold (this figure's share) + contrast
head(6.5, 6, "THRESHOLD + CONTRAST WITH fig21")
BY, BH = 0.4, 5.2

fs.eqbox(ax, 2.5, BY, 52.0, BH,
         "APB SLOT \u2014 bounded per ACCESS, one instance per slot\n"
         f"     timeout = TimeoutCycles = {TC_APB},  "
         f"CntWidth = $clog2({TC_APB}) = {CNT_APB} bit\n"
         f"     expired = (cnt_q == TimeoutCycles-1) = (cnt_q == "
         f"{TC_APB - 1})  \u2192  {TC_APB} idle ACCESS cycles",
         fs=6.2)

fs.note(ax, 57.5, BY, 65.0, BH,
        "CONTRAST WITH fig21, THE AXI-LITE MONITOR \u2014 the simplicity is "
        "the point:\n"
        "   no state enum (one sticky flag, not three states), no address "
        "decode (one threshold for every slot), and a 4-bit\n"
        "   counter instead of 17-bit. An APB slot is one register access "
        "with one fixed budget; an AXI-Lite transaction is a\n"
        "   multi-beat burst whose slave may still be dribbling beats out, "
        "which is why that one needs an FSM.", fs=6.4)

fs.footer(fig, "Deliberately the smallest of the three monitor figures: with "
               "one threshold, one counter and one flag there is genuinely "
               "nothing else to draw \u2014 what the two monitors share is "
               "fig23.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig22_apb_timeout_monitor.png")