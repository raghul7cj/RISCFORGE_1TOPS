"""fig21 -- the AXI-Lite timeout monitor on its own (axi_lite_timeout_monitor.sv).

Split out of d_monitors.py (fig05), panel 1.  The parent figure stays frozen.
Geometry rule used here: every row-to-row wire leaves a box on its RIGHT edge
(2 u in), never on its centre, so the numbered panel headers can sit in the
gaps without a text/wire collision.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

# ------------------------------------------------------------------ real RTL
TC_AXI_APB = 131072               # TimeoutApb
TC_AXI_DEF = 64                  # TimeoutDefault
CNT_AXI = 17                      # $clog2(TimeoutApb) = $clog2(131072)
APB_BASE, APB_END = "0x4000_0000", "0x5000_0000"

fig, ax = fs.slide(
    "The AXI-Lite monitor counts idle cycles per transaction \u2014 131072 "
    "inside the APB window, 64 outside \u2014 and answers SLVERR with "
    "0xDEAD_DEAD once the threshold is crossed",
    "axi_lite_timeout_monitor.sv: where it sits, what counts as progress, "
    "the counter and its two thresholds, the error FSM, and the answer "
    "on the bus",
)
XW, YH = fs.canvas(ax)

COL = [(2.5, 36.0), (44.5, 36.0), (86.5, 36.0)]      # three data columns
CX = [c[0] + c[1] / 2.0 for c in COL]
RX = [c[0] + c[1] - 2.0 for c in COL]                # right-edge drop points
RH = 5.4                                             # every logic row height
FSY, FSH = 8.2, 5.4                                  # FSM row


def B(col, y, h, text, kind="ctrl", f=6.9):
    """block placed in one of the three column slots, auto-shrunk to fit."""
    f = fs.fit_fs(ax, text, COL[col][1] - 1.7, fs=f)
    return fs.block(ax, COL[col][0], y, COL[col][1], h, text, kind=kind, fs=f)


def head(y, n, txt, right=False):
    """numbered panel header with a badge, the way the improved parents do."""
    if right:
        fs.badge(ax, 121.2, y, n, r=1.05, fs=7.0)
        fs.label(ax, 117.4, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="right")
    else:
        fs.badge(ax, 3.6, y, n, r=1.05, fs=7.0)
        fs.label(ax, 6.2, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="left")


# ------------------------------------------------------------- reading order
fs.label(ax, 2.5, 57.4,
         "START HERE \u2193   read TOP to BOTTOM, LEFT to RIGHT:   "
         "1 WHERE IT SITS   \u2192   2 PROGRESS   \u2192   3 COUNTER   \u2192   "
         "4 FIRE + ANSWER   \u2192   5 ERROR FSM   \u2192   6 THRESHOLDS",
         fs=7.4, color=fs.ACCENT, weight="bold", ha="left")

# ------------------------------------------- 1  placement strip (own context)
head(54.6, 1, "WHERE IT SITS \u2014 in-line on the RESPONSE path, never on "
              "the request path")
SY, SH = 47.6, 5.4
NODES = [
    (6.0,  18.0, "RV32\ncore", "cpu", None),
    (30.0, 24.0, "hybrid_mem_\ninterface", "bus", "slv_req / slv_resp"),
    (60.0, 30.0, "axi_lite_timeout_\nmonitor", "alarm", "131072 / 64 cyc"),
    (96.0, 22.0, "axi_lite_\nxbar", "bus", "crossbar"),
]
anchors = []
for x, w, txt, kind, sub in NODES:
    anchors.append(fs.block(ax, x, SY, w, SH, txt, kind=kind, fs=7.3, sub=sub,
                            sub_fs=6.2))
for a, b in zip(anchors, anchors[1:]):
    fs.wire(ax, a["e"], b["w"], color=fs.ACCENT, lw=1.9)
fs.label(ax, 75.0, 46.2, "\u2190 this figure: the monitor", fs=6.8,
         color=fs.RED, weight="bold")

# ------------------------------------- 2  what counts as progress (row A)
head(44.4, 2, "WHAT COUNTS AS PROGRESS \u2014 idle means NO handshake")
fs.label(ax, 122.5, 44.4, "write path shown \u2014 read path identical", fs=6.8,
         color=fs.GREY, ha="right")
B(0, 37.4, RH, "PROGRESS\nwr_b_hs = b_valid & b_ready\n"
               "rd_r_hs = r_valid & r_ready", "resp")
B(1, 37.4, RH, "NO HANDSHAKE\nwr_busy = wr_inflight_q\n"
               "| slv_req_i.aw_valid", "write")
B(2, 37.4, RH, "REGION SPLIT\nwr_apb_q = addr_in_apb()\n"
               f"{APB_BASE} \u2264 addr < {APB_END}", "addr")

# ------------------------------------------- 3  counter and its thresholds
head(35.0, 3, "THE COUNTER \u2014 idle cycles only")
B(0, 28.2, RH, "wr_cnt_q / rd_cnt_q\n"
               f"{CNT_AXI} bit = $clog2({TC_AXI_APB})\n"
               "saturating, never wraps", "addr")
B(1, 28.2, RH, "wr_thresh_m1\n"
               f"apb ? {TC_AXI_APB - 1} : {TC_AXI_DEF - 1}", "ctrl")
B(2, 28.2, RH, "wr_expired\n"
               "= (wr_cnt_q >= wr_thresh_m1)", "ctrl")

# progress / no-handshake / region -> counter chain
for i in range(3):
    fs.wire(ax, (RX[i], 37.4), (RX[i], 33.6))
for a, b in ((0, 1), (1, 2)):
    fs.wire(ax, (COL[a][0] + COL[a][1], 30.9), (COL[b][0], 30.9))

# ------------------------------------- 4  the fire condition + the answer
head(25.2, 4, "FIRE + THE ANSWER")
fire = fs.block(ax, 2.5, 18.2, 78.0, RH,
                "wr_fire = (wr_state_q == StPass) & wr_busy\n"
                "        & wr_expired & ~wr_b_hs",
                kind="alarm", fs=7.2)
err = B(2, 18.2, RH, "slv_resp_o\nRRESP = SLVERR\ndata = 0xDEAD_DEAD",
        "alarm")
fs.wire(ax, fire["e"], err["w"])

# the counter feeds the fire term directly (its own short stub on the right)
fs.wire(ax, (RX[0], 28.2), (RX[0], 23.6), color=fs.ACCENT, lw=1.6)
# the threshold term takes the red branch lane under the counter row
fs.wire(ax, (RX[2], 28.2), (RX[2], 26.4), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (RX[2], 26.4), (41.5, 26.4), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (41.5, 26.4), (41.5, 23.6), arrow=True, color=fs.RED, lw=1.6)
fs.onwire(ax, 62.5, 26.4, "wr_expired", color=fs.RED, fs=6.6)

# fire -> error FSM, in its own lane under the fire box
fs.wire(ax, (41.5, 18.2), (41.5, 16.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (41.5, 16.6), (CX[0], 16.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (CX[0], 16.6), (CX[0], FSY + FSH), arrow=True, color=fs.ACCENT,
        lw=1.6)

# --------------------------------------------------------- 5  the error FSM
head(15.0, 5, "ERROR FSM  state_e \u2014 three states, because a stalled "
              "slave may still dribble beats", right=True)


def S(col, name, sub):
    return fs.block(ax, COL[col][0], FSY, COL[col][1], FSH, name,
                    kind="plain", fs=7.6, sub=sub, sub_fs=6.2)


sp = S(0, "StPass", "forward beats; count idle\nexit: wr_fire")
si = S(1, "StInject", "drain the orphan beats\nexit: slv_req_i.b_ready")
sd = S(2, "StDrain", "swallow late B; SLVERR new AW\nexit: !aw_pend & !w_pend")
fs.wire(ax, sp["e"], si["w"])
fs.wire(ax, si["e"], sd["w"])
# return edge routed around the perimeter, in its own lane
fs.wire(ax, sd["s"], sp["s"], via=[(CX[2], 7.6), (CX[0], 7.6)],
        color=fs.GREY, lw=1.5)
fs.onwire(ax, 62.5, 7.6, "all pending drained \u2192 back to StPass",
          color=fs.GREY, fs=6.4)

# ------------------------------- 6  threshold table (this figure's share) + glossary
head(6.5, 6, "THRESHOLDS + GLOSSARY")
BY, BH = 0.4, 5.2

fs.eqbox(ax, 2.5, BY, 58.0, BH,
         "AXI-LITE \u2014 bounded per TRANSACTION, threshold from the address\n"
         f"     thresh_m1 = addr_in_apb() ? {TC_AXI_APB - 1} : "
         f"{TC_AXI_DEF - 1}      (TimeoutApb = {TC_AXI_APB}, "
         f"TimeoutDefault = {TC_AXI_DEF})\n"
         f"     addr in {APB_BASE} \u2026 {APB_END}  \u2192  {TC_AXI_APB} "
         f"idle cycles to fire,   any other address  \u2192  {TC_AXI_DEF}   "
         f"(CntWidth = {CNT_AXI} bit)",
         fs=6.2)

fs.note(ax, 63.5, BY, 59.0, BH,
        "GLOSSARY\n"
        " SLVERR \u2014 the AXI/Lite slave-error code: the bus's way of saying "
        "'this access failed', which the core turns into\n"
        "   a bus error trap.      xbar \u2014 crossbar: the AXI-Lite "
        "interconnect this monitor sits in front of.      wr_ / rd_ \u2014 the\n"
        "   write path / read path: separate registers, identical behaviour, "
        "so only the write path is drawn here.", fs=6.4)

fs.footer(fig, "This figure is the AXI-Lite half only \u2014 the APB monitor is "
               "fig22, the rules both obey are fig23. Idle cycles are counted, "
               "not elapsed time, so a slow slave that keeps handshaking is "
               "never killed.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig21_axi_lite_timeout_monitor.png")