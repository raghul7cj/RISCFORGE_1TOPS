"""fig10 -- AON timer (lowRISC OpenTitan aon_timer) as instantiated from its own RTL.

RTL read (max 2 files):
  rtl/ips/aon_timer/rtl/aon_timer.sv        (wrapper: 2 clock domains, 2 resets)
  rtl/ips/aon_timer/rtl/aon_timer_core.sv  (the actual counters + comparators)

Key facts taken from the RTL (not invented):
  * aon_timer_core has NO rst_ni port.  Its only reset is rst_aon_ni.
  * clk_i  / rst_ni    : TL-UL register file (aon_timer_reg_top), prim_intr_hw
  * clk_aon_i / rst_aon_ni : prescale_count_q, wkup_count, wdog_count,
                             aon_rst_req_q  -- all reset by rst_aon_ni only
  * prescale_count_q : 12-bit  (F[prescaler]:12:1 of WKUP_CTRL @ 0x4)
  * wkup_count       : 64-bit  = {wkup_count_hi, wkup_count_lo} @ 0x10/0x14
  * wkup_thold       : 64-bit  @ 0x08/0x0c
  * wdog_count       : 32-bit  @ 0x28 ; bark @0x20, bite @0x24
  * wkup_incr = lc_tx_test_false_strict(lc_escalate_en_i[1])
               & wkup_ctrl.enable.q & (prescale_count_q == prescaler.q)
  * wkup_intr_o   = wkup_incr & (wkup_count >= wkup_thold)          [>=, not ==]
  * wdog_intr_o   = wdog_incr & (wdog_count >= wdog_bark_thold)
  * wdog_reset_req_o = wdog_incr & (wdog_count >= wdog_bite_thold)
  * aon_rst_req_d = aon_rst_req_set | aon_rst_req_q  (sticky until rst_aon_ni)
  * wkup_cause    : set by HW, cleared by SW -> wkup_req_o
  * sleep_mode_i is async, 2-synced into clk_aon by prim_flop_2sync(rst_aon_ni)
System-level: riscforge_soc_subsystem.sv does NOT instantiate aon_timer today
(the 6th APB slot is documented as replacing CLIC, irq inputs tied 0), so every
system-role claim below is drawn as an INTENDED / ghost connection.
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
# vertical budget (canvas y):
#   A 41.6 .. 53.2   reset / clock-domain relationship   (the headline)
#   B 30.8 .. 40.8   datapath (wkup row / wdog row)
#   C 16.0 .. 29.6   FSM (left) + formula box (right)
#   D  1.7 .. 15.2   waveform lanes (4 lanes, lane_gap 3.4)
A_CAP, A_LANE_T, A_T, A_B, A_LANE_B = 53.0, 51.3, 49.7, 44.1, 42.9
A_MID = (A_T + A_B) / 2.0                      # 46.9
B_CAP, B_WK_Y, B_WD_Y, B_ROW_H, B_TAP = 40.7, 39.7, 31.2, 4.0, 30.3
B_MID = B_WK_Y - B_ROW_H / 2.0                 # 37.7  (wakeup row wire axis)
D_MID = B_WD_Y + B_ROW_H / 2.0                 # 33.2  (watchdog row wire axis)
C_CAP, C_LANE_T, C_BADGE, C_BOX_T, C_BOX_B, C_LANE_B = 28.4, 27.5, 25.7, 24.9, 18.1, 16.9
EQ_Y, EQ_H = 20.2, 8.8
NOTE_Y, NOTE_H = 16.0, 3.4

FSM_X = [1.8, 19.1, 36.4, 53.7, 71.0]
FSM_W = 12.8
FSM_MID = (C_BOX_T + C_BOX_B) / 2.0          # 21.6

WX0, WU, WN = 26.0, 6.9, 12
LGAP = 3.7

TITLE = ("The always-on timer keeps counting through a reset that kills "
         "everything else \u2014 the only reason it can wake the system")
SUB = ("AON = always-on.  Read top to bottom:  STEP 1 which reset reaches the counters "
       "-> STEP 2 the two counter paths -> STEP 3 the sequencer -> STEP 4 the wrap "
       "on the wire")

fig, ax = fs.slide(TITLE, SUB)
X, Y = fs.canvas(ax)   # slide canvas ~125.3 x 59.1 units

# =============================== LAYER 2a : reset / clock-domain relationship
fs.label(ax, 1.8, A_CAP, "STEP 1  \u2014  WHAT MAKES IT AON: TWO CLOCKS, TWO RESETS, "
         "AND ONLY ONE OF THEM REACHES THE COUNTERS",
         fs=fs.FS_LANE, weight="bold", ha="left", va="bottom", color=fs.ACCENT)

B1 = fs.block(ax, 2.0, A_B, 14.0, A_T - A_B, "rst_ni\nMAIN SoC RESET",
              kind="write", sub="every reset in the SoC")
B2 = fs.block(ax, 19.0, A_B, 19.0, A_T - A_B,
              "clk_i  domain  +  rst_ni\naon_timer_reg_top",
              kind="bus", sub="TileLink-UL (TL-UL) regs 0x00..0x34", sub_fs=6.4)
B4 = fs.block(ax, 54.0, A_B, 25.0, A_T - A_B,
              "clk_aon_i  domain  +  rst_aon_ni\naon_timer_core",
              kind="periph", sub="clock-domain crossing \u00b7 no rst_ni port", sub_fs=6.6)
B5 = fs.block(ax, 85.0, A_B, 12.6, A_T - A_B, "rst_aon_ni\nAON RESET",
              kind="write", sub="core's only reset")
B6 = fs.block(ax, 101.0, A_B, 22.8, A_T - A_B,
              "aon_timer_rst_req_o\nwkup_req_o",
              kind="resp", sub="wkup_cause: set by HW, cleared by SW", sub_fs=6.4)

fs.wire(ax, (16.0, A_MID), (19.0, A_MID), color=fs.MID)
fs.label(ax, 17.5, A_MID + 1.0, "rst_ni", fs=6.6, ha="center", va="bottom", color=fs.MID)
CDC = ["prescaler[11:0] @0x04", "wkup_thold[63:0] @0x0c",
       "wdog bark/bite @0x20/24", "wkup/wdog count (rb)"]
for i, s in enumerate(CDC):
    # 1.32 u lane pitch: the on-wire pills are 1.23 u tall, so they no longer
    # overlap each other, and the stack clears B2 (x=38) and B4 (x=54).
    yy = A_MID + (i - 1.5) * 1.32
    fs.wire(ax, (39.2, yy), (53.4, yy), color=fs.ACCENT, lw=1.05)
    fs.onwire(ax, 46.3, yy, s, fs=5.8, color=fs.ACCENT)
fs.wire(ax, (85.0, A_MID), (79.0, A_MID), color=fs.MID)
fs.label(ax, 82.0, A_MID + 1.0, "rst_aon_ni", fs=6.2, ha="center", va="bottom", color=fs.MID)

# clk_aon_i output -> AON request, over the top lane
fs.wire(ax, (66.5, A_T), (112.4, A_T),
        via=[(66.5, A_LANE_T), (112.4, A_LANE_T)], color=fs.GREEN, lw=2.0)
fs.onwire(ax, 92.0, A_LANE_T, "sticky: set by wdog, cleared only by rst_aon_ni", fs=6.8)

# the perimeter return: the timer's own reset request -> the SoC reset
# The system-reset path is NOT instantiated in the SoC today, so it is drawn
# as a quiet grey footnote: it must not out-shout the two real resets above.
fs.wire(ax, (112.4, A_B), (8.3, A_B),
        via=[(112.4, A_LANE_B), (8.3, A_LANE_B)], color=fs.GREY, lw=1.3, dashed=True)
fs.onwire(ax, 55.0, A_LANE_B,
          "NOT WIRED TODAY \u2014 soc_subsystem does not instantiate aon_timer, "
          "so this system-reset path is drawn for reference only",
          fs=6.4, color=fs.GREY, weight="normal")

# =============================== LAYER 2b : the internal datapath
fs.label(ax, 1.8, B_CAP, "STEP 2  \u2014  INTERNAL DATAPATH: ONE CLOCK, ONE DIVIDER FOR "
         "THE WAKEUP COUNTER, NONE FOR THE WATCHDOG (wdog)   \u00b7   "
         "NMI = non-maskable interrupt",
         fs=fs.FS_LANE - 1.0, ha="left", va="bottom", color=fs.GREY)

# --- wakeup timer row (divided by prescale_count_q) -------------------------
WK = [(2.0, 11.0, "clk_aon_i\nsame clock", "ctrl"),
      (18.5, 17.5, "DIVIDER\nprescale_count_q[11:0]", "ctrl"),
      (41.5, 18.5, "wkup_count_q[63:0]\n{hi,lo} @ 0x10/0x14", "mux"),
      (65.5, 19.5, "COMPARE\ncount >= wkup_thold", "addr"),
      (90.5, 13.0, "wkup_intr_o", "resp"),
      (108.5, 15.3, "wkup_cause.q\n\u2192 wkup_req_o", "resp")]
for x, w, t, k in WK:
    fs.block(ax, x, B_WK_Y - B_ROW_H, w, B_ROW_H, t, kind=k)
WKL = ["1 clk_aon", "wkup_incr", "count[63:0]", "1 incr", "set"]
for i, s in enumerate(WKL):
    fs.wire(ax, (WK[i][0] + WK[i][1], B_MID), (WK[i + 1][0], B_MID), color=fs.MID)
    fs.onwire(ax, (WK[i][0] + WK[i][1] + WK[i + 1][0]) / 2.0, B_MID, s, fs=6.0)

# --- watchdog row (no divider: one count per clk_aon_i) ----------------------
WD = [(2.0, 12.5, "clk_aon_i\n+ pause_in_sleep", "ctrl"),
      (19.5, 16.5, "wdog_count_q[31:0]\n@ 0x28", "mux"),
      (41.5, 19.0, "count >= bark_thold\n@ 0x20", "addr"),
      (66.5, 17.5, "wdog_intr_o \u00b7 nmi\nintr_out[1]", "resp"),
      (93.0, 13.6, "count >=\nbite_thold @ 0x24", "alarm"),
      (111.0, 12.8, "aon_rst_req_q\nsticky", "alarm")]
for x, w, t, k in WD:
    fs.block(ax, x, B_WD_Y, w, B_ROW_H, t, kind=k, fs=8.2)
WDL = ["wdog_incr", "count[31:0]", "bark", None, "bite"]
for i, s in enumerate(WDL):
    if s is None:
        continue
    fs.wire(ax, (WD[i][0] + WD[i][1], D_MID), (WD[i + 1][0], D_MID), color=fs.MID)
    fs.onwire(ax, (WD[i][0] + WD[i][1] + WD[i + 1][0]) / 2.0, D_MID, s, fs=5.8)
fs.label(ax, 88.9, D_MID, "int path ends\nhere \u2014 the bite\ntap is below",
         fs=6.2, ha="center", va="center", color=fs.GREY)

# the bite compare taps the SAME count: routed in its own lane under the row
fs.wire(ax, (28.0, B_WD_Y), (28.0, B_TAP), via=[(99.5, B_TAP), (99.5, B_WD_Y)],
        color=fs.MID, lw=1.5)
# label sits on the right half of the tap lane: at x=62 its pill ran into the
# "STATE MACHINE ..." section caption sitting just above it.
fs.onwire(ax, 94.0, B_TAP, "wdog_count[31:0]  \u2014  one counter, two compares",
          fs=6.8)

# =============================== LAYER 3 : the state machine
fs.label(ax, 1.6, C_CAP, "STEP 3  \u2014  SEQUENCER: aon_timer_core has NO state enum; "
         "these are the states its enables and comparators imply",
         fs=fs.FS_LANE - 1.0, ha="left", va="bottom", color=fs.GREY)

FSM_X = [1.6, 19.7, 37.8, 55.9, 74.0]
FSM_W = 11.0
FSM_MID = (C_BOX_T + C_BOX_B) / 2.0                     # 21.45
ST = [("RESET\n!rst_aon_ni\nall counters -> 0", "write", "cleared by rst_aon_ni"),
      ("ARMED / idle\nenable=0 or\nlc_escalate_en=1", "mux", "no state advances"),
      ("DIVIDE\nprescale_count_q\n++ (holds if en=0)", "ctrl", "12 bits wide"),
      ("COUNT\nwkup_count ++\nper (prescaler+1)", "ctrl", "64-bit counter"),
      ("MATCH\ncount >= thold\nintr_o, cause=1", "resp", "wkup_cause.q=1")]
for i, (t, k, sb) in enumerate(ST):
    fs.block(ax, FSM_X[i], C_BOX_B, FSM_W, C_BOX_T - C_BOX_B, t,
             kind=k, fs=7.0, bold=False, sub=sb, sub_fs=6.4)
    fs.badge(ax, FSM_X[i] + 1.0, C_BADGE, i + 1, r=0.8)

# straight path: RESET -> ARMED -> DIVIDE -> COUNT -> MATCH
for i, s in [(0, "rst_aon_ni=1"), (2, "== prescaler"), (3, "count>=thold")]:
    xa, xb = FSM_X[i] + FSM_W, FSM_X[i + 1]
    fs.wire(ax, (xa, FSM_MID), (xb, FSM_MID), color=fs.MID)
    fs.onwire(ax, (xa + xb) / 2.0, FSM_MID, s, fs=6.2)

# ARMED <-> DIVIDE is a two-way door: the divider freezes, it does not reset
x2a, x2b = FSM_X[1] + FSM_W, FSM_X[2]
xc = (x2a + x2b) / 2.0
fs.wire(ax, (x2a, FSM_MID + 1.2), (x2b, FSM_MID + 1.2), color=fs.MID)
fs.onwire(ax, xc, FSM_MID + 1.2, "enable=1", fs=6.2)
fs.wire(ax, (x2b, FSM_MID - 1.2), (x2a, FSM_MID - 1.2), color=fs.MID, back=True)
fs.onwire(ax, xc, FSM_MID - 1.2, "enable=0", fs=6.2)

# MATCH -> COUNT on the top lane (software clears the cause, the counter never stops)
fs.wire(ax, (FSM_X[4] + 5.5, C_BOX_T), (FSM_X[3] + 5.5, C_BOX_T),
        via=[(FSM_X[4] + 5.5, C_LANE_T), (FSM_X[3] + 5.5, C_LANE_T)],
        color=fs.MID, back=True)
fs.onwire(ax, (FSM_X[3] + FSM_X[4]) / 2.0 + 5.5, C_LANE_T,
          "sw clears wkup_cause @0x34  (the count never stops)", fs=6.4)
# rst_aon_ni = 0 from ANY state, on the bottom perimeter lane
fs.wire(ax, (FSM_X[4] + 8.0, C_BOX_B), (FSM_X[0] + 5.5, C_BOX_B),
        via=[(FSM_X[4] + 8.0, C_LANE_B), (FSM_X[0] + 5.5, C_LANE_B)],
        color=fs.RED, lw=1.8, dashed=True)
fs.onwire(ax, 54.0, C_LANE_B, "rst_aon_ni = 0, from ANY state, async: prescale_count_q, "
          "wkup/wdog count, intr_state and aon_rst_req_q all cleared", fs=6.6,
          color=fs.RED)
# =============================== LAYER 4a : formula box + reset honesty note
EQ_X, EQ_W = 87.0, 36.8
EQ_LINES = [
    "prescale_count_q  12 bits   wraps at 2**12 - 1 = 4095 = 12'hFFF",
    "wkup_count_q      64 bits   wraps at 2**64 - 1  (no wrap compare in RTL)",
    "thold = threshold register;  the compare is '>=', NOT '=='",
    "match   wkup_incr & (wkup_count >= wkup_thold)",
    "wkup_incr = enable & lc_ok & (prescale_count_q == prescaler)",
    "     -> one wkup_incr every (prescaler + 1) clk_aon_i cycles",
    "example   prescaler = 12'd0,  WKUP_THOLD_LO @0x0c = 64'd9",
    "     -> wkup_intr_o is high while the count reads 0x09, for 1 incr",
]
# A neutral box, not a yellow "address" box: these are supporting formulae, they
# must not out-shout the reset-domain block that carries the title.
fs.eqbox(ax, EQ_X, 17.4, EQ_W, 10.4, "\n".join(EQ_LINES), fs=6.2,
         fc="#F2F2F2", ec="#BFBFBF", color="#404040")

# =============================== LAYER 4b : wrap / compare waveform panel
# STEP 4 has no room for a full-width caption: it sits in the left gutter,
# clear of the STEP 3 reset perimeter lane above (which starts at x = 25.6).
fs.label(ax, 2.2, 8.6, "STEP 4  \u2014  ON THE WIRE", fs=6.4, rot=90,
         weight="bold", color=fs.GREY)

WX0, WU, WN = 24.0, 6.8, 11
ROWS = [("cnt", "wkup_count_q", "64-bit @ 0x10/0x14 \u2014 low byte"),
        ("rst", "rst_ni   main SoC reset", "kills the clk_i side only"),
        ("m", "wkup_intr_o", "high for one increment"),
        ("q", "wkup_cause.q / wkup_req_o", "sticky @0x34, cleared by SW")]
ax, ys, u = fs.lanes(fig, ROWS, WX0, WX0 + WN * WU, unit=WU,
                     lane_gap=LGAP, label_fs=7.0, sub_fs=6.4, cycle_names=None,
                     left_pad=0.55)
XCELL = ["0xFF", "0x00", "0x01", "0x02", "0x03", "0x04",
         "0x05", "0x06", "0x07", "0x08", "0x09"]
fs.cycle_guides(ax, WX0, WN, u, bottom=1.6, top=14.75)
fs.bus_cells(ax, WX0, XCELL[:1], u, ys["cnt"] - 0.95, 1.9,
             fill=fs.S_ALARM, ec=fs.RED, color=fs.RED)
fs.bus_cells(ax, WX0 + u, XCELL[1:], u, ys["cnt"] - 0.95, 1.9,
             fill=fs.S_ADDR, ec="#BF8F00", color="#7F6000")
fs.sigwave(ax, WX0, [1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1], u,
           ys["rst"] - 0.7, ys["rst"] + 0.7, color=fs.RED)
fs.sigwave(ax, WX0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], u,
           ys["m"] - 0.7, ys["m"] + 0.7, color=fs.GREEN)
fs.sigwave(ax, WX0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], u,
           ys["q"] - 0.7, ys["q"] + 0.7, color=fs.ORANGE)

# wrap boundary and the compare cycle.  The caption goes in the clear band
# ABOVE the cell row: at its old y (12.62) it was printed straight through the
# red rst_ni trace, which occupies y 11.45..12.85.
WRAP_X = WX0 + u
ax.plot([WRAP_X, WRAP_X], [ys["cnt"] - 1.95, ys["cnt"] + 0.18], color=fs.RED,
        lw=1.1, ls=(0, (3, 2)), zorder=5)
fs.label(ax, WRAP_X, ys["cnt"] + 0.70, "low-byte wrap  0xFF \u2192 0x00", fs=6.0,
         ha="center", color=fs.RED, weight="bold")
MATCH_X = WX0 + (WN - 1) * u + u / 2.0
fs.txn_mark(ax, MATCH_X, ys["m"] + 0.7,
            "count reads 0x09 = thold:  9 increments past the 0x00 wrap cell",
            xytext=(56, 10), fs=6.2, ha="center", va="bottom")

# What the reset preserves and what it clears -- this is the punchline of the
# whole figure, so it sits beside the waveform it explains instead of floating
# in the bottom-right corner.  It replaces two duplicate grey notes.
fs.note(ax, 100.4, 1.9, 23.4, 6.0,
        "PRESERVED across rst_ni: the AON counters\n"
        "CLEARED by rst_aon_ni only: counters + flags\n"
        "There is NO 'preserve' reset in this RTL",
        fs=6.2, valign="center")

# =============================== LAYER 5 : sign-off
FOOT = ("Why a design needs a counter that survives the reset it must wake the "
        "system from: everything else sits at its reset value while rst_ni is "
        "low, so the AON counter is the only thing that can still be counting.")
fs.footer(fig, FOOT)
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig10_aon_timer_fsm.png")
