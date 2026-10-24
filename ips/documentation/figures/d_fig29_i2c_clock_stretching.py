"""fig29 -- the I2C clock-stretch strip of fig12 (FROZEN), extracted, given a
declared to-scale time base and expanded onto its own canvas.

RTL read (the one file the parent script cited):
  rtl/ips/apb_i2c-master/i2c_master_bit_ctrl.sv
    :189  dscl_oen  <= scl_oen
    :196  slave_wait <= (scl_oen & ~dscl_oen & ~sSCL) | (slave_wait & ~sSCL)
    :200  scl_sync   = dSCL & ~sSCL & scl_oen
    :210  if (~|cnt | !ena | scl_sync) cnt<=clk_cnt, clk_en<=1
    :215  else if (slave_wait)         cnt<=cnt,     clk_en<=0
    :239  cSCL <= {cSCL[0], scl_i}          2-stage synchroniser
    :260/:277/:280  fSCL -> sSCL -> dSCL   filter + one more flop
    :373  if (clk_en) case (c_state) ...   FSM advances ONLY on clk_en
    changelog r1.12 "fixed short scl high pulse after clock stretch"
             r1.14 "Added clock synchronization logic" / "Fixed slave_wait"
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

TITLE = ("Clock stretching is implemented: the slave holds SCL low and the FSM "
         "stalls in slave_wait for one full bit period")
SUB = ("START HERE at (1), the SCL/SDA strip at the top: the dashed scl_oen trace "
       "leaves the line, the solid pin trace does not.  Then read down: (2) the "
       "drive request  (3) the synchronised pin  (4) slave_wait + clk_en  "
       "(5) the frozen micro-state  (6) why the high pulse is still full length")

# ------------------------------------------------- declared time base --------
NC = 14                     # micro-states drawn  = 3.5 bit periods
X0 = 19.0                   # left edge of column 0
U = 5.30                    # one micro-state = T/4 = 2.5 us  (T = 10 us)
XEND = X0 + NC * U          # 93.2
# micro-state index -> the RTL one-hot FSM state
ST = ["wr_a", "wr_b", "wr_c", "wr_d", "wr_a", "wr_b", "wr_b", "wr_b",
      "wr_b", "wr_b", "wr_c", "wr_d", "wr_a", "wr_b"]
OEN = [0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1]   # 1 = SCL released
PIN = [0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1]   # SCL on the pad = scl_i
SDA = [1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]
WAIT = [0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0]  # slave_wait
CLK_EN = [1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1]  # FSM heartbeat
STALL = (5, 8)               # the four frozen micro-states

# ---------------------------------------------------------------- lanes ----
Y_BUS0, Y_BUS1 = 45.8, 54.2
Y_OEN0, Y_OEN1 = 41.6, 45.6
Y_SYN0, Y_SYN1 = 35.4, 41.4
Y_CTL0, Y_CTL1 = 29.4, 35.2
Y_FSM0, Y_FSM1 = 23.6, 29.2
C_STALL = "#FBE4E4"

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}   XEND={XEND:.1f}")


def wrap(ax, s, max_w, f=6.2, weight="normal"):
    """Greedy wrap on MEASURED text width -- fs.note() does not wrap."""
    lines, cur = [], ""
    for w in s.split():
        t = (cur + " " + w).strip()
        if not cur or fs.text_w(ax, t, fs=f, weight=weight) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def lane(y0, y1, title, sub=None):
    """Waveform-lane scaffolding, same look as fs.lanes()."""
    ax.add_line(Line2D([1.0, XEND + 1.6], [y1, y1], color="#C8C8C8", lw=0.7,
                       ls=(0, (2, 3)), zorder=1))
    mid = (y0 + y1) / 2.0
    fs.label(ax, X0 - 1.2, mid + 1.2, title, fs=6.8, color=fs.TXT,
             weight="bold", ha="right", va="center", zorder=8)
    if sub:
        fs.label(ax, X0 - 1.2, mid - 1.2, sub, fs=6.2, color=fs.GREY,
                 ha="right", va="center", zorder=8)


def right(n, y_top, head, body, color=fs.ACCENT):
    """Step n's explanation, in the right-hand column, anchored to its lane."""
    x = XEND + 3.4
    w = XW - x - 1.0
    t = ax.text(x, y_top - 0.2, "%d \u00b7 %s" % (n, head), ha="left",
                va="top", fontsize=6.9, color=color, fontweight="bold",
                zorder=8)
    fs._reg(ax, t)
    t2 = ax.text(x, y_top - 1.6, wrap(ax, body, w), ha="left",
                 va="top", fontsize=6.2, color=fs.TXT, zorder=8,
                 linespacing=1.35)
    fs._reg(ax, t2)


def pbar(y, h, spans):
    """Segment bar with auto-fitted labels (fs.phase_bar does not fit text)."""
    for c0, c1, text, col in spans:
        xa, w = X0 + c0 * U, (c1 - c0) * U
        ax.add_patch(Rectangle((xa + 0.04, y), w - 0.08, h, facecolor=col,
                               edgecolor="#7F7F7F", linewidth=0.8, zorder=4))
        if text:
            fs.label(ax, xa + w / 2.0, y + h / 2.0, text,
                     fs=fs.fit_fs(ax, text, w - 1.0, 7.0), color="#202020",
                     weight="bold", zorder=6)


# ------------------------------------------------ entry point + time base --
_tb = ("TIME BASE  \u2014  1 column = 1 micro-state = T/4 = 2.5 \u00b5s   "
       "(T = 10 \u00b5s = one I2C bit period at 100 kHz)")
fs.chip(ax, X0 - 2.0 - fs.text_w(ax, "START HERE \u2192", 7.0, "bold"),
        57.9, "START HERE \u2192", fc=fs.ACCENT, ec=fs.ACCENT, tc="white", fs=7.0)
fs.chip(ax, XW - 1.0 - fs.text_w(ax, _tb, 6.4), 57.9, _tb,
        fc="#FFF2CC", ec="#BF8F00", tc="#7F6000", fs=6.4)

# three bit periods, drawn on that scale
pbar(54.4, 1.8, [
    (0.0, 4.0, "BIT PERIOD 1", "#D9D9D9"),
    (4.0, 8.0, "BIT PERIOD 2  \u2014  STRETCHED", "#F4B8B8"),
    (8.0, 14.0, "BIT PERIOD 3", "#D9D9D9")])
# ============================ (1) THE WIRES ==============================
lane(Y_BUS0, Y_BUS1, "SCL  /  SDA",
     "the bus itself\nscl_i = the master's read of SCL")
# the stall window, shaded behind everything in this band
ax.add_patch(Rectangle((X0 + STALL[0] * U - 0.25, Y_BUS0 - 0.3),
                       (STALL[1] - STALL[0]) * U + 0.5,
                       Y_BUS1 - Y_BUS0 + 0.6, facecolor=C_STALL,
                       edgecolor="none", zorder=1))
fs.sigwave(ax, X0, PIN, U, 50.0, 52.8, color=fs.ACCENT, lw=2.2)
fs.sigwave(ax, X0, SDA, U, 46.0, 48.2, color=fs.MID, lw=1.8)
fs.onwire(ax, X0 + 1.5 * U, 53.4, "SCL", fs=7.0, color=fs.ACCENT)
fs.onwire(ax, X0 + 11.0 * U, 47.4, "SDA", fs=7.0, color=fs.MID)
fs.onwire(ax, X0 + 6.5 * U, 49.3,
          "slave holds SCL low  \u2014  4 micro-states = one full bit period",
          fs=6.8, color="#8B1A1A", fc="#FDF0F0", ec="#E39B9B")
right(1, Y_BUS1,
     "THE SLAVE IS NOT READY",
     "The slave is not ready, so it pulls SCL low and keeps it there for four "
     "micro-states. SDA cannot move either: data may only change while SCL is low.")

# ==================== (2) WHAT THE MASTER ASKS FOR ========================
lane(Y_OEN0, Y_OEN1, "scl_oen", "master drive request")
fs.sigwave(ax, X0, OEN, U, 42.4, 44.6, color=fs.MID, lw=2.0, dashed=True)
fs.onwire(ax, X0 + 5.0 * U, 45.2, "scl_oen", fs=7.0, color=fs.MID)
right(2, Y_OEN1, "THE MASTER ALREADY LET GO",
     "scl_oen = 1 = the master has released SCL and lets the pull-up drive it. "
     "It goes to 1 in micro-state 5.")
# ================== (3) THE PIN, AS THE RTL SEES IT =======================
lane(Y_SYN0, Y_SYN1, "sSCL / dSCL  (from scl_i)",
     "2-stage sync + filter")
fs.sigwave(ax, X0 + 0.35, PIN, U, 38.7, 40.4, color=fs.GREEN, lw=1.7)
fs.sigwave(ax, X0 + 0.75, PIN, U, 35.7, 37.4, color=fs.ORANGE, lw=1.7)
fs.onwire(ax, X0 + 1.5 * U, 41.0, "sSCL", fs=6.6, color=fs.GREEN)
fs.onwire(ax, X0 + 1.5 * U, 36.9, "dSCL", fs=6.6, color=fs.ORANGE)
right(3, Y_SYN1, "THE MASTER MUST SEE THE LOW",
     "scl_i \u2192 cSCL (2-stage flop) \u2192 fSCL (glitch filter) \u2192 sSCL "
     "\u2192 dSCL.  Drawn shifted right: that path costs a few clk cycles, and clk "
     "is far faster than T/4.")

# ================== (4) slave_wait AND clk_en ============================
lane(Y_CTL0, Y_CTL1, "slave_wait / clk_en", "the stall control")
fs.sigwave(ax, X0, WAIT, U, 32.5, 34.2, color=fs.RED, lw=2.2)
fs.sigwave(ax, X0, CLK_EN, U, 29.9, 31.4, color=fs.ACCENT, lw=1.8)
fs.onwire(ax, X0 + 5.5 * U, 34.8, "slave_wait", fs=6.6, color=fs.RED)
fs.onwire(ax, X0 + 11.4 * U, 30.0, "clk_en", fs=6.6, color=fs.ACCENT)
right(4, Y_CTL1, "clk_en IS FORCED TO 0",
     "slave_wait latches high when scl_oen has just gone to 1 and sSCL is still "
     "low, and holds until sSCL rises. Then clk_en is forced to 0 and cnt is held.")
# ================== (5) THE MICRO-STATE FSM IS FROZEN ====================
lane(Y_FSM0, Y_FSM1, "c_state  (18-bit one-hot)",
     "4 states per bit period")
EC = {"wr_a": "#D9D9D9", "wr_b": "#D9D9D9", "wr_c": "#D9D9D9", "wr_d": "#D9D9D9"}
for i, s in enumerate(ST):
    hot = STALL[0] <= i < STALL[1]
    fs.bus_cells(ax, X0 + i * U, [s], U, 26.0, 4.0,
                 fill="#F4B8B8" if hot else EC[s],
                 ec="#C00000" if hot else "#BFBFBF",
                 color="#7F1010" if hot else "#404040", fs=6.6)
fs.label(ax, X0 + (STALL[0] + 2) * U, 28.8,
         "FROZEN  \u2014  clk_en = 0", fs=6.6, color="#C00000",
         weight="bold")
right(5, Y_FSM1, "IT STAYS IN wr_b",
     "The FSM advances only inside if (clk_en). clk_en is 0 for four whole "
     "micro-states, so the state does not move: the master is parked in wr_b.")

# ================== the declared ruler ==================================
for i in range(NC):
    ax.add_line(Line2D([X0 + i * U, X0 + i * U], [22.9, 23.6],
                       color="#D0D0D0", lw=0.6, zorder=1))
    fs.label(ax, X0 + (i + 0.5) * U, 22.2, str(i), fs=6.0, color=fs.GREY)
ax.add_line(Line2D([X0, XEND], [21.4, 21.4], color="#9A9A9A", lw=1.0, zorder=1))
for i, lab in ((0, "0"), (4, "10 \u00b5s"), (8, "20 \u00b5s"), (12, "30 \u00b5s")):
    ax.add_line(Line2D([X0 + i * U, X0 + i * U], [21.4, 22.0],
                       color="#9A9A9A", lw=1.0, zorder=1))
    fs.label(ax, X0 + i * U, 20.6, lab, fs=6.4, color="#404040", weight="bold")
fs.label(ax, X0, 19.7, "micro-state index \u2192      time on the bus",
         fs=6.2, color=fs.GREY, ha="left")
# ================== THE RTL, VERBATIM (glossary + equations) =============
QY, QH = 12.2, 7.0
COLS = [
    (1.4, "THE TWO WIRES  \u2014  open drain",
     "SCL and SDA are pulled up. A device only\n"
     "ever pulls them LOW, and scl_oen = 1 means\n"
     "the master has RELEASED SCL (it is not driving).\n"
     "SDA may only change while SCL is low \u2014 which\n"
     "is why a stalled clock also freezes the data."),
    (32.2, "THE PIN COMES BACK IN THROUGH A FILTER",
     "scl_i \u2192 cSCL   2-stage synchroniser\n"
     "cSCL  \u2192 fSCL   3-stage glitch filter, clocked\n"
     "fSCL  \u2192 sSCL   filtered SCL; the RTL decides on this\n"
     "sSCL  \u2192 dSCL   one more flop: the previous clk's copy\n"
     "All of it runs on clk \u2014 many times per micro-state."),
    (63.0, "slave_wait LATCHES, clk_en IS FORCED TO 0",
     "slave_wait <= (scl_oen & ~dscl_oen & ~sSCL)\n"
     "              | (slave_wait & ~sSCL);\n"
     "if (~|cnt | !ena | scl_sync) cnt<=clk_cnt, clk_en<=1;\n"
     "else if (slave_wait)         cnt<=cnt,      clk_en<=0;\n"
     "and  if (clk_en) case (c_state) \u2014 the FSM moves only here."),
    (93.8, "scl_sync RE-BASES THE LOW COUNT",
     "scl_sync = dSCL & ~sSCL & scl_oen\n"
     "An SCL falling edge seen while the master has\n"
     "released the line reloads cnt = clk_cnt: the\n"
     "low time is counted again in full, so the next\n"
     "high pulse is a full T/2 (changelog r1.12)."),
]
for x, head, body in COLS:
    fs.eqbox(ax, x, QY, 29.0, QH, head + "\n" + body, fs=5.6,
             fc="#FFF8E7" if x < 60 else "#FFF2CC", ec="#D6B656",
             color="#5C4A0A")
print("reference strip ok")
# ============ (6a) WHY THE HIGH PULSE IS STILL FULL LENGTH ===============
fs.badge(ax, 3.4, 11.2, 6)
fs.label(ax, 6.4, 11.2, "THE PAYOFF \u2014 the SCL high pulse afterwards is still "
         "a full T/2", fs=7.2, color=fs.ACCENT, weight="bold", ha="left")
X6, U6 = 7.6, 2.55
BROKEN = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0]   # a sliver of a state

fs.label(ax, X6, 10.3, "if the master had kept counting through the stall",
         fs=6.3, color=fs.GREY, ha="left", weight="bold")
fs.sigwave(ax, X6, BROKEN, U6, 8.5, 9.7, color="#B0B0B0", lw=1.8, dashed=True)
fs.label(ax, X6 + 9.5 * U6, 7.9, "SCL high = one sliver", fs=6.4,
         color="#8B1A1A", weight="bold")

fs.label(ax, X6, 7.0, "clk_en gated by slave_wait  \u2014  this RTL", fs=6.3,
         color=fs.GREEN, ha="left", weight="bold")
fs.sigwave(ax, X6, PIN, U6, 5.0, 6.2, color=fs.GREEN, lw=2.0)
fs.label(ax, X6 + 10.0 * U6, 4.6, "SCL high = two micro-states = T/2", fs=6.4,
         color="#1B5E20", weight="bold")
fs.note(ax, X6, 1.4, 44.0, 2.4,
        "The FSM is still in wr_b when the slave lets go, so a whole micro-state "
        "is still ahead of it:\nSCL high is a full T/2, never a sliver. Rev 1.12: "
        "\"fixed short scl high pulse after clock stretch\".", fs=5.8)
# ====== (6b) THE COST OF A MASTER THAT IGNORES STRETCHING ================
fs.badge(ax, 57.4, 11.2, 6, fc=fs.ORANGE)
fs.label(ax, 60.4, 11.2, "WHY IT IS WORTH IMPLEMENTING \u2014 what a master "
         "without stretching does", fs=7.2, color="#B45F06", weight="bold",
         ha="left")
fs.note(ax, 56.0, 1.8, 67.4, 8.8,
        "\u2022  It releases SCL, counts its own clk_cnt, and clocks on anyway "
        "\u2014 the slave is still\n"
        "    holding the line low, so it shifts out a bit the slave never sampled.\n"
        "\u2022  The slave sees no clock edge, holds its own sample, and the two "
        "bit streams slip\n"
        "    by one: the byte the master reads back is wrong, with no NACK to say "
        "so.\n"
        "\u2022  And while that master is itself holding SCL low for its own low "
        "time, a slower slave\n"
        "    cannot even begin \u2014 the bus appears hung, not slow.  I2C requires "
        "the master to support\n"
        "    clock stretching; without it, a 100 kHz master simply cannot talk to "
        "a slow device.", fs=6.0)

fs.footer(fig, "FAILURE MODE IF STRETCHING IS IGNORED \u2014 either the slave "
              "never sees a full SCL high pulse and latches the wrong bit, or the "
              "master samples SDA before the slave is ready: the byte is corrupted "
              "and nothing on the bus reports it.")

fs.pad_limits(ax, 0.06)
print(fs.qa_report(fig))
fs.save(fig, "fig29_i2c_clock_stretching.png")