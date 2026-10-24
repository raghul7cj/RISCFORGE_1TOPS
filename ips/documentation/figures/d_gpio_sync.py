"""
fig31 - GPIO input synchroniser, extracted from fig14 (d_gpio.py).

Grounded in the SAME sources the parent used:
  gpio_input_stage.sv  : tc_clk_gating + sync #(.STAGES(2)) + serial_q compare,
                         r_edge_o / f_edge_o, s_gpio_in_sync
  common_cells/sync.sv : reg_q <= {reg_q[STAGES-2:0], serial_i}
  gpio.sv              : 4-way interrupt mask (rise / fall / lvl hi / lvl lo)
  gpio_reg_pkg.sv      : the register names + offsets quoted here

The parent fig14 is FROZEN.  This script only re-composes its section 3/4.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
import _figstyle as fs
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle

TITLE = ("Two flops are the whole input path: the pad is sampled twice, the edge "
         "flag is armed by flop 2 one clock later,\nand software only ever reads "
         "flop 2")
SUB = ("read left to right, top band then bottom \u2014 1 the path, pad to irq  "
       "\u00b7 2 all four modes the RTL has  \u00b7 3 one pad edge, cycle by cycle"
       "  \u00b7 4 what two flops cost, and why a raw read would glitch")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
L, R = 2.4, 122.9

# ------------------------------------------------------------------ geometry
H1Y = 56.2                     # 1  header
CY, CH = 45.8, 8.6             # 1  the chain
SIGY = 43.4                    # 1b signal names
H2Y = 41.8                     # 2  header
MY, MH = 30.6, 10.0             # 2  four mode cards
H3Y = 29.0                     # 3  header
X0, U, NCELL = 29.0, 8.0, 7
XEND = X0 + NCELL * U          # 85.0
RX, RW = 87.5, 35.4            # 4  right-hand explanation column
LGAP, WHI = 4.6, 1.4

BANDS = [("header 1", H1Y - 0.5, H1Y + 0.5), ("1 chain", CY, CY + CH),
         ("header 2", H2Y - 0.5, H2Y + 0.5), ("2 modes", MY, MY + MH),
         ("header 3", H3Y - 0.5, H3Y + 0.5), ("3 wave + 4 col", 1.2, 27.6)]
print(f"canvas = {XW:.2f} x {YH:.2f} units   (x content {L} .. {R})")
for i in range(len(BANDS) - 1):
    print(f"   gap {BANDS[i][1] - BANDS[i + 1][2]:5.2f}   above '{BANDS[i + 1][0]}'")
assert min(BANDS[i][1] - BANDS[i + 1][2] for i in range(len(BANDS) - 1)) > 0.45
print("L1 ok")

# =============================== L2  THE INPUT PATH CHAIN
fs.label(ax, L, H1Y, "1   THE PATH   one pad pin, one instance of "
         "gpio_input_stage \u00b7  NrGPIOs = 32 of them",
         fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, H1Y - 0.05, "entry point: the two heavy-outlined flops",
         fs=7.0, color=fs.GREY, ha="right")

CHAIN = [
    (2.4, 8.6, "PAD", "plain", None, "gpio_in[n]\nasynchronous\noutside clk domain"),
    (13.8, 19.2, "STAGE 1", "periph", 1, "i_sync.reg_q[0]\nsync #(.STAGES = 2)"),
    (35.8, 19.2, "STAGE 2", "periph", 2, "reg_q[1] = serial_o\n{reg_q[0], serial_i}"),
    (57.8, 12.8, "serial_q", "ctrl", None, "third flop,\nthe compare copy"),
    (73.4, 17.0, "edge detect", "mem", None,
     "r_edge_o = serial & ~serial_q\nf_edge_o = ~serial & serial_q\n"
     "combinational, 1 clk wide"),
    (93.2, 19.4, "4 masks \u2192 sticky", "ctrl", None,
     "& INTRPT_*_EN[n]\nrise | fall | lvl hi | lvl lo"),
    (115.4, 7.5, "irq", "alarm", None, "global_\ninterrupt_o"),
]
ax.add_patch(Rectangle((12.6, CY - 1.3), 43.6, CH + 2.2, facecolor="none",
                       edgecolor="#548235", linewidth=1.7,
                       linestyle=(0, (4, 2.5)), zorder=2))
fs.label(ax, 12.6, CY + CH + 3.0, "the whole synchroniser \u2014 two flops",
         fs=6.6, color="#1B5E20", weight="bold", ha="left")

ch = []
for i, (x, w, tx, kd, bd, sb) in enumerate(CHAIN):
    ch.append(fs.block(ax, x, CY, w, CH, tx, kind=kd, fs=7.4, sub=sb,
                       sub_fs=5.9, lw=2.8 if i in (1, 2) else 1.15))
    if bd:
        fs.badge(ax, x + 1.7, CY + CH - 1.7, bd)
for i in range(len(ch) - 1):
    fs.wire(ax, ch[i]["e"], ch[i + 1]["w"], color=fs.ACCENT)

for gx, nm in [(10.4, "gpio_in[n]"), (32.0, "reg_q[0]"), (54.8, "serial"),
               (70.2, "serial_q"), (89.6, "r_edge_o / f_edge_o"),
               (114.0, "pending")]:
    fs.label(ax, gx, SIGY, nm, fs=6.2, color=fs.ACCENT, weight="bold")
fs.qa_report(fig)
print("L2 ok")

# =============================== L3  ALL FOUR MODES
fs.label(ax, L, H2Y, "2   ALL FOUR MODES THE RTL HAS   two edge modes are "
         "combinational and fire once  \u00b7  two level modes re-assert every "
         "cycle the level holds", fs=7.6, color=fs.ACCENT, weight="bold",
         ha="left")
fs.label(ax, R, H2Y - 0.05, "GPIO_CFG 0x004 [1] picks the pair",
         fs=7.0, color=fs.GREY, ha="right")

MODES = [
    ("RISING  (edge mode)", "periph",
     "GPIO_INTRPT_RISE_EN     0x028  R/W\n"
     "GPIO_INTRPT_RISE_STATUS 0x03C  W1C\n"
     "r_edge_o = serial & ~serial_q\n"
     "one clk wide. A steady high with\n"
     "only RISE_EN set gives EXACTLY\n"
     "ONE interrupt, on the transition."),
    ("FALLING  (edge mode)", "periph",
     "GPIO_INTRPT_FALL_EN     0x02C  R/W\n"
     "GPIO_INTRPT_FALL_STATUS 0x040  W1C\n"
     "f_edge_o = ~serial & serial_q\n"
     "also one clk wide: the same\n"
     "compare with serial and serial_q\n"
     "swapped. A falling level fires once."),
    ("LEVEL HIGH", "ctrl",
     "GPIO_INTRPT_LVL_HIGH_EN   0x030 R/W\n"
     "GPIO_INTRPT_LVL_HIGH_STATUS 0x044 R\n"
     "reads s_gpio_in_sync = serial_q\n"
     "the mask term stays true while\n"
     "the pin is high, so the sticky\n"
     "status re-asserts until W1C."),
    ("LEVEL LOW", "ctrl",
     "GPIO_INTRPT_LVL_LOW_EN    0x034 R/W\n"
     "GPIO_INTRPT_LVL_LOW_STATUS 0x048 R\n"
     "reads s_gpio_in_sync = serial_q\n"
     "same, inverted: it pends while\n"
     "the pin is LOW, and drops out\n"
     "again when the pin goes high."),
]
CW, CG, HH = 29.0, 1.7, 1.7
for i, (nm, kd, body) in enumerate(MODES):
    x = L + i * (CW + CG)
    fs.block(ax, x, MY + MH - HH, CW, HH, nm, kind=kd, fs=7.2, lw=1.7)
    fs.note(ax, x, MY, CW, MH - HH, body, fs=6.1, kind="note")
fs.qa_report(fig)
print("L3 ok")

# =============================== L4  WAVEFORM
fs.label(ax, L, H3Y, "3   ONE RISING EDGE ON PIN 3   \u2014  what happens, cycle "
         "by cycle: pad \u2192 stage 1 \u2192 stage 2 \u2192 flag", fs=7.6,
         color=fs.ACCENT, weight="bold", ha="left")
fs.chip(ax, 88.0, H3Y, "\u25b6  START HERE \u2014 the pad edge in lane 1",
        fs=6.6, fc="#FFFFFF", ec=fs.RED, tc="#7F1010")

ROWS = [("sts", "INTRPT_RISE_STATUS[3]", "sticky, set by hardware"),
        ("flg", "r_edge_o", "1 clk wide \u00b7 never the pad"),
        ("s2", "STAGE 2   reg_q[1]", "= serial_o"),
        ("s1", "STAGE 1   i_sync.reg_q[0]", "sync #(.STAGES = 2)"),
        ("pad", "PAD   gpio_in[3]", "asynchronous")]
axl, ys, u = fs.lanes(fig, ROWS, X0, XEND, unit=U, left_pad=1.0, lane_gap=LGAP,
                      label_fs=6.5, sub_fs=5.9)
assert abs(u - U) < 1e-9
fs.cycle_guides(ax, X0, NCELL, U, bottom=2.6, top=25.8)

EDGEC = X0 + 1.5 * U
ax.add_line(Line2D([X0, EDGEC, EDGEC, XEND], [ys["pad"] - WHI] * 2 +
                   [ys["pad"] + WHI] * 2, color=fs.RED, lw=2.0,
                   solid_capstyle="round", solid_joinstyle="round", zorder=6))
ax.add_line(Line2D([EDGEC, EDGEC], [2.8, 25.8], color=fs.RED, lw=1.0,
                   ls=(0, (3, 2.5)), zorder=4))
for k, lv in (("s1", [0, 1, 1, 1, 1, 1, 1]),
              ("s2", [0, 0, 1, 1, 1, 1, 1]),
              ("flg", [0, 0, 0, 1, 0, 0, 0]),
              ("sts", [0, 0, 0, 1, 1, 1, 1])):
    fs.sigwave(ax, X0, lv, U, ys[k] - WHI, ys[k] + WHI,
               color=(fs.GREEN if k in ("flg", "sts") else fs.ACCENT), lw=1.9)

fs.txn_mark(ax, X0 + 3 * U, ys["flg"] - WHI,
            "armed by STAGE 2, one clk after reg_q[1]",
            xytext=(-92, 10), fs=6.5)
fs.label(ax, EDGEC - 1.4, 1.9, "pad edge", fs=6.2, color=fs.RED, weight="bold",
         ha="right")
for c in range(2, 6):
    fs.label(ax, X0 + (c + 0.5) * U, 1.9, f"clk {c}", fs=6.0, color=fs.GREY)
fs.legend_row(ax, 2.6, 26.9, [("line", fs.RED, "PAD, asynchronous"),
                              ("line", fs.ACCENT, "synchroniser flops"),
                              ("line", fs.GREEN, "flag / sticky status")], fs=6.3)
fs.qa_report(fig)
print("L4 ok")

# =============================== L5  RIGHT COLUMN -- what two flops buy
fs.eqbox(ax, RX, 22.2, RW, 5.4,
         "4   settle  =  n_stages \u00d7 1 clk  =  2 clk   (n_stages = 2)\n"
         "GPIO_IN 0x014 = s_gpio_in_sync = serial_o = serial_q\n"
         "\u2192 software sees the pin 3 clk after it moved\n"
         "   (2 sync + 1 compare) \u2014 never the raw wire",
         fs=6.0)
fs.note(ax, RX, 11.2, RW, 10.3,
        "WHY A COMBINATIONAL READ WOULD GLITCH\n"
        "A combinational read of gpio_in[n] has no clock edge\n"
        "to sample against: it can change mid-period, show a\n"
        "value the pin never held, and arrive 2 clk EARLY.\n"
        "Stage 1 may go metastable at the edge; stage 2 is the\n"
        "first flop guaranteed settled. GPIO_IN and all four\n"
        "masks read flop 2 \u2014 the pad wire is never exported.",
        fs=6.0, kind="alarm")
fs.note(ax, RX, 1.6, RW, 9.0,
        "GLOSSARY \u2014 R = read-only \u00b7 R/W = read/write\n"
        "W1C = write 1 to clear (writing 0 leaves the bit alone)\n"
        "hw-set = set by hardware \u00b7 OD0 / OD1 = open-drain 0 / 1\n"
        "CLOCK GATE \u2014 tc_clk_gating #(.IS_FUNCTIONAL(0)),\n"
        "en_i = GPIO_EN[n].q. GPIO_EN[n] = 0 freezes reg_q,\n"
        "serial_q and the GPIO_IN read-back at reset 0.",
        fs=5.9, kind="note")
fs.qa_report(fig)
print("L5 ok")

# =============================== L6  FOOTER
fs.footer(fig,
          "Two flops is the minimum clean input bit: flop 1 can metastable, flop "
          "2 gives it a full clock, and GPIO_IN plus every mask read flop 2 only "
          "\u2014 wire the pad straight to a register and software reads a bit "
          "that never existed.")

fs.qa_report(fig)
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig31_gpio_input_synchroniser.png")
