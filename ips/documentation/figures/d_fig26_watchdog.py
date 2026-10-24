"""fig26 -- AON timer WATCHDOG path: one un-divided 32-bit counter, two compares.

Split of fig10 (d_aon_timer.py).  The parent keeps the two reset domains; this
figure owns the watchdog (wdog) counter path only.

Facts copied verbatim from d_aon_timer.py / aon_timer_core.sv:
  * wdog_count_q      : 32-bit                                    @ 0x28
  * wdog_bark_thold   : 32-bit                                    @ 0x20
  * wdog_bite_thold   : 32-bit                                    @ 0x24
  * wdog_count_q has NO prescaler: one wdog_incr per clk_aon_i cycle
    (the wakeup path in fig25 has prescale_count_q[11:0]; this one does not)
  * wdog_intr_o       = wdog_incr & (wdog_count >= wdog_bark_thold)
                        -> intr_out[1], an NMI (non-maskable interrupt)
  * wdog_reset_req_o  = wdog_incr & (wdog_count >= wdog_bite_thold)
  * aon_rst_req_d = aon_rst_req_set | aon_rst_req_q  -> sticky until rst_aon_ni
  * soc_subsystem does NOT instantiate aon_timer today, so the system-reset
    destination is drawn as a GHOST path, exactly as the parent does.
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
# A 47.5 .. 52.1  STEP 1  the counter and the missing prescaler  (axis 49.8)
# B 41.0 .. 45.0  STEP 2  compare 1: the NMI branch            (axis 43.0)
# B 33.5 .. 37.5          compare 2: the sticky reset branch   (axis 35.5)
# C 17.0 .. 30.0  STEP 3  the arithmetic, verbatim from the RTL
A_CAP, A_T, A_B = 54.5, 52.1, 47.5
A_MID = (A_T + A_B) / 2.0                       # 49.8
B_CAP, B_H = 45.9, 4.0
B1_AX, B2_AX = 43.0, 35.5
B1_T, B1_B = B1_AX + B_H / 2.0, B1_AX - B_H / 2.0        # 45.0 / 41.0
B2_T, B2_B = B2_AX + B_H / 2.0, B2_AX - B_H / 2.0        # 37.5 / 33.5
C_CAP, C_BOX_Y, C_BOX_H = 31.5, 18.0, 11.5

SPINE_X = 56.0
CMP_X, CMP_W = 63.0, 20.0
OUT_X, OUT_W = 91.0, 17.0
GHOST_X, GHOST_W = 113.5, 10.8

TITLE = ("The watchdog counts every clk_aon_i cycle with no divider: \u201c>= bark\u201d "
         "raises an NMI and \u201c>= bite\u201d latches a sticky AON reset request")
SUB = ("AON = always-on.  Left to right, top to bottom:   STEP 1 the counter and the "
       "prescaler that is NOT there   \u2192   STEP 2 the two compares and what they "
       "raise   \u2192   STEP 3 the arithmetic   \u2192   STEP 4 bark before bite on "
       "the wire")

fig, ax = fs.slide(TITLE, SUB)
X, Y = fs.canvas(ax)   # slide canvas ~125.3 x 59.1 units

# ================================================== STEP 1 : the counter row
fs.label(ax, 1.8, A_CAP, "STEP 1  \u2014  THE WATCHDOG COUNTER: ONE CLOCK, ONE "
          "COUNT, AND NO DIVIDER ANYWHERE",
          fs=fs.FS_LANE, weight="bold", ha="left", va="bottom", color=fs.ACCENT)

fs.dot(ax, 1.4, A_MID, r=0.55, fc=fs.ACCENT)
fs.label(ax, 8.6, A_T + 0.55, "START HERE", fs=6.6, weight="bold",
         color=fs.ACCENT, va="bottom")

X0_CLK, W_CLK, X_GH, W_GH = 2.6, 13.4, 20.4, 13.4
fs.block(ax, X0_CLK, A_B, W_CLK, A_T - A_B, "clk_aon_i\n+ pause_in_sleep",
         kind="ctrl")

# the absent prescaler, drawn as an empty crossed-out slot so the contrast with
# the wakeup path (fig25, prescale_count_q[11:0]) is impossible to miss
fs.block(ax, X_GH, A_B, W_GH, A_T - A_B, "prescaler?\nNOT PRESENT HERE",
         kind="plain", ls="--", lw=1.3, fs=8.0)
XP, YP = X_GH + W_GH / 2.0, A_MID
for d in (-1, 1):
    ax.plot([XP - 1.5 * d, XP + 1.5 * d], [YP - 1.5 * d, YP + 1.5 * d],
            color=fs.RED, lw=2.0, zorder=6, solid_capstyle="round")
fs.label(ax, XP, A_T + 0.55, "the wakeup path HAS one (fig25)", fs=6.0,
         color=fs.RED, ha="center", va="bottom", weight="bold")

X1_WD = 38.0
fs.wire(ax, (X0_CLK + W_CLK, A_MID), (X_GH, A_MID), color=fs.MID)
fs.onwire(ax, (X0_CLK + W_CLK + X_GH) / 2.0, A_MID, "1 clk_aon", fs=5.8)
fs.wire(ax, (X_GH + W_GH, A_MID), (X1_WD, A_MID), color=fs.MID)
fs.onwire(ax, (X_GH + W_GH + X1_WD) / 2.0, A_MID, "1 incr", fs=5.8)

fs.block(ax, X1_WD, A_B, 16.0, A_T - A_B, "wdog_count_q[31:0]\n@ 0x28",
         kind="mux")

# ============================== STEP 2 : one counter, two compares, two outcomes
fs.label(ax, 1.8, B_CAP, "STEP 2  \u2014  ONE COUNT, TWO COMPARES, TWO OUTCOMES",
         fs=fs.FS_LANE, weight="bold", ha="left", va="bottom", color=fs.ACCENT)

# fan-out spine: the count leaves the counter once and feeds both comparators
fs.wire(ax, (X1_WD + 16.0, A_MID), (SPINE_X, A_MID), color=fs.MID)
fs.wire(ax, (SPINE_X, A_MID), (SPINE_X, B2_AX), via=[(SPINE_X, A_MID)], color=fs.MID)
fs.label(ax, SPINE_X + 3.5, 51.2, "one counter,\ntwo compares", fs=6.4,
         color=fs.GREY, ha="center", va="center", style="italic")
PILL_X = (SPINE_X + CMP_X) / 2.0
fs.onwire(ax, PILL_X, B1_AX, "cnt[31:0]", fs=6.0)
fs.onwire(ax, PILL_X, B2_AX, "cnt[31:0]", fs=6.0)

# --- branch 1 : bark -> NMI --------------------------------------------------
fs.block(ax, CMP_X, B1_B, CMP_W, B_H, "COMPARE 1:  count >=\nwdog_bark_thold @ 0x20",
         kind="addr", fs=7.0)
fs.wire(ax, (SPINE_X, B1_AX), (CMP_X, B1_AX), color=fs.MID)
fs.block(ax, OUT_X, B1_B, OUT_W, B_H, "wdog_intr_o\nintr_out[1]", kind="resp", fs=8.0)
fs.wire(ax, (CMP_X + CMP_W, B1_AX), (OUT_X, B1_AX), color=fs.MID)
fs.onwire(ax, (CMP_X + CMP_W + OUT_X) / 2.0, B1_AX, "bark", fs=6.0)
fs.label(ax, 116.0, B1_AX, "NMI = non-maskable\ninterrupt: software\ncannot mask or\n"
         "delay it", fs=6.2, ha="center", va="center", color=fs.GREEN)

# --- branch 2 : bite -> sticky AON reset request -----------------------------
fs.block(ax, CMP_X, B2_B, CMP_W, B_H, "COMPARE 2:  count >=\nwdog_bite_thold @ 0x24",
         kind="alarm", fs=7.0)
fs.wire(ax, (SPINE_X, B2_AX), (CMP_X, B2_AX), color=fs.MID)
fs.block(ax, OUT_X, B2_B, OUT_W, B_H, "aon_rst_req_q\nsticky", kind="alarm", fs=8.0)
fs.wire(ax, (CMP_X + CMP_W, B2_AX), (OUT_X, B2_AX), color=fs.MID)
fs.onwire(ax, (CMP_X + CMP_W + OUT_X) / 2.0, B2_AX, "bite", fs=6.0)

# GHOST destination: the SoC does not instantiate aon_timer today, so this is
# drawn dashed and grey, exactly as the parent (fig10) draws it.
GHOST = "aon_timer_rst_req_o\nto the SoC reset tree\nNOT INSTANTIATED"
fs.block(ax, GHOST_X, B2_B, GHOST_W, B_H, GHOST, kind="plain", ls="--", lw=1.3,
         tc=fs.GREY, fs=6.4)
fs.wire(ax, (OUT_X + OUT_W, B2_AX), (GHOST_X, B2_AX), color=fs.GREY, lw=1.3,
        dashed=True)
fs.label(ax, (OUT_X + OUT_W + GHOST_X) / 2.0, B2_AX + 0.9,
         "GHOST", fs=6.0, ha="center", va="bottom", color=fs.GREY, weight="bold")

# ====================================================== STEP 3 : the arithmetic
fs.label(ax, 1.8, C_CAP, "STEP 3  \u2014  THE ARITHMETIC, WORD FOR WORD FROM THE RTL  "
         "\u00b7  BOTH COMPARES ARE \u201c>=\u201d, NOT \u201c==\u201d",
         fs=fs.FS_LANE - 0.5, ha="left", va="bottom", color=fs.GREY)

EQ_W = 74.0
WD_LINES = [
    "wdog_count_q      32 bits   wraps at 2**32 - 1     @ 0x28",
    "wdog_bark_thold   32 bits   the NMI threshold      @ 0x20",
    "wdog_bite_thold   32 bits   the reset threshold    @ 0x24",
    "",
    "wdog_incr = wdog_ctrl.enable & pause_in_sleep, on EVERY clk_aon_i cycle",
    "wdog_intr_o      = wdog_incr & (wdog_count >= wdog_bark_thold)",
    "wdog_reset_req_o = wdog_incr & (wdog_count >= wdog_bite_thold)",
    "",
    "bark < bite, so the NMI fires first;  both compares are '>=', NOT '=='",
]
fs.eqbox(ax, 2.0, C_BOX_Y, EQ_W, C_BOX_H, "\n".join(WD_LINES), fs=5.6,
         fc="#F2F2F2", ec="#BFBFBF", color="#404040")

GL = ("GLOSSARY\n"
      "NMI \u2014 non-maskable interrupt: software can\n"
      "        neither mask nor delay it.  Raised on\n"
      "        intr_out[1].\n"
      "bark / bite \u2014 the two 32-bit thresholds: bark\n"
      "        gives the NMI, bite gives the reset request.\n"
      "aon_rst_req_q \u2014 sticky: OR-ed into itself, so it\n"
      "        holds until rst_aon_ni clears it.\n"
      "GHOST \u2014 dashed grey = reference only: the SoC\n"
      "        does not instantiate aon_timer today.")
fs.note(ax, 78.0, C_BOX_Y, 46.0, C_BOX_H, GL, fs=5.4, valign="center")

# ============================= STEP 4 : the escalation, one clk_aon_i per count
fs.label(ax, 2.2, 7.0, "STEP 4  \u2014  ON THE WIRE", fs=6.4, rot=90,
         weight="bold", color=fs.GREY)
fs.label(ax, 8.0, 15.4, "EXAMPLE:  wdog_bark_thold = 32'd3   @ 0x20,   "
         "wdog_bite_thold = 32'd5   @ 0x24", fs=6.4, ha="left", va="bottom",
         color=fs.ACCENT, weight="bold")

WX0, WU, WN = 44.0, 7.5, 9
ROWS = [("cnt", "wdog_count_q[31:0]", "one count per clk_aon_i — no divider"),
        ("nmi", "wdog_intr_o  (NMI)", "high from count 3 onwards"),
        ("rst", "aon_rst_req_q", "latches at count 5, sticky")]
ax, ys, u = fs.lanes(fig, ROWS, WX0, WX0 + WN * WU, unit=WU, lane_gap=3.7,
                     label_fs=7.0, sub_fs=6.4, cycle_names=None, left_pad=0.6)
fs.cycle_guides(ax, WX0, WN, u, bottom=1.4, top=13.8)
fs.bus_cells(ax, WX0, [str(i) for i in range(WN)], u, ys["cnt"] - 0.95, 1.9,
             fill=fs.S_ADDR, ec="#BF8F00", color="#7F6000")
fs.sigwave(ax, WX0, [0, 0, 0, 1, 1, 1, 1, 1, 1], u,
           ys["nmi"] - 0.7, ys["nmi"] + 0.7, color=fs.GREEN)
fs.sigwave(ax, WX0, [0, 0, 0, 0, 0, 1, 1, 1, 1], u,
           ys["rst"] - 0.7, ys["rst"] + 0.7, color=fs.RED)
BARK_X = WX0 + 3 * u
BITE_X = WX0 + 5 * u
ax.plot([BARK_X, BARK_X], [ys["cnt"] - 1.95, ys["cnt"] + 0.20], color=fs.GREEN,
        lw=1.1, ls=(0, (3, 2)), zorder=5)
fs.label(ax, BARK_X + 0.4, ys["cnt"] + 0.70, "bark: count reaches 3", fs=6.0,
         ha="left", color=fs.GREEN, weight="bold")
ax.plot([BITE_X, BITE_X], [ys["cnt"] - 1.95, ys["cnt"] + 0.20], color=fs.RED,
        lw=1.1, ls=(0, (3, 2)), zorder=5)
fs.label(ax, BITE_X + 0.4, ys["cnt"] + 0.70, "bite: count reaches 5", fs=6.0,
         ha="left", color=fs.RED, weight="bold")
fs.label(ax, WX0, 0.7, "two cycles from bark to bite: the NMI gives software a "
         "window to react before the sticky reset request latches",
         fs=6.2, ha="left", color=fs.GREY)

fs.footer(fig, "No prescaler is the whole difference: the wakeup counter advances "
               "once every (prescaler + 1) cycles, this one advances on every "
               "single clk_aon_i cycle, which is why it needs only 32 bits.")
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig26_aon_timer_watchdog_path.png")




