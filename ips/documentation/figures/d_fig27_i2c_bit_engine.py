"""fig27 -- STEP 2 of fig11, extracted and re-composed as a standalone figure:
the I2C quarter-bit SCL engine (i2c_master_bit_ctrl.sv) and the micro-state
cost equation.

Parent fig11 is FROZEN; this file copies only its STEP 2 band.

RTL read (same 2 files the parent used):
  rtl/ips/apb_i2c-master/apb_i2c.sv                (APB wrapper, r_pre divider)
  rtl/ips/apb_i2c-master/i2c_master_bit_ctrl.sv   (micro-phases, clk_en, slave_wait)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ============================ LANE BUDGET (units, 1u = 0.1 inch) ==========
R_X = 7.4                              # rotated band-label rail
B1_Y, B1_H = 47.4, 7.6                 # 1  APB inputs -> clk_en   47.4..55.0
B2_Y, B2_H = 34.6, 7.0                 # 2  five quarter-phases    34.6..41.6
B3_Y, B3_H = 25.8, 5.4                 # 3  command -> micro-states 25.8..31.2
B4_Y, B4_H = 13.8, 9.8                 # 4  cost eq + clock stretch 13.8..23.6
G_Y, G_H = 4.0, 8.0                    # glossary                  4.0..12.0

TITLE = ("One byte command costs five SCL quarter-phases, each one clk_en tick of "
         "(r_pre + 1) \u00d7 HCLK")
SUB = ("START HERE at (1), the APB register block, top left.  Read top to bottom:  "
       "(1)-(3) the prescaler that makes the tick  ->  (4) the five quarter-phases "
       "of one command  ->  (5) what each command costs  ->  (6) the cost equation "
       "and the slave's clock stretch")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}")
print(f"  b1 {B1_Y}..{B1_Y+B1_H} | b2 {B2_Y}..{B2_Y+B2_H} | "
      f"b3 {B3_Y}..{B3_Y+B3_H} | b4 {B4_Y}..{B4_Y+B4_H} | gloss {G_Y}..{G_Y+G_H}")
fs.pad_limits(ax, 0.06)
B1CY = B1_Y + B1_H / 2.0

# ============================ BAND 1 : APB INPUTS -> clk_en ===============
fs.label(ax, R_X, B1CY, "1 \u00b7 APB INPUTS", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
fs.label(ax, 5.6, B1CY, "apb_i2c.sv", fs=5.8, color=fs.GREY, rot=90)

fs.block(ax, 13.0, B1_Y, 29.0, B1_H,
         "APB slave @ 0x4000_0000  (APB[0])\n"
         "REG_PRE  0x00 (16 b) \u2014 prescale value r_pre\n"
         "REG_CTRL 0x04 \u2014 [7] s_core_en   [6] s_ien",
         kind="bus", fs=6.2, bold=True)
fs.badge(ax, 14.7, B1_Y + B1_H + 1.15, 1)

fs.wire(ax, (42.0, B1CY), (48.0, B1CY), label="r_pre", label_fs=6.0)

fs.block(ax, 48.0, B1_Y, 30.0, B1_H,
         "bit_ctrl.clk_cnt \u2014 a 16-bit down-counter\n"
         "loaded with r_pre, decrements every HCLK,\n"
         "pulses clk_en = 1 for ONE clk when it hits 0",
         kind="ctrl", fs=6.2, bold=True)
fs.badge(ax, 49.7, B1_Y + B1_H + 1.15, 2)

fs.wire(ax, (78.0, B1CY), (84.0, B1CY), label="clk_en", label_fs=6.0,
        color=fs.GREEN)

fs.block(ax, 84.0, B1_Y, 35.0, B1_H,
         "clk_en is the ONLY thing that advances the micro-state:\n"
         "if (clk_en) case (cmd) c_state <= start_a / stop_a / ...\n"
         "no clk_en  \u21d2  the engine sits in the state it is already in",
         kind="periph", fs=6.2, bold=True)
fs.badge(ax, 85.7, B1_Y + B1_H + 1.15, 3)
print("B1 ok")

# ==================== BAND 2 : THE FIVE SCL QUARTER-PHASES ================
# Boxes and waveforms copied verbatim from the parent fig11 STEP 2 lane.
CW, PITCH, CY0, CH, X0 = 20.0, 21.0, 36.0, 4.4, 13.0
PH = ["start_a\nSCL low, SDA released\n(sda_oen <= 1)",
      "start_b\nSCL released high\n(scl_oen <= 1)",
      "start_c\nSDA pulled LOW\n= START condition",
      "start_d\nhold SDA low, SCL high\n(one quarter phase)",
      "start_e\nSCL pulled low\ncmd_ack <= 1 \u2192 byte FSM"]
PK = ["mux", "ctrl", "write", "ctrl", "resp"]

fs.label(ax, R_X, B2_Y + B2_H / 2.0, "2 \u00b7 PHASES", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
for i in range(5):
    fs.block(ax, X0 + i * PITCH, CY0, CW, CH, PH[i], kind=PK[i], fs=5.6,
             bold=True)
    if i:
        fs.wire(ax, (X0 + i * PITCH - 1.1, CY0 + CH / 2.0),
                (X0 + i * PITCH, CY0 + CH / 2.0), head_scale=7.0, lw=1.4,
                label="1 clk_en" if i == 2 else None, label_fs=5.4)

fs.badge(ax, (X0 + X0 + 4 * PITCH + CW) / 2.0, CY0 + CH + 1.15, 4)
fs.label(ax, (X0 + X0 + 4 * PITCH + CW) / 2.0, 43.4,
         "the five quarter-phases of ONE command \u2014 START shown here; "
         "STOP / WRITE / READ use the same A/B/C/D shape",
         fs=5.8, color=fs.GREY)

fs.sigwave(ax, X0, [0, 1, 1, 1, 0], PITCH, 34.9, 35.9, color=fs.ACCENT, lw=2.0)
fs.sigwave(ax, X0, [1, 1, 0, 0, 0], PITCH, 33.2, 34.1, color=fs.GREEN,
           dashed=True, lw=1.8)
fs.cycle_guides(ax, X0, 5, PITCH, bottom=32.9, top=41.4, color="#EAEAEA")
fs.label(ax, 12.2, 35.4, "SCL", fs=6.2, weight="bold", color=fs.ACCENT, ha="right")
fs.label(ax, 12.2, 33.65, "SDA", fs=6.2, weight="bold", color=fs.GREEN, ha="right")
print("B2 ok")

# ============ BAND 3 : WHICH COMMAND COSTS HOW MANY MICRO-STATES ==========
fs.label(ax, R_X, B3_Y + B3_H / 2.0, "3 \u00b7 CMDS", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
CMDS = [("START", "start_a  start_b  start_c\nstart_d  start_e", "5 ticks", "write"),
        ("STOP",  "stop_a  stop_b\nstop_c  stop_d", "4 ticks", "resp"),
        ("WRITE", "wr_a  wr_b\nwr_c  wr_d", "4 ticks", "periph"),
        ("READ",  "rd_a  rd_b\nrd_c  rd_d", "4 ticks", "periph")]
CW3, GAP3 = 23.0, 2.0
for i, (nm, sts, tk, kd) in enumerate(CMDS):
    x = 13.0 + i * (CW3 + GAP3)
    fs.block(ax, x, B3_Y, CW3, B3_H,
             "%s    cmd = I2C_CMD_%s\n%s\n%s" % (nm, nm, sts, tk),
             kind=kd, fs=5.8, bold=True)
fs.badge(ax, (13.0 + 13.0 + 3 * (CW3 + GAP3) + CW3) / 2.0, B3_Y + B3_H + 1.15, 5)

print("B3 ok")

# ============ BAND 4 : THE COST EQUATION =================================
fs.label(ax, R_X, B4_Y + B4_H / 2.0, "4 \u00b7 COST", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
fs.eqbox(ax, 13.0, 16.4, 35.0, 4.8,
         "cost of ONE micro-state = 1 clk_en = (r_pre + 1) \u00d7 HCLK\n"
         "cost of ONE command = its micro-state count \u00d7 (r_pre + 1) \u00d7 HCLK",
         fs=5.8)
fs.badge(ax, 14.7, 22.35, 6)
print("B4 ok")

# ==================== CLOCK STRETCH : slave_wait ==========================
fs.label(ax, 52.5, 23.3, "CLOCK STRETCH \u2014 the slave can make any command "
                         "longer, never shorter",
         fs=6.4, color=fs.RED, weight="bold", ha="left")
ST = [("master releases SCL high\n(scl_oen <= 1)", "ctrl"),
      ("slave keeps SCL LOW\n(clock stretching)", "periph"),
      ("slave_wait = 1\nclk_en = 0, cnt frozen", "alarm"),
      ("c_state does NOT advance\nthe bit engine waits here", "alarm")]
CW4, GAP4, CY4, CH4 = 15.0, 1.8, 18.6, 4.0
for i, (t, kd) in enumerate(ST):
    x = 52.5 + i * (CW4 + GAP4)
    fs.block(ax, x, CY4, CW4, CH4, t, kind=kd, fs=5.6, bold=True)
    if i:
        fs.wire(ax, (x - GAP4, CY4 + CH4 / 2.0), (x, CY4 + CH4 / 2.0),
                head_scale=7.0, lw=1.4)

RB = 52.5 + 4 * CW4 + 3 * GAP4
fs.wire(ax, (RB, CY4), (52.5, CY4 + CH4 / 2.0),
        via=[(RB, 16.2), (51.0, 16.2), (51.0, CY4 + CH4 / 2.0)],
        back=True, color=fs.ORANGE, lw=1.5)
fs.label(ax, 52.5, 14.9,
         "slave finally releases SCL \u2192 slave_wait = 0 \u2192 clk_en resumes "
         "in the SAME micro-state: no bit is lost and none is repeated",
         fs=5.8, color=fs.ORANGE, ha="left")
print("stretch ok")

# ============================ GLOSSARY =====================================
fs.note(ax, 13.0, G_Y, 51.0, G_H,
        "GLOSSARY \u2014 read this once and the figure needs no other file\n"
        "HCLK \u2014 the bus clock the whole I2C block runs on. There is no separate\n"
        "I2C clock: the SCL line is built from software-scheduled HCLK ticks.\n"
        "r_pre \u2014 the 16-bit prescale value in REG_PRE (0x00). It is the ONLY\n"
        "speed knob the design gives software; clk_en follows it, nothing else does.",
        fs=5.8)
fs.note(ax, 66.0, G_Y, 53.5, G_H,
        "oen \u2014 scl_oen / sda_oen, the two OUTPUT ENABLES, and they are ACTIVE LOW:\n"
        "     oen <= 1  RELEASES the line (the slave or the pull-up may drive it)\n"
        "     oen <= 0  the master pulls the line LOW\n"
        "quarter-phase / micro-state \u2014 one A/B/C/D/i state inside a command chain;\n"
        "four or five of them make one command, a fraction of one SCL bit period.",
        fs=5.8)

fs.footer(fig, "Nothing here is a free-running clock divider producing SCL \u2014 there "
               "is only a down-counter that decides when the engine is allowed to "
               "take its next micro-state. That is why a command costs a countable "
               "number of (r_pre + 1) \u00d7 HCLK ticks, and why the only variable part "
               "of a transaction is how long a slave chooses to hold SCL low. A whole "
               "byte is a RUN of these command chains \u2014 one per bit, each with its "
               "own ACK bit \u2014 never a single one.")

fs.pad_limits(ax, 0.06)
print(fs.qa_report(fig))
fs.save(fig, "fig27_i2c_bit_engine.png")


