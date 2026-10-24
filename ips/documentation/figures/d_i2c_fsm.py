"""fig11 -- RISCFORGE APB I2C master (APB[0] @ 0x4000_0000):
byte-level sequencer (i2c_master_byte_ctrl.sv) + quarter-bit SCL engine
(i2c_master_bit_ctrl.sv) and every branch that leaves the main chain.

RTL read (2 files + defines macros):
  rtl/ips/apb_i2c-master/apb_i2c.sv                (APB wrapper, r_pre divider)
  rtl/ips/apb_i2c-master/i2c_master_byte_ctrl.sv  (byte sequencer states)
  rtl/ips/apb_i2c-master/i2c_master_bit_ctrl.sv   (A/B/C/D micro-phases, al)
  rtl/ips/apb_i2c-master/i2c_master_defines.sv    (I2C_CMD_* macros)
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
# usable after fs.pad_limits(ax,0.06):  x 5..120 ,  y 4..55.5
U_Y0, U_H = 43.0, 7.0                  # upper row  43.0..50.0  (cy 46.5)
D_Y0, D_H = 33.0, 6.5                  # data  row  33.0..39.5  (cy 36.25)
FORK_Y, CONV_Y = 42.2, 41.0            # corridor 39.5..43.0, two levels
CONV2_Y = 31.0                         # ST_WRITE converge under-run lane
NACK_Y = 25.4                          # NACK branch lane
AL_Y = 18.6                            # arbitration-lost lane
PH_Y0, PH_H = 5.6, 8.4                 # SCL quarter-phase lane 5.6..14.0
# ---- main row boxes
IDLE_X0, IDLE_X1 = 13.0, 33.0
ST_X0, ST_X1 = 38.0, 57.0
ACK_X0, ACK_X1 = 73.0, 93.0
STOP_X0, STOP_X1 = 98.0, 114.0
# ---- data row boxes
WR_X0, WR_X1 = 38.0, 56.0
RD_X0, RD_X1 = 59.0, 77.0
RS_Y, RET_Y, BADGE_Y = 52.8, 55.2, 51.2   # top perimeter lanes + badge row

TITLE = ("The I2C master is a bit engine plus a byte sequencer \u2014 and the ACK bit "
         "is the only evidence the slave is alive,\nso every data byte must branch on it")
SUB = ("START HERE, top left, at ST_IDLE (1).  Read the three bands top to bottom:  "
       "STEP 1 byte sequencer  ->  STEP 2 bit engine (SCL quarter-phases)  ->  "
       "STEP 3 the branches that leave the main chain")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}")
print("LANE BUDGET  x 5..120  y 4..55.5")
print(f"  top perimeter : ret{RET_Y}  repeat-start {RS_Y}  badges {BADGE_Y}")
print(f"  upper row     : {U_Y0}..{U_Y0+U_H}   IDLE/START/ACK/STOP")
print(f"  corridor      : fork {FORK_Y}  converge {CONV_Y}")
print(f"  data row      : {D_Y0}..{D_Y0+D_H}   ST_WRITE / ST_READ")
print(f"  write under-run {CONV2_Y} | NACK {NACK_Y} | ARB-LOST {AL_Y}")
print(f"  SCL phases    : {PH_Y0}..{PH_Y0+PH_H}")
fs.pad_limits(ax, 0.06)

UCY = U_Y0 + U_H / 2.0          # 46.5
DCY = D_Y0 + D_H / 2.0          # 36.25
NFS = 6.2                        # node font

# ============================ LAYER 2 : IDLE -> START =====================
fs.block(ax, IDLE_X0, U_Y0, IDLE_X1 - IDLE_X0, U_H,
         "ST_IDLE  5'b0_0000\n"
         "go = (read|write|stop) & ~cmd_ack\n"
         "start\u2192START  read\u2192READ\n"
         "write\u2192WRITE  else\u2192STOP",
          kind="mux", fs=6.2, bold=True)
fs.badge(ax, IDLE_X0 + 1.7, U_Y0 + U_H + 1.2, 1)

fs.block(ax, ST_X0, U_Y0, ST_X1 - ST_X0, U_H,
         "ST_START  5'b0_0001\n"
         "wait core_ack (cmd=START)\n"
         "read ? ST_READ : ST_WRITE\n"
         "ld <= 1  (sr <= din)",
          kind="ctrl", fs=6.4, bold=True)
fs.badge(ax, ST_X0 + 1.7, U_Y0 + U_H + 1.2, 2)

fs.wire(ax, (IDLE_X1, UCY), (ST_X0, UCY), label="go", label_fs=6.0)

# fork out of ST_START into the two data states
fs.wire(ax, (46.0, U_Y0), (46.0, D_Y0 + D_H), label="write=1", label_at=(48.6, 41.2), label_fs=6.0)
fs.wire(ax, (51.5, U_Y0), (68.0, D_Y0 + D_H), via=[(51.5, FORK_Y), (68.0, FORK_Y)],
        label="read=1", label_at=(60.0, FORK_Y), label_fs=6.0)
print("L2 ok")

# ==================== LAYER 3 : DATA -> ACK -> STOP ========================
ACK_X0, ACK_X1 = 74.0, 97.0
STOP_X0, STOP_X1 = 102.0, 119.0

fs.block(ax, WR_X0, D_Y0, WR_X1 - WR_X0, D_H,
         "ST_WRITE  5'b0_0100\ncore_ack & !cnt_done:\n"
         "  stay, cmd=WRITE, shift<=1\ncore_ack & cnt_done \u2192 ST_ACK",
          kind="periph", fs=6.4, bold=True)
fs.badge(ax, WR_X0 + 1.7, D_Y0 + D_H + 1.2, 3)

fs.block(ax, RD_X0, D_Y0, RD_X1 - RD_X0, D_H,
         "ST_READ  5'b0_0010\ncore_ack & !cnt_done:\n"
         "  stay, cmd=READ, shift<=1\ncore_ack & cnt_done \u2192 ST_ACK",
          kind="periph", fs=6.4, bold=True)
fs.badge(ax, RD_X1 - 1.7, D_Y0 + D_H + 1.2, 4)

fs.block(ax, ACK_X0, U_Y0, ACK_X1 - ACK_X0, U_H,
         "ST_ACK  5'b0_1000\ncore_ack & !stop \u2192 ST_IDLE, cmd_ack<=1\n"
         "core_ack &  stop \u2192 ST_STOP\nack_out <= core_rxd  \u25c0 ACK BIT\n"
         "core_txd <= ack_in (SDA released)",
kind="alarm", fs=5.6, bold=True)
fs.badge(ax, ACK_X0 + 1.7, U_Y0 + U_H + 1.2, 5)

fs.block(ax, STOP_X0, U_Y0, STOP_X1 - STOP_X0, U_H,
         "ST_STOP  5'b1_0000\nwait core_ack\n(stop_a..stop_d driven)\n"
         "core_ack \u2192 ST_IDLE",
          kind="resp", fs=6.4, bold=True)
fs.badge(ax, STOP_X0 + 1.7, U_Y0 + U_H + 1.2, 6)

# converge: ST_READ straight up into ST_ACK, ST_WRITE around under the data row
fs.wire(ax, (80.0, D_Y0 + D_H), (80.0, U_Y0))
fs.wire(ax, (WR_X1, DCY), (88.0, U_Y0),
        via=[(58.0, DCY), (58.0, CONV2_Y), (88.0, CONV2_Y)],
        label="core_ack & cnt_done  \u2014  8 bits shifted (dcnt 3'h7\u21920)",
        label_at=(72.0, CONV2_Y), label_fs=6.0)
fs.wire(ax, (ACK_X1, UCY), (STOP_X0, UCY), label="stop=1", label_fs=6.0)
print("L3 ok")

# ==================== LAYER 4 : BRANCH LANES ================================
# -- perimeter: STOP -> IDLE (top lane), repeated START (second top lane).
# The routine return is a quiet grey note: ST_STOP already says "core_ack ->
# ST_IDLE", and repeating it in the loud lane put two identical statements in
# the first thing the eye meets.
fs.wire(ax, (110.0, U_Y0 + U_H), (28.0, U_Y0 + U_H),
        via=[(110.0, RET_Y), (28.0, RET_Y)], back=True, color=fs.GREY, lw=1.3,
        label="back to ST_IDLE (cmd_ack <= 1)  \u2014  byte complete, dout is held",
        label_at=(69.0, RET_Y), label_fs=5.8)
fs.wire(ax, (90.0, U_Y0 + U_H), (45.0, U_Y0 + U_H),
        via=[(90.0, RS_Y), (45.0, RS_Y)], back=True, color=fs.GREEN, lw=1.5,
        label="repeated START (SR) \u2014 re-issued from ST_IDLE, no STOP bit",
        label_at=(60.0, RS_Y), label_fs=6.0, label_color=fs.GREEN)

# -- NACK branch, own lane below, converges on STOP
fs.wire(ax, (92.0, U_Y0), (100.0, NACK_Y - 0.8),
        via=[(92.0, NACK_Y - 0.8)], color=fs.RED, lw=2.1,
        label="ack_out=1", label_at=(95.2, NACK_Y - 0.8), label_fs=5.6)
fs.block(ax, 100.0, NACK_Y - 3.6, 19.0, 5.6,
         "NACK = NOT acknowledge\nack_out == 1 (slave left SDA high)\n"
         "no NACK state exists in the FSM:\nsoftware MUST issue STOP",
         kind="alarm", fs=6.0, bold=True)
fs.wire(ax, (109.0, NACK_Y + 2.0), (109.0, U_Y0), color=fs.RED, lw=2.1)
fs.onwire(ax, 109.0, 35.2, "converge: STOP frees the bus", fs=6.0, color=fs.RED)

# -- arbitration lost / bus error, own lane, own left perimeter corridor
fs.wire(ax, (42.0, D_Y0), (15.5, U_Y0),
        via=[(42.0, AL_Y), (15.5, AL_Y)], color=fs.ORANGE, back=True,
        label="arbitration lost / bus error:  i2c_al (async, from any state)",
        label_at=(30.0, AL_Y),
        label_fs=6.0, label_color=fs.ORANGE)
fs.onwire(ax, 15.5, 31.6, "force ST_IDLE, no STOP", fs=6.0, color=fs.ORANGE)
fs.label(ax, 28.8, 16.4,
         "al = (sda_chk & ~sSDA & sda_oen)   |   (|c_state & sto_condition & ~cmd_stop)",
         fs=5.7, color=fs.ORANGE, style="italic")
print("L4 ok")

# ============ LAYER 5 : SCL quarter-phase lane + info callout ==============
CW, PITCH, CY0, CH = 13.2, 14.1, 7.2, 5.4
PH = ["start_a\nSCL low, SDA released\n(sda_oen <= 1)",
      "start_b\nSCL released high\n(scl_oen <= 1)",
      "start_c\nSDA pulled LOW\n= START condition",
      "start_d\nhold SDA low, SCL high\n(one quarter phase)",
      "start_e\nSCL pulled low\ncmd_ack <= 1 \u2192 byte FSM"]
PK = ["mux", "ctrl", "write", "ctrl", "resp"]
fs.label(ax, 48.8, 14.0,
         "STEP 2  \u00b7  BIT ENGINE (i2c_master_bit_ctrl) \u2014 every command = 5 "
         "micro-states A/B/C/D/i, one clk_en tick each",
         fs=6.4, color=fs.GREY, weight="bold")
for i in range(5):
    fs.block(ax, 14.0 + i * PITCH, CY0, CW, CH, PH[i], kind=PK[i], fs=5.2,
             bold=True)
    if i:
        fs.wire(ax, (14.0 + i * PITCH - 0.9, CY0 + CH / 2.0),
                (14.0 + i * PITCH, CY0 + CH / 2.0), head_scale=7.0, lw=1.4)
fs.sigwave(ax, 14.0, [0, 1, 1, 1, 0], PITCH, 5.9, 6.9, color=fs.ACCENT, lw=2.0)
fs.sigwave(ax, 14.0, [1, 1, 0, 0, 0], PITCH, 3.9, 4.9, color=fs.GREEN,
           dashed=True, lw=1.8)
fs.cycle_guides(ax, 14.0, 5, PITCH, bottom=3.8, top=12.8, color="#EAEAEA")
fs.label(ax, 11.4, 6.4, "SCL", fs=6.2, weight="bold", color=fs.ACCENT)
fs.label(ax, 11.4, 4.4, "SDA", fs=6.2, weight="bold", color=fs.GREEN)
fs.label(ax, 48.8, 2.8,
         "START = start_a..start_e (5)   ·   STOP = stop_a..stop_d (4)   "
         "·   WRITE = wr_a..wr_d (4)   ·   READ = rd_a..rd_d (4)",
         fs=5.7, color=fs.GREY)
fs.block(ax, 18.0, 22.4, 23.0, 7.0,
         "APB slave @ 0x4000_0000 (APB[0])\n"
         "REG_PRE  0x00 (16b) — prescale r_pre\n"
         "           → bit_ctrl.clk_cnt\n"
         "REG_CTRL 0x04 — [7] s_core_en  [6] s_ien",
         kind="bus", fs=6.2, bold=True)
fs.label(ax, 18.0, 20.9, "INPUTS \u2014 APB register block", fs=6.0, ha="left",
         weight="bold", color=fs.GREY)

fs.eqbox(ax, 87.0, 11.4, 32.0, 3.0,
         "one micro-state = 1 clk_en = (r_pre + 1) \u00d7 HCLK\n"
         "slave_wait (slave holds SCL low) \u2192 clk_en = 0", fs=6.2)
fs.note(ax, 87.0, 3.0, 32.0, 7.8,
        "REPEATED-START RULE   (start_a \u2026 start_e)\n"
        "SCL is released high first, then SDA is pulled\n"
        "low while SCL is high \u2014 no STOP bit in\n"
        "between: a STOP here would release the bus\n"
        "to any other master mid-address.", fs=5.7)
print("L5 ok")

# ============ LAYER 6 : legend, transaction strip, footer, QA, save ========
fs.label(ax, 9.5, 46.5, "STEP 1  \u00b7  BYTE SEQUENCER", fs=6.4, color=fs.GREY,
         weight="bold", rot=90)
fs.label(ax, 5.6, 46.5, "i2c_master_byte_ctrl.sv", fs=6.0, color=fs.GREY,
         rot=90)
fs.label(ax, 66.0, 15.4, "STEP 3  \u2014  BRANCHES THAT LEAVE THE MAIN CHAIN",
         fs=6.4, color=fs.GREY, weight="bold")
fs.legend_row(ax, 87.0, 21.5,
              [("box", "ctrl", "byte sequencer state"),
               ("line", fs.GREEN, "repeated START"),
               ("line", fs.RED, "NACK / abort (slave pulled SDA HIGH)")],
              gap=1.2, fs=5.8, vertical=True)
fs.label(ax, 67.0, 24.8,
         "one WRITE transaction \u2014 every byte is followed by an ACK bit",
         fs=6.4, color=fs.ACCENT, weight="bold")
fs.phase_bar(ax, 44.0, 6.0, 26.0, 3.4,
             [(0.0, 0.9, "START", fs.S_RESP),
              (0.9, 2.5, "ADDRESS + W", fs.S_ADDR),
              (2.5, 3.3, "ACK", fs.S_RESP),
              (3.3, 4.9, "DATA + W", fs.S_REQ),
              (4.9, 5.5, "ACK", fs.S_RESP),
              (5.5, 6.0, "STOP", fs.S_RESP)], unit=7.6, fs=6.4)

fs.footer(fig, "Ignore the ACK bit \u2014 or issue a repeated START while the previous "
               "ACK is still being clocked \u2014 and the bus is corrupted silently: the "
               "SCL/SDA waveforms still look legal, so no APB or I2C bus monitor ever "
               "flags it. The ACK bit is the only proof the slave is alive.")
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig11_i2c_master_fsm.png")
