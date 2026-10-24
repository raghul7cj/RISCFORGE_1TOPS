"""fig28 -- STEP 3 of fig11, extracted and re-composed as a standalone figure:
the three ways execution leaves the I2C byte-sequencer main chain.

Parent fig11 is FROZEN; this file copies only its STEP 3 branch lanes.

RTL read (same 2 files the parent used):
  rtl/ips/apb_i2c-master/i2c_master_byte_ctrl.sv  (byte sequencer states, ack_out)
  rtl/ips/apb_i2c-master/i2c_master_bit_ctrl.sv  (al = arbitration lost / bus error)
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
R_X = 7.4                              # rotated rail
M_Y, M_H = 48.4, 4.4                   # main chain (context)  48.4..52.8
N_Y, N_H = 40.2, 6.0                   # lane 1  NACK           40.2..46.2
S_Y, S_H = 27.6, 8.0                   # lane 2  SR             27.6..35.6
A_Y, A_H = 18.8, 5.8                   # lane 3  arbitration    18.8..24.6
V_Y, V_H = 11.2, 5.8                   # verdict                11.2..17.0
G_Y, G_H = 4.6, 6.0                    # glossary                4.6..10.6

TX0, TX1 = 13.0, 38.0                  # column 1  trigger
RX0, RX1 = 42.0, 72.0                  # column 2  what the RTL does
VX0, VX1 = 76.0, 119.0                 # column 3  verdict / consequence

TITLE = ("Three ways off the main chain \u2014 a NACK, a repeated START and "
         "arbitration-lost \u2014 and only one of them the FSM can act on")
SUB = ("START HERE at (1), the grey main chain across the top: that is the path every "
       "lane below leaves.  Then read the three lanes top to bottom, each one left to "
       "right:  what TRIGGERS it  ->  what the RTL ACTUALLY does  ->  VERDICT")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}")
print(f"  main {M_Y}..{M_Y+M_H} | NACK {N_Y}..{N_Y+N_H} | SR {S_Y}..{S_Y+S_H} | "
      f"AL {A_Y}..{A_Y+A_H} | verdict {V_Y} | gloss {G_Y}")
fs.pad_limits(ax, 0.06)

# ================== BAND 1 : THE MAIN CHAIN, FOR CONTEXT ONLY ============
fs.label(ax, R_X, M_Y + M_H / 2.0, "1 \u00b7 MAIN CHAIN", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
fs.badge(ax, 14.7, 54.2, 1)
fs.label(ax, 18.0, 54.2,
         "CONTEXT ONLY \u2014 i2c_master_byte_ctrl.sv.  Every lane below leaves one "
         "of these five boxes.",
         fs=6.0, color=fs.GREY, ha="left")

CHAIN = ["ST_IDLE\n5'b0_0000", "ST_START\n5'b0_0001",
         "ST_WRITE / ST_READ\n5'b0_0100 / 5'b0_0010",
         "ST_ACK\n5'b0_1000   \u25c0 the ACK bit", "ST_STOP\n5'b1_0000"]
CWD, CGP = 18.0, 2.6
MCY = M_Y + M_H / 2.0
for i, t in enumerate(CHAIN):
    x = TX0 + i * (CWD + CGP)
    fs.block(ax, x, M_Y, CWD, M_H, t, kind="plain", fs=5.8, bold=True,
             tc=fs.GREY)
    if i:
        fs.wire(ax, (x - CGP, MCY), (x, MCY), color=fs.GREY, lw=1.3,
                head_scale=7.0)
print("main chain ok")

# ============ LANE 2 : NACK ===============================================
def lane_head(y, n, txt, color):
    fs.badge(ax, 14.7, y, n)
    fs.label(ax, 18.0, y, txt, fs=6.4, color=color, weight="bold", ha="left")


def lane(y, h, trig, rtl, verd, kt, kr, kv, fs1=5.8, fs2=5.8, fs3=5.6):
    ncy = y + h / 2.0
    fs.block(ax, TX0, y, TX1 - TX0, h, trig, kind=kt, fs=fs1, bold=True)
    fs.block(ax, RX0, y, RX1 - RX0, h, rtl, kind=kr, fs=fs2, bold=True)
    fs.block(ax, VX0, y, VX1 - VX0, h, verd, kind=kv, fs=fs3, bold=True)
    fs.wire(ax, (TX1, ncy), (RX0, ncy), color=fs.GREY, lw=1.4, head_scale=8.0)
    fs.wire(ax, (RX1, ncy), (VX0, ncy), color=fs.GREY, lw=1.4, head_scale=8.0)


lane_head(47.2, 2, "NACK  \u2014  the slave did not acknowledge this byte",
          fs.RED)
lane(N_Y, N_H,
     "TRIGGER  \u2014  leaves ST_ACK\n"
     "ack_out == 1, because the slave\n"
     "left SDA HIGH through the\n"
     "9th (ACK) clock of the byte",
     "WHAT THE RTL DOES  \u2014  nothing\n"
     "The byte FSM has NO NACK state\n"
     "and NO error state. ST_ACK goes on\n"
     "to ST_IDLE / ST_STOP either way.",
     "VERDICT  \u2014  SOFTWARE CONTRACT, NOT A TRANSITION\n"
     "ack_out is only a readable output bit, copied into the APB read data.\n"
     "The NACK \u2192 STOP path is a SOFTWARE obligation: the driver must read the\n"
     "bit and issue cmd = STOP itself. Nothing in the RTL enforces it.",
     "alarm", "ctrl", "alarm", fs1=5.8, fs2=5.6, fs3=5.6)
print("lane NACK ok")

# ============ LANE 3 : REPEATED START (SR) ================================
lane_head(36.6, 3, "SR  \u2014  repeated START: a second address without a STOP",
          fs.GREEN)
SCY = S_Y + S_H / 2.0
fs.block(ax, TX0, S_Y, TX1 - TX0, S_H,
         "TRIGGER  \u2014  leaves ST_IDLE\n"
         "software issues cmd = START\n"
         "again while still in ST_IDLE\n"
         "and BEFORE any STOP has been\n"
         "clocked (write = 0, read = 0)",
         kind="ctrl", fs=5.8, bold=True)
fs.block(ax, RX0, S_Y, RX1 - RX0, S_H,
         "WHAT THE RTL DOES\n"
         "ST_START simply runs a second\n"
         "time: start_a..start_e once\n"
         "more, and NO STOP bit is\n"
         "clocked in between the two\n"
         "addresses",
         kind="ctrl", fs=5.8, bold=True)
fs.wire(ax, (TX1, SCY), (RX0, SCY), color=fs.GREY, lw=1.4, head_scale=8.0)
fs.wire(ax, (RX1, SCY), (VX0, SCY), color=fs.GREY, lw=1.4, head_scale=8.0)
fs.eqbox(ax, VX0, S_Y, VX1 - VX0, S_H,
         "REPEATED-START RULE   \u2014   read this before reusing the bus\n"
         "SCL is released high FIRST, and only then is SDA pulled low,\n"
         "while SCL is high.  Never clock a STOP in between: a STOP here\n"
         "would release the bus to any other master in the middle of an\n"
         "address, and both transactions would be silently corrupted.",
         fs=6.0, fc=fs.S_ALARM, ec=fs.RED, color="#8B1A1A")
print("lane SR ok")

# ============ LANE 4 : ARBITRATION LOST / BUS ERROR (i2c_al) =============
lane_head(25.6, 4, "i2c_al  \u2014  arbitration lost or bus error, from any state",
          fs.ORANGE)
lane(A_Y, A_H,
     "TRIGGER  \u2014  leaves ANY state\n"
     "al = (sda_chk & ~sSDA & sda_oen)\n"
     "   | (|c_state & sto_condition\n"
     "       & ~cmd_stop)\n"
     "asynchronous: true in every state",
     "WHAT THE RTL DOES\n"
     "The one hard branch in this figure:\n"
     "force c_state <= idle straight out\n"
     "of any state. No STOP is clocked\n"
     "and ack_out is left untouched.",
     "VERDICT  \u2014  A REAL RTL TRANSITION\n"
     "This is the only branch the FSM acts on by itself, and the only one\n"
     "that a bus monitor outside the block can see. A NACK and a repeated\n"
     "START both depend entirely on software doing the right thing.",
     "periph", "alarm", "resp", fs1=5.6, fs2=5.6, fs3=5.6)
print("lane AL ok")

# ============ VERDICT ====================================================
lane_head(17.8, 5, "THE HONEST SUMMARY", fs.ACCENT)
fs.note(ax, 13.0, V_Y, 106.0, V_H,
        "Only 1 of these 3 is a hardware transition.  A NACK is a bit that software must read and "
        "act on, and a repeated START is a path that software must choose;  arbitration-lost "
        "is the only branch the byte FSM takes on its own.", fs=5.8)
print("verdict ok")

# ============================ GLOSSARY =====================================
fs.note(ax, 13.0, G_Y, 51.0, G_H,
        "GLOSSARY \u2014 read once, then the figure needs no other file\n"
        "ack_out \u2014 the ACK bit the slave returned. A plain output copied into the\n"
        "   APB read data: not a state, not an error flag, and nothing reacts to it.\n"
        "NACK \u2014 NOT-acknowledge: the slave left SDA HIGH on the ACK clock.",
        fs=6.2)
fs.note(ax, 66.0, G_Y, 53.5, G_H,
        "SR \u2014 the software abbreviation for a repeated START; not an RTL signal.\n"
        "i2c_al / al \u2014 arbitration lost or bus error; asynchronous, valid in any state.\n"
        "cmd \u2014 the APB command selecting a chain: START / STOP / WRITE / READ.\n"
        "cmd_ack \u2014 handshake back to APB: the bit engine finished the command.",
        fs=6.2)

fs.footer(fig, "The dangerous part is what the hardware does NOT do: it keeps clocking "
               "the same legal-looking SCL/SDA waveform whether or not the slave ever "
               "acknowledged. Ignore the ACK bit, and nothing in this block, in the APB "
               "bus monitor or in the I2C bus monitor will ever report the error.")

fs.pad_limits(ax, 0.06)
print(fs.qa_report(fig))
fs.save(fig, "fig28_i2c_error_branches.png")





