#!/usr/bin/env python3
"""
fig09  APB Timer internals  --  RISCFORGE SoC peripheral figures.

RTL source (2 files, read-only):
  apb_timer-master/rtl/apb_timer.sv   APB front end, TIMER_CNT instances
  apb_timer-master/rtl/timer.sv       the timer itself (3 registers)

FACTS TAKEN FROM THE RTL (verified line by line):

  apb_timer.sv:17   parameter TIMER_CNT = 2
  apb_timer.sv:38   slave_address_int = PADDR[$clog2(TIMER_CNT)+3 : 4] = PADDR[4]
  apb_timer.sv:85   irq_o[2*k+1 : 2*k]  -> irq_o[1:0] t0, irq_o[3:2] t1
  apb_timer.sv:31   output [(TIMER_CNT*2)-1:0] irq_o = irq_o[3:0]
  apb_timer.sv:54-56 PSEL low -> PRDATA=0, PREADY=1, PSLVERR=0 (zero wait state)
  timer.sv:12-15    `REGS_MAX_IDX=2, REG_TIMER=2'b00, REG_TIMER_CTRL=2'b01,
                    REG_CMP=2'b10
  timer.sv:41       register_adr = PADDR[3:2]  ->  byte offsets +0x00/+0x04/+0x08
  timer.sv:16-18    PRESCALER_STARTBIT=3, PRESCALER_STOPBIT=5, ENABLE_BIT=0
  timer.sv:72       prescaler_int = regs_q[CTRL][5:3]   (3 bit, logic [2:0])
  timer.sv:47       regs_q / regs_n : 3 x 32 bit
  timer.sv:63-64    irq_o[0] (overflow) = EN && TIMER==32'hffff_ffff && PS==cnt
  timer.sv:67-68    irq_o[1] (compare)  = EN && CMP!=0 && TIMER==CMP && PS==cnt
  timer.sv:80-81    if (irq_o[0] || irq_o[1])  regs_n[TIMER] = 0     <-- RELOAD
  timer.sv:82-85    else if (EN && PS!=0 && PS==cnt) TIMER = TIMER+1   <-- prescale
  timer.sv:86-87    else if (EN && PS==0)              TIMER = TIMER+1   <-- every clk
  timer.sv:90-91    if (cycle_counter_q >= PS) cycle_counter_n = 0
  timer.sv:94-109   APB write; writing REG_CMP also clears TIMER to 0 (line 107)
  timer.sv:121-130  APB read returns TIMER / CTRL / CMP; no other address decodes
  timer.sv:139-140  reset -> all three registers 0  => EN=0, timer halted

  NOT IN THE RTL (do not draw as if they exist):
    STATUS register, MASK register, LOAD/RELOAD register, one-shot/periodic
    select bit, read-to-clear status, COUNT_WIDTH != 32.

  PREScaler math (verified): cycle_counter_q runs 0,1,..,PS then wraps, and the
  increment of TIMER happens on the cycle where cycle_counter_q == PS, so the
  tick period is PS+1 HCLK  ->  tick = HCLK/(PS+1), NOT HCLK/2**PS.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs  # noqa: E402  (drawing kernel - do not modify)

TITLE = ("No status bit and no reload: irq_o[1] is combinational "
         "REG_TIMER==REG_CMP, and the match itself clears the counter")
SUB = ("timer.sv, inside the APB (Advanced Peripheral Bus) Timer 0 slave "
       "\u2014 three registers at +0x00 / +0x04 / +0x08, a 3-bit prescaler "
       "PS in CTRL[5:3], and one compare-match interrupt line.")

# ---------------------------------------------------------------- coordinates
# canvas = X x Y  ->  125.3 x 59.1 units (13.0 x 7.3 in slide).  +y is up.
#
# COL A  x  3 .. 30   APB register file (3 x 32 bit) + "what does NOT exist"
# COL B  x 33 .. 91   datapath: prescaler row (y45-56), comparator row (y29-40)
# COL C  x 95 .. 121  irq_o[1] output block
# inset  y  1 .. 17   waveform (x 4..91)  +  formula box (x 95..121)
# notes  y 18.5..26.5 three callouts across the full width
#
# rects are (x0, y0, x1, y1)
XA0, XA1 = 3.0, 30.0
# block heights are sized to their two lines of text (title + sub); the wire
# axes stay at y 50.5 / 34.5, i.e. every row keeps its mid-height wire entry.
R1 = (XA0, 44.7, XA1, 50.3)        # REG_TIMER       +0x00  (also the counter)
R2 = (XA0, 36.7, XA1, 42.3)        # REG_TIMER_CTRL  +0x04
R3 = (XA0, 28.7, XA1, 34.3)        # REG_CMP         +0x08
NOTE_A = (XA0, 19.4, XA1, 26.5)
NOTE_B = (33.0, 17.6, 91.0, 26.5)
NOTE_C = (95.0, 1.2, 121.0, 13.4)
EQBOX = (95.0, 15.0, 121.0, 27.0)

G1 = (33.0, 47.1, 51.0, 53.9)      # cycle_counter_q[31:0]  prescaler sub-count
G2 = (57.0, 47.1, 71.0, 53.9)      # tick = (PS == cnt) && PS != 0
G3 = (75.0, 47.1, 91.0, 53.9)      # REG_TIMER  32-bit counter
G4 = (35.8, 31.1, 57.0, 37.9)      # comparator  REG_TIMER == REG_CMP
G5 = (61.0, 31.1, 80.0, 37.9)      # match / irq_o[1] qualifier
G6 = (96.0, 31.1, 121.0, 37.9)     # irq_o[1] out of the APB slave
HCLK = (31.4, 39.8, 37.6, 42.2)    # clock chip  (centre 34.5, 41.0)
CH_PS, CH_CMP = 31.0, 31.8         # COL A escape channels
LN_TICK = 43.4                     # G3 -> G4 return lane (over comparator row)
LN_RELOAD = 57.4                   # reload lane, over the top: x 83 -> 108
WAVE = dict(x0=44.0, n=8, u=5.9, gap=3.9, ch=2.7, y_q=11.7, y_t=7.8, y_c=3.9)
NOTE_D = (1.5, 1.6, 25.0, 15.4)   # "what does not exist", bottom left



def blk(ax, r, text, sub, kind):
    return fs.block(ax, r[0], r[1], r[2] - r[0], r[3] - r[1], text, kind=kind,
                    fs=8.4, sub=sub, sub_fs=6.9)


def draw_reg_block(ax):
    """COL A - the three registers timer.sv actually decodes (PADDR[3:2])."""
    blk(ax, R1, "REG_TIMER", "+0x00   32-bit counter value", "periph")
    blk(ax, R2, "REG_TIMER_CTRL", "+0x04   EN = bit 0,  PS (prescaler) = [5:3]",
        "ctrl")
    blk(ax, R3, "REG_CMP", "+0x08   compare value, 0 = disabled", "mem")
    fs.label(ax, (XA0 + XA1) / 2, 52.3, "APB register file  -  3 x 32 bit, "
            "PADDR[3:2]", fs=7.2, color=fs.MID, weight="bold")
    fs.brace_v(ax, 1.9, 28.7, 50.3, None, side="left")


# ------------------------------------------------------- reading-order markers
def draw_reading_order(ax):
    """The figure has three stages; say so, and give the eye an entry point."""
    fs.label(ax, 3.0, 56.6,
             "START HERE \u2193   read LEFT to RIGHT:   1 COUNT   \u2192   "
             "2 COMPARE   \u2192   3 INTERRUPT",
             fs=7.4, color=fs.ACCENT, weight="bold", ha="left")
    fs.label(ax, 33.0, 54.9, "1  COUNT", fs=7.4, color=fs.ACCENT,
             weight="bold", ha="left")
    fs.label(ax, 44.0, 40.4, "2  COMPARE", fs=7.4, color=fs.ACCENT,
             weight="bold", ha="left")
    fs.label(ax, 96.0, 40.4, "3  INTERRUPT", fs=7.4, color=fs.ACCENT,
             weight="bold", ha="left")


def draw_prescaler(ax):
    """COL B row 1 - HCLK -> prescaler sub-counter -> tick -> 32-bit counter."""
    blk(ax, G1, "cycle_counter_q[31:0]", "if (cnt >= PS) cnt = 0", "ctrl")
    blk(ax, G2, "tick", "PS == cnt  &&  PS != 0", "plain")
    blk(ax, G3, "REG_TIMER", "regs_q[0]  +0x00 register", "periph")
    fs.chip(ax, 34.5, 41.0, "HCLK", fs=7.0)
    fs.label(ax, 34.5, 39.1, "bus clock", fs=6.0, color=fs.GREY)
    fs.wire(ax, (34.5, 42.2), (34.5, 47.1))
    fs.wire(ax, (51.0, 50.5), (57.0, 50.5), label="HCLK")
    fs.wire(ax, (71.0, 50.5), (75.0, 50.5), label="tick")
    # CTRL[5:3] -> prescaler_int, escaping through channel CH_PS
    fs.wire(ax, (XA1, 39.5), (33.0, 50.5), via=[(CH_PS, 39.5), (CH_PS, 50.5)],
            label="PS", label_at=(31.9, 47.5))


def draw_match_irq(ax):
    """Comparator -> match -> irq_o[1], plus the self-clear reload detour.

    timer.sv has NO status register and NO mask: irq_o[1] is a pure
    combinational function of regs_q, and the same condition that raises it
    forces regs_n[REG_TIMER] = 0, so the pulse is exactly one cycle wide.
    """
    blk(ax, G4, "REG_TIMER == REG_CMP", "32-bit equality, no mask term", "alarm")
    blk(ax, G5, "match", "EN=1  &  REG_CMP!=0  &  PS==cnt", "resp")
    blk(ax, G6, "irq_o[1]  compare interrupt",
        "1 cycle wide - no status bit to clear", "alarm")
    # counter value down to the comparator, over the comparator row
    fs.wire(ax, (83.0, 47.1), (40.0, 37.9),
            via=[(83.0, LN_TICK), (40.0, LN_TICK)], label="regs_q[0]",
            label_at=(62.0, LN_TICK))
    # REG_CMP up into the comparator's west edge
    fs.wire(ax, (XA1, 31.5), (35.8, 34.5),
            via=[(CH_CMP, 31.5), (CH_CMP, 34.5)], label="CMP",
            label_at=(33.8, 34.5))
    fs.wire(ax, (57.0, 34.5), (61.0, 34.5), label="eq")
    fs.wire(ax, (80.0, 34.5), (96.0, 34.5), label="irq_o[1]",
            label_at=(88.0, 34.5))
    # self-clear: routed AROUND the top perimeter, never through the comparator
    fs.wire(ax, (108.5, 37.9), (83.0, 53.9),
            via=[(108.5, LN_RELOAD), (83.0, LN_RELOAD)],
            label="regs_n[REG_TIMER] = 0   -   the match clears the counter",
            label_at=(96.0, LN_RELOAD))


FORMULA = ("timer.sv relations\n"
           "PS     = CTRL[5:3]     (3 bit)\n"
           "tick   = HCLK / (PS + 1)\n"
           "T_cmp  = CMP ticks  (EN = 1)\n"
           "period = (CMP + 1) x tick\n"
           "irq_o[0] @ TIMER = 0xFFFF_FFFF\n"
           "reload = 0  (no LOAD register)")


def draw_formula(ax):
    fs.eqbox(ax, EQBOX[0], EQBOX[1], EQBOX[2] - EQBOX[0], EQBOX[3] - EQBOX[1],
             FORMULA, fs=7.0)


def draw_inset(ax, fig):
    """8 clocks, PS = 0 (tick every HCLK), EN = 1, software wrote CMP = 5."""
    w = WAVE
    x0, n, u = w["x0"], w["n"], w["u"]
    fs.label(ax, x0, 15.8, "CLOCK LEVEL \u00b7 PS = 0, CMP = 5", fs=7.0,
             color=fs.ACCENT, weight="bold", ha="left")
    n0 = len(ax.lines)
    _, ys, u = fs.lanes(fig, [("q", "irq_o[1]", None),
                              ("t", "REG_TIMER", None),
                              ("c", "REG_CMP", None)],
                        x0, x0 + n * u, unit=u, lane_gap=w["gap"])
    # lanes() always rules to the right canvas edge; stop them at the eqbox
    for ln in ax.lines[n0:]:
        xs = list(ln.get_xdata())
        if len(xs) == 2 and xs[1] > 93.0:
            ln.set_xdata([xs[0], 93.0])
    fs.cycle_guides(ax, x0, n, u, bottom=2.3, top=14.0,
                    names=["0", "1", "2", "3", "4", "t = TIM", "6", "7"])
    fs.bus_cells(ax, x0, ["5"] * n, u, w["y_c"], w["ch"], fill=fs.S_WRITE)
    fs.bus_cells(ax, x0, ["0", "1", "2", "3", "4", "5", "0", "1"], u,
                 w["y_t"], w["ch"], fill=fs.S_ADDR)
    fs.sigwave(ax, x0, [0, 0, 0, 0, 0, 1, 0, 0], u,
               w["y_q"] - 1.1, w["y_q"] + 1.1, color=fs.RED, lw=2.0)
    fs.label(ax, x0 - 1.4, 11.9, "MATCH = irq_o[1]", fs=6.8, color=fs.RED,
             weight="bold", bbox=dict(fc="#FFFFFF", ec="none", pad=1.0))
    fs.txn_mark(ax, x0 + 5.5 * u, w["y_q"] + 1.1,
                "clock 5:  regs_q[0] == regs_q[2] (5)\n"
                "-> irq_o[1] = 1 and regs_n[REG_TIMER] = 0",
                xytext=(0, 13), fs=6.9)
    return ys


NOTE_B_TXT = (
    "THE INTERRUPT PATH, IN ONE SENTENCE\n"
    "  irq_o[1] = EN & REG_CMP!=0 & (REG_TIMER == REG_CMP) & PS==cnt \u2014 pure "
    "combinational logic on regs_q:\n"
    "  no status register, no mask bit, nothing for software to read-and-clear.\n"
    "  It is one cycle wide for free: the very comparison that raises it also "
    "forces regs_n[REG_TIMER] = 0\n"
    "  (timer.sv:80-81), so the counter restarts at 0 and the next match lands "
    "CMP + 1 ticks later \u2014 periodic by\n"
    "  construction, but only because it reloads 0. Writing REG_CMP also zeroes "
    "REG_TIMER (timer.sv:107), so re-arming\n"
    "  is one APB write.")

NOTE_C_TXT = (
    "APB FRONT END (apb_timer.sv)\n"
    "PREADY = 1, PSLVERR = 0 always:\n"
    "zero wait states, no error reply.\n"
    "Only +0x00 / +0x04 / +0x08 decode;\n"
    "+0x0C is silently dropped.\n"
    "PADDR[4] picks the instance:\n"
    "TIMER_CNT = 2, so timer 1 sits\n"
    "at +0x10 / +0x14 / +0x18.")

FOOTER = ("Failure mode avoided: an APB read of the counter is not atomic with the compare it is "
          "judged against, and there is no LOAD to reprogram mid-count - the deadline lives in "
          "its own COMPARE register.")


NOTE_FS = 6.5   # one size for all three sibling callouts


def draw_notes(ax):
    """Bottom band: the software view (left), the takeaway (centre), the
    APB front end (right).  The takeaway is an eqbox, not a note -- it is the
    sentence the title makes, so it has to outrank everything around it."""
    fs.note(ax, 1.5, 17.8, 25.0, 9.8,
            "WHAT FIRMWARE PROGRAMS \u2014 three writes,\n"
            "then the hardware repeats for ever.\n"
            "\n"
            "  1  write +0x08 = N   (also zeroes TIMER)\n"
            "  2  write +0x04 = 1 | PS<<3   (EN = 1, PS\n"
            "        is the prescaler field)\n"
            "  3  done \u2014 repeats every N+1 ticks",
            fs=6.5, pad_x=1.0, pad_y=0.7)
    fs.note(ax, NOTE_D[0], NOTE_D[1], NOTE_D[2] - NOTE_D[0],
            NOTE_D[3] - NOTE_D[1],
            "AND WHAT THIS TIMER DOES NOT HAVE\n"
            "\n"
            "  No STATUS register.  No MASK register.\n"
            "  No LOAD / RELOAD register \u2014 reload is\n"
            "  hard-wired to 0, so the timer is periodic\n"
            "  by construction and there is no one-shot /\n"
            "  periodic bit: there is nothing to reload\n"
            "  from.  Re-arming it is just step 1 above,\n"
            "  one APB write.",
            fs=6.5, pad_x=1.0, pad_y=0.7)
    fs.eqbox(ax, 27.0, 18.0, 66.0, 9.6, NOTE_B_TXT, fs=6.4)
    fs.note(ax, 95.0, 1.2, 26.0, 13.4, NOTE_C_TXT, fs=NOTE_FS, pad_x=0.9,
            pad_y=0.7)


def main():
    fig, ax = fs.slide(TITLE, SUB)
    X, Y = fs.canvas(ax)
    print(f"canvas = {X:.1f} x {Y:.1f} units")
    draw_reg_block(ax)
    draw_reading_order(ax)
    draw_prescaler(ax)
    draw_match_irq(ax)
    draw_formula(ax)
    draw_inset(ax, fig)
    draw_notes(ax)
    fs.footer(fig, FOOTER)
    fs.pad_limits(ax, 0.06)
    fs.qa_report(fig)
    fs.save(fig, "fig09_apb_timer_internals.png")
    return fig, ax



if __name__ == "__main__":
    main()
