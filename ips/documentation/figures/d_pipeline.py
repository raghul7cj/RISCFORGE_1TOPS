#!/usr/bin/env python3
"""fig17 - RISCFORGE RV32IM_Zicsr five-stage pipeline: forwarding network,
hazard unit, and the one-cycle load-use bubble.

RTL source of truth (only these two files were read):
  riscv_core/rtl/top.v         - stage instances + real boundary port names
  riscv_core/rtl/hazard_unit.v - ForwardAE/BE encodings, lwstall, Stall*/Flush*
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import _figstyle as fs
from _figstyle import (ACCENT, MID, GREEN, RED, ORANGE, GREY, TXT, S_REQ,
                       S_ADDR, S_ALARM)
from matplotlib.patches import Rectangle

TITLE = ("Forwarding covers ALU-to-ALU with zero cost \u2014 the hazard unit only "
         "has to earn its keep on the one case a bypass cannot fix")
SUBTITLE = ("read left to right: the five stages and the four latches between them, "
            "then the two bypass paths that feed EX \u2014 the load-use bubble is the "
            "one case they cannot cover")

# ============================================================ COLUMN BUDGET
HAZ_X0, HAZ_X1 = 1.5, 20.5          # hazard_unit column (w 19.0, clears 17.64 text)
LANE_W = {"F": 14.0, "D": 16.0, "E": 18.0, "M": 13.5, "W": 13.5}
LANE_X = {"F": (22.5, 36.5), "D": (39.5, 55.5), "E": (58.5, 76.5),
          "M": (79.5, 93.0), "W": (96.0, 109.5)}
LATCH_X = {"F/D": 38.0, "D/E": 57.0, "E/M": 78.0, "M/W": 94.5}
LEG_X0, LEG_X1 = 111.0, 122.5        # right legend column

# vertical bands
Y_FLUSH = 55.4        # branch redirect / flush, over the top perimeter
Y_BOUND = 49.6        # boundary latch chips
Y_NAME = 52.0         # boundary register names (2 lines)
LY1, LY0 = 47.0, 29.0  # lane box
Y_BLK = 43.6          # top of the main datapath block row (h 5.0 -> 39.6..44.6)
Y_CHIP = 45.9         # stage title chip inside each lane
Y_EX2EX, Y_MEM2EX, Y_WB2EX = 26.8, 24.0, 21.2
Y_STALL = 19.0        # stall path under the forwarding band
Y_HDR = 16.9          # cycle-strip header chips
Y_CYC, Y_ROWS = 15.4, {"F": 13.5, "D": 10.6, "E": 7.7, "M": 4.8}
Y_COND = 2.4

fig, ax = fs.slide(TITLE, SUBTITLE)
CX, CY = fs.canvas(ax)

print("=" * 78)
print(f"CANVAS  {CX:.1f} x {CY:.1f} data units   (1 unit = 0.1 in = 11 px)")
print("COLUMN BUDGET (x)")
print(f"   hazard_unit   {HAZ_X0:6.1f} -> {HAZ_X1:6.1f}   w = {HAZ_X1 - HAZ_X0:5.1f}")
for k in ("F", "D", "E", "M", "W"):
    x0, x1 = LANE_X[k]
    print(f"   lane {k}        {x0:6.1f} -> {x1:6.1f}   w = {x1 - x0:5.1f}   c = {(x0 + x1) / 2:5.1f}")
print("   latch centres  " + "  ".join(f"{k}:{v:.1f}" for k, v in LATCH_X.items()))
print(f"   legend column  {LEG_X0:6.1f} -> {LEG_X1:6.1f}   right margin = "
      f"{CX - LANE_X['W'][1]:.1f}")
print("VERTICAL BANDS (y)")
print(f"   flush wire {Y_FLUSH} | latch chip {Y_BOUND} | reg names {Y_NAME}")
print(f"   lane box {LY0}..{LY1} | stage chip {Y_CHIP} | block row {Y_BLK - 5.0}..{Y_BLK}")
print(f"   EX2EX {Y_EX2EX} | MEM2EX {Y_MEM2EX} | WB2EX {Y_WB2EX} | stall {Y_STALL}")
print(f"   cycle strip: header {Y_HDR}, cycle {Y_CYC}, rows {Y_ROWS}, cond {Y_COND}")
print("=" * 78)

# ============================================================ L2: SWIMLANES
STAGE = {"F": "F \u2014 FETCH", "D": "D \u2014 DECODE", "E": "E \u2014 EXECUTE",
         "M": "M \u2014 MEMORY", "W": "W \u2014 WRITEBACK"}
LANE_FC = {"F": "#FDF3E0", "D": "#EAF2FA", "E": "#FDF3E0", "M": "#EAF7EC",
           "W": "#F3EAF8"}

for k in ("F", "D", "E", "M", "W"):
    x0, x1 = LANE_X[k]
    ax.add_patch(Rectangle((x0, LY0), x1 - x0, LY1 - LY0, facecolor=LANE_FC[k],
                           edgecolor=MID, linewidth=1.0, linestyle=(0, (5, 3)),
                           alpha=0.55, zorder=1))
    fs.chip(ax, (x0 + x1) / 2.0, Y_CHIP, STAGE[k], fc="#FFFFFF", ec=ACCENT,
            tc=ACCENT, fs=8.0, ha="center")

# --- boundary latches: RTL names them by destination-stage suffix ----------
LATCH = {
    "F/D": ("F/D latch", "Fetch _D outputs", "InstrD \u00b7 PCD \u00b7 PCPlus4D"),
    "D/E": ("D/E latch", "Decode _E outputs",
            "RD1_E \u00b7 RD2_E \u00b7 Imm_Ext_E \u00b7 RD_E"),
    "E/M": ("E/M latch", "Execute _M outputs",
            "ALU_ResultM \u00b7 WriteDataM \u00b7 RD_M"),
    "M/W": ("M/W latch", "Memory _W outputs",
            "ResultW \u00b7 RDW \u00b7 RegWriteW"),
}
for nm, cx in LATCH_X.items():
    ax.add_patch(Rectangle((cx - 0.6, LY0 + 1.0), 1.2, LY1 - LY0 - 2.0,
                           facecolor="#FFF2CC", edgecolor="#BF8F00",
                           linewidth=1.0, linestyle=(0, (3, 2)), zorder=2))
    t1, t2, t3 = LATCH[nm]
    fs.chip(ax, cx, Y_BOUND, t1, fc="#FFF2CC", ec="#BF8F00", tc="#7F6000",
            fs=7.0, ha="center")
    fs.label(ax, cx, Y_NAME + 0.6, t2, fs=5.8, color="#7F6000", weight="bold")
    fs.label(ax, cx, Y_NAME - 0.6, t3, fs=5.8, color=TXT)

# ============================================================ L3: DATAPATH
def blk(x0, w, y, h, name, sub, kind="cpu"):
    return fs.block(ax, x0, y, w, h, name, kind=kind, fs=9.0, sub=sub,
                    sub_fs=7.4)


blk(23.6, 11.8, Y_BLK - 5.0, 5.0, "fetch_cycle", "PC + ISRAM read", "bus")
blk(40.6, 13.8, Y_BLK - 5.0, 5.0, "decode_cycle", "decoder + regfile x0\u2013x31",
    "bus")
blk(59.4, 16.2, Y_BLK - 5.0, 5.0, "execute_cycle", "imm gen \u00b7 ALU \u00b7 rv32m",
    "cpu")
blk(80.6, 11.8, Y_BLK - 5.0, 5.0, "memory_cycle", "LSU DMEM \u00b7 RD_M", "mem")
blk(97.1, 11.8, Y_BLK - 5.0, 5.0, "writeback_cycle", "ResultW mux \u00b7 RD_W",
    "mux")

blk(40.2, 14.6, 32.4, 4.8, "csr_regfile",
    "mstatus mie mtvec mepc\nmcause mtval mscratch", "ctrl")
fs.chip(ax, 29.5, 34.5, "PC ← PCTargetE", fc="#FFFFFF", ec=ORANGE,
        tc=ORANGE, fs=6.8, ha="center")

# ============================================ L4: FORWARDING + HAZARD UNIT
fs.chip(ax, (HAZ_X0 + HAZ_X1) / 2.0, 48.4, "hazard_unit", fc="#FFF2CC",
        ec="#BF8F00", tc="#7F6000", fs=8.0, ha="center")
fs.block(ax, HAZ_X0, 39.4, HAZ_X1 - HAZ_X0, 7.6,
         "FORWARDING   (priority MEM > WB)\n"
         "MEM > WB > none  (RTL priority)\n"
         " 2'b10  RegWriteM & RD_M==Rs1_E\n"
         " 2'b01  RegWriteW & RD_W==Rs1_E\n"
         " 2'b00  no bypass, regfile read",
         kind="ctrl", fs=5.8)
fs.block(ax, HAZ_X0, 31.4, HAZ_X1 - HAZ_X0, 6.6,
         "LOAD-USE   lwstall\n"
         "ResultSrcE == 2'b01  (load in EX)\n"
         "& (Rs1_D == RdE | Rs2_D == RdE)\n"
         "& RdE!=0  → StallF/D + FlushE",
         kind="alarm", fs=5.8)

MUX = (60.0, 31.0, 14.0, 5.0)      # operand / forward mux box
blk(MUX[0], MUX[2], MUX[1], MUX[3], "forward mux", "ForwardA_E / ForwardB_E",
    "addr")

X_EX_DROP, X_MEM_DROP, X_WB_DROP = 66.0, 66.8, 65.0
fs.wire(ax, (66.0, 38.6), (X_EX_DROP, MUX[1] + MUX[3]), color=ACCENT, lw=2.0,
        label="EX\u2192EX same cycle", label_at=(66.0, 37.3), label_fs=6.2)
fs.wire(ax, (89.0, 38.6), (X_MEM_DROP, MUX[1]),
        via=[(89.0, Y_MEM2EX), (X_MEM_DROP, Y_MEM2EX)], color=GREEN, lw=2.0,
        label="2'b10 MEM\u2192EX \u00b7 RegWriteM & RD_M",
        label_at=(76.5, Y_MEM2EX), label_fs=6.2)
fs.wire(ax, (107.0, 38.6), (X_WB_DROP, MUX[1]),
        via=[(107.0, Y_WB2EX), (X_WB_DROP, Y_WB2EX)], color=ORANGE, lw=2.0,
        label="2'b01 WB\u2192EX \u00b7 RegWriteW & RD_W == Rs1_E",
        label_at=(86.0, Y_WB2EX), label_fs=6.2)

# ============================== L5a: STALL PATH + BRANCH / FLUSH PERIMETER
fs.wire(ax, (11.0, 31.4), (57.0, 30.0), via=[(11.0, Y_STALL), (57.0, Y_STALL)],
        color=RED, lw=1.9, dashed=True, back=True, ls_dash=(4.5, 2.6),
        label="FlushE → 1 bubble in ID/EX", label_at=(24.0, Y_STALL),
        label_fs=6.2)
fs.wire(ax, (38.0, Y_STALL), (38.0, 30.0), color=RED, lw=1.9, dashed=True,
        ls_dash=(4.5, 2.6))
fs.onwire(ax, 38.0, 24.0, "StallF · StallD  freeze IF/ID", fs=6.2, color=RED,
          ec=RED)

fs.wire(ax, (67.5, 47.0), (24.0, 47.0),
        via=[(67.5, Y_FLUSH), (24.0, Y_FLUSH)], color=RED, lw=1.9, dashed=True,
        back=True, ls_dash=(4.5, 2.6),
        label="FlushD · FlushE — branch resolves in EX (PCSrcE) → PC ← PCTargetE",
        label_at=(46.5, Y_FLUSH), label_fs=6.2)

# ============================================ L5b: TWO-CASE CYCLE STRIP
UNIT, CH = 4.4, 2.2
CELL = {"add": (S_REQ, MID, TXT), "lw": (S_ADDR, "#BF8F00", "#7F6000"),
        "bubble": (S_ALARM, RED, "#7F1010")}
CASES = [(7.0, "case A \u00b7 add x1 / add x4 \u00b7 0 bubbles\nALU \u2192 ALU, the bypass covers it",
          "#F2F5FA", GREY, {"F": ["add", "add", "", "", ""],
                           "D": ["", "add", "add", "", ""],
                           "E": ["", "", "add", "add", ""],
                           "M": ["", "", "", "add", ""]}),
         (32.0, "case B \u00b7 lw x1 / add x4 \u00b7 1 bubble\nload \u2192 ALU, no bypass can \u2014 THE HEADLINE",
          S_ALARM, RED, {"F": ["lw", "add", "add", "add", ""],
                         "D": ["", "lw", "lw", "lw", "add"],
                         "E": ["", "", "lw", "bubble", "add"],
                         "M": ["", "", "", "lw", ""]})]

for r in ("F", "D", "E", "M"):
    fs.label(ax, 6.0, Y_ROWS[r], r, fs=7.4, color=ACCENT, weight="bold",
             ha="right")

for x0, head, hbg, hec, rows in CASES:
    ctr = x0 + 2.5 * UNIT
    fs.chip(ax, ctr, Y_HDR, head, fc="#FFFFFF", ec=hec, tc=ACCENT, fs=6.4,
            ha="center")
    fs.block(ax, x0 - 1.2, Y_ROWS["M"] - 1.9, 5 * UNIT + 2.4,
             (Y_CYC + 1.2) - (Y_ROWS["M"] - 1.9), "", kind="plain",
             lw=1.0, box_alpha=hbg, rounding=0.3)
    for i in range(5):
        fs.label(ax, x0 + (i + 0.5) * UNIT, Y_CYC, str(i + 1), fs=6.4,
                 color=GREY)
    for r in ("F", "D", "E", "M"):
        y = Y_ROWS[r]
        for i, v in enumerate(rows[r]):
            if v:
                fc, ec, tc = CELL[v]
                fs.bus_cells(ax, x0 + i * UNIT, [v], UNIT, y, CH, fill=fc, ec=ec,
                             color=tc, fs=7.8)

fs.label(ax, 18.0, Y_COND, "RegWriteM & RD_M==Rs1_E  →  2'b10", fs=6.2,
         color=GREEN, weight="bold")
fs.label(ax, 43.0, Y_COND, "ResultSrcE==2'b01 & Rs1_D==RdE", fs=6.2,
         color=RED, weight="bold")

# ------------------------------------------------------- right column key
fs.chip(ax, LEG_X0, 46.6, "wire key", fc="#FFFFFF", ec=ACCENT, tc=ACCENT, fs=7.0)
fs.legend_row(ax, LEG_X0, 44.0,
              [("line", ACCENT, "EX→EX  same cycle"),
               ("line", GREEN, "2'b10  MEM→EX"),
               ("line", ORANGE, "2'b01  WB→EX"),
               ("dash", RED, "Flush / stall")], vertical=True, gap=1.1)
fs.note(ax, LEG_X0, 28.2, 11.7, 7.4,
        "no stall, no bubble:\nthe bypass lands in EX\nbefore the consumer\nreads the "
        "regfile.", fs=6.0)

# ============================================================ L6: EQ + FOOTER
# the two formulas are content (keep them as an eqbox); the paragraph that
# explains them is a note and must recede, so it goes in a grey fs.note rather
# than a second saturated yellow panel.
fs.eqbox(ax, 60.0, 12.0, 62.0, 5.4,
         "load-use penalty  =  1 cycle per load\u2192consumer pair\n"
         "CPI  =  1 + (load-use stalls) / dynamic instructions", fs=8.2)
fs.note(ax, 60.0, 3.0, 62.0, 8.2,
        "GOLDEN RULE \u2014 forward first; stall only when the source value "
        "does not exist yet.\nA load's result is not in the EX/MEM latch "
        "until the cycle after it leaves MEM, so\nno bypass can deliver it "
        "in time: that is the whole job of lwstall \u2192 StallF, StallD, "
        "FlushE.", fs=6.6)

fs.footer(fig, "The bypass muxes are combinational and only have to pick the "
               "newer of MEM/WB; the hazard unit is the part that must be "
               "provably correct — a wrong ForwardAE corrupts data silently, "
               "a wrong lwstall only costs a cycle, but a missing one hangs "
               "the machine in a trap loop.")

fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig17_rv32_pipeline.png")