"""fig30 -- RISCFORGE APB SPI/QSPI master: there is no mode register.

Extracted from fig13 (d_spi_fsm.py): the hard-wired CPOL/CPHA treatment plus the
shift/FIFO datapath, given the whole canvas.

RTL read (same 3 files the parent used):
  spi_master_ip/spi_master/spi_master_controller.sv  (`SPI_STD/QUAD_TX/QUAD_RX, enum)
  spi_master_ip/spi_master/apb_spi_master.sv         (BUFFER_DEPTH = 10 FIFOs)
  spi_master_ip/spi_master/spi_master_clkgen.sv      (divider, spi_rise/spi_fall)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ============================== LANE BUDGET (1 unit = 0.1 inch) ==============
GRID_Y, GRID_H = 44.6, 10.0        # 44.6..54.6   the four CPOL/CPHA cells
DEAD_Y = 43.0                     # the MODE-state footnote
TRAP_Y, TRAP_H = 29.4, 9.8         # 29.4..39.2   the spi_mode[1:0] trap
CLK_Y, CLK_H = 18.6, 7.0           # 18.6..25.6   clkgen tier + SCLK equation
ROW_Y, ROW_H = 9.8, 7.6           #  9.8..17.4   the shift / FIFO data path
STALL_Y, STALL_H = 4.8, 3.6       #  4.8.. 8.4   the only back-pressure
GLOSS_Y = (3.1, 1.8)              # two glossary lines

TITLE = ("There is no mode register: CPOL = 0 and CPHA = 0 are hard-wired, so the "
         "shifters get `spi_fall`\nand `spi_rise`, and the FIFO can only stop the "
         "master by refusing to raise SCLK")
SUB = ("read top to bottom \u2014  1 \u00b7 the four SPI modes, and which one this RTL is "
       "in   2 \u00b7 the trap: `spi_mode[1:0]` is a bus-WIDTH code, not CPOL/CPHA   "
       "3 \u00b7 the only back-pressure: two 10-deep FIFOs, and the stall is silent")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}   usable x 4..121  y 1.5..57")

fs.chip(ax, 4.5, 55.6,
        "1 \u00b7 THE FOUR SPI MODES \u2014 START HERE \u25b6: the first cell is the only "
        "one that exists in this RTL", fs=6.6)

# ===================== BAND 1 : the 4-mode grid =============================
# grep CPOL|CPHA over every spi_master/*.sv  ->  zero hits.  The mode is fixed by
# two hard-wired facts instead:
#   clkgen resets spi_clk <= 1'b0 and parks it only at 0      -> CPOL = 0
#   tx_edge = spi_fall, rx_edge = spi_rise                   -> CPHA = 0
CW = (121.0 - 4.5 - 3 * 1.2) / 4.0
MODES = [(0, 0), (0, 1), (1, 0), (1, 1)]
for i, (cpol, cpha) in enumerate(MODES):
    x0 = 4.5 + i * (CW + 1.2)
    live = (cpol == 0 and cpha == 0)
    fs.block(ax, x0, GRID_Y, CW, GRID_H, "", kind="periph" if live else "mux",
             lw=2.2 if live else 1.0, alpha=1.0 if live else 0.5)
    fs.label(ax, x0 + CW / 2, 53.45, f"MODE {i}   \u00b7   CPOL {cpol}   \u00b7   CPHA {cpha}",
             fs=6.2, weight="bold", color="#1B5E20" if live else fs.GREY)
    fs.label(ax, x0 + CW / 2, 52.30,
             "\u25b6 THIS DESIGN \u2014 hard-wired" if live else "NOT IMPLEMENTED \u2014 needs an RTL change",
             fs=5.6, weight="bold", color="#1B5E20" if live else "#7A7A7A")
print("band1 grid ok")

# ---- inside each cell: 1.5 bit periods, both edges visible -----------------
LO, HI = 48.50, 51.30
for i, (cpol, cpha) in enumerate(MODES):
    x0 = 4.5 + i * (CW + 1.2)
    live = (cpol == 0 and cpha == 0)
    wx0, hw = x0 + 2.6, (CW - 5.2) / 3.0
    h = [wx0 + k * hw for k in range(4)]
    for xa, xb, fc in ((wx0, h[1], "#FBE4E4"), (h[1], h[2], "#E2EFDA"),
                       (h[2], wx0 + 3 * hw, "#FBE4E4")):
        ax.add_patch(fs.Rectangle((xa, LO - 0.30), xb - xa, (HI - LO) + 0.60,
                                  facecolor=fc, edgecolor="none", zorder=2))
    lv = [cpol, 1 - cpol, cpol]
    ys = [(HI if v else LO) for v in lv] + [HI if lv[-1] else LO]
    ax.add_line(fs.Line2D([wx0, h[1], h[2], wx0 + 3 * hw], ys, color="#303030",
                          lw=2.0, drawstyle="steps-post", zorder=5))
    s_x = h[1] if ((cpha == 0) == (cpol == 0)) else h[2]
    t_x = h[2] if s_x == h[1] else h[1]
    for xe, txt, col, at_high in ((s_x, "sample MISO", fs.GREEN,
                                   ((cpha == 0) == (cpol == 0))),
                                  (t_x, "shift MOSI", fs.ORANGE,
                                   ((cpha == 1) == (cpol == 0)))):
        rise = (cpol == 0) if at_high else (cpol == 1)
        ax.add_line(fs.Line2D([xe, xe], [LO - 0.34, HI + 0.34], color=col, lw=1.0,
                              ls=(0, (2, 2)), zorder=6))
        fs.dot(ax, xe, HI if rise else LO, r=0.31, fc=col, zorder=7)
        fs.label(ax, xe, 47.65, txt, fs=5.0, color=col, weight="bold")
    fs.label(ax, x0 + CW / 2, 45.55,
             f"idle SCLK = {cpol}   \u00b7   "
             f"{'sample on RISE, shift on FALL' if cpha == 0 else 'sample on FALL, shift on RISE'}",
             fs=5.4, color="#303030" if live else "#8C8C8C",
             weight="bold" if live else "normal")
print("band1 waves ok")

# ---- footnote: the MODE *state* is dead code (parent's verified finding) ----
fs.label(ax, 4.5, DEAD_Y,
         "One more trap: the FSM state MODE (5'b0_0011) does exist in the state enum, "
         "but no state_next ever targets it \u2014 it is dead code, reachable never, "
         "reported only as status[3]. It is not the SPI mode.",
         fs=5.5, color=fs.GREY, ha="left")

# ============= BAND 2 : the trap -- spi_mode[1:0] is NOT CPOL/CPHA ===========
fs.chip(ax, 4.5, 40.6,
        "2 \u00b7 THE TRAP \u2014 `spi_mode[1:0]` sounds like the mode bits and is not "
        "them: it is the bus-WIDTH code", fs=6.6)

fs.block(ax, 4.5, TRAP_Y, 42.0, TRAP_H,
         "WHAT THE NAME SUGGESTS\n"
         "Two bits you program, meaning the mode:\n"
         "  CPOL \u2014 clock polarity: is SCLK idle HIGH\n"
         "         (CPOL 1) or idle LOW (CPOL 0)?\n"
         "  CPHA \u2014 clock phase: is MISO sampled on\n"
         "         the edge MOSI changes, or the other?\n"
         "2 bits \u00d7 2 values = 4 modes, so any of\n"
         "modes 0\u20133 could be selected in software.",
         kind="note", fs=5.6, bold=False, ls=(0, (3, 2)))

fs.block(ax, 47.0, 32.9, 6.2, 4.4, "NOT CPOL\nOR CPHA", kind="alarm",
         fs=5.2, bold=True)

RX0, RX1 = 53.6, 121.0
fs.block(ax, RX0, TRAP_Y, RX1 - RX0, TRAP_H, "", kind="mux")
fs.label(ax, (RX0 + RX1) / 2.0, 37.95,
         "WHAT `spi_mode[1:0]` ACTUALLY IS \u2014 HOW MANY DATA LINES, "
         "not when to clock them", fs=6.0, weight="bold")
CODES = [("`SPI_STD`     2'b00", "single-lane SPI \u2014 1 wire out, 1 wire in", fs.MID),
         ("`SPI_QUAD_TX` 2'b01", "quad (4-line) data OUT \u2014 master drives 4", fs.ORANGE),
         ("`SPI_QUAD_RX` 2'b10", "quad (4-line) data IN  \u2014 master reads 4", fs.ACCENT)]
for k, (code, desc, col) in enumerate(CODES):
    cy = 36.15 - k * 2.35
    fs.chip(ax, RX0 + 2.4, cy, code, fc="#FFFFFF", ec=col, tc=col, fs=5.8)
    fs.label(ax, RX0 + 2.4 + fs.text_w(ax, code, fs=5.8, weight="bold") + 1.4, cy,
             desc, fs=5.4, color="#303030", ha="left")
fs.label(ax, RX0 + 2.4, 30.35,
         "chosen per transaction from the request strobes: spi_qrd | spi_qwr "
         "\u2192 SPI_QUAD_TX, otherwise SPI_STD (spi_master_controller.sv)",
         fs=5.2, color=fs.GREY, ha="left")
print("band2 trap ok")
# ============ BAND 3 : the only back-pressure = the FIFOs, not SCLK =========
fs.chip(ax, 4.5, 27.2,
        "3 \u00b7 THE SHIFT / FIFO DATAPATH \u2014 and the ONLY back-pressure in the IP",
        fs=6.6)

# ---- top tier : the clock generator and the divider it obeys --------------
fs.block(ax, 4.5, CLK_Y, 33.0, CLK_H,
         "WHY CPOL = 0 IS STRUCTURAL\n"
         "clkgen resets spi_clk <= 1'b0 and parks it\n"
         "only at 0 \u2014 no software bit can make SCLK\n"
         "idle HIGH. SCLK always idles LOW.",
         kind="note", fs=5.4, bold=False)
fs.block(ax, 40.0, CLK_Y, 38.0, CLK_H,
         "spi_master_clkgen   8-bit counter, reloads on clk_div_valid,\n"
         "toggles when counter == counter_trgt\n"
         "emits two strobes per SCLK period:  spi_rise  and  spi_fall",
         kind="ctrl", fs=5.4, bold=True)
fs.eqbox(ax, 82.0, CLK_Y, 39.0, CLK_H,
         "SCLK = HCLK / ( 2 \u00b7 (clk_div + 1) )\n"
         "half period = clk_div + 1 HCLK\n"
         "clk_div = 0 \u2192 HCLK / 2   (reset value)\n"
         "clk_div = 255 \u2192 HCLK / 512", fs=5.6)

# ---- bottom tier : the data path, left to right ----------------------------
TXF, TXS, SLV = (4.5, 26.0), (30.0, 50.0), (54.5, 66.5)
RXS, RXF = (71.0, 91.0), (95.0, 116.5)
BY = ROW_Y + ROW_H / 2.0
fs.block(ax, TXF[0], ROW_Y, TXF[1] - TXF[0], ROW_H,
         "TX FIFO\n32 b \u00d7 10 deep\nBUFFER_DEPTH = 10\n"
         "full \u2192 tx_clk_en = 0", kind="write", fs=5.2, bold=True)
fs.block(ax, TXS[0], ROW_Y, TXS[1] - TXS[0], ROW_H,
         "tx shifter   u_txreg\n32-b, MSB first, no byte swap\n"
         "tx_edge = spi_fall\nMOSI changes on the FALL",
         kind="write", fs=5.2, bold=True)
fs.block(ax, SLV[0], ROW_Y, SLV[1] - SLV[0], ROW_H,
         "the SPI\nSLAVE\n(off-figure)", kind="periph", fs=5.0, bold=True)
fs.block(ax, RXS[0], ROW_Y, RXS[1] - RXS[0], ROW_H,
         "rx shifter   u_rxreg\n32-b shift-in, MSB first\n"
         "rx_edge = spi_rise\nMISO sampled on the RISE",
         kind="req", fs=5.2, bold=True)
fs.block(ax, RXF[0], ROW_Y, RXF[1] - RXF[0], ROW_H,
         "RX FIFO\n32 b \u00d7 10 deep\nBUFFER_DEPTH = 10\n"
         "full \u2192 clk_en_o = 0", kind="req", fs=5.2, bold=True)
fs.wire(ax, (TXF[1], BY), (TXS[0], BY), label="32-b word", label_fs=5.2)
fs.wire(ax, (TXS[1], BY), (SLV[0], BY), label="MOSI", label_fs=5.2)
fs.wire(ax, (SLV[1], BY), (RXS[0], BY), label="MISO", label_fs=5.2)
fs.wire(ax, (RXS[1], BY), (RXF[0], BY), label="32-b word", label_fs=5.2)
print("band3 datapath ok")

# ---- clkgen drives the two shifters: one edge each, both hard-wired --------
fs.wire(ax, (52.0, CLK_Y), (42.0, ROW_Y + ROW_H),
        via=[(52.0, CLK_Y - 1.3), (42.0, CLK_Y - 1.3)],
        label="spi_fall  \u2192  tx_edge", label_at=(47.0, CLK_Y - 1.3), label_fs=5.2,
        color=fs.ORANGE)
fs.wire(ax, (66.0, CLK_Y), (81.0, ROW_Y + ROW_H),
        via=[(66.0, CLK_Y - 1.3), (81.0, CLK_Y - 1.3)],
        label="spi_rise  \u2192  rx_edge", label_at=(73.5, CLK_Y - 1.3), label_fs=5.2,
        color=fs.GREEN)
fs.label(ax, 79.0, 26.05,
         "the ONLY two edge strobes in the IP \u2014 which one goes to which "
         "shifter is fixed in the RTL, not in software", fs=5.4, color=fs.GREY,
         ha="right")

# ---- the back-pressure statement -------------------------------------------
fs.eqbox(ax, 4.5, STALL_Y, 116.5, STALL_H,
         "THE ONLY BACK-PRESSURE:  no word ready \u2192 tx_clk_en = 0 \u2192 the "
         "MASTER SIMPLY STOPS RAISING SCLK, so CS# stays LOW and the byte stalls "
         "mid-transfer.\n"
         "There is no ready/valid on the wire, no NACK and no error flag \u2014 a full "
         "FIFO just makes the transfer slower. The FIFO, not the wire, is what "
         "applies pressure.",
         fs=5.6)

# ---- glossary + failure mode ----------------------------------------------
fs.label(ax, 4.5, GLOSS_Y[0],
         "CPOL = clock polarity \u00b7 CPHA = clock phase \u00b7 SCLK = serial clock, "
         "the bit clock this MASTER drives \u00b7 MOSI = master-out / slave-in (data "
         "out) \u00b7 MISO = master-in / slave-out (data in)",
         fs=5.2, color=fs.GREY, ha="left")
fs.label(ax, 4.5, GLOSS_Y[1],
         "CS# = chip select, active low (the # is 'bar') \u00b7 SLAVE = the "
         "off-figure chip at the other end of the wire \u00b7 FIFO = first-in "
         "first-out queue \u00b7 quad = 4 data lines instead of 1",
         fs=5.2, color=fs.GREY, ha="left")
fs.footer(fig, "Failure mode: there is no handshake on the wire, so a CPOL/CPHA "
               "mismatch does not fault \u2014 it shifts every bit silently. The waveform "
               "still looks legal,\nno bus monitor flags it, and the payload arrives "
               "wrong. Only the CS# boundaries (which bytes the master framed) and "
               "a MOSI\u2192MISO loopback reveal it.")
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig30_spi_mode_and_backpressure.png")
