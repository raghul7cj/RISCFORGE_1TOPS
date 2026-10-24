"""fig06 -- APB4 protocol timing (Setup / Access two-phase handshake)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

# ----------------------------------------------------------------- geometry
N = 11                     # cycles on the shared x grid
U = 7.0                    # one cycle = 7 canvas units
X0 = 22.0                  # left edge of cycle 0
GAP = 5.0                  # lane pitch
LOW = -1.5                 # waveform low, relative to lane centre
HIGH = 1.5

fig, ax = fs.slide(
    "APB is a two-phase handshake: PSEL/PENABLE are asserted a full cycle "
    "before any transfer, and PENABLE may only drop on PREADY",
    "APB4 (Advanced Peripheral Bus) bus cycles seen at the AXI-Lite->APB "
    "bridge (axi_lite_to_apb.sv, Setup|Access FSM) -- WRITE, READ, and a "
    "2-wait-state READ",
)
XW, _YH = fs.canvas(ax)

rows = [("psel",  "PSEL",    "held whole txn"),
        ("pen",   "PENABLE", "1 only in ACCESS"),
        ("pwr",   "PWRITE",  "1 = write"),
        ("prdy",  "PREADY",  "slave response"),
        ("paddr", "PADDR",   "bus cells"),
        ("pwdat", "PWDATA",  "bus cells"),
        ("prdat", "PRDATA",  "last ACCESS only"),
        ("pslve", "PSLVERR", "final ACCESS only")]

ax, ys, unit = fs.lanes(fig, rows, X0, X0 + N * U, unit=U, lane_gap=GAP,
                        left_pad=1.0, label_fs=8.2, sub_fs=6.6)
TOP = ys["psel"] + 2.0
fs.cycle_guides(ax, X0, N, unit, bottom=2.6, top=TOP)


def w(key, levels, color=fs.ACCENT, dashed=False):
    fs.sigwave(ax, X0, levels, unit, ys[key] + LOW, ys[key] + HIGH,
               color=color, dashed=dashed)


# cycle map:  0 idle | 1 W-setup 2 W-access | 3 idle
#             4 R-setup 5 R-access | 6 WS-setup 7,8 wait 9 done | 10 idle
w("psel", [0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0])
w("pen",  [0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0])
w("pwr",  [0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0])
w("prdy", [0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0], color=fs.MID, dashed=True)

# ------------------------------------------------------- payload bus cells
SETUP = dict(fill=fs.S_ADDR, ec="#BF8F00", color="#7F6000")     # phase-bar SETUP
ACCESS = dict(fill=fs.S_RESP, ec="#548235", color="#3F6228")    # phase-bar ACCESS
IDLE = dict(fill="#EFEFEF", ec="#A6A6A6", color="#6E6E6E")
CELL_H = 2.5


def cells(key, c0, values, **kw):
    fs.bus_cells(ax, X0 + c0 * U, values, unit, ys[key], CELL_H, **kw)


# WRITE -- setup c1, access c2
for lane, val in (("paddr", "0x4000_1000"), ("pwdat", "0x0000_0028")):
    cells(lane, 1, [val], **SETUP)
cells("paddr", 2, ["0x4000_1000"], **ACCESS)
cells("pwdat", 2, ["0x0000_0028"], **ACCESS)
# READ -- setup c4, access c5
cells("paddr", 4, ["0x4000_1004"], **SETUP)
cells("paddr", 5, ["0x4000_1004"], **ACCESS)
# READ with 2 wait states -- setup c6, access c7..c9
cells("paddr", 6, ["0x4000_1004"], **SETUP)
cells("paddr", 7, ["0x4000_1004", "0x4000_1004", "0x4000_1004"], **ACCESS)
cells("prdat", 4, ["0x0000_0028"], **ACCESS)
cells("prdat", 7, ["--", "--"], **IDLE)
cells("prdat", 9, ["0x0000_0028"], **ACCESS)
# PSLVERR shares RULE 3 with PRDATA: both are "valid in the final ACCESS
# cycle", so both get the ACCESS green -- a pink SLVERR=0 cell would read as
# an error.  The red dashed line below stays as the "0 everywhere else" cue.
cells("pslve", 9, ["0"], **ACCESS)
fs.sigwave(ax, X0, [0] * N, unit, ys["pslve"] + LOW - 0.4, ys["pslve"] + LOW,
           color=fs.RED, dashed=True)

# ------------------------------------------------------- phase strip + cases
fs.phase_bar(ax, X0, N, 0.0, 2.0,
             [(0, 1, "IDLE", "#EDEDED"),
              (1, 2, "S_SETUP", fs.S_ADDR),
              (2, 3, "S_ACCESS", fs.S_RESP),
              (3, 4, "IDLE", "#EDEDED"),
              (4, 5, "S_SETUP", fs.S_ADDR),
              (5, 6, "S_ACCESS", fs.S_RESP),
              (6, 7, "S_SETUP", fs.S_ADDR),
              (7, 10, "S_ACCESS   N = 2 wait states", fs.S_RESP),
              (10, 11, "IDLE", "#EDEDED")], unit=unit)

# ha="center": x is the CENTRE of each transaction's span, not its left edge.
fs.chip(ax, X0 + 2 * U, 44.5, "WRITE \u00b7 PWRITE = 1", ha="center")
fs.chip(ax, X0 + 5 * U, 44.5, "READ \u00b7 PWRITE = 0", ha="center")
fs.chip(ax, X0 + 8 * U, 44.5, "READ + 2 WAIT STATES",
        fc=fs.S_ALARM, ec=fs.RED, tc="#7F1010", ha="center")

# ------------------------------------------- right-hand commentary gutter
GX = 100.5                       # left edge of the free right-hand column
ax.add_patch(fs.Rectangle((GX - 1.6, 0.0), XW - GX + 3.0, 45.4,
                          facecolor="#FFFFFF", edgecolor="none", zorder=1.5))

fs.eqbox(ax, GX, 1.0, 23.0, 7.6,
         "bus cycles = 1 SETUP + 1 + N ACCESS\n"
         "PENABLE high (N + 1) cycles\n"
         "N \u2264 16 = TimeoutCycles", fs=7.2)

# newcomer glossary: unboxed, small, grey -- it must recede behind the waveform
fs.label(ax, GX, 22.8, "SIGNAL NAMES", fs=6.6, color=fs.GREY, weight="bold",
         ha="left")
fs.label(ax, GX, 21.0,
         "PSEL select  \u00b7  PENABLE enable\n"
         "PREADY slave ready  \u00b7  PWRITE 1 = write\n"
         "PADDR address  \u00b7  PWDATA write data\n"
         "PRDATA read data  \u00b7  PSLVERR slave error",
         fs=6.5, color=fs.GREY, ha="left", va="top")

fs.label(ax, GX, 14.6,
         "timer.sv ties PREADY = 1, so N = 0 on Timer0.\n"
         "A slow slave can hold PREADY low;\n"
         "apb_timeout_monitor bounds the ACCESS phase\n"
         "(TimeoutCycles = 16).", fs=6.5, color=fs.GREY, ha="left", va="top")

fs.txn_mark(ax, X0 + 9.5 * U, ys["prdy"] + HIGH,
            "PENABLE & PREADY\n= last access cycle",
            xytext=(12 * 7.2, 0), ha="left", va="center", arrow=True)

# key for the encodings, in the free upper part of the right-hand column
fs.label(ax, GX, 44.0, "KEY", fs=6.8, color=fs.GREY, weight="bold", ha="left")
fs.legend_row(ax, GX, 40.6, [
    ("box", "addr", "cell = value valid in SETUP"),
    ("box", "resp", "cell = value valid in ACCESS"),
    ("dash", fs.MID, "PREADY \u2014 driven by the slave"),
    ("dash", fs.RED, "PSLVERR = 0 reference"),
], vertical=True, gap=2.2, fs=7.0)

# ------------------------------------------------- three protocol rules
# Explicit reading order (the figure has two panels, so it gets one) plus a
# number on each rule that is repeated on the waveform itself.
fs.label(ax, X0 - 1.0, 57.4,
         "HOW TO READ   ① the three rules   →   ② bus cycle = "
         "1 SETUP + 1 + N ACCESS (phase strip, bottom)   →   "
         "③ the margin number marks the signal each rule governs",
         fs=7.0, color=fs.ACCENT, weight="bold", ha="left")

RULES = [
    (1, 3.0, "RULE 1 — PENABLE may not drop\nbefore PREADY",
     "The slave latches only on PSEL & PENABLE & PREADY.\n"
     "Falling PENABLE early splits one access into two and\n"
     "the write is applied twice, or never."),
    (2, 43.0, "RULE 2 — PSEL stays asserted for the\nwhole access phase",
     "It may drop only in the cycle after PREADY, together\n"
     "with PENABLE — the single legal return to IDLE.\n"
     "Never re-select while PENABLE is high."),
    (3, 83.0, "RULE 3 — PRDATA and PSLVERR are valid\nonly in the final access cycle",
     "That is the one cycle where PREADY is sampled high.\n"
     "Sampling them earlier returns the previous slave's\n"
     "response."),
]
CARD_Y, CARD_W, CARD_H = 46.4, 38.0, 10.2
for n, cx, lead, body in RULES:
    # white card + hairline border: commentary, not a headline
    fs.note(ax, cx, CARD_Y, CARD_W, CARD_H, "", kind="plain")
    fs.badge(ax, cx + 2.0, CARD_Y + CARD_H - 2.0, n, r=1.2, fc=fs.ACCENT,
             tc="white", fs=7.6)
    fs.label(ax, cx + 4.2, CARD_Y + CARD_H - 2.2, lead, fs=7.5,
             color=fs.ACCENT, weight="bold", ha="left")
    fs.label(ax, cx + 1.4, CARD_Y + CARD_H - 4.4, body, fs=6.8,
             color=fs.GREY, ha="left", va="top")

# ------------------------------------------------------- rule -> signal map
# Each rule number sits beside the signal it governs, so the reader can go
# rule -> signal -> waveform without hunting.
for lane, n in (("pen", 1), ("psel", 2), ("prdat", 3)):
    fs.badge(ax, X0 - 1.7, ys[lane], n, r=1.05, fc=fs.ACCENT, tc="white",
             fs=7.0)

fs.footer(fig, "Failure mode: dropping PENABLE before PREADY, or re-asserting "
               "PSEL while PENABLE is high, lets the slave latch a phantom "
               "transfer -- two AXI beats, one register written.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig06_apb_protocol_timing.png")