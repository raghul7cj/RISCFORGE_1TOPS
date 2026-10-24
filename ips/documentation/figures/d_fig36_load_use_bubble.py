#!/usr/bin/env python3
"""fig36 -- the load-use bubble strip of fig17 (FROZEN), extracted and given the
whole canvas as the evidence figure for the parent.

RTL read (only the two files the parent script cited):
  riscv_core/rtl/hazard_unit.v
    :127/:133  ForwardAE/ForwardBE  -- 2'b10 MEM, 2'b01 WB, 2'b00 none
    :148  lwstall = (ResultSrcE == 2'b01) && ((Rs1_D == RdE) || (Rs2_D == RdE))
          && (RdE != 5'd0)
    :170/:171  StallF / StallD = lwstall | csr_stall | csr_gpr_stall
                            | stallMUL | mem_stall_i
    :189  FlushE = lwstall | (csr_gpr_stall & ~mem_stall_i) | PCSrcE | csr_stall
          | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1] | stallMUL
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
import _figstyle as fs
from _figstyle import ACCENT, MID, GREEN, RED, ORANGE, GREY, TXT, S_REQ, \
    S_ADDR, S_ALARM
from matplotlib.patches import Rectangle

TITLE = ("A load-use pair is the one case no bypass can fix: the loaded value is "
         "not in the EX/MEM latch until the cycle after it is needed, so "
         "lwstall must cost exactly one cycle")
SUB = ("START HERE at (1), the control case on the left \u2014 zero bubbles.  Then "
       "(2) the load\u2192ALU case on the right: one bubble, sitting in EX.  "
       "(3) the RTL expression that produces it  (4) why the bypass encodings "
       "cannot help  (5) the other stalls that can stretch it  (6) the CPI cost")

fig, ax = fs.slide(TITLE, SUB)
CX, CY = fs.canvas(ax)
print(f"canvas {CX:.1f} x {CY:.1f} units")


def wrap(ax, s, max_w, f=6.0, weight="normal"):
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

# ============================================================ ENTRY POINT
_lbl = "START HERE \u2192"
fs.chip(ax, 3.0 + fs.text_w(ax, _lbl, 7.0, "bold"), 57.4, _lbl,
        fc=ACCENT, ec=ACCENT, tc="white", fs=7.0)
_tb = ("both tables below share one time base: one column = one clock cycle, "
       "rows are pipeline stages")
_tbw = fs.text_w(ax, _tb, 6.4, "bold") + 1.4
fs.chip(ax, CX - 0.8 - _tbw, 57.4, _tb,
        fc="#FFF2CC", ec="#BF8F00", tc="#7F6000", fs=6.4)

# ==================================================== BAND 1: CYCLE TABLES
Y_HDR, Y_CYC = 53.9, 50.8
Y_ROWS = {"F": 48.2, "D": 45.4, "E": 42.6, "M": 40.0}
CH = 2.2
CELL = {"add": (S_REQ, MID, TXT), "lw": (S_ADDR, "#BF8F00", "#7F6000"),
        "bubble": (S_ALARM, RED, "#7F1010")}
MUTE = {"add": ("#F1F3F6", "#C6CBD3", GREY),
        "lw": ("#F4F1E8", "#CFC8B4", "#7F7460"),
        "bubble": ("#F7EFEF", "#D8B4B4", "#8B7070")}

# --- Case A: the control, deliberately unframed and greyed ---------------
XA0, UA = 9.5, 5.30
fs.badge(ax, 5.2, 50.8, 1, fc=GREY)
fs.chip(ax, XA0 + 2.5 * UA, Y_HDR,
        "case A \u00b7 add x1, x2, x3 / add x4, x3, x5 \u00b7 0 bubbles\n"
        "ALU \u2192 ALU \u2014 the bypass covers it, the control case",
        fc="#FFFFFF", ec="#C6CBD3", tc=GREY, fs=6.4, ha="center")
for i in range(5):
    fs.label(ax, XA0 + (i + 0.5) * UA, Y_CYC, str(i + 1), fs=6.2, color=GREY)
ROWS_A = {"F": ["add", "add", "", "", ""],
          "D": ["", "add", "add", "", ""],
          "E": ["", "", "add", "add", ""],
          "M": ["", "", "", "add", ""]}
for r in ("F", "D", "E", "M"):
    fs.label(ax, XA0 - 1.1, Y_ROWS[r], r, fs=7.0, color=GREY, weight="bold",
             ha="right")
    for i, v in enumerate(ROWS_A[r]):
        if v:
            fc, ec, tc = MUTE[v]
            fs.bus_cells(ax, XA0 + i * UA, [v], UA, Y_ROWS[r], CH, fill=fc,
                         ec=ec, color=tc, fs=7.0)

# --- Case B: the headline, framed --------------------------------------
BX0, UB = 50.0, 7.90
fs.block(ax, 44.6, 37.2, 47.2, 19.0, "", kind="plain", lw=2.0,
         box_alpha="#FDF0F0", rounding=0.6)
fs.badge(ax, 40.8, 50.8, 2, fc=RED)
fs.chip(ax, BX0 + 2.5 * UB, Y_HDR,
        "case B \u00b7 lw x1, 0(x2) / add x4, x1, x5 \u00b7 1 bubble\n"
        "load \u2192 ALU \u2014 no bypass can, THIS is the headline",
        fc="#FFFFFF", ec=RED, tc=RED, fs=7.2, ha="center")
for i in range(5):
    fs.label(ax, BX0 + (i + 0.5) * UB, Y_CYC, str(i + 1), fs=7.0, color=TXT,
             weight="bold")
ROWS_B = {"F": ["lw", "add", "add", "add", ""],
          "D": ["", "lw", "lw", "lw", "add"],
          "E": ["", "", "lw", "bubble", "add"],
          "M": ["", "", "", "lw", ""]}
for r in ("F", "D", "E", "M"):
    fs.label(ax, BX0 - 1.1, Y_ROWS[r], r, fs=7.8, color=ACCENT, weight="bold",
             ha="right")
    for i, v in enumerate(ROWS_B[r]):
        if v:
            fc, ec, tc = CELL[v]
            fs.bus_cells(ax, BX0 + i * UB, [v], UB, Y_ROWS[r], CH, fill=fc,
                         ec=ec, color=tc, fs=8.4)

# --- captions under each table (kept outside the boxes) -----------------
fs.onwire(ax, XA0 + 2.5 * UA, 32.4,
          "no bubble \u2014 the 2nd add finds x3 already forwarded into EX",
          fs=6.4, color="#5A6472", fc="#F4F6F9", ec="#C6CBD3")
fs.onwire(ax, BX0 + 2.5 * UB, 32.4,
          "one bubble \u2014 it sits in EX, and the add enters EX one cycle late",
          fs=6.8, color="#8B1A1A", fc="#FDF0F0", ec=RED)

# ==================================================== right column: legend
RX, RW = 94.6, CX - 94.6 - 0.8
fs.chip(ax, RX, 53.4, "what the cells mean", fc="#FFFFFF", ec=ACCENT, tc=ACCENT,
        fs=7.0)
LEG = [("box", S_REQ, "add \u2014 an ALU instruction"),
       ("box", S_ADDR, "lw \u2014 the load, in flight"),
       ("box", S_ALARM, "bubble \u2014 FlushE killed ID/EX"),
       ("box", "#FFFFFF", "empty \u2014 that stage is idle")]
fs.legend_row(ax, RX, 49.4, LEG, fs=6.4, vertical=True, gap=0.9, step=3.0)
fs.note(ax, RX, 31.0, RW, 10.4,
        wrap(ax, "the two tables are the same pair of dependent "
                 "instructions. Swapping the first instruction from an add to "
                 "a lw moves one cell across and costs one cycle that no "
                 "bypass can recover.", (RW - 2.6) * 0.90, 6.0), fs=6.0)

# ============================== (3) THE RTL EXPRESSION, TERM BY TERM
fs.badge(ax, 5.2, 30.6, 3, fc=ACCENT)
fs.label(ax, 8.4, 30.6, "THREE TERMS ALL MUST BE TRUE \u2014 and together they are "
         "exactly one bubble in EX", fs=7.6, color=ACCENT, weight="bold", ha="left")
fs.eqbox(ax, 3.0, 25.8, 88.0, 3.9,
         "lwstall = (ResultSrcE == 2'b01) && ((Rs1_D == RdE) || (Rs2_D == RdE)) "
         "&& (RdE != 5'd0)\n"
         "\u2192  StallF  \u00b7  StallD  \u00b7  FlushE        "
         "(hazard_unit.v:148 / :170 / :189)", fs=7.0, fc="#FFF2CC", ec="#BF8F00",
         color="#7F6000")

TERMS = [
    ("(1)  ResultSrcE == 2'b01", "the instruction now in EX is a load \u2014 its "
     "result is not in the EX/MEM latch yet"),
    ("(2)  Rs1_D == RdE  ||  Rs2_D == RdE", "the instruction behind it, in D, "
     "reads the very register the load will write"),
    ("(3)  RdE != 5'd0", "and that register is not x0, which is hardwired to "
     "zero and can never be a hazard"),
]
TW, TG = 28.0, 2.0
for i, (term, body) in enumerate(TERMS):
    tx = 3.0 + i * (TW + TG)
    fs.block(ax, tx, 17.4, TW, 7.6, "", kind="note", box_alpha="#F5F8FC",
             lw=1.0, rounding=0.3)
    fs.label(ax, tx + 1.1, 24.0, term, fs=6.8, color="#1F4E79", weight="bold",
             ha="left", va="center")
    fs.label(ax, tx + 1.1, 20.6, wrap(ax, body, (TW - 2.4) * 0.90, 6.0),
             fs=6.0, color=TXT, ha="left", va="center", linespacing=1.4)

# ================== (4) THE FORWARDING ENCODINGS, RIGHT COLUMN
fs.block(ax, RX, 3.0, RW, 14.4, "", kind="plain", lw=1.2,
         box_alpha="#FFFFFF", rounding=0.4)
fs.badge(ax, RX + 1.9, 15.4, 4, fc=ACCENT)
fs.label(ax, RX + 3.9, 15.4, "WHY NO ENCODING SAVES THE LOAD", fs=7.0,
         color=ACCENT, weight="bold", ha="left")
FWD = [("2'b10", "from EX/MEM", "RegWriteM & RD_M == Rs1_E", GREEN),
       ("2'b01", "from MEM/WB", "RegWriteW & RD_W == Rs1_E", ORANGE),
       ("2'b00", "no bypass", "read the register file", MID)]
for i, (code, src, cond, col) in enumerate(FWD):
    fy = 12.6 - i * 2.75
    fs.chip(ax, RX + 0.9, fy, code, fc="#FFFFFF", ec=col, tc=col, fs=6.8)
    fs.label(ax, RX + 5.3, fy, src, fs=6.4, color=TXT, weight="bold", ha="left")
    fs.label(ax, RX + 0.9, fy - 1.35, cond, fs=5.8, color=GREY, ha="left")
fs.label(ax, RX + 0.9, 4.3, wrap(ax,
         "RTL priority: MEM, then WB, then none.  2'b00 is fine for case A "
         "(the producer's ALU result is computed in the very cycle the "
         "consumer needs it) and one cycle too late for a load.", (RW - 2.0) * 0.90,
         5.8), fs=5.8, color=TXT, ha="left", va="center", linespacing=1.4)

fs.pad_limits(ax, 0.06)
print(fs.qa_report(fig))
fs.save(fig, "fig36_rv32_load_use_bubble.png")