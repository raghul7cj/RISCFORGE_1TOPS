"""
fig32 - GPIO register map + output path, extracted from fig14 (d_gpio.py).

Grounded in the SAME sources the parent used, plus two lines re-read from
gpio.sv for the MODE decode and the SET/CLR/TGL write-back:
  gpio_reg_pkg.sv : register names, index order, GPIO_PERMIT
  gpio_reg_top.sv : reggen block, BlockAw = 11
  gpio.sv:168     : assign gpio_out[n] = s_reg2hw.gpio_out[n].q
  gpio.sv:173-186 : 2'b00 INPUT_ONLY / 2'b01 OUTPUT_ACTIVE /
                    2'b10 OPEN_DRAIN0 / 2'b11 OPEN_DRAIN1 -> gpio_tx_en_o[n]
  gpio.sv:201-213 : SET / CLEAR / TOGGLE write gpio_out with de = 1

The parent fig14 is FROZEN.  This script only re-composes its sections 1 and 2.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
import _figstyle as fs
from matplotlib.patches import Rectangle

TITLE = ("Nineteen registers and one rule: SET / CLR / TGL write GPIO_OUT "
         "atomically and MODE decides TX from RX \u2014\nthere is no port-update "
         "FSM")
SUB = ("read the table first, then down the columns \u2014 1 all 19 registers, "
       "with real names and offsets  \u00b7 2 the output path and the 2-bit MODE "
       "encoding  \u00b7 3 why reading 0x018 is atomic  \u00b7 4 what people "
       "expect but the RTL does not have")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
L, R = 2.4, 122.9

# ------------------------------------------------------------------ geometry
H1Y = 56.2                     # 1  header
ROWH, HDRH = 2.6, 2.3
TLY = 33.9                     # bottom of the data rows
NROW = 7                       # tallest group
HDRY = TLY + NROW * ROWH       # column-header row sits on top
GLY = 31.9                     # 2  glossary line
GY = (0, 7, 13)                # first register index of each of 3 groups
GX, GW = (2.4, 43.2, 84.0), 39.0

REGS = [
    ("0x000", "GPIO_INFO", "R", "[9:0] = 32 pins"),
    ("0x004", "GPIO_CFG", "R/W", "[0] glbl, [1] pin_lvl"),
    ("0x008", "GPIO_GPIO_MODE_0", "R/W", "2 bits/pin, GPIO[15:0]"),
    ("0x00C", "GPIO_GPIO_MODE_1", "R/W", "same, GPIO[31:16]"),
    ("0x010", "GPIO_GPIO_EN", "R/W", "input sampling enable"),
    ("0x014", "GPIO_GPIO_IN", "R", "\u2190 s_gpio_in_sync"),
    ("0x018", "GPIO_GPIO_OUT", "R/W", "atomic read-back"),
    ("0x01C", "GPIO_GPIO_SET", "W", "1 \u2192 set gpio_out bit"),
    ("0x020", "GPIO_GPIO_CLEAR", "W", "1 \u2192 clear gpio_out bit"),
    ("0x024", "GPIO_GPIO_TOGGLE", "W", "1 \u2192 invert gpio_out bit"),
    ("0x028", "GPIO_INTRPT_RISE_EN", "R/W", "rising-edge mask"),
    ("0x02C", "GPIO_INTRPT_FALL_EN", "R/W", "falling-edge mask"),
    ("0x030", "GPIO_INTRPT_LVL_HIGH_EN", "R/W", "level-high mask"),
    ("0x034", "GPIO_INTRPT_LVL_LOW_EN", "R/W", "level-low mask"),
    ("0x038", "GPIO_INTRPT_STATUS", "R/W1C", "OR of the four below"),
    ("0x03C", "GPIO_INTRPT_RISE_STATUS", "R/W1C", "sticky, hw-set"),
    ("0x040", "GPIO_INTRPT_FALL_STATUS", "R/W1C", "sticky"),
    ("0x044", "GPIO_INTRPT_LVL_HIGH_STATUS", "R", "hw-set sticky"),
    ("0x048", "GPIO_INTRPT_LVL_LOW_STATUS", "R", "hw-set sticky"),
]
KEY = {5, 6, 7, 8, 9}          # input read + the atomic-write group
TLYE = TLY + len(REGS) * ROWH

print(f"canvas = {XW:.2f} x {YH:.2f} units   (x content {L} .. {R})")
print(f"rows {TLY:.2f} .. {HDRY:.2f}   hdr {HDRY:.2f} .. {HDRY + HDRH:.2f}"
      f"   glossary {GLY:.2f}")
assert HDRY + HDRH < H1Y - 1.0
for g in GX:
    assert g + GW <= R + 0.3, g
print("L1 ok")

# =============================== L2  THE 19-REGISTER TABLE
fs.label(ax, L, H1Y, "1   THE REGISTER FILE   19 \u00d7 32-bit, APB[3], "
         "lowRISC reggen  \u00b7  base 0x4000_3000", fs=7.6,
         color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, H1Y - 0.05, "block decode BlockAw = 11  \u00b7  "
         "GPIO_PERMIT[0] = 4'b0111: INFO is the only partial-write register",
         fs=7.0, color=fs.GREY, ha="right")

HCOLS = ((0.8, "OFFSET"), (6.4, "REGISTER"), (23.6, "TYPE"),
         (27.0, "WHAT IT DOES"))
for g in range(3):
    ax.add_patch(Rectangle((GX[g], HDRY), GW, HDRH, facecolor="#E8EEF7",
                           edgecolor="#9BB0CC", linewidth=0.9, zorder=2))
    for cx, t in HCOLS:
        fs.label(ax, GX[g] + cx, HDRY + HDRH / 2.0, t, fs=6.4, color="#1F3864",
                 weight="bold", ha="left")


def row(g, i, off, name, typ, desc, hot):
    # GY[g] is the FIRST (lowest-offset) register of the group and must appear
    # at the TOP of the band, so the row index counts down, not up.
    x, y = GX[g], TLY + (NROW - 1 - (i - GY[g])) * ROWH
    ax.add_patch(Rectangle(
        (x, y), GW, ROWH, facecolor="#FFF6DC" if hot else "#FFFFFF",
        edgecolor="#C8C8C8", linewidth=0.7, zorder=2))
    if hot:
        ax.add_patch(Rectangle((x, y), 0.42, ROWH, facecolor=fs.ORANGE,
                               edgecolor="none", zorder=3))
    fs.label(ax, x + 0.8, y + ROWH / 2.0, off, fs=6.3, color=fs.ACCENT,
             weight="bold", ha="left")
    fs.label(ax, x + 6.4, y + ROWH / 2.0, name, fs=6.3, color=fs.TXT,
             weight="bold", ha="left")
    fs.label(ax, x + 23.6, y + ROWH / 2.0, typ, fs=6.2, color=fs.GREY,
             ha="left")
    fs.label(ax, x + 27.0, y + ROWH / 2.0, desc, fs=6.2, color=fs.TXT,
             ha="left")


for g in range(3):
    for i in range(GY[g], GY[g] + (7 if g == 0 else 6)):
        off, name, typ, desc = REGS[i]
        row(g, i, off, name, typ, desc, i in KEY)

fs.label(ax, L, GLY, "R = read-only  \u00b7  R/W = read/write  \u00b7  "
         "W = write-only  \u00b7  W1C = write 1 to clear (writing 0 leaves the "
         "bit alone)  \u00b7  hw-set = the bit is set by hardware, not by "
         "software  \u00b7  OD0 / OD1 = open-drain 0 / 1",
         fs=6.6, color="#3F3F3F", ha="left")
fs.label(ax, L, GLY - 2.3, "highlighted rows: GPIO_IN is the only input read, "
         "and GPIO_OUT / SET / CLEAR / TOGGLE are the four registers the output "
         "path is built from", fs=6.6, color=fs.ORANGE, ha="left")
fs.qa_report(fig)
print("L2 ok")

# =============================== L3  COLUMN A -- OUTPUT PATH + MODE ENCODING
H2Y, AY0 = 28.4, 1.6
AX0, AW = 2.4, 41.6                    # column A x extent
fs.label(ax, AX0, H2Y, "2   OUTPUT PATH   two registers in, two signals out",
         fs=7.6, color=fs.ACCENT, weight="bold", ha="left")
fs.chip(ax, 35.6, H2Y, "\u25b6  START HERE", fs=6.6, fc="#FFFFFF", ec=fs.GREEN,
        tc="#1B5E20")

OY, OH = 19.8, 3.3                     # source rows (row B sits 4.2 below)
src = [
    fs.block(ax, AX0, OY, 14.6, OH, "GPIO_GPIO_OUT", kind="ctrl",
             fs=6.6, sub="0x018  R/W  \u00b7  the level", sub_fs=5.8),
    fs.block(ax, AX0, OY + 4.2, 14.6, OH, "GPIO_GPIO_MODE_0 / _1", kind="ctrl",
             fs=6.6, sub="0x008 / 0x00C  \u00b7  2 bits per pin", sub_fs=5.8),
]
mid = [
    fs.block(ax, 19.4, OY, 12.6, OH, "gpio_out[n]", kind="mem", fs=6.4,
             sub="= reg2hw.gpio_out[n].q", sub_fs=5.6),
    fs.block(ax, 19.4, OY + 4.2, 12.6, OH, "gpio_tx_en_o[n]", kind="mem",
             fs=6.4, sub="decoded from MODE", sub_fs=5.6),
]
padb = fs.block(ax, 34.4, OY, 9.8, 2 * OH + 0.9, "PAD n", kind="plain",
                fs=7.0, sub="data + tx_en\n0 = RX, 1 = TX", sub_fs=5.6)
for a2, b2 in zip(src, mid):
    fs.wire(ax, a2["e"], b2["w"], color=fs.ACCENT)
for b2 in mid:
    fs.wire(ax, b2["e"], (padb["x"], b2["c"][1]), color=fs.ACCENT)
fs.qa_report(fig)
print("L3 ok")

# --- 2b  the 2-bit MODE encoding, verbatim from the case statement in gpio.sv
MRH, MTOP = 2.35, 7.0
fs.label(ax, AX0, MTOP + 4 * MRH + 0.5, "2 bits per pin in GPIO_GPIO_MODE_0/1 "
         "\u2192 the whole TX decision   (gpio.sv)", fs=6.8, color="#1F3864",
         weight="bold", ha="left")
MODE = [("00", "INPUT_ONLY", "0", "receive: pad drives the input path"),
        ("01", "OUTPUT_ACTIVE", "1", "push-pull \u2014 always drive"),
        ("10", "OPEN_DRAIN0", "gpio_out[n].q", "drive only while the bit = 1"),
        ("11", "OPEN_DRAIN1", "~gpio_out[n].q", "drive only while the bit = 0")]
for i, (code, nm, tx, meaning) in enumerate(MODE):
    y = MTOP + (3 - i) * MRH
    ax.add_patch(Rectangle((AX0, y), AW, MRH - 0.15,
                           facecolor="#EDF5E7" if i < 2 else "#F4F4F4",
                           edgecolor="#B9C9B4", linewidth=0.8, zorder=2))
    fs.label(ax, AX0 + 0.8, y + (MRH - 0.15) / 2.0, code, fs=7.0,
             color=fs.ACCENT, weight="bold", ha="left")
    fs.label(ax, AX0 + 4.4, y + (MRH - 0.15) / 2.0, nm, fs=6.6, color="#1B5E20",
             weight="bold", ha="left")
    fs.label(ax, AX0 + 17.4, y + (MRH - 0.15) / 2.0, tx, fs=6.4,
             color=fs.TXT, ha="left")
    fs.label(ax, AX0 + 24.4, y + (MRH - 0.15) / 2.0, meaning, fs=6.2,
             color="#3F3F3F", ha="left")
fs.label(ax, AX0, MTOP - 1.6, "no pin can be an input and an output at once \u2014 "
         "MODE alone decides which", fs=6.4, color=fs.GREY, ha="left")
fs.qa_report(fig)
print("L3b ok")

# =============================== L4  COLUMN B -- THE ATOMIC READ-BACK PROOF
BX0, BW = 46.6, 40.0
fs.label(ax, BX0, H2Y, "3   THE ONE RULE: SET / CLR / TGL write\n"
         "GPIO_OUT back, with de = 1", fs=7.6, color=fs.ACCENT,
         weight="bold", ha="left", va="top")

fs.eqbox(ax, BX0, 18.8, BW, 5.6,
         "gpio.sv, inside the APB write of SET / CLEAR / TOGGLE:\n"
         "   s_hw2reg.gpio_out[n].d  = 1'b1;   .de = 1'b1;   // SET\n"
         "   s_hw2reg.gpio_out[n].d  = 1'b0;   .de = 1'b1;   // CLEAR\n"
         "   s_hw2reg.gpio_out[n].d  = ~reg2hw.gpio_out[n].q;  .de = 1;\n"
         "                                    // TOGGLE",
         fs=6.0)

fs.note(ax, BX0, 1.6, BW, 16.6,
        "de = 1 is the whole trick. It is the write-enable of the GPIO_OUT\n"
        "register inside the reggen block, so the same APB write that\n"
        "computes the new bit also pushes it into GPIO_OUT.q \u2014 one cycle,\n"
        "one address, no read-modify-write.\n"
        "\n"
        "Consequence: read-modify-write is not needed and not possible.\n"
        "Software never has to read 0x018, mask it and write it back, so\n"
        "there is no window in which an interrupt handler \u2014 or another\n"
        "bus master \u2014 can change a pin underneath the update.\n"
        "\n"
        "GPIO_OUT is R/W, so reading 0x018 always returns the value that is\n"
        "currently on the pads. The read-back is atomic by construction,\n"
        "not by convention: there is no second register to get out of step\n"
        "and no status bit to poll.",
        fs=6.1, kind="note")
fs.qa_report(fig)
print("L4 ok")

# =============================== L5  COLUMN C -- NO PORT-UPDATE FSM
def note_auto(x, y_top, w, s, f=6.2, kind="note", pad=1.0):
    """note() whose height is derived from the text, growing downward."""
    fig.canvas.draw()
    tmp = ax.text(0, -1e5, s, fontsize=f, linespacing=1.42, clip_on=False)
    h = tmp.get_window_extent(
        renderer=fig.canvas.get_renderer()).height * fs.upu(ax) + 2.0 * pad
    tmp.remove()
    return fs.note(ax, x, y_top - h, w, h, s, fs=f, kind=kind)


CX0, CW2 = 89.4, 33.5
fs.label(ax, CX0, H2Y, "4   NO PORT-UPDATE FSM", fs=7.6, color=fs.RED,
         weight="bold", ha="left")
note_auto(CX0, 27.0, CW2,
          "Search gpio.sv and gpio_reg_top.sv and you will not\n"
          "find one: there is no state machine, no update-enable\n"
          "handshake and no busy bit between the APB write and\n"
          "the pad. What exists instead is a REGISTER-WRITE\n"
          "ORDER \u2014 and it is a convention, not enforcement:\n"
          "  1. write MODE / EN first, so the pin is configured\n"
          "     before it is driven;\n"
          "  2. then SET, CLEAR or TOGGLE to change it;\n"
          "  3. read 0x018 to confirm \u2014 no polling needed.\n"
          "Each of those is an independent APB write. Nothing\n"
          "waits, nothing retries, no state is held between them.",
          f=6.2, kind="alarm")

note_auto(CX0, 11.4, CW2,
          "WHAT PEOPLE EXPECT vs WHAT IS HERE\n"
          "\u2717  a port-update FSM sequencing EN, MODE and OUT\n"
          "   \u2014 none; all three are independent registers\n"
          "\u2717  a DONE / READY bit to poll after a port write\n"
          "   \u2014 none; the write completes in one clk\n"
          "\u2717  shadow and output registers to keep in step\n"
          "   \u2014 one register, GPIO_OUT, read/write",
          f=6.2, kind="note")
fs.qa_report(fig)
print("L5 ok")

# =============================== L6  FOOTER
fs.footer(fig,
          "Nineteen registers, no hidden state: GPIO_OUT plus SET / CLEAR / "
          "TOGGLE are enough to drive any pin pattern without ever reading it "
          "back first, and GPIO_MODE alone decides whether a pin listens or "
          "drives \u2014 so the 'sequencing' in this block is the order software "
          "writes registers, not a state machine in the RTL.")

fs.qa_report(fig)
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig32_gpio_register_map_and_output.png")
