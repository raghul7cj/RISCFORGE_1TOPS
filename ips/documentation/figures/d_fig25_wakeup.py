"""fig25 -- AON timer WAKEUP path: prescaler -> 64-bit counter -> '>=' compare.

Split of fig10 (d_aon_timer.py).  The parent keeps STEP 1 (the two reset
domains); this figure owns the wakeup counter path only.

Facts copied verbatim from d_aon_timer.py / aon_timer_core.sv:
  * prescale_count_q : 12-bit, wraps at 2**12 - 1 = 4095 = 12'hFFF   @ 0x04
  * wkup_count       : 64-bit = {wkup_count_hi, wkup_count_lo}      @ 0x10/0x14
  * wkup_thold       : 64-bit                                      @ 0x08/0x0c
  * wkup_incr = lc_ok & wkup_ctrl.enable & (prescale_count_q == prescaler)
  * wkup_intr_o = wkup_incr & (wkup_count >= wkup_thold)   [>=, NOT ==]
  * -> one wkup_incr every (prescaler + 1) clk_aon_i cycles
  * wkup_cause.q set by HW, cleared by SW (WKUP_CAUSE @ 0x34) -> wkup_req_o
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# --------------------------------------------------------------- coordinates
# A 45.8 .. 50.2  STEP 1  the wakeup counter row        (axis 48.0)
# B 34.3 .. 40.4  STEP 2  the sequencer states it drives (badges 41.9)
# C 18.0 .. 30.0  STEP 3  the arithmetic, verbatim from the RTL
# D  1.6 .. 15.4  STEP 4  the wrap + compare, on the wire
A_CAP, A_T, A_B = 54.5, 52.1, 46.5
A_MID = (A_T + A_B) / 2.0                       # 49.3
B_CAP, B_BADGE, B_BOX_T, B_BOX_B = 44.6, 42.4, 40.9, 34.8
B_MID = (B_BOX_T + B_BOX_B) / 2.0               # 37.85
C_CAP, C_BOX_Y, C_BOX_H = 33.1, 18.5, 12.0
D_TOP = 15.4

FSM_X = [1.6, 19.7, 37.8, 55.9, 74.0]
FSM_W = 11.0

WX0, WU, WN = 24.0, 6.8, 11
LGAP = 3.6

TITLE = ("The wakeup path is a 12-bit prescaler, a 64-bit counter and a "
         "\u201c>=\u201d compare, so one increment happens every (prescaler+1) cycles")
SUB = ("AON = always-on.  Left to right, top to bottom:   STEP 1 the counter row "
       "\u2192   STEP 2 the sequencer states that row drives   \u2192   STEP 3 the "
       "arithmetic   \u2192   STEP 4 the wrap and the compare on the wire")

fig, ax = fs.slide(TITLE, SUB)
X, Y = fs.canvas(ax)   # slide canvas ~125.3 x 59.1 units

# ============================================================ STEP 1 : the row
fs.label(ax, 1.8, A_CAP, "STEP 1  \u2014  THE WAKEUP COUNTER ROW: EVERY BLOCK ON THIS "
          "LINE EXISTS ONLY TO DIVIDE, COUNT AND COMPARE",
          fs=fs.FS_LANE, weight="bold", ha="left", va="bottom", color=fs.ACCENT)

# entry point marker: the eye must land on the clock first
fs.dot(ax, 1.4, A_MID, r=0.55, fc=fs.ACCENT)
fs.label(ax, 8.1, A_T + 0.55, "START HERE", fs=6.6, weight="bold",
         color=fs.ACCENT, va="bottom")

WK = [(2.6, 11.0, "clk_aon_i\nsame clock", "ctrl"),
      (19.1, 17.5, "DIVIDER\nprescale_count_q[11:0]", "ctrl"),
      (42.1, 18.5, "wkup_count_q[63:0]\n{hi,lo} @ 0x10/0x14", "mux"),
      (66.1, 19.5, "COMPARE\ncount >= wkup_thold", "addr"),
      (91.1, 13.0, "wkup_intr_o", "resp"),
      (109.1, 15.2, "wkup_cause.q\n\u2192 wkup_req_o", "resp")]
for x, w, t, k in WK:
    fs.block(ax, x, A_B, w, A_T - A_B, t, kind=k)
WKL = ["1 clk_aon", "wkup_incr", "count[63:0]", "1 incr", "set"]
for i, s in enumerate(WKL):
    fs.wire(ax, (WK[i][0] + WK[i][1], A_MID), (WK[i + 1][0], A_MID), color=fs.MID)
    fs.onwire(ax, (WK[i][0] + WK[i][1] + WK[i + 1][0]) / 2.0, A_MID, s, fs=6.0)

# ==================================================== STEP 2 : the sequencer
fs.label(ax, 1.6, B_CAP, "STEP 2  \u2014  THE SEQUENCER THE ROW ABOVE DRIVES: "
          "aon_timer_core has NO state enum; these are the states its enables and "
          "comparators imply",
          fs=fs.FS_LANE - 1.0, ha="left", va="bottom", color=fs.GREY)

ST = [("RESET\n!rst_aon_ni\nall counters -> 0", "write", "cleared by rst_aon_ni"),
      ("ARMED / idle\nenable=0 or\nlc_escalate_en=1", "mux", "no state advances"),
      ("DIVIDE\nprescale_count_q\n++ (holds if en=0)", "ctrl", "12 bits wide"),
      ("COUNT\nwkup_count ++\nper (prescaler+1)", "ctrl", "64-bit counter"),
      ("MATCH\ncount >= thold\nintr_o, cause=1", "resp", "wkup_cause.q=1")]
for i, (t, k, sb) in enumerate(ST):
    fs.block(ax, FSM_X[i], B_BOX_B, FSM_W, B_BOX_T - B_BOX_B, t,
             kind=k, fs=7.0, bold=False, sub=sb, sub_fs=6.4)
    fs.badge(ax, FSM_X[i] + 1.0, B_BADGE, i + 1, r=0.8)

for i, s in [(0, "rst_aon_ni=1"), (2, "== prescaler"), (3, "count>=thold")]:
    xa, xb = FSM_X[i] + FSM_W, FSM_X[i + 1]
    fs.wire(ax, (xa, B_MID), (xb, B_MID), color=fs.MID)
    fs.onwire(ax, (xa + xb) / 2.0, B_MID, s, fs=6.2)

# ARMED <-> DIVIDE is a two-way door: the divider freezes, it does not reset
x2a, x2b = FSM_X[1] + FSM_W, FSM_X[2]
xc = (x2a + x2b) / 2.0
fs.wire(ax, (x2a, B_MID + 1.3), (x2b, B_MID + 1.3), color=fs.MID)
fs.onwire(ax, xc, B_MID + 1.3, "enable=1", fs=6.2)
fs.wire(ax, (x2b, B_MID - 1.3), (x2a, B_MID - 1.3), color=fs.MID, back=True)
fs.onwire(ax, xc, B_MID - 1.3, "enable=0", fs=6.2)

# MATCH -> COUNT on the top lane: software clears the cause, the count never stops
LANE_T = B_BADGE + 1.5
fs.wire(ax, (FSM_X[4] + 5.5, B_BOX_T), (FSM_X[3] + 5.5, B_BOX_T),
        via=[(FSM_X[4] + 5.5, LANE_T), (FSM_X[3] + 5.5, LANE_T)],
        color=fs.MID, back=True)
fs.onwire(ax, (FSM_X[3] + FSM_X[4]) / 2.0 + 5.5, LANE_T,
          "sw clears wkup_cause @0x34  (the count never stops)", fs=6.4)

# ====================================================== STEP 3 : the arithmetic
fs.label(ax, 1.6, C_CAP, "STEP 3  \u2014  THE ARITHMETIC, WORD FOR WORD FROM THE RTL  "
          "\u00b7  NOTE THE COMPARE IS \u201c>=\u201d, NOT \u201c==\u201d",
          fs=fs.FS_LANE - 1.0, ha="left", va="bottom", color=fs.GREY)

EQ_LINES = [
    "prescale_count_q   12 bits   wraps at 2**12 - 1 = 4095 = 12'hFFF   @ 0x04",
    "wkup_count_q       64 bits   = {hi, lo}                         @ 0x10 / 0x14",
    "wkup_thold         64 bits   the threshold                      @ 0x08 / 0x0c",
    "",
    "wkup_incr = lc_escalate_en OK & wkup_ctrl.enable & (prescale_count_q == prescaler)",
    "            -> exactly ONE wkup_incr every (prescaler + 1) clk_aon_i cycles",
    "",
    "wkup_intr_o = wkup_incr & (wkup_count >= wkup_thold)     [ '>=', NOT '==' ]",
    "              a '==' compare would miss the match while the count is already",
    "              past the threshold, so the RTL deliberately uses '>='.",
]
fs.eqbox(ax, 12.0, C_BOX_Y, 104.0, C_BOX_H, "\n".join(EQ_LINES), fs=6.1,
         fc="#F2F2F2", ec="#BFBFBF", color="#404040")

# glossary: nothing here needs the parent figure open to be understood
GL = ("GLOSSARY\n"
      "thold \u2014 threshold register, compared\n"
      "          against the count\n"
      "prescaler \u2014 WKUP_CTRL[prescaler]:12 @ 0x04,\n"
      "          the divide value\n"
      "wkup_cause \u2014 sticky flag: set by HW,\n"
      "          cleared by SW @ 0x34\n"
      "wkup_req_o \u2014 the wakeup request\n"
      "          leaving the block")
fs.note(ax, 99.6, 2.0, 24.6, 12.4, GL, fs=5.8, valign="center")

# ================================================ STEP 4 : the wrap + compare
fs.label(ax, 2.2, 8.6, "STEP 4  \u2014  ON THE WIRE", fs=6.4, rot=90,
         weight="bold", color=fs.GREY)

ROWS = [("pre", "prescale_count_q", "12-bit divider @ 0x04"),
        ("cnt", "wkup_count_q", "64-bit @ 0x10/0x14 — low byte"),
        ("i", "wkup_incr", "one pulse per (prescaler+1)"),
        ("m", "wkup_intr_o", "high while count >= thold")]
ax, ys, u = fs.lanes(fig, ROWS, WX0, WX0 + WN * WU, unit=WU,
                     lane_gap=LGAP, label_fs=7.0, sub_fs=6.4, cycle_names=None,
                     left_pad=0.55)
XCELL = ["0xFF", "0x00", "0x01", "0x02", "0x03", "0x04",
         "0x05", "0x06", "0x07", "0x08", "0x09"]
PCELL = ["12'h%03X" % i for i in range(11)]
fs.cycle_guides(ax, WX0, WN, u, bottom=1.6, top=14.9)
fs.bus_cells(ax, WX0, PCELL, u, ys["pre"] - 0.95, 1.9,
             fill="#F2F2F2", ec="#BFBFBF", color="#404040")
fs.bus_cells(ax, WX0, XCELL[:1], u, ys["cnt"] - 0.95, 1.9,
             fill=fs.S_ALARM, ec=fs.RED, color=fs.RED)
fs.bus_cells(ax, WX0 + u, XCELL[1:], u, ys["cnt"] - 0.95, 1.9,
             fill=fs.S_ADDR, ec="#BF8F00", color="#7F6000")
fs.sigwave(ax, WX0, [1] * WN, u, ys["i"] - 0.7, ys["i"] + 0.7, color=fs.MID)
fs.sigwave(ax, WX0, [0] * (WN - 1) + [1], u, ys["m"] - 0.7, ys["m"] + 0.7,
           color=fs.GREEN)

WRAP_X = WX0 + u
ax.plot([WRAP_X, WRAP_X], [ys["cnt"] - 1.95, ys["cnt"] + 0.18], color=fs.RED,
        lw=1.1, ls=(0, (3, 2)), zorder=5)
fs.label(ax, WRAP_X, ys["cnt"] + 0.70, "low-byte wrap  0xFF \u2192 0x00", fs=6.0,
         ha="center", color=fs.RED, weight="bold")
MATCH_X = WX0 + (WN - 1) * u + u / 2.0
fs.txn_mark(ax, MATCH_X, ys["m"] + 0.7,
            "count reads 0x09 = thold (WKUP_THOLD_LO @0x0c = 64'd9)",
            xytext=(-6, 9), fs=6.2, ha="right", va="bottom")
fs.label(ax, WX0, ys["pre"] + 1.15, "prescaler = 12'd0  ->  (prescaler + 1) = 1, "
          "so one increment every clk_aon_i cycle", fs=6.0, ha="left",
         color="#404040", weight="bold")

fs.footer(fig, "The prescaler is what makes this path slow: the 64-bit counter on the row above only ever sees one "
               "increment per "
               "(prescaler + 1) clk_aon_i cycles.")
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig25_aon_timer_wakeup_path.png")


