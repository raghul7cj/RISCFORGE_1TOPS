"""fig20 -- panel B of fig04, extracted: the AXI-Lite -> APB timing of ONE write.

Parent fig04 is FROZEN; this file copies only its right-hand waveform panel and
gives it the whole canvas, so the six-cycle latency can be read on its own.

RTL read (same 2 files the parent used):
  rtl/ips/axi_lite_to_apb/axi_lite_to_apb.sv  (apb_state_q: Setup / Access, PSEL
        from apb_req_valid, response emitted on PREADY)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

TITLE = ("One AXI-Lite write takes 6 clocks end to end because WVALID is held "
         "until clk4 and BVALID only rises after PREADY")
SUB = ("one AXI-Lite write, clk0 \u2192 clk8.   AW retires at clk1 and W at clk4 \u2014 "
       "the two AXI channels are independent; there is exactly ONE commit point, "
       "and it is PREADY.")

fig, ax = fs.slide(TITLE, SUB)
X, Y = fs.canvas(ax)
fs.pad_limits(ax, 0.06)
ax.set_autoscale_on(False)
print("canvas %.1f x %.1f units" % (X, Y))

# --------------------------------------------------------------- geometry
X0, U, N = 20.0, 8.4, 9                      # clk0 .. clk8, 8.4 u per clock
XR = X0 + N * U                              # 95.6 -- right edge of the waves
RC0, RC1 = 97.6, 123.0                       # right-hand annotation column
YAW, YW, YB, YAPB = 42.5, 35.0, 27.5, 20.0   # lane centres, top to bottom
GAP = 7.5
LO, HI = -2.2, 2.2                           # waveform excursion per lane

C_ADDR, C_WRITE, C_RESP = "#BF8F00", "#C55A11", fs.GREEN

# ------------------------------------------------------------------- header
fs.badge(ax, 4.6, 56.6, "1", r=1.3, fc=fs.ACCENT, tc="white", fs=8.4)
fs.label(ax, 7.4, 56.9,
         "START HERE at the top lane, AWVALID / AWREADY, then read DOWN the "
         "lanes to the APB signals.",
         fs=7.8, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, 7.4, 53.9,
         "READING ORDER    1  the four lanes, top to bottom     \u2192     "
         "2  the PHASE bar underneath     \u2192     3  the green commit mark "
         "on clk7 and the cycle arithmetic beside it",
         fs=7.0, color=fs.TXT, weight="bold", ha="left")
fs.legend_row(ax, 7.4, 51.1,
              [("line", C_ADDR, "AW channel"),
               ("line", C_WRITE, "W channel"),
               ("line", C_RESP, "B channel"),
               ("line", fs.ACCENT, "PSEL / PENABLE"),
               ("dash", C_RESP, "PREADY")], fs=6.6, gap=0.7)
fs.label(ax, 56.0, 51.1,
         "solid = VALID, driven by the AXI master   \u00b7   dashed = READY, "
         "driven back by the bridge or the APB slave",
         fs=6.6, color=fs.GREY, ha="left")
fs.label(ax, 7.4, 48.6,
         "AW = write address   \u00b7   W = write data   \u00b7   B = write "
         "response   \u00b7   PSEL = APB slave select   \u00b7   PENABLE = APB "
         "strobe   \u00b7   PREADY = slave ready",
         fs=6.6, color=fs.GREY, ha="left")
print("header ok")
# ------------------------------------------------- lanes + the AXI transaction
def lane(cy, title, sub):
    """Lane divider + right-aligned lane title / gloss."""
    from matplotlib.lines import Line2D
    ax.add_line(Line2D([3.0, XR], [cy - GAP / 2.0, cy - GAP / 2.0],
                       color="#C8C8C8", lw=0.7, ls=(0, (2, 3)), zorder=1))
    fs.label(ax, 19.0, cy + 0.6, title, fs=7.4, color=fs.TXT, weight="bold",
             ha="right", va="bottom")
    fs.label(ax, 19.0, cy - 1.3, sub, fs=6.4, color=fs.GREY, ha="right",
             va="top")


def sig(cy, hi, color, dashed=False, lo=LO, hi_y=HI):
    v = [0] * N
    for a, b in hi:
        for i in range(a, b):
            v[i] = 1
    fs.sigwave(ax, X0, v, U, cy + lo, cy + hi_y, color=color, dashed=dashed)


lane(YAW, "AWVALID / AWREADY", "AW = write address")
lane(YW,  "WVALID / WREADY",   "W = write data")
lane(YB,  "BVALID / BREADY",   "B = write response")
lane(YAPB, "PSEL / PENABLE / PREADY", "APB side \u2014 fig06")

# AXI-Lite: VALID solid (master), READY dashed (bridge).  Copied from fig04.
sig(YAW, [(0, 2)], C_ADDR)
sig(YAW, [(1, 3)], C_ADDR, dashed=True)
sig(YW,  [(2, 5)], C_WRITE)
sig(YW,  [(3, 6)], C_WRITE, dashed=True)
sig(YB,  [(7, 9)], C_RESP)
sig(YB,  [(6, 8)], C_RESP, dashed=True)
# APB: three traces stacked in one lane -- PSEL, PENABLE, PREADY
sig(YAPB, [(5, 7)], fs.ACCENT, lo=1.5, hi_y=2.4)
sig(YAPB, [(6, 7)], fs.ACCENT, lo=0.2, hi_y=1.1)
sig(YAPB, [(6, 7)], C_RESP, dashed=True, lo=-1.2, hi_y=-0.3)

# the three APB traces sit one above the other -- tag each one where it is high
for tag, ty, col in [("PSEL", YAPB + 2.4, fs.ACCENT),
                     ("PENABLE", YAPB + 1.0, fs.ACCENT),
                     ("PREADY", YAPB - 0.4, C_RESP)]:
    fs.label(ax, X0 + 7 * U + 0.9, ty, tag, fs=5.8, color=col, weight="bold",
             ha="left", va="center")

fs.cycle_guides(ax, X0, N, U, bottom=15.6, top=46.0,
                names=["clk%d" % i for i in range(N)], name_fs=6.6)

# the deliberate demonstration: two different retire cycles, two channels
fs.dot(ax, X0 + 1 * U, YAW + HI, fc=fs.GREEN)
fs.label(ax, X0 + 1 * U, YAW - 3.75, "AW retires (clk1)", fs=6.4,
         color="#1B5E20", weight="bold")
fs.dot(ax, X0 + 4 * U, YW + HI, fc=fs.ACCENT)
fs.label(ax, X0 + 4 * U, YW - 3.75, "W retires (clk4) \u2014 a different cycle",
         fs=6.4, color=fs.ACCENT, weight="bold")
print("lanes ok")

# ------------------------------------------------------- (2) the PHASE bar
fs.badge(ax, 4.6, 12.4, "2", r=1.3, fc=fs.ACCENT, tc="white", fs=8.4)
fs.label(ax, 7.4, 12.4, "PHASE \u2014 apb_state_q plus the APB signals it drives",
         fs=7.4, color=fs.TXT, weight="bold", ha="left")
fs.phase_bar(ax, X0, N, 8.6, 3.0,
             [(0, 5, "IDLE \u2014 no PSEL yet", "#EDEDED"),
              (5, 6, "SETUP", fs.S_ADDR),
              (6, 7, "ACCESS", fs.S_WRITE),
              (7, 9, "RESPONSE", fs.S_RESP)], unit=U, fs=6.4)

# ------------------------------- (3) the commit cycle and the cycle arithmetic
CX = X0 + 7 * U
fs.badge(ax, 98.9, 37.4, "3", r=1.3, fc=fs.ACCENT, tc="white", fs=8.4)
fs.label(ax, 101.4, 37.4, "THE COMMIT CYCLE \u2014 clk7", fs=6.9,
         color=fs.ACCENT, weight="bold", ha="left")
fs.txn_mark(ax, CX, YB + HI,
            "BVALID rises at clk7\n"
            "PREADY is sampled inside ACCESS at clk6,\n"
            "so the response cannot exist one clock\n"
            "earlier:  clk1 AW \u2192 clk5 PSEL \u2192 clk6 PREADY\n"
            "\u2192 clk7 BVALID  =  6 clocks end to end (7 \u2212 1)",
            xytext=(232, 12), fs=6.2, ha="center", va="center", arrow=True)

fs.note(ax, RC0, 13.4, RC1 - RC0, 11.2,
        "WHY BVALID CANNOT RISE EARLIER\n"
        "1   PSEL may not rise until BOTH halves of the\n"
        "     transfer are held.  W only retires at clk4,\n"
        "     so the earliest legal PSEL is clk5.\n"
        "2   APB needs a whole SETUP clock before the\n"
        "     ACCESS clock in which PREADY is sampled.\n"
        "3   BVALID is the response to PREADY, so it can\n"
        "     only rise in the clock after clk6.",
        fs=5.9, kind="note", valign="top")
print("phase + commit ok")

# ------------------------------------------------ the punchline / invariant
fs.eqbox(ax, 3.0, 0.8, 120.3, 6.6,
         "INVARIANT \u2014 the bridge must not accept the next AXI-Lite transaction "
         "until the APB access phase ends.\n"
         "Accept early and a second PSEL rises while the first access is still open, "
         "so two APB slaves would see overlapping selects on one bus.",
         fs=7.4)

fs.footer(fig, "FAILURE MODES \u2014 AWVALID arriving before WVALID (legal AXI: park "
               "the address, assert no PSEL), or a slave that never asserts PREADY "
               "(FSM parks in Access; fig05 monitor fires at 16 clocks).")

print(fs.qa_report(fig))
fs.save(fig, "fig20_axi_lite_to_apb_bridge_timing.png")
