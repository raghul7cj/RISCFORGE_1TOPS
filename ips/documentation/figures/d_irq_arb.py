"""fig16 - IRQ arbitration: the LIVE in-core irq_gateway + irq_arbiter
(fixed inter-class priority, intra-class round-robin, no claim) contrasted
with the CLIC claim/complete scheme the SoC does not instantiate.

RTL read:
  riscv_core/rtl/top.v            (irq_raw / edge_mode wiring, lines 204-249)
  riscv_core/rtl/irq_gateway.v    (edge capture + sticky latch)
  riscv_core/rtl/irq_arbiter.v    (class decode, RR, inter-class, preempt)
  clic-master/clic.sv             (mode localparams; claim reg) - NOT built
  RTL_SOC/riscforge_soc_subsystem.sv:1164,1236-1251 (6th APB slot replaces
        CLIC, ext_irq_i/sw_irq_i tied 0, fast_irq_i map)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

TITLE = ("Arbitration resolves at two different points \u2014 the live in-core arbiter "
         "picks by fixed inter-class priority with round-robin inside a class, "
         "while a CLIC would pick only when software claims, and the two give "
         "different winners")
SUB = ("read A sources \u2192 B the live arbiter \u2192 C one timeline \u00b7 the dashed "
       "panel and the CLIC rows are the scheme that is NOT built  (CLIC = Core "
       "Local Interruptor)")

T1 = ("Arbitration resolves at two different points \u2014 the live in-core arbiter "
      "picks by fixed inter-class priority with round-robin inside a class,")
T2 = ("while a CLIC would pick only when software claims, and the two give "
      "different winners")

fig, ax = fs.slide(None, None)
X, Y = fs.canvas(ax)

# ---- custom two-line title (title_block does not wrap) --------------------
fs.label(ax, X / 2.0, 56.4, T1, fs=10.6, color=fs.ACCENT, weight="bold", va="center")
fs.label(ax, X / 2.0, 54.2, T2, fs=10.6, color=fs.ACCENT, weight="bold", va="center")
fs.label(ax, X / 2.0, 51.9, SUB, fs=8.4, color=fs.GREY, va="center")
ax.plot([4.0, X - 4.0], [50.6, 50.6], color=fs.MID, lw=1.1, alpha=0.75)

# ---------------------------------------------------------------- lane budget
BUDGET = [
    # name,                 x0,    x1,    y0,    y1,   what lives here
    ("title/subtitle/rule", 4.0, 121.0, 51.0, 57.0, "2-line title + subtitle"),
    ("A  source table",      4.0,  56.0, 31.0, 49.2, "6 live sources -> mip"),
    ("A' CLIC COMPARE",     58.0, 121.0, 31.8, 49.8, "dashed, 6 claim steps"),
    ("B  live arbiter chain", 4.3, 120.7, 20.2, 29.0, "6 numbered boxes"),
    ("B' eq / rule boxes",   4.0, 121.0, 17.6, 19.8, "active[] + preempt eq"),
    ("C  preemption fall",   4.0,  96.0,  2.5, 17.4, "9-slot timeline, 2 rows"),
    ("C' rule callouts",    99.5, 121.0,  2.3, 17.4, "3 fs.note, NO wire"),
]
print(f"canvas {X:.1f} x {Y:.1f} units | content x[4,{X-4:.0f}] y[2.4,57]")
print(f"title L1 {fs.text_w(ax, T1, 10.6, 'bold'):.1f}u  "
      f"L2 {fs.text_w(ax, T2, 10.6, 'bold'):.1f}u  "
      f"sub {fs.text_w(ax, SUB, 8.4):.1f}u  (limit {X-8:.1f}u)")
print("LANE BUDGET")
for nm, a, b, c, d, wh in BUDGET:
    print(f"  {nm:<22} x[{a:6.1f},{b:6.1f}] y[{c:5.1f},{d:5.1f}]  {wh}")

# =========================================================== L2  SOURCE TABLE
# real map: top.v:207 irq_raw = {fast_irq_i[11], timer_irq_i, fast_irq_i[3:0]}
# top.v:54-59 active[k] = pend_i[k] & mie_i[mipbit] & mstatus_mie_i
CLS_KIND = {2: "alarm", 1: "req", 0: "resp"}
CLS_FG = {2: "#7F1010", 1: fs.ACCENT, 0: "#548235"}
CLS_NM = {2: "C2 Real-Time", 1: "C1 Stream", 0: "C0 Background"}
SRC = [
    ("Watchdog slot", "spi_events_o[1]", "fast_irq_i[11] [5]", 2, "fixed > Timer0", "mip[27]"),
    ("Timer 0 compare", "timer0_irq_o[1]", "timer_irq_i   [4]", 2, "fixed < Watchdog", "mip[7]"),
    ("UART", "uart_int_o", "fast_irq_i[3] [3]", 1, "round-robin \u2194 SPI", "mip[19]"),
    ("SPI end-of-xfer", "spi_events_o[0]", "fast_irq_i[2] [2]", 1, "round-robin \u2194 UART", "mip[18]"),
    ("I2C", "i2c_interrupt_o", "fast_irq_i[1] [1]", 0, "round-robin \u2194 GPIO", "mip[17]"),
    ("GPIO global", "gpio_global_int_o", "fast_irq_i[0] [0]", 0, "round-robin \u2194 I2C", "mip[16]"),
]
TX0, TX1 = 4.0, 56.0
# col 0 starts at 5.2 so the 0.9-wide class swatch at TX0 never touches the
# source name; every cell then fits at ~6.4 pt (no per-column font shrink).
CXS = [5.2, 14.9, 23.7, 32.2, 41.0, 51.3, 56.0]
CW = [CXS[i + 1] - CXS[i] for i in range(6)]
HDR = ("A \u00b7 interrupt source", "SoC signal", "fast_irq_i / arb slot", "class",
       "intra-class rule", "mip bit")
fs.block(ax, TX0, 47.2, TX1 - TX0, 2.0, "", kind="dark", lw=0.8)
for i, h in enumerate(HDR):
    fs.label(ax, CXS[i] + CW[i] / 2.0, 48.2, h, fs=6.3, color="white", weight="bold")
for r, (nm, sig, idx, k, rule, mip) in enumerate(SRC):
    y0 = 47.2 - 2.05 * (r + 1)
    fs.block(ax, TX0, y0, TX1 - TX0, 2.05, "", kind="plain", lw=0.6, rounding=0.30)
    fs.block(ax, TX0, y0, 0.9, 2.05, "", kind=CLS_KIND[k], lw=0.7, rounding=0.30)
    cells = ((0, nm, True), (1, sig, False), (2, idx, False),
             (3, CLS_NM[k], True), (4, rule, False), (5, mip, True))
    for ci, t, bold in cells:
        col = CLS_FG[k] if ci == 3 else (fs.ACCENT if bold else fs.TXT)
        fs.label(ax, CXS[ci] + CW[ci] / 2.0, y0 + 1.03, t,
                 fs=fs.fit_fs(ax, t, CW[ci] - 0.7, fs=6.4,
                              weight="bold" if bold else "normal"),
                 weight="bold" if bold else "normal", color=col)
fs.note(ax, TX0, 30.9, TX1 - TX0, 3.8,
        "MEIP mip[11] / MSIP mip[3] are tied to 0 \u2014 no PLIC, no CLINT "
        "(soc_subsystem.sv:1250).\n"
        "fast_irq_i[10:4] ARE wired in the SoC but are dropped at top.v:548 \u2014\n"
        "mip[20..26] can therefore never be set by hardware.", fs=5.7)
# ================================================= L3a  LIVE ARBITER CHAIN (B)
# irq_arbiter.v, in evaluation order (purely combinational, no claim register)
BX = [4.3 + 19.8 * i for i in range(6)]
BW, BY0, BY1 = 17.4, 20.2, 26.4
CHAIN = [
    ("irq_gateway\npend[5:0]", "edge/level capture of slot [5:0]", "periph"),
    ("active[5:0]\npend & mie & MIE", "gated by mie bit", "req"),
    ("class decode\nC2 = {WD, T0}\nC1 = {UART, SPI}\nC0 = {I2C, GPIO}", None, "ctrl"),
    ("inter-class FIXED\nC2 > C1 > C0", "inside C2: WD > Timer0", "alarm"),
    ("intra-class\nround-robin", "rr_ptr_c1 / rr_ptr_c0", "write"),
    ("winner \u2192 irq_pending\n\u2192 trap taken", "no claim register", "cpu"),
]
fs.label(ax, 4.3, 29.9, "B  \u00b7  LIVE  \u2014  read 1\u20136 left to right: the in-core "
         "irq_gateway + irq_arbiter, one winner per cycle, no claim register",
         fs=7.2, color=fs.GREEN, weight="bold", ha="left", va="center")
for i, ((txt, sub, kind), x) in enumerate(zip(CHAIN, BX)):
    fs.badge(ax, x + BW / 2.0, 27.9, i + 1, r=1.05)
    fs.block(ax, x, BY0, BW, BY1 - BY0, txt, kind=kind, sub=sub, sub_fs=6.6, fs=7.9)
    if i:
        fs.wire(ax, (BX[i - 1] + BW, (BY0 + BY1) / 2.0), (x, (BY0 + BY1) / 2.0),
               color=fs.ACCENT, lw=1.7)
fs.eqbox(ax, 4.0, 17.6, 54.0, 2.2,
         "active[k] = pend_i[k] & mie_i[mip_bit] & mstatus.MIE"
         "        (irq_arbiter.v:54-59)", fs=7.0)
fs.eqbox(ax, 60.0, 17.6, 61.0, 2.5,
         "preempt_ok = (nest_depth == 0) | (winner_class > cur_class)"
         "     (irq_arbiter.v:150)\n"
         "WD = watchdog  \u00b7  T0 = Timer 0  \u00b7  "
         "C0 / C1 / C2 = Background / Stream / Real-Time", fs=6.6)
fs.wire(ax, (BX[5] + BW / 2.0, BY0), (BX[5] + BW / 2.0, 19.8), arrow=False,
        color=fs.ACCENT, lw=1.2)
# ============================================ L3b  CLIC CLAIM/COMPLETE COMPARE
PX0, PX1, PY0, PY1 = 58.0, 121.0, 31.8, 49.8
fs.block(ax, PX0, PY0, PX1 - PX0, PY1 - PY0, "", kind="plain", ls="--", lw=1.0)
fs.label(ax, PX0 + 1.4, 48.7, "D  \u00b7  NOT BUILT \u2014 clic.sv, the Core Local "
         "Interruptor (CLIC) claim scheme (SoC APB slot 6 replaces it)", fs=6.7,
         color=fs.RED, weight="bold", ha="left", va="center")
CX = [60.0, 80.2, 100.4]
CWID, RA0, RA1, RB0, RB1 = 18.0, 40.9, 44.9, 32.9, 36.9
CMID, CLO = (RA0 + RA1) / 2.0, (RB0 + RB1) / 2.0
CROW = [
    ("ip & ie & intmode\n\u2192 the line pends", "hardware picks for you", "bus"),
    ("key = {mode, prio, id}", "MSB: M(11) > HS > VS > U(00)", "ctrl"),
    ("priority tree, strict >\nLOWEST id wins a tie", "no round-robin, no classes", "req"),
    ("SW reads clicintctl.id", "the only arbitration point", "ctrl"),
    ("CLAIM: hw clears ip\n(1-cycle pulse)", "critical section opens", "write"),
    ("SW writes eid\n\u2192 complete, source freed", "cannot re-pend until done", "periph"),
]
for i, (txt, sub, kind) in enumerate(CROW):
    top = RA1 if i < 3 else RB1
    y0 = RA0 if i < 3 else RB0
    # no step badges here: the LIVE chain above owns 1-6, and a second 1-6 on the
    # same canvas reads as "these are the same six steps".
    fs.block(ax, CX[i % 3], y0, CWID, top - y0, txt, kind=kind, sub=sub,
             sub_fs=6.3, fs=6.9, lw=1.0, alpha=0.72)
for i in (0, 1):
    fs.wire(ax, (CX[i] + CWID, CMID), (CX[i + 1], CMID), color=fs.GREY, lw=1.2,
            alpha=0.8)
for i in (1, 2):
    fs.wire(ax, (CX[i - 1] + CWID, CLO), (CX[i], CLO), color=fs.GREY, lw=1.2,
            alpha=0.8)
fs.wire(ax, (CX[0], CMID), (CX[0], CLO), via=[(59.0, CMID), (59.0, CLO)],
        color=fs.GREY, lw=1.2, alpha=0.8)
fs.label(ax, 91.0, 39.6, "hardware has already chosen \u2014 only the ID is left to take",
         fs=6.6, color=fs.GREY, style="italic")
fs.wire(ax, (CX[2] + CWID, CLO), (74.5, RA1),
        via=[(120.0, CLO), (120.0, 47.5), (74.5, 47.5)],
        back=True, dashed=True, color=fs.GREY, lw=1.2)
fs.onwire(ax, 97.0, 47.5, "complete \u2192 ip free \u2192 a new event may pend again",
          fs=6.2, color=fs.GREY)
fs.label(ax, 59.4, 38.0, "read: top row left\u2192right, then bottom row left\u2192right",
         fs=6.0, color=fs.GREY, ha="left", va="center", style="italic")

# ================================================ L4a  PREEMPTION WATERFALL
WX0, WU, WN = 12.4, 8.55, 9


def wx(i):
    return WX0 + WU * i


EV = [(0, "GPIO pends\nmip[16]", fs.GREEN), (2, "UART pends\nmip[19]", fs.MID),
      (4, "SPI pends\nmip[18]", fs.MID), (6, "WD pends\nmip[27]", fs.RED),
      (8, "I2C pends\nmip[17]", fs.GREEN)]
for sl, txt, col in EV:
    for y0, y1 in ((3.7, 9.5), (14.85, 16.1)):
        ax.plot([wx(sl), wx(sl)], [y0, y1], color=col, lw=0.8, ls=(0, (2, 3)),
                alpha=0.55, zorder=2)
    fs.onwire(ax, wx(sl), 16.2, txt, fs=6.2, color=col)
LIVE = [("GPIO   mip[16]   C0", 0, 8, "resp", (13.2, 14.8)),
        ("UART   mip[19]   C1", 2, 8, "req", (11.4, 13.0)),
        ("WD  27", 6, 7, "alarm", (9.6, 11.2)),
        ("SPI  18", 8, 9, "req", (9.6, 11.2))]
for txt, a, b, kind, (y0, y1) in LIVE:
    fs.block(ax, wx(a), y0, wx(b) - wx(a), y1 - y0, txt, kind=kind, fs=6.3,
             rounding=0.25)
fs.label(ax, 7.7, 14.4, "C \u00b7 LIVE", fs=7.2, color=fs.GREEN, weight="bold")
fs.label(ax, 7.7, 13.4, "in-core arbiter", fs=6.2, color=fs.GREY)
fs.label(ax, 7.7, 7.3, "CLIC", fs=7.6, color=fs.RED, weight="bold")
fs.label(ax, 7.7, 6.3, "intended \u2014", fs=6.2, color=fs.GREY)
fs.label(ax, 7.7, 5.3, "not built", fs=6.2, color=fs.GREY)
ax.plot([WX0 - 0.6, wx(WN)], [3.6, 3.6], color=fs.GREY, lw=1.0)
for i in range(WN + 1):
    ax.plot([wx(i), wx(i)], [3.6, 3.2], color=fs.GREY, lw=0.8)
    if i < WN:
        fs.label(ax, wx(i) + WU / 2.0, 2.9, "s%d" % i, fs=6.0, color=fs.GREY)
fs.label(ax, wx(WN) + 0.8, 2.9, "time \u2192", fs=6.0, color=fs.GREY, ha="left")
# --- L4b  what a CLIC would have done at the same arrival points -----------
# plain text, not a pill: the pill pad was taller than the 1.3-unit lane
# between the dashed CLIC box (top 8.3) and the WD/SPI bars (bottom 9.6).
fs.label(ax, wx(4) + 2.2, 8.9, "SPI blocked at s4:  C1 > C1 is false", fs=6.0,
         weight="bold", color=fs.RED)
fs.label(ax, wx(8) - 1.4, 8.9, "I2C blocked:  C0 < C1", fs=6.0,
         weight="bold", color=fs.RED)
fs.block(ax, wx(0), 5.7, wx(WN) - wx(0), 2.6,
         "CLIC: winner = highest {mode, prio, id} key among ALL pending, every "
         "cycle \u2014 no cur_class gate\nand the tree compares with a strict \u2018>\u2019, "
         "so the LOWEST id wins every tie \u2014 the opposite of WD(27) > Timer0(7)",
         kind="plain", fs=6.0, lw=1.0, ls="--")
fs.block(ax, wx(4), 3.95, wx(5.8) - wx(4), 1.5,
         "CLIC nests SPI id 18 in UART", kind="req", fs=5.4, rounding=0.22,
         lw=1.0, ls="--")
fs.block(ax, wx(6.05), 3.95, wx(7.6) - wx(6.05), 1.5,
         "CLIC winner = GPIO id 16", kind="alarm", fs=5.4, rounding=0.22,
         lw=1.0, ls="--")


# ============================================ L5  RULE CALLOUTS (wire-free lane)
NOTES = [
    (12.7, "ROUND-ROBIN RULE",
     "rr_ptr_c1 / rr_ptr_c0 flip only on a\nwriteback commit, so the source just\n"
     "served is served LAST \u2014 both alternate.", fs.MID),
    (7.5, "FIXED INTER-CLASS PRIORITY",
     "C2 > C1 > C0 on every cycle. While any\nC1 or C2 bit is pending, no C0 "
     "source can\nbe chosen \u2014 a hot UART starves GPIO.", fs.RED),
    (2.3, "NO CLAIM \u2014 FINISH BEFORE mret",
     "The gateway latches with pulse-wins\nprecedence. The handler MUST clear "
     "its\nown source, or the next cycle re-enters.", fs.ORANGE),
]
for ny, head, body, col in NOTES:
    fs.note(ax, 99.5, ny, 21.5, 4.7, "", kind="note")
    fs.label(ax, 100.6, ny + 4.05, head, fs=6.3, color=col, weight="bold",
             ha="left")
    fs.label(ax, 100.6, ny + 3.4, body, fs=5.7, color="#3F3F3F", ha="left",
             va="top")
# class-colour key sits immediately after the B header it belongs to, so it can
# no longer be misread as the key for the dashed panel above it.
fs.legend_row(ax, 79.0, 29.9, [("box", "alarm", "C2 Real-Time"),
                               ("box", "req", "C1 Stream"),
                               ("box", "resp", "C0 Background")], fs=6.2)
# ============================================================ L6  FINISH / SAVE
FOOT = ("Failure mode: two sources at equal class priority with no deterministic "
        "tie-break livelock at the handler boundary \u2014 and with no claim, "
        "software must service the highest mip bit first or it re-enters "
        "forever.")
fs.pad_limits(ax, 0.06)
fs.footer(fig, FOOT)
print("footer width %.1f units (canvas %.1f)" % (fs.text_w(ax, FOOT, 8.0,
                                                          style="italic"), X))
fs.qa_report(fig)
fs.save(fig, "fig16_irq_arbitration.png")