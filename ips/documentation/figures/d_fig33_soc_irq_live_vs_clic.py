"""fig33 - the LIVE SoC interrupt path vs the CLIC that is NOT built, in one
honest side-by-side, plus the preemption waterfall that shows the two schemes
handing a DIFFERENT winner for the same six events.

Parents (FROZEN, copied from, never modified):
  d_clic.py      -> fig15_clic_internals.png  (CLIC claim scheme, mintvec rule)
  d_irq_arb.py   -> fig16_irq_arbitration.png (live gateway + arbiter, waterfall)

RTL read (nothing new invented):
  riscv_core/rtl/top.v            irq_raw wiring / dropped fast_irq_i[10:4]
  riscv_core/rtl/irq_gateway.v    edge capture
  riscv_core/rtl/irq_arbiter.v    class decode, RR, inter-class, preempt
  clic-master/clic_target.sv      priority tree, strict '>', claim pulse
  RTL_SOC/riscforge_soc_subsystem.sv:1164 (6th APB slot replaces CLIC),
        1250-1251 (ext_irq_i/sw_irq_i = 0), 1236-1251 (fast_irq_i map)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

T1 = ("None of the CLIC is connected: this SoC ships a 6-source in-core "
      "gateway and a 2-class arbiter")
T2 = ("straight into mip[16..27] \u2014 with no claim step, no ID and no mintvec")
SUB = ("read 1 sources \u2192 2 the wires it drops \u2192 3 the live arbiter \u2192 "
       "4 the CLIC that is NOT built \u2192 5 the same six events, two different "
       "winners")
G1 = ("CLIC = Core Local Interruptor  \u00b7  mip = machine interrupt-pending  "
      "\u00b7  mie = machine interrupt-enable  \u00b7  MIE = the mstatus.MIE "
      "global gate")
G2 = ("NMI = non-maskable interrupt, the aon_timer's nmi_wdog_timer_bark_o \u2014 "
      "aon_timer/ is not instantiated, so no NMI exists  \u00b7  WD = watchdog  "
      "\u00b7  T0 = Timer 0")

fig, ax = fs.slide(None, None)
X, Y = fs.canvas(ax)

fs.label(ax, X / 2.0, 56.6, T1, fs=11.2, color=fs.ACCENT, weight="bold",
         va="center")
fs.label(ax, X / 2.0, 54.6, T2, fs=11.2, color=fs.ACCENT, weight="bold",
         va="center")
fs.label(ax, X / 2.0, 52.6, SUB, fs=8.4, color=fs.GREY, va="center")
ax.plot([4.0, X - 4.0], [51.4, 51.4], color=fs.MID, lw=1.1, alpha=0.75)

print(f"canvas {X:.1f} x {Y:.1f} | limit {X - 8:.1f}u")
print(f"  T1 {fs.text_w(ax, T1, 11.2, 'bold'):.1f}u   T2 {fs.text_w(ax, T2, 11.2, 'bold'):.1f}u"
      f"   SUB {fs.text_w(ax, SUB, 8.4):.1f}u")
print(f"  G1 {fs.text_w(ax, G1, 7.0, 'bold'):.1f}u   G2 {fs.text_w(ax, G2, 7.0, 'bold'):.1f}u")
# ===================================================== L0  entry point + glossary
# chip() takes the VERTICAL CENTRE of the pill
c0 = fs.chip(ax, 4.0, 49.9, "START HERE", fs=7.4, fc=fs.ACCENT, tc="white")
c1 = fs.chip(ax, c0[0] + c0[2] + 2.0, 49.9,
             "read 1\u20135  \u00b7  left = BUILT (solid)  \u00b7  right = NOT "
             "BUILT (dashed, de-emphasised)", fs=7.0, fc="#FFFFFF", ec=fs.GREY,
             tc="#404040")
fs.chip(ax, 4.0, 48.1, G1, fs=7.0, fc="#FFFFFF", ec=fs.GREY, tc="#404040")
fs.chip(ax, 4.0, 46.3, G2, fs=7.0, fc="#FFFFFF", ec=fs.GREY, tc="#404040")
print(f"  entry row ends x={c1[0] + c1[2]:.1f}u  chip h={c0[3]:.2f}u")

# ==================================== L1 (left)  THE SOURCES THE SOC REALLY WIRES
LX0, LX1 = 4.0, 61.0
fs.label(ax, LX0, 44.6, "1  \u00b7  LIVE SOURCES \u2014 the six interrupts this SoC "
         "actually wires, solid = real elaborated RTL", fs=7.2, color=fs.GREEN,
         weight="bold", ha="left", va="center")
CXS = [5.2, 17.2, 29.2, 40.0, 50.0, 61.0]
CW = [CXS[i + 1] - CXS[i] for i in range(5)]
HDR = ("A \u00b7 interrupt source", "SoC signal", "fast_irq_i \u2192 slot",
       "class (arbiter_decode)", "mip bit")
fs.block(ax, LX0, 42.2, LX1 - LX0, 1.9, "", kind="dark", lw=0.8)
for i, h in enumerate(HDR):
    fs.label(ax, CXS[i] + CW[i] / 2.0, 43.15, h, fs=6.1, color="white",
             weight="bold")
CLS_KIND = {2: "alarm", 1: "req", 0: "resp"}
CLS_FG = {2: "#7F1010", 1: fs.ACCENT, 0: "#548235"}
CLS_NM = {2: "C2 Real-Time", 1: "C1 Stream", 0: "C0 Background"}
SRC = [
    ("Watchdog slot", "spi_events_o[1]", "fast_irq_i[11] \u2192 slot 5", 2, "mip[27]"),
    ("Timer 0 compare", "timer0_irq_o[1]", "timer_irq_i \u2192 slot 4", 2, "mip[7]"),
    ("UART rx/tx", "uart_int_o", "fast_irq_i[3] \u2192 slot 3", 1, "mip[19]"),
    ("SPI end-of-xfer", "spi_events_o[0]", "fast_irq_i[2] \u2192 slot 2", 1, "mip[18]"),
    ("I2C done/err", "i2c_interrupt_o", "fast_irq_i[1] \u2192 slot 1", 0, "mip[17]"),
    ("GPIO global", "gpio_global_int_o", "fast_irq_i[0] \u2192 slot 0", 0, "mip[16]"),
]
for r, (nm, sig, slot, k, mip) in enumerate(SRC):
    y0 = 42.2 - 1.72 * (r + 1)
    fs.block(ax, LX0, y0, LX1 - LX0, 1.72, "", kind="plain", lw=0.6, rounding=0.30)
    fs.block(ax, LX0, y0, 0.9, 1.72, "", kind=CLS_KIND[k], lw=0.7, rounding=0.30)
    cells = ((0, nm, True), (1, sig, False), (2, slot, False),
             (3, CLS_NM[k], True), (4, mip, True))
    for ci, t, bold in cells:
        col = CLS_FG[k] if ci == 3 else (fs.ACCENT if bold else fs.TXT)
        fs.label(ax, CXS[ci] + CW[ci] / 2.0, y0 + 0.86, t,
                 fs=fs.fit_fs(ax, t, CW[ci] - 0.6, fs=6.2,
                              weight="bold" if bold else "normal"),
                 weight="bold" if bold else "normal", color=col)
# ============================ L2 (left)  THE DROPPED WIRES -- a real defect
fs.label(ax, LX0, 31.1, "2  \u00b7  DROPPED WIRES \u2014 seven of the twelve "
         "fast_irq_i lines never reach the gateway", fs=7.2, color=fs.RED,
         weight="bold", ha="left", va="center")
DEF = ["riscforge_soc_subsystem.sv DRIVES fast_irq_i[10:4] (Timer0 ch0/ch1, "
       "Timer1 ch0/ch1),",
       "but top.v hands the gateway only  {4'b0, pend_gateway[5], 7'b0, "
       "pend_gateway[3:0]}",
       "\u2192 mip[20..26] can NEVER be set by hardware. Only 6 of 12 wires "
       "survive."]
fs.note(ax, LX0, 27.2, LX1 - LX0, 3.2, "\n".join(DEF), fs=5.4, kind="note")

# ================================ L3 (left)  THE LIVE ARBITER, one winner/cycle
fs.label(ax, LX0, 26.2, "3  \u00b7  LIVE CHAIN \u2014 read left to right: one winner "
         "every cycle, chosen by hardware, no claim step", fs=7.2,
         color=fs.GREEN, weight="bold", ha="left", va="center")
BX = [4.2 + 19.2 * i for i in range(3)]
BW, BY0, BY1 = 17.2, 19.7, 25.4
CHAIN = [
    ("irq_gateway\npend[5:0]", "edge / pulse capture, slot [5:0]", "periph"),
    ("irq_arbiter\nC2 > C1 > C0  fixed\nround-robin in a class",
     "rr_ptr flips on commit", "ctrl"),
    ("mip[16..27]\nno claim reg \u00b7 no ID\nno mintvec",
     "trap taken the same cycle", "cpu"),
]
for i, (txt, sub, kind) in enumerate(CHAIN):
    fs.block(ax, BX[i], BY0, BW, BY1 - BY0, txt, kind=kind, sub=sub, sub_fs=6.0,
             fs=7.4)
    for ln in txt.split("\n"):
        assert fs.text_w(ax, ln, 7.4, "bold") < BW - 0.8, (i, ln)
    assert fs.text_w(ax, sub, 6.0) < BW - 0.8, (i, sub)
    if i:
        fs.wire(ax, (BX[i - 1] + BW, (BY0 + BY1) / 2.0), (BX[i], (BY0 + BY1) / 2.0),
                color=fs.ACCENT, lw=1.7)
fs.eqbox(ax, LX0, 18.0, LX1 - LX0, 1.9,
         "active[k] = pend_i[k] & mie_i[mip_bit] & mstatus.MIE        "
         "(irq_arbiter.v:54-59)", fs=6.8)
# =========================== L4 (right)  WHAT THE CLIC WOULD DO -- NOT BUILT
RX0, RX1 = 64.0, 121.0
fs.block(ax, RX0, 28.6, RX1 - RX0, 17.0, "", kind="plain", ls=(0, (5, 3)),
         lw=1.2)
fs.label(ax, RX0 + 1.2, 44.6, "4  \u00b7  NOT BUILT \u2014 what a CLIC would do "
         "instead (dashed, de-emphasised)", fs=7.2, color=fs.RED,
         weight="bold", ha="left", va="center")
CLIC = [
    ("the priority tree resolves at CLAIM time, never continuously",
     "no winner exists while software has not asked for one", "bus"),
    ("the tree compares with a strict `>` \u2192 the LOWEST id wins a tie",
     "the live arbiter does the opposite: WD 27 beats Timer0 7", "req"),
    ("priority is a packed key = {mode, vsprio, prio}, mode is the MSB",
     "M(11) > HS(10) > VS(01) > U(00)   \u00b7   clic_target.sv", "ctrl"),
    ("CLAIM clears ip for exactly one cycle; hardware hands SW only an ID",
     "mintvec = ID * 4 + base \u2014 computed by software, no hw register", "write"),
]
for i, (txt, sub, kind) in enumerate(CLIC):
    y1 = 43.2 - 3.5 * i
    fs.block(ax, 65.4, y1 - 3.2, 54.2, 3.2, "", kind="plain", ls="--", lw=1.0,
             alpha=0.55)
    fs.label(ax, 65.9, y1 - 0.85, txt, fs=fs.fit_fs(ax, txt, 53.0, 6.6),
             ha="left", va="center", color=fs.GREY, weight="bold")
    fs.label(ax, 65.9, y1 - 2.35, sub, fs=fs.fit_fs(ax, sub, 53.0, 6.0),
             ha="left", va="center", color=fs.GREY)
# --- ground truth: why nothing on the right is in the silicon
TRUTH = [
    "GROUND TRUTH \u00b7 WHY NOTHING ON THE RIGHT IS IN THE SILICON",
    "riscforge_soc_subsystem.sv never instantiates `clic`: line 1164 says the "
    "6th APB slot 'replaces CLIC at",
    "this APB slot'.  clic-master/ is real, elaborated, Apache-2.0 RTL \u2014 "
    "just not connected to this SoC.",
    "ext_irq_i and sw_irq_i are tied to 1'b0 (1250-1251: 'no platform PLIC', "
    "'no CLINT') \u2192 MEIP mip[11]",
    "and MSIP mip[3] are dead.  aon_timer/ is not instantiated at all \u2192 no "
    "NMI source, no AON wake.",
    "The APB/AXI timeout sticky is an observation, not an interrupt: the CPU "
    "sees an access fault (mcause 5/7).",
    "The seven dropped fast_irq_i[10:4] lines (step 2) would have been CLIC "
    "IDs 4..10 \u2014 the closest this",
    "SoC comes to a wider ID space.",
]
fs.note(ax, RX0, 17.6, RX1 - RX0, 10.0, "\n".join(TRUTH), fs=5.2, kind="note",
        valign="center")
ax.plot([62.5, 62.5], [17.2, 46.0], color=fs.GREY, lw=1.0, ls=(0, (3, 3)),
        alpha=0.7, zorder=2)
# ================= L5  ONE TIMELINE, TWO SCHEMES, TWO DIFFERENT WINNERS
fs.label(ax, LX0, 16.9, "5  \u00b7  THE SAME SIX EVENTS \u2014 the two schemes do "
         "not even pick the same winner", fs=7.2, color=fs.GREEN,
         weight="bold", ha="left", va="center")
WX0, WU, WN = 12.4, 8.55, 9


def wx(i):
    return WX0 + WU * i


EV = [(0, "GPIO pends mip[16]", fs.GREEN), (2, "UART pends mip[19]", fs.MID),
      (4, "SPI pends mip[18]", fs.MID), (6, "WD pends mip[27]", fs.RED),
      (8, "I2C pends mip[17]", fs.GREEN)]
for sl, txt, col in EV:
    ax.plot([wx(sl), wx(sl)], [3.7, 14.9], color=col, lw=0.8, ls=(0, (2, 3)),
            alpha=0.55, zorder=2)
    fs.label(ax, wx(sl), 15.4, txt, fs=6.1, color=col, weight="bold")
LIVE = [("GPIO   mip[16]   C0", 0, 8, "resp", (13.2, 14.8)),
        ("UART   mip[19]   C1", 2, 8, "req", (11.4, 13.0)),
        ("WD  27", 6, 7, "alarm", (9.6, 11.2)),
        ("SPI  18", 8, 9, "req", (9.6, 11.2))]
for txt, a, b, kind, (y0, y1) in LIVE:
    fs.block(ax, wx(a), y0, wx(b) - wx(a), y1 - y0, txt, kind=kind, fs=6.3,
             rounding=0.25)
fs.label(ax, 7.7, 14.4, "LIVE", fs=7.4, color=fs.GREEN, weight="bold")
fs.label(ax, 7.7, 13.4, "in-core arbiter", fs=6.2, color=fs.GREY)
fs.label(ax, 7.7, 7.4, "CLIC", fs=7.4, color=fs.RED, weight="bold")
fs.label(ax, 7.7, 6.4, "NOT built \u2014", fs=6.2, color=fs.GREY)
ax.plot([WX0 - 0.6, wx(WN)], [3.6, 3.6], color=fs.GREY, lw=1.0)
for i in range(WN + 1):
    ax.plot([wx(i), wx(i)], [3.6, 3.2], color=fs.GREY, lw=0.8)
    if i < WN:
        fs.label(ax, wx(i) + WU / 2.0, 2.9, "s%d" % i, fs=6.0, color=fs.GREY)
fs.label(ax, wx(WN) + 0.8, 2.9, "time \u2192", fs=6.0, color=fs.GREY, ha="left")
fs.label(ax, wx(4) + 2.2, 8.9, "SPI blocked at s4:  C1 > C1 is false", fs=6.0,
         weight="bold", color=fs.RED)
fs.label(ax, wx(8) - 1.4, 8.9, "I2C blocked:  C0 < C1", fs=6.0, weight="bold",
         color=fs.RED)
fs.block(ax, wx(0), 5.7, wx(WN) - wx(0), 2.6,
         "CLIC: winner = highest {mode, prio, id} key among ALL pending, every "
         "cycle \u2014 no cur_class gate\nand the tree compares with a strict "
         "`>`, so the LOWEST id wins every tie \u2014 the opposite of WD(27) > "
         "Timer0(7)", kind="plain", fs=6.0, lw=1.0, ls="--")
fs.block(ax, wx(4), 3.95, wx(5.8) - wx(4), 1.5,
         "CLIC nests SPI id 18 in UART", kind="req", fs=5.4, rounding=0.22,
         lw=1.0, ls="--")
fs.block(ax, wx(6.05), 3.95, wx(7.6) - wx(6.05), 1.5,
         "CLIC winner = GPIO id 16", kind="alarm", fs=5.4, rounding=0.22,
         lw=1.0, ls="--")
# ============================== L6  RULE CALLOUTS (wire-free lane, far right)
RULES = [
    (10.4, 6.6, "STARVATION IS THE FAILURE MODE", fs.RED,
     "round-robin only re-orders sources\n"
     "INSIDE one class, and C2 > C1 > C0 is\n"
     "fixed on every cycle \u2014 so while any\n"
     "C1 or C2 bit is pending, I2C mip[17]\n"
     "and GPIO mip[16] wait."),
    (2.3, 6.6, "NO CLAIM \u00b7 THE GATE IS THREE WIDE", fs.ORANGE,
     "no claim register: the gateway latches\n"
     "with pulse-wins precedence, so the\n"
     "handler must clear its own source or\n"
     "the next cycle re-enters it.  A source\n"
     "must be pend AND mie AND MIE."),
]
for ny, nh, head, col, body in RULES:
    fs.note(ax, 99.0, ny, 22.0, nh, "", kind="note")
    fs.label(ax, 100.1, ny + nh - 0.85, head, fs=6.1, color=col, weight="bold",
             ha="left", va="center")
    fs.label(ax, 100.1, ny + nh - 1.75, body, fs=5.4, color="#3F3F3F", ha="left",
             va="top")

# ================================================================ FINISH / SAVE
FOOT = ("Failure mode \u2014 starvation: round-robin only re-orders sources "
        "inside a class, so GPIO mip[16] and I2C mip[17] can be postponed "
        "indefinitely while any C1 or C2 bit is pending.")
fs.pad_limits(ax, 0.06)
fs.footer(fig, FOOT)
print("footer width %.1f units (canvas %.1f, limit %.1f)"
      % (fs.text_w(ax, FOOT, 8.0, style="italic"), X, X - 8))
fs.qa_report(fig)
fs.save(fig, "fig33_soc_irq_live_vs_clic.png")