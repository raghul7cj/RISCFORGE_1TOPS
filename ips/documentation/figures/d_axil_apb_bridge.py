"""fig04 - AXI-Lite -> APB bridge FSM + the AXI transaction it generates.

RTL:  rtl/ips/axi_lite_to_apb/axi_lite_to_apb.sv   (apb_state_q: Setup / Access)
      rtl/ips/axi_lite_to_apb/axi_pkg.sv           (RESP_OKAY/SLVERR/DECERR)
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

TITLE = ("The bridge is only safe because it parks AXI data until the APB access "
         "phase completes \u2014 that ordering is what stops two PSELs from ever overlapping")
SUB = "bridge FSM (left) and the AXI-Lite transaction it generates (right)"

fig, ax = fs.slide(TITLE, SUB)
X, Y = fs.canvas(ax)
# Fix the data->pixel scale before anything is measured: text sizes are
# absolute (points) while box sizes follow the transform, so the scale must
# not drift between font fitting and the QA pass.
fs.pad_limits(ax, 0.06)
ax.set_autoscale_on(False)
print("canvas %.1f x %.1f units" % (X, Y))

# ---------------------------------------------------------------- left: FSM
SY, SH = 27.0, 16.0
SW, AW = 18.0, 18.0
AX0 = 27.0

# Two panels with two different reading paths, so the figure is told how to
# be read rather than leaving the eye to find an entry point on its own.
fs.label(ax, 3, 57.6,
         "READ   A · the FSM — how one AXI-Lite request becomes an APB access"
         "   →   B · the timing — one AXI-Lite write through that FSM",
         fs=7.2, color=fs.ACCENT, weight="bold", ha="left")

fs.badge(ax, 5.4, 56.0, "A", r=1.35, fc=fs.ACCENT, tc="white", fs=8.6)
fs.label(ax, 8.0, 56.0, "axi_lite_to_apb.sv  —  apb_state_q : a two-state FSM",
         fs=9.2, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, 3, 53.2, "`FFLARN(apb_state_q, apb_state_d, apb_update, Setup, clk_i, rst_ni)`",
         fs=6.9, color=fs.GREY, ha="left")
fs.label(ax, 3, 50.8, "reset value Setup — Idle and Setup are the same state",
         fs=6.9, color=fs.GREY, ha="left")
fs.label(ax, 3, 48.9,
         "APB signals:  PSEL = select  ·  PENABLE = enable  ·  PREADY = ready",
         fs=6.6, color=fs.GREY, ha="left")
fs.label(ax, 3, 45.4,
         "AXI-Lite response channels:  B = write  ·  R = read",
         fs=6.6, color=fs.GREY, ha="left")



def fit_text(lines, x, y, w, h, weight="bold", fs0=7.0, floor=4.4, ls=1.35,
             pad=1.1):
    """Largest font size whose rendered text fits the rect (x, y, w, h).

    Measured in pixels against the rect's own two corners, so it is immune
    to the axes data limits drifting while patches are being added.
    """
    fig.canvas.draw()
    a = ax.transData.transform((x + pad, y + pad))
    b = ax.transData.transform((x + w - pad, y + h - pad))
    mw, mh = abs(b[0] - a[0]), abs(b[1] - a[1])
    s, f = "\n".join(lines), fs0
    while f > floor:
        t = ax.text(0, -1e5, s, fontsize=f, fontweight=weight,
                    linespacing=ls, clip_on=False)
        bb = t.get_window_extent(renderer=fig.canvas.get_renderer())
        t.remove()
        if bb.width <= mw - 2.0 and bb.height <= mh - 2.0:
            break
        f -= 0.1
    return f


def node(x, y, w, h, lines, kind):
    """State box with per-line auto font shrink so nothing overflows."""
    return fs.block(ax, x, y, w, h, "\n".join(lines), kind=kind,
                    fs=fit_text(lines, x, y, w, h))


node(3, SY, SW, SH, [
    "Setup       apb_state_q = 1'b0",
    "PSEL=1  PENABLE=0",
    "Idle + Setup step of one APB",
    "transfer; holds while there is",
    "no apb_req_valid, or a response",
    "spill register is busy",
    "\u2192 Access when apb_req_valid",
    "   && apb_wresp_ready",
    "   && apb_rresp_ready",
    "   && apb_dec_valid",
    "   && ((write && |strb) || !write)",
], "addr")

node(AX0, SY, AW, SH, [
    "Access      apb_state_q = 1'b1",
    "PSEL=1  PENABLE=1",
    "access phase: paddr, pwdata,",
    "pstrb held stable from the",
    "Setup step",
    "\u2192 Setup when",
    "   apb_resp_i[sel].pready = 1",
    "same cycle: apb_req_ready = 1,",
    "request popped, response",
    "emitted to the B / R channel",
], "write")

fs.wire(ax, (21.0, SY + SH / 2), (AX0, SY + SH / 2), color=fs.ACCENT)
fs.onwire(ax, 24.0, SY + SH / 2, "1 clk", fs=6.6)


# ------------------------------------------------- left: response branch lanes
def lane(n, x_src, y_edge, y_run, sink, txt, lab_cx, kind, color, bx, by):
    """Rectangular route on its own lane + labelled sink block."""
    fs.wire(ax, (x_src, y_edge), (49.0, y_run), via=[(x_src, y_run)],
            color=color, lw=1.5)
    fs.badge(ax, bx, by, n, fc=color)
    fs.onwire(ax, lab_cx, y_run, txt, fs=6.5, color=color)
    node(49.0, y_run - 3.5, 12.0, 7.0, sink, kind)


lane(1, 30.0, SY + SH, 47.5,
     ["B channel", "axi_bresp /", "axi_bresp_valid"],
     "write:  pslverr ? SLVERR : OKAY", 37.5, "resp", fs.GREEN, 26.6, 47.5)
lane(2, 33.0, SY, 24.5,
     ["R channel", "axi_rresp /", "axi_rresp_valid"],
     "read:  apb_rresp.data = prdata", 38.5, "resp", fs.GREEN, 27.5, 24.5)
lane(3, 9.0, SY, 16.0,
     ["no PSEL at all", "a write, strb == 0", "answers OKAY instead"],
     "decode error:  apb_req_ready = 1,  no PSEL,  resp = RESP_DECERR",
     27.5, "alarm", fs.RED, 6.0, 16.0)

# --------------------------------------------------------------- right: waves
RX0, RU, N = 88.0, 3.9, 9

fs.badge(ax, 72.4, 55.4, "B", r=1.35, fc=fs.ACCENT, tc="white", fs=8.6)
fs.label(ax, 75.0, 55.4,
         "AW retires at clk1, W at clk4 — independent channels, one commit point",
         fs=9.2, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, 70, 52.6,
         "one AXI-Lite write; the bridge drives no APB signal until it holds both "
         "halves of the transfer", fs=6.9, color=fs.GREY, ha="left")
fs.label(ax, 70, 50.0,
         "AXI-Lite channels:  AW = write address  ·  W = write data  ·  "
         "B = write response",
         fs=6.6, color=fs.GREY, ha="left")

rows = [("aw", "AWVALID / AWREADY", "address \u2014 retires at clk1"),
        ("w",  "WVALID / WREADY",    "data parks until clk4"),
        ("b",  "BVALID / BREADY",    "commit point, after PREADY"),
        ("apb", "PSEL / PENABLE",     "PREADY green, dashed")]
ax, ys, u = fs.lanes(fig, rows, RX0, RX0 + N * RU, unit=RU, left_pad=0.55,
                     lane_gap=5.6)

C_ADDR, C_WRITE, C_RESP = "#BF8F00", "#C55A11", fs.GREEN
W = [0] * N


def lv(hi):
    v = list(W)
    for a, b in hi:
        for i in range(a, b):
            v[i] = 1
    return v


def sig(key, hi, color, dashed=False, lo=-2.1, hi_y=2.1):
    fs.sigwave(ax, RX0, lv(hi), u, ys[key] + lo, ys[key] + hi_y,
               color=color, dashed=dashed)


sig("aw", [(0, 2)], C_ADDR)
sig("aw", [(1, 3)], C_ADDR, dashed=True)
sig("w", [(2, 5)], C_WRITE)
sig("w", [(3, 6)], C_WRITE, dashed=True)
sig("b", [(7, 9)], C_RESP)
sig("b", [(6, 8)], C_RESP, dashed=True)
# one APB lane, three stacked traces: PSEL, PENABLE, PREADY
sig("apb", [(5, 7)], fs.ACCENT, lo=1.6, hi_y=2.5)
sig("apb", [(6, 7)], fs.ACCENT, lo=0.2, hi_y=1.1)
sig("apb", [(6, 7)], C_RESP, dashed=True, lo=-1.2, hi_y=-0.3)

fs.cycle_guides(ax, RX0, N, u, bottom=2.0, top=35.0,
                names=["clk%d" % i for i in range(N)])

# ----------------------------------------------- phase bar, commit, callouts
fs.label(ax, RX0, 44.6, "bridge phase  (apb_state_q + the APB signals it drives)",
         fs=7.4, color=fs.TXT, weight="bold", ha="left")

fs.phase_bar(ax, RX0, N, 31.5, 3.2,
             [(0, 5, "IDLE  \u2014  no PSEL yet", "#EDEDED"),
              (5, 6, "SETUP", fs.S_ADDR),
              (6, 7, "ACCESS", fs.S_WRITE),
              (7, 9, "RESPONSE", fs.S_RESP)], unit=u, fs=5.0)

# 5 items at fs 7 ran ~37 units and the last swatch was clipped by the canvas
# edge -> shrink the type and the gaps so the row ends inside the frame.
fs.legend_row(ax, RX0 - 1.0, 47.2,
              [("box", fs.S_ADDR, "SETUP / address"),
               ("box", fs.S_WRITE, "ACCESS / write"),
               ("box", fs.S_RESP, "RESPONSE"),
               ("dash", C_RESP, "PREADY"),
               ("line", fs.ACCENT, "APB drive")], fs=6.2, gap=0.5)

CX = RX0 + 6.5 * RU
fs.txn_mark(ax, CX, 34.9,
            "commit \u2014 in Access, apb_resp_i[sel].pready sampled at clk6\n"
            "apb_req_ready = 1, state \u2192 Setup, bresp emitted\n"
            "AW accepted clk1 \u2192 BVALID clk7  =  6 clk end-to-end",
            xytext=(-46, 10))

# sized to its two lines so it does not read as a mostly-empty yellow slab
fs.eqbox(ax, 11.0, 17.0, 22.0, 4.4,
         "paddr = aligned_addr(addr, 2)\nAPB 2.1.1: unaligned paddr is undefined",
         fs=6.6)

NLINES = [
    "Safety argument: apb_req_o comes only from apb_state_q, so PSEL cannot rise",
    "while an older access is open; the AXI request is popped only on PREADY",
    "(apb_req_ready = 1 in Access) \u2014 no new AXI transaction is accepted until",
    "the access phase ends. If PREADY never asserts, the FSM parks in Access",
    "forever and the fig05 APB monitor fires at TimeoutCycles = 16.",
]
fs.note(ax, 3, 1.4, 43.0, 10.2, "\n".join(NLINES),
        fs=fit_text(NLINES, 3, 1.4, 43.0, 10.2, "normal", fs0=7.4, ls=1.42,
                    pad=1.5))

fs.footer(fig, "AXI channels are independent, APB is not \u2014 the bridge has to "
               "serialise: it parks AW/W until the access phase ends, and that "
               "ordering is what stops two PSELs from ever overlapping.")

fig.canvas.draw()
print(fs.qa_report(fig))
fs.save(fig, "fig04_axil_to_apb_bridge_fsm.png")