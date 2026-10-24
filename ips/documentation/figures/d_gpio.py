"""
fig14 - GPIO controller internals (gpio.sv / gpio_apb_wrap.sv / gpio_input_stage.sv).

Grounded in:
  gpio_reg_pkg.sv      : GPIOCount = 32, 19 registers, index order, GPIO_PERMIT
  gpio_reg_top.sv      : reggen block, BlockAw = 11 (2 KB)
  gpio_apb_wrap.sv     : apb_to_reg + sub-word-write guard (PSLVERR)
  gpio.sv              : output path (GPIO_OUT/GPIO_MODE), 4-way interrupt
                         mask/status, CFG pulse-vs-sticky select
  gpio_input_stage.sv  : tc_clk_gating + sync #(.STAGES(2)) + serial_q compare
  common_cells/sync.sv : reg_q <= {reg_q[STAGES-2:0], serial_i}
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

TITLE = ("GPIO is an output register plus a two-flop input synchronizer \u2014 "
         "and that synchronizer is the whole design, so a raw input register "
         "cannot be read")
SUB = ("read top to bottom — 1 the 19 registers · 2 the APB front-end and "
       "output path · 3 the two-flop input synchroniser and the edge-detect "
       "interrupt · 4 what two flops cost, on the wire")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
L, R = 2.4, 122.9

# ------------------------------------------------------------------ geometry
R1Y, R1H, H1Y = 43.0, 11.7, 55.7    # 1  register map (3 note columns)
R2Y, R2H, H2Y = 33.1, 7.8, 42.0     # 2  APB front-end + output path
R3Y, R3H, SIGY, H3Y = 22.9, 5.6, 29.7, 31.5   # 3  input path chain
INY, INH, IHY = 14.6, 6.0, 21.6     # 3b sync inset (eqbox + notes)
CAPY = 13.1                         # waveform caption
X0, U, NCELL = 28.0, 9.4, 10
XEND = X0 + NCELL * U        # 122.0
LGAP = 2.7
WHI = 1.0                    # waveform half-height

# top -> bottom, each entry (name, y_lo, y_hi)
BANDS = [("header 1", H1Y - 0.5, H1Y + 0.5), ("1 register map", R1Y, R1Y + R1H),
         ("header 2", H2Y - 0.5, H2Y + 0.5), ("2 apb + output", R2Y, R2Y + R2H),
         ("header 3", H3Y - 0.5, H3Y + 0.5), ("3 sig names", SIGY - 0.5, SIGY + 0.5),
         ("3 input path", R3Y, R3Y + R3H), ("3b inset hdr", IHY - 0.5, IHY + 0.5),
         ("3b sync inset", INY, INY + INH), ("4 waveform + mark", 1.2, 14.0)]

print(f"canvas = {XW:.2f} x {YH:.2f} units   (x content {L} .. {R})")
print("LANE BUDGET  (y units, top -> bottom)")
for nm, a, b in BANDS:
    print(f"   {nm:<15s} {a:6.2f} .. {b:6.2f}   h = {b - a:5.2f}")
for i in range(len(BANDS) - 1):
    print(f"   gap {BANDS[i][1] - BANDS[i + 1][2]:5.2f}   above '{BANDS[i + 1][0]}'")
print(f"   headroom  top {YH - BANDS[0][2]:.2f}   bottom {BANDS[-1][1]:.2f}")
assert min(BANDS[i][1] - BANDS[i + 1][2] for i in range(len(BANDS) - 1)) > 0.45
print("L1 ok")

# =============================== L2a  REGISTER MAP (real names + offsets)
fs.label(ax, L, H1Y, "1   APB REGISTER FILE   gpio_reg_pkg.sv  \u00b7  "
         "gpio_reg_top.sv  \u00b7  lowRISC reggen, BlockAw = 11  \u00b7  "
         "APB = Advanced Peripheral Bus",
         fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, H1Y - 0.05, "base 0x4000_3000  \u00b7  APB[3]  \u00b7  2 KB decode"
         "  \u00b7  19 \u00d7 32-bit", fs=7.0, color=fs.GREY, ha="right")

COLS = [
    ["GPIO_INFO             0x000  R     [9:0] = 32 pins, [19:10] = ver 2",
     "GPIO_CFG              0x004  R/W   [0] glbl_intrpt_mode  [1] pin_lvl_intrpt_mode",
     "GPIO_GPIO_MODE_0      0x008  R/W   00 IN \u00b7 01 OUT \u00b7 10 OD0 \u00b7 11 OD1",
     "GPIO_GPIO_MODE_1      0x00C  R/W   same encoding, GPIO[16..31]",
     "GPIO_GPIO_EN          0x010  R/W   per-pin input sampling enable",
     "GPIO_GPIO_IN          0x014  R     \u2190 s_gpio_in_sync = serial_q",
     "GPIO_GPIO_OUT         0x018  R/W   atomic read-back of SET / CLR / TGL"],
    ["GPIO_GPIO_SET         0x01C  W      1 \u2192 set gpio_out bit",
     "GPIO_GPIO_CLEAR       0x020  W      1 \u2192 clear gpio_out bit",
     "GPIO_GPIO_TOGGLE      0x024  W      1 \u2192 invert gpio_out bit",
     "GPIO_INTRPT_RISE_EN   0x028  R/W   rising-edge mask",
     "GPIO_INTRPT_FALL_EN   0x02C  R/W   falling-edge mask",
     "GPIO_INTRPT_LVL_HIGH_EN 0x030 R/W  level-high mask",
     "GPIO_INTRPT_LVL_LOW_EN  0x034 R/W  level-low mask"],
    ["GPIO_INTRPT_STATUS          0x038  R/W1C  OR of the four below",
     "GPIO_INTRPT_RISE_STATUS     0x03C  R/W1C  sticky, hw-set beats W1C",
     "GPIO_INTRPT_FALL_STATUS     0x040  R/W1C  sticky",
     "GPIO_INTRPT_LVL_HIGH_STATUS 0x044  R      hw-set sticky",
     "GPIO_INTRPT_LVL_LOW_STATUS  0x048  R      hw-set sticky",
     "GPIO_PERMIT[0] = 4'b0111 \u2014 INFO is the only partial-write register",
     "R = read-only \u00b7 R/W = read/write \u00b7 W1C = write 1 to clear",
     "OD0/OD1 = open-drain 0/1 \u00b7 hw-set = set by hardware"],
]
for i, col in enumerate(COLS):
    fs.note(ax, L + i * 40.5, R1Y, 39.5, R1H, "\n".join(col), fs=6.2,
            pad_y=0.7)
fs.qa_report(fig)
print("L2a ok")

# =============================== L2b  APB FRONT-END + OUTPUT PATH
fs.label(ax, L, H2Y, "2   APB FRONT-END \u2192 gpio_reg_top \u2192 OUTPUT PATH"
         "   \u00b7   no port-update FSM: MODE, EN, mask, W1C is a register-write "
         "ORDER", fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, H2Y - 0.05, "SET/CLR/TGL = set/clear/toggle writes GPIO_OUT, "
         "de=1 \u2014 atomic", fs=7.0, color=fs.GREY, ha="right")

AY, AH = 33.6, 6.6
# gaps 3.5 / 5.0 / 5.4 -- wide enough for the on-wire label pills to clear
apb = [fs.block(ax, 2.4, AY, 14.4, AH, "gpio_apb_wrap", kind="bus", fs=7.4,
                sub="sub-word store, pstrb \u2260 4'hF\n\u2192 PSLVERR, access "
                    "blocked", sub_fs=5.8),
       fs.block(ax, 20.3, AY, 11.0, AH, "apb_to_reg", kind="ctrl", fs=7.4,
                sub="wstrb hardcoded '1\n(pstrb never arrives)", sub_fs=5.8),
       fs.block(ax, 36.3, AY, 8.8, AH, "REG_BUS", kind="mux", fs=7.4,
                sub="addr / data\nvalid", sub_fs=5.8),
       fs.block(ax, 50.5, AY, 11.9, AH, "gpio_reg_top", kind="periph", fs=7.4,
                sub="reg2hw / hw2reg\n19 \u00d7 32-bit", sub_fs=5.8)]
for a2, b2, lb in zip(apb, apb[1:], ["APB", "reg_bus", "req / rsp"]):
    fs.onwire(ax, (a2["e"][0] + b2["w"][0]) / 2.0, AY + AH / 2.0, lb,
              fs=5.0, color=fs.ACCENT)

FSX = 66.0
fu = fs.block(ax, FSX, 37.5, 41.0, 3.8,
              "GPIO_OUT.q \u2192 gpio_out[n]  \u00b7  0x018 R/W  \u00b7  "
              "SET / CLR / TGL write back", kind="ctrl", fs=6.6)
fl = fs.block(ax, FSX, 33.1, 41.0, 3.8,
              "GPIO_MODE \u2192 gpio_tx_en_o[n]  \u00b7  00 IN  01 OUT  "
              "10 OD0  11 OD1", kind="ctrl", fs=6.6)
pad = fs.block(ax, 110.4, 33.1, 12.5, 8.2, "PAD n", kind="plain", fs=7.6,
               sub="data + tx_en\n0 = RX, 1 = TX", sub_fs=6.0)

RB, FORKX = (62.4, 36.9), 64.3
fs.wire(ax, RB, (FSX, 35.0), via=[(FORKX, 36.9), (FORKX, 35.0)], color=fs.ACCENT)
fs.wire(ax, RB, (FSX, 39.4), via=[(FORKX, 36.9), (FORKX, 39.4)], color=fs.ACCENT)
fs.wire(ax, fl["e"], (pad["x"], 35.0), color=fs.ACCENT)
fs.wire(ax, fu["e"], (pad["x"], 39.4), color=fs.ACCENT)
fs.qa_report(fig)
print("L2b ok")

# =============================== L3  INPUT PATH
fs.label(ax, L, H3Y, "3   INPUT PATH   pad \u2192 TWO synchronizer registers \u2192 "
         "one-cycle edge detect \u2192 mask \u2192 sticky status \u2192 irq",
         fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.chip(ax, 70.0, H3Y, "\u25b6  START HERE \u2014 the two boxed flops",
        fs=6.6, fc="#FFFFFF", ec=fs.GREEN, tc="#1B5E20")
fs.label(ax, R, H3Y - 0.05, "gpio_input_stage  \u00b7  NrGPIOs = 32 instances, "
         "one per pin", fs=7.0, color=fs.GREY, ha="right")

CH = [
    (2.4, 8.0, "PAD", "plain", None, "gpio_in[n]\nasynchronous"),
    (13.2, 15.4, "STAGE 1", "periph", 1, "i_sync.reg_q[0]\nsync #(.STAGES=2)"),
    (31.4, 16.4, "STAGE 2", "periph", 2, "reg_q[1] = serial\n{reg_q[0], serial_i}"),
    (50.6, 11.8, "serial_q", "ctrl", None, "compare\nflop"),
    (65.2, 16.4, "edge detect", "mem", None,
     "r_edge = serial & ~serial_q\nf_edge = ~serial & serial_q"),
    (84.4, 12.6, "INTRPT_*_EN[n]", "ctrl", None, "rise | fall\nlvl hi | lvl lo"),
    (99.8, 13.4, "INTRPT_*_STATUS[n]", "resp", None, "sticky, hw-set\nbeats W1C"),
]
ch = []
ax.add_patch(Rectangle((12.2, 22.45), 36.6, 6.45, facecolor="none",
                       edgecolor="#548235", linewidth=1.6,
                       linestyle=(0, (4, 2.5)), zorder=2))
for i, (x, w, tx, kd, bd, sb) in enumerate(CH):
    ch.append(fs.block(ax, x, R3Y, w, R3H, tx, kind=kd, fs=6.9, sub=sb,
                       sub_fs=5.8, lw=2.4 if i in (1, 2) else 1.15))
    if bd:
        fs.badge(ax, x + 1.55, R3Y + R3H - 1.6, bd)
irq = fs.block(ax, 116.0, R3Y, 6.9, R3H, "irq", kind="alarm", fs=7.0,
               sub="global_\ninterrupt_o", sub_fs=5.4)

for i in range(len(ch) - 1):
    fs.wire(ax, ch[i]["e"], ch[i + 1]["w"], color=fs.ACCENT)
fs.wire(ax, ch[6]["e"], irq["w"], color=fs.ACCENT)

# signal names live in the free lane ABOVE the chain (gaps are only 2.8 wide)
for gx, nm in [(11.8, "gpio_in[n]"), (30.0, "reg_q[0]"), (49.2, "serial"),
               (63.8, "r_edge_o"), (83.0, "& mask"), (98.4, "OR"),
               (114.6, "pending")]:
    fs.label(ax, gx, SIGY, nm, fs=6.2, color=fs.ACCENT, weight="bold")
fs.qa_report(fig)
print("L3 ok")

# =============================== L4a  SYNCHRONIZER INSET + eqbox
fs.label(ax, L, IHY, "4   SYNCHRONIZER INSET   \u2014  what two flops buy",
         fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, IHY - 0.05, "WHY: a combinational read of the pad fires 2 cycles "
         "early and can glitch mid-cycle",
         fs=7.0, color=fs.RED, weight="bold", ha="right")

fs.eqbox(ax, L, INY, 40.0, INH,
         "settle  =  n_stages \u00d7 1 clk  =  2 clk      (n_stages = 2)\n"
         "GPIO_IN 0x014 = s_gpio_in_sync = serial_o = serial_q\n"
         "\u2192 software sees the pin 3 clk after it moved (2 sync + 1 compare)\n"
         "and never the raw wire. serial_q is the only flop-backed view.\n"
         "CFG[0]:  0 \u2192 irq = |edges (1 clk)    1 \u2192 irq = |pending (sticky)",
         fs=6.0)
fs.note(ax, 44.0, INY, 38.0, INH,
        "CLOCK GATE \u2014 tc_clk_gating #(.IS_FUNCTIONAL(0)),\n"
        "en_i = GPIO_EN[n].q. GPIO_EN[n] = 0 gates the clock\n"
        "off: reg_q, serial_q AND the GPIO_IN read-back all\n"
        "freeze at reset 0 \u2014 which is why the level interrupts\n"
        "also carry & s_gpio_en: a disabled pin would pend.",
        fs=6.0, kind="note")
fs.note(ax, 84.0, INY, 38.9, INH,
        "EDGE vs LEVEL \u2014 r_edge_o = serial & ~serial_q is\n"
        "combinational and one clk wide. A steady level with only\n"
        "RISE_EN set gives EXACTLY ONE interrupt, on the transition;\n"
        "hold the level and nothing more arrives. Level mode reads\n"
        "s_gpio_in_sync, so it re-asserts while the level holds.",
        fs=6.0, kind="alarm")
fs.qa_report(fig)
print("L4a ok")

# =============================== L4b  WAVEFORM LANES
ROWS = [("irq", "r_edge_o \u2192 INTRPT_RISE_STS", None),
        ("s2", "STAGE 2   reg_q[1] = serial", None),
        ("s1", "STAGE 1   i_sync.reg_q[0]", None),
        ("pad", "PAD gpio_in[3]   async", None)]
axl, ys, u = fs.lanes(fig, ROWS, X0, XEND, unit=U, left_pad=1.0, lane_gap=LGAP,
                      label_fs=6.6, sub_fs=6.0)
assert abs(u - U) < 1e-9
fs.cycle_guides(ax, X0, NCELL, U, bottom=1.4, top=12.2)

EDGEC = X0 + 1.55 * U
ax.add_line(Line2D([X0, EDGEC, EDGEC, XEND], [ys["pad"] - WHI] * 2 +
                   [ys["pad"] + WHI] * 2, color=fs.RED, lw=1.9,
                   solid_capstyle="round", solid_joinstyle="round", zorder=6))
ax.add_line(Line2D([EDGEC, EDGEC], [1.6, 12.2], color=fs.RED, lw=1.0,
                   ls=(0, (3, 2.5)), zorder=4))
for k, lv in (("s1", [0, 0, 1, 1, 1, 1, 1, 1, 1, 1]),
              ("s2", [0, 0, 0, 1, 1, 1, 1, 1, 1, 1]),
              ("irq", [0, 0, 0, 1, 0, 0, 0, 0, 0, 0])):
    fs.sigwave(ax, X0, lv, U, ys[k] - WHI, ys[k] + WHI,
               color=fs.GREEN if k == "irq" else fs.ACCENT, lw=1.9)

fs.txn_mark(ax, X0 + 3.5 * U, ys["irq"] + WHI,
            "the flag is armed by STAGE 2 \u2014 one clk AFTER reg_q[1] changes, "
            "never by the pad", xytext=(0, 6), fs=7.0)
fs.legend_row(ax, 2.6, 13.15, [("line", fs.RED, "PAD, asynchronous"),
                               ("line", fs.GREEN, "INTRPT_RISE_STS[n]")], fs=6.4)
fs.label(ax, R, 13.15, "stage 1 latches \u2192 stage 2 latches \u2192 flag: "
         "2 \u00d7 T_clk, edge-triggered", fs=6.6, color=fs.GREY, ha="right")
fs.label(ax, EDGEC - 0.7, 0.8, "pad edge", fs=6.0, color=fs.RED, weight="bold",
         ha="right")
for c in (2, 3):
    fs.label(ax, X0 + (c + 0.5) * U, 0.8, f"clk {c}", fs=6.0, color=fs.GREY)
fs.qa_report(fig)
print("L4b ok")

# =============================== L5  FOOTER
fs.footer(fig,
          "Two flops is the minimum clean input bit: flop 1 can metastable, flop "
          "2 gives it a full clock, and GPIO_IN plus every mask read flop 2 only "
          "\u2014 wire the pad to a register and software reads a bit that never "
          "existed.")

# ---- QA / SAVE ----
fs.qa_report(fig)
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig14_gpio_internals.png")