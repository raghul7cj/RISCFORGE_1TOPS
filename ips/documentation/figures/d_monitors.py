"""fig05 -- AXI-Lite + APB bus timeout monitors (bus_monitors/*.sv)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

# ------------------------------------------------------------------ real RTL
TC_APB = 16                       # apb_timeout_monitor  TimeoutCycles
CNT_APB = 4                       # $clog2(TimeoutCycles) = $clog2(16)
TC_AXI_APB = 131072               # axi_lite_timeout_monitor TimeoutApb
TC_AXI_DEF = 64                  # axi_lite_timeout_monitor TimeoutDefault
CNT_AXI = 17                      # $clog2(TimeoutApb) = $clog2(131072)
APB_BASE, APB_END = "0x4000_0000", "0x5000_0000"

fig, ax = fs.slide(
    "A stalled slave is indistinguishable from a slow one \u2014 the monitor "
    "counts no-progress cycles, not elapsed cycles, then escalates to an "
    "error software can see",
    "AXI-Lite and APB timeout monitors: progress detect, counter, threshold, "
    "escalation",
)
XW, YH = fs.canvas(ax)

# ============================================================== system strip
SY, SH = 48.9, 5.9
NODES = [
    (4.0,   11.0, "RV32\ncore",           "cpu",    None),
    (17.6,  16.0, "hybrid_mem_\ninterface", "bus",  "slv_req / slv_resp"),
    (36.2,  16.0, "axi_lite_timeout_\nmonitor", "alarm", "131072 / 64 cyc"),
    (54.8,  12.0, "axi_lite_\nxbar",     "bus",    None),
    (69.4,  14.0, "axi_lite_\nto_apb",    "bus",    None),
    (86.0,  14.0, "apb_timeout_\nmonitor", "alarm", "16 cyc"),
    (102.6, 15.0, "APB slave\nUART/TIMER/I2C", "periph", None),
]
anchors = []
for x, w, txt, kind, sub in NODES:
    anchors.append(fs.block(ax, x, SY, w, SH, txt, kind=kind, fs=7.3,
                            sub=sub, sub_fs=6.2))
for a, b in zip(anchors, anchors[1:]):
    fs.wire(ax, a["e"], b["w"], color=fs.ACCENT, lw=1.9)

fs.label(ax, XW / 2, 57.7,
         "WHERE THE TWO MONITORS SIT — both are in-line on the response "
         "path, never on the request path   (xbar = crossbar)",
         fs=7.8, color=fs.ACCENT, weight="bold")

def brace(ax, x, y0, y1, txt, side="left"):
    """brace_v without its label (the kernel's label param shadows the fn)."""
    fs.brace_v(ax, x, y0, y1, None, side=side)
    fs.label(ax, x, y1 + 1.0, txt, fs=6.8, color=fs.GREY, weight="bold")


# brace_v draws with ax.add_line, so qa_report cannot see it: keep its lower
# tick above the ".sv" of the monitor header lines (header text tops at 48.20).
brace(ax, 34.9, SY - 0.35, SY + SH + 0.4, "AXI-LITE SIDE")
brace(ax, 84.6, SY - 0.35, SY + SH + 0.4, "APB SIDE")

# =============================================== AXI-LITE monitor internals
AX0, AW = 2.5, 18.5                     # three columns: x, gap 3.0, x, gap 3.0
COL = [(2.5, 18.5), (24.0, 18.5), (45.5, 17.5)]
CX = [c[0] + c[1] / 2.0 for c in COL]


def B(col, y, h, text, kind="ctrl", f=6.9):
    """block placed in one of the three column slots, auto-shrunk to fit."""
    f = f or 6.9
    f = fs.fit_fs(ax, text, COL[col][1] - 1.7, fs=f)
    return fs.block(ax, COL[col][0], y, COL[col][1], h, text, kind=kind, fs=f)


fs.label(ax, 2.5, 47.6, "1  AXI-LITE MONITOR   axi_lite_timeout_monitor.sv",
         fs=8.2, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, 63.0, 47.6, "wr path shown \u2014 rd path identical",
         fs=6.9, color=fs.GREY, ha="right")

# row 1 -- what counts as progress
fs.label(ax, 2.5, 45.6, "PROGRESS DETECT", fs=6.9, color=fs.GREY,
         weight="bold", ha="left")
B(0, 39.8, 5.2, "PROGRESS\nwr_b_hs = b_valid & b_ready\n"
                 "rd_r_hs = r_valid & r_ready", "resp")
B(1, 39.8, 5.2, "NO HANDSHAKE\nwr_busy = wr_inflight_q\n"
                 "| slv_req_i.aw_valid", "write")
B(2, 39.8, 5.2, "REGION SPLIT\nwr_apb_q = addr_in_apb()\n"
                 f"{APB_BASE} \u2264 addr < {APB_END}", "addr")
# row 2 -- counter and threshold
B(0, 32.6, 5.2, "wr_cnt_q / rd_cnt_q\n"
                 f"{CNT_AXI} bit = $clog2({TC_AXI_APB})\n"
                 "saturating, never wraps", "addr")
B(1, 32.6, 5.2, "wr_thresh_m1\n"
                 f"apb ? {TC_AXI_APB - 1} : {TC_AXI_DEF - 1}", "ctrl")
B(2, 32.6, 5.2, "wr_expired\n= (wr_cnt_q >= wr_thresh_m1)", "ctrl")
# row 3 -- escalation out of the AXI-Lite port
fire = fs.block(ax, 2.5, 25.4, 39.5, 5.2,
                "wr_fire = (wr_state_q == StPass) & wr_busy\n"
                "        & wr_expired & ~wr_b_hs",
                kind="alarm", fs=7.2)
err = B(2, 25.4, 5.2, "slv_resp_o\nRRESP = SLVERR\ndata = 0xDEAD_DEAD",
        "alarm")
fs.wire(ax, fire["e"], err["w"])

# progress / no-progress / region -> counter chain.
# Only the two end boxes get a down-stub: the middle box reaches row 3 through
# wr_expired on its right, and its stub would sit 0.2u off the red branch lane.
for i in range(3):
    fs.wire(ax, (CX[i], 39.8), (CX[i], 38.0))
    if i != 1:
        fs.wire(ax, (CX[i], 32.6), (CX[i], 31.8), arrow=False)
for a, b in ((0, 1), (1, 2)):
    fs.wire(ax, (COL[a][0] + COL[a][1], 34.9), (COL[b][0], 34.9))

# threshold -> fire : branch lane at y = 29.6, fully below the counter row
fs.wire(ax, (CX[2], 32.6), (CX[2], 31.6), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (CX[2], 31.6), (22.0, 31.6), via=None, arrow=False, color=fs.RED,
        lw=1.6)
fs.wire(ax, (22.0, 31.6), (22.0, 30.6), arrow=True, color=fs.RED, lw=1.6)
fs.onwire(ax, 38.0, 31.6, "wr_expired", color=fs.RED, fs=6.6)

# counter row -> region split is the only other input; fire -> FSM
fs.wire(ax, (22.0, 25.4), (22.0, 23.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (22.0, 23.6), (CX[0], 23.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (CX[0], 23.6), (CX[0], 20.6), arrow=True, color=fs.ACCENT, lw=1.6)

# ---------------------------------------------------------------- AXI FSM
fs.label(ax, 63.0, 22.4, "ERROR FSM  state_e  StPass \u2192 StInject \u2192 "
                          "StDrain", fs=6.9, color=fs.GREY, weight="bold",
         ha="right")


def S(col, name, sub):
    return fs.block(ax, COL[col][0], 15.0, COL[col][1], 5.6, name,
                    kind="plain", fs=7.6, sub=sub, sub_fs=6.2)


sp = S(0, "StPass", "forward beats; count idle\nexit: wr_fire")
si = S(1, "StInject", "drain the orphan beats\nexit: slv_req_i.b_ready")
sd = S(2, "StDrain", "swallow late B; SLVERR new AW\nexit: !aw_pend & !w_pend")
fs.wire(ax, sp["e"], si["w"])
fs.wire(ax, si["e"], sd["w"])
# return edge routed around the perimeter, in its own lane
fs.wire(ax, sd["s"], sp["s"], via=[(CX[2], 13.2), (CX[0], 13.2)],
        color=fs.GREY, lw=1.5)
fs.onwire(ax, 33.0, 13.2, "all pending drained \u2192 back to StPass",
          color=fs.GREY, fs=6.4)

# ================================================== APB monitor internals
COL = [(65.5, 18.5), (87.0, 18.5), (108.5, 15.5)]
CX = [c[0] + c[1] / 2.0 for c in COL]

fs.label(ax, 65.5, 47.6, "2  APB MONITOR   apb_timeout_monitor.sv",
         fs=8.2, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, 124.0, 47.6, "one instance per APB slot",
         fs=6.9, color=fs.GREY, ha="right")

fs.label(ax, 65.5, 45.6, "PROGRESS DETECT", fs=6.9, color=fs.GREY,
         weight="bold", ha="left")
B(0, 39.8, 5.2, "PROGRESS = PREADY\n!waiting \u2192 cnt_q \u2264 '0\n"
                 "= !PSEL&PENABLE&PREADY", "resp")
B(1, 39.8, 5.2, "NO ANSWER\npsel & penable & ~pready\n"
                 "\u2192 cnt_q \u2264 cnt_q + 1", "write")
B(2, 39.8, 5.2, "NO REGION SPLIT\none threshold for every\n"
                 "slot, no address decode", "addr")
B(0, 32.6, 5.2, "cnt_q\n4 bit = $clog2(TimeoutCycles)\n"
                 "saturates at 15, never wraps", "addr")
B(1, 32.6, 5.2, "expired\n= (cnt_q == TimeoutCycles-1)\n= (cnt_q == 15)",
  "ctrl")
B(2, 32.6, 5.2, "blocked_q\nsticky slot block\n"
                 "set on every fire", "ctrl")
fire2 = fs.block(ax, 65.5, 25.4, 39.5, 5.2,
                 "fire = waiting & (expired | blocked_q)\n"
                 "qualified with waiting  \u2192  \u201creal PREADY wins\u201d",
                 kind="alarm", fs=7.2)
err2 = B(2, 25.4, 5.2, "apb_resp_mst_o\nPREADY = 1\nPSLVERR = 1", "alarm")
fs.wire(ax, fire2["e"], err2["w"])

for i in range(3):
    fs.wire(ax, (CX[i], 39.8), (CX[i], 38.0))
    if i != 1:
        fs.wire(ax, (CX[i], 32.6), (CX[i], 31.8), arrow=False)
for a, b in ((0, 1), (1, 2)):
    fs.wire(ax, (COL[a][0] + COL[a][1], 34.9), (COL[b][0], 34.9))
fs.wire(ax, (CX[2], 32.6), (CX[2], 31.6), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (CX[2], 31.6), (85.0, 31.6), arrow=False, color=fs.RED, lw=1.6)
fs.wire(ax, (85.0, 31.6), (85.0, 30.6), arrow=True, color=fs.RED, lw=1.6)
fs.onwire(ax, 105.0, 31.6, "expired | blocked_q", color=fs.RED, fs=6.6)
fs.wire(ax, (85.0, 25.4), (85.0, 23.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (85.0, 23.6), (CX[0], 23.6), arrow=False, color=fs.ACCENT, lw=1.6)
fs.wire(ax, (CX[0], 23.6), (CX[0], 20.6), arrow=True, color=fs.ACCENT, lw=1.6)

# ------------------------------------------ APB "FSM": the sticky slot block
fs.label(ax, 124.0, 22.4, "no enum state \u2014 one flag, blocked_q, does the "
                          "same job", fs=6.9, color=fs.GREY, weight="bold",
         ha="right")
sb0 = fs.block(ax, 65.5, 15.0, 27.5, 5.6, "blocked_q = 0  TRANSPARENT",
               kind="plain", fs=7.4, sub="slave owns the response\n"
                                         "exit: fire = waiting & expired",
               sub_fs=6.2)
sb1 = fs.block(ax, 96.5, 15.0, 27.5, 5.6, "blocked_q = 1  SLOT BLOCKED",
               kind="alarm", fs=7.4, sub="answer later accesses at once\n"
                                         "clear: !psel & pready",
               sub_fs=6.2)
fs.wire(ax, sb0["e"], sb1["w"])
fs.wire(ax, sb1["s"], sb0["s"], via=[(110.2, 13.2), (79.2, 13.2)],
        color=fs.GREY, lw=1.5)
fs.onwire(ax, 94.7, 13.2, "slave shows PREADY while deselected",
          color=fs.GREY, fs=6.4)

# ============================================== bottom band: threshold / rule
# ============================ bottom band: threshold / golden rule / escalation
# The band carries material common to BOTH monitors, so it gets its own header
# -- otherwise three unrelated boxes look like the tail of panel 2.
fs.label(ax, XW / 2, 11.7,
         "SHARED BY BOTH MONITORS  —  the thresholds, the golden rule, "
         "and how the error reaches software",
         fs=7.0, color=fs.ACCENT, weight="bold")
BY, BH = 1.2, 9.6

fs.eqbox(ax, 2.5, BY, 36.0, BH,
         "APB SLOT \u2014 bounded per access\n"
         f"     timeout = TimeoutCycles = {TC_APB},  "
         f"CntWidth = $clog2({TC_APB}) = {CNT_APB} bit\n"
         f"     expired = (cnt_q == {TC_APB - 1})  \u2192  {TC_APB} idle "
         "ACCESS cycles\n"
         "AXI-LITE \u2014 bounded per transaction, threshold from the address\n"
         f"     thresh_m1 = apb ? {TC_AXI_APB - 1} : {TC_AXI_DEF - 1}   "
         f"(CntWidth = $clog2({TC_AXI_APB}) = {CNT_AXI} bit)\n"
         f"     \u2192 {TC_AXI_APB} idle cycles in the APB window, "
         f"{TC_AXI_DEF} elsewhere",
         fs=6.1)

fs.note(ax, 40.5, BY, 37.0, BH,
        "GOLDEN RULE \u2014 a monitor must reset on PROGRESS, so a\n"
        "legitimately slow slave that keeps advancing is never\n"
        "killed. 16 APB cycles of PREADY low in a row is a stall,\n"
        "but a thousand wait-states punctuated by a PREADY each\n"
        "time round is normal service. Both counters SATURATE\n"
        "rather than wrap, so the verdict can never be a wrap\n"
        "artefact, and timeout_sticky_o preserves it after the\n"
        "bus has already moved on.", fs=6.2)

# ----------------------------------------- escalation: chip chains, in-line
GX, GW = 79.5, 44.5
fs.note(ax, GX, BY, GW, BH, "", valign="top")
fs.label(ax, GX + 1.1, BY + BH - 0.75,
         "ESCALATION — the error becomes a core trap"
         "  (mcause = RISC-V cause register)", fs=6.9,
         color=fs.ACCENT, weight="bold", ha="left")


def chain(y, head, names, f=6.4, gap=1.5):
    """one horizontal escalation chain, each step its own chip."""
    fs.label(ax, GX + 1.1, y + 2.2, head, fs=6.3, color=fs.GREY, weight="bold",
             ha="left")
    x = GX + 1.1
    prev = None
    for n in names:
        x0, y0, w, h = fs.chip(ax, x, y, n, fc=fs.S_ALARM, ec=fs.RED,
                                tc="#7F1010", fs=f, padx=0.55)
        if prev is not None:
            fs.wire(ax, (prev, y), (x0, y), color=fs.RED, lw=1.4)
        prev, x = x0 + w, x0 + w + gap
    return prev


chain(6.9, "APB side",
      ["fire → PSLVERR=1", "RESP_SLVERR", "core bus error",
       "mcause 5 / 7"])
chain(2.8, "AXI-Lite side",
      ["wr_fire → SLVERR", "core bus error", "mcause 5 / 7",
       "wr/rd_sticky_o"])
fs.footer(fig, "Failure mode: an elapsed-time-only watchdog kills healthy slow "
               "slaves; a progress-only watchdog with no escalation hangs the "
               "bus silently \u2014 the counter has to do both jobs.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig05_bus_timeout_monitors.png")