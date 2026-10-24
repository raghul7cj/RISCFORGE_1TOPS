"""fig13 -- RISCFORGE APB SPI/QSPI master (APB[4] @ 0x4000_4000):
the controller FSM, the hard-wired CPOL/CPHA mode, the shift/FIFO datapath and
one full-duplex byte on the wire.

RTL read:
  spi_master_ip/spi_master/spi_master_controller.sv  (enum state, CS#, edge mux)
  spi_master_ip/spi_master/apb_spi_master.sv         (BUFFER_DEPTH=10 FIFOs)
  spi_master_ip/spi_master/spi_master_clkgen.sv      (divider, spi_rise/spi_fall)
  spi_master_ip/spi_master/spi_master_tx.sv / _rx.sv (MSB-first shift, clk_en_o)
  spi_master_ip/spi_master/spi_master_fifo.sv        (full = elements==DEPTH)
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
# canvas 125.3 x 59.1 ; keep content inside x 4..121, y 1.5..57
TOP_LANE = 54.2          # perimeter return  WAIT_EDGE -> IDLE
ROWA_Y, ROWA_H = 45.6, 7.4        # 45.6..53.0   cy 49.3   command-phase chain
CORR_Y = 44.2           # branch lane     DUMMY -> DATA_TX
ROWB_Y, ROWB_H = 36.6, 6.4        # 36.6..43.0   cy 39.8   data phase + WAIT_EDGE
RET_LANE = 35.0         # perimeter return DATA_TX -> IDLE (under row B)
DP_Y, DP_H = 27.6, 6.6            # 27.6..34.2   datapath row (MOSI|clkgen|MISO|CS)
MODE_Y, MODE_H = 18.6, 6.4         # 18.6..25.0   4-mode CPOL/CPHA mini-diagrams
WAVE_GAP = 4.2          # waveform lanes: cs 4.2 / sclk 8.4 / mosi 12.6 / miso 16.8
CAP_Y = 1.2             # one-line bit-boundary caption under the lanes
WX0, WU = 26.0, 9.0     # 10 cells: 1 idle + 8 bits + 1 post  -> 26..116
# ---- row A boxes (command phase) ----  gaps >= 5.4 so the tx_done pills clear
A_X = [(5.5, 24.5), (30.5, 49.5), (55.5, 74.5), (80.5, 99.0), (103.0, 120.0)]
A_NAME = ["IDLE", "CMD", "ADDR", "DUMMY", "MODE"]
# ---- row B boxes (data phase) ----
B_X = [(46.0, 65.0), (71.0, 90.5), (96.5, 120.0)]
B_NAME = ["DATA_TX", "DATA_RX", "WAIT_EDGE"]
# ---- datapath boxes ----  gaps >= 4.9 so the spi_fall / spi_rise pills clear
D_X = [(5.0, 30.2), (35.1, 60.6), (65.5, 90.5), (95.4, 120.0)]
EQ_X, EQ_Y, EQ_W, EQ_H = 21.0, 36.6, 23.0, 6.4

TITLE = ("SPI has no handshake \u2014 the master only shifts, so the only back-pressure "
         "is the TX\nFIFO filling up and the clock stalling")
SUB = ("read top to bottom — BAND 1 controller FSM · BAND 2 shift/FIFO "
       "datapath · BAND 3 hard-wired mode (CPOL = clock polarity, CPHA = clock "
       "phase) · BAND 4 one byte on the wire")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print(f"canvas {XW:.1f} x {YH:.1f}   usable x 4..121  y 1.5..57")
print("LANE BUDGET")
print(f"  TOP perimeter {TOP_LANE} | FSM row A {ROWA_Y}..{ROWA_Y+ROWA_H} cy 49.3")
print(f"  corridor {CORR_Y} | FSM row B {ROWB_Y}..{ROWB_Y+ROWB_H} cy 39.8"
      f" | bottom return {RET_LANE}")
print(f"  eqbox {EQ_X}..{EQ_X+EQ_W} x {EQ_Y}..{EQ_Y+EQ_H}")
print(f"  datapath {DP_Y}..{DP_Y+DP_H}  (MOSI | clkgen | MISO | CS#)")
print(f"  mode strip {MODE_Y}..{MODE_Y+MODE_H}")
print(f"  waveform lanes {WAVE_GAP}..{4*WAVE_GAP}  grid {WX0}..{WX0+10*WU}  cap {CAP_Y}")
print(f"  row A x {A_X}")
print(f"  row B x {B_X}")
fs.pad_limits(ax, 0.06)

# ============================== LAYER 2 : the FSM =============================
# spi_master_controller.sv:94
#   enum logic [4:0] {IDLE,CMD,ADDR,MODE,DUMMY,DATA_TX,DATA_RX,WAIT_EDGE}
ACY, BCY = ROWA_Y + ROWA_H / 2.0, ROWB_Y + ROWB_H / 2.0      # 49.3 / 39.8
fs.chip(ax, 5.5, 56.4,
        "BAND 1 \u00b7 THE CONTROLLER FSM \u2014 enter at badge 1 (IDLE), then "
        "follow the arrows 2\u21927:  spi_master_controller.sv \u00b7 enum logic "
        "[4:0] state, state_next \u2014 8 states, 7 reachable", fs=6.6)

ROW_A = [
    ("IDLE  5'b0_0000   status[0]\n"
     "CS#\u21930, spi_clock_en\u21921\n"
     "go = rd|wr|qrd|qwr\n"
     "cmd_len\u22600 \u2192 CMD\n"
     "addr_len\u22600 \u2192 ADDR\n"
     "data_len\u22600 \u2192 DUMMY/DATA_*", "mux"),
    ("CMD   5'b0_0001   status[1]\n"
     "shifts spi_cmd out, MSB 1st\n"
     "counter_tx = cmd_len (BITS)\n"
     "exit: tx_done\n"
     " \u2192 ADDR if addr_len\u22600\n"
     " else DATA_* or IDLE", "ctrl"),
    ("ADDR  5'b0_0010   status[2]\n"
     "shifts spi_addr out, MSB 1st\n"
     "counter_tx = addr_len (BITS)\n"
     "exit: tx_done\n"
     " \u2192 DUMMY / DATA_TX / DATA_RX\n"
     " else IDLE (eot only from DUMMY)", "addr"),
    ("DUMMY 5'b0_0100   status[4]\n"
     "source = DATA_EMPTY (all-zero 32b)\n"
     "counter_tx = dummy_rd or dummy_wr\n"
     "exit: tx_done \u2192\n"
     "  do_rx ? DATA_RX : DATA_TX\n"
     "  no data_len \u2192 eot=1, IDLE", "write"),
]
for i, (txt, kind) in enumerate(ROW_A):
    x0, x1 = A_X[i]
    fs.block(ax, x0, ROWA_Y, x1 - x0, ROWA_H, txt, kind=kind, fs=5.0, bold=True)

# MODE: declared, never targeted by any state_next -> dead code
fs.block(ax, A_X[4][0], ROWA_Y, A_X[4][1] - A_X[4][0], ROWA_H,
         "MODE  5'b0_0011\ndead code \u2014 no\nstate_next ever\ntargets MODE\n"
         "only status[3]", kind="mux", fs=5.0, bold=True, ls=(0, (3, 2)), alpha=0.75)

for (a, b), lab in zip([(0, 1), (1, 2), (2, 3)], ["go", "tx_done", "tx_done"]):
    fs.wire(ax, (A_X[a][1], ACY), (A_X[b][0], ACY), label=lab, label_fs=5.6)
print("L2 row A ok")

# ---- row B : the data phase + the trailing WAIT_EDGE
ROW_B = [
    ("DATA_TX  5'b0_0101  status[5]\n"
     "spi_clock_en = tx_clk_en\n"
     "tx_clk_en = 0 \u2192 SCLK STALLS\n"
     "word source = DATA_FIFO\n"
     "exit: tx_done \u2192 eot=1, IDLE", "write"),
    ("DATA_RX  5'b0_0110  status[6]\n"
     "spi_clock_en = rx_clk_en\n"
     "rx_clk_en = 0 while the RX\n"
     "FIFO cannot accept a word\n"
     "exit: rx_done \u2192 WAIT_EDGE", "req"),
    ("WAIT_EDGE  5'b0_0111  status[6]\n"
     "spi_clock_en = 0 \u2014 clock parked\n"
     "SCLK only ever stops LOW\n"
     "exit: spi_fall \u2192 eot=1, IDLE\n"
     "then CS# high (no ACK wait)", "ctrl"),
]
for i, (txt, kind) in enumerate(ROW_B):
    x0, x1 = B_X[i]
    fs.block(ax, x0, ROWB_Y, x1 - x0, ROWB_H, txt, kind=kind, fs=5.0, bold=True)

# ---- reading order: the traversal order of the 7 reachable states ----------
fs.badge(ax, 6.9, 51.7, "1")
fs.badge(ax, 31.9, 51.7, "2")
fs.badge(ax, 56.9, 51.7, "3")
fs.badge(ax, 80.9, 51.7, "4")
fs.badge(ax, 47.4, 41.7, "5")
fs.badge(ax, 72.4, 41.7, "6")
fs.badge(ax, 97.9, 41.7, "7")
fs.label(ax, 4.9, 54.15, "START HERE  \u25b6", fs=6.0, color=fs.GREEN,
         weight="bold", ha="left")

# DUMMY -> DATA_TX (own corridor lane) and DUMMY -> DATA_RX (straight drop)
fs.wire(ax, (84.0, ROWA_Y), (56.0, ROWB_Y + ROWB_H),
        via=[(84.0, CORR_Y), (56.0, CORR_Y)],
        label="tx_done, do_tx = 1", label_at=(70.0, CORR_Y), label_fs=5.6)
fs.wire(ax, (88.0, ROWA_Y), (88.0, ROWB_Y + ROWB_H))
fs.label(ax, 89.4, 44.3, "tx_done, do_rx = 1", fs=5.4, color=fs.MID,
         weight="bold", ha="left")
fs.wire(ax, (B_X[1][1], BCY), (B_X[2][0], BCY), label="rx_done", label_fs=5.6)

# returns to IDLE: DATA_TX under the band, WAIT_EDGE over the top perimeter
fs.wire(ax, (56.0, ROWB_Y), (15.5, ROWA_Y),
        via=[(56.0, RET_LANE), (15.5, RET_LANE)], color=fs.GREEN, lw=1.7,
        label="DATA_TX: tx_done \u2192 eot=1 \u2192 IDLE \u2192 CS# high, SCLK already low",
        label_at=(36.0, RET_LANE), label_fs=5.6, label_color=fs.GREEN)
fs.wire(ax, (101.0, ROWB_Y + ROWB_H), (15.5, ROWA_Y + ROWA_H),
        via=[(101.0, TOP_LANE), (15.5, TOP_LANE)], color=fs.GREEN, lw=1.7,
        label="WAIT_EDGE: the trailing falling edge parks SCLK at idle \u2192 eot=1 "
              "\u2192 IDLE \u2192 CS# high",
        label_at=(58.0, TOP_LANE), label_fs=5.6, label_color=fs.GREEN)
print("L2 row B ok")

# =================== LAYER 3 : CPOL / CPHA — mode 0 only ==================
# grep CPOL|CPHA over every spi_master/*.sv : zero hits.  The polarity is
# hard-wired by which edge each shifter is given:
#   spi_master_tx  .tx_edge (spi_fall)  -> MOSI changes on the FALLING edge
#   spi_master_rx  .rx_edge (spi_rise)  -> MISO sampled on the RISING edge
#   clkgen resets spi_clk <= 1'b0 and only parks it at 0  -> CPOL = 0
_c2 = fs.chip(ax, 4.5, 26.3, "BAND 2 \u00b7 THE SHIFT / FIFO DATAPATH", fs=6.6)
fs.chip(ax, _c2[0] + _c2[2] * 1.07 + 2.6, 26.3,
        "BAND 3 \u00b7 THE HARD-WIRED MODE \u2014 CPOL = clock polarity, CPHA = "
        "clock phase; no mode register exists (grep CPOL|CPHA over "
        "spi_master/*.sv finds nothing)", fs=6.6)

CW = (121.0 - 4.5 - 3 * 1.2) / 4.0
MODES = [(0, 0), (0, 1), (1, 0), (1, 1)]
for i, (cpol, cpha) in enumerate(MODES):
    x0 = 4.5 + i * (CW + 1.2)
    live = (cpol == 0 and cpha == 0)
    fs.block(ax, x0, MODE_Y, CW, MODE_H, "", kind="periph" if live else "mux",
             lw=1.6 if live else 1.0, alpha=1.0 if live else 0.55)
    fs.label(ax, x0 + CW / 2, 24.30, f"MODE {i}  \u00b7  CPOL {cpol}  \u00b7 CPHA {cpha}",
             fs=5.7, weight="bold", color="#1B5E20" if live else fs.GREY)
    fs.label(ax, x0 + CW / 2, 23.20,
             "IMPLEMENTED \u2014 hard-wired" if live else "not implemented",
             fs=5.3, weight="bold", color=fs.GREEN if live else "#4D4D4D")
    # 1.5 bit periods out of idle: both edges are visible inside the cell
    wx0, hw = x0 + 2.0, (CW - 4.0) / 3.0
    lo, hi = 20.55, 21.45
    h = [wx0 + i * hw for i in range(4)]
    for xa, xb, fc in ((wx0, h[1], "#FBE4E4"), (h[1], h[2], "#E2EFDA"),
                       (h[2], wx0 + 3 * hw, "#FBE4E4")):
        ax.add_patch(fs.Rectangle((xa, lo - 0.32), xb - xa, (hi - lo) + 0.64,
                                  facecolor=fc, edgecolor="none", zorder=2))
    lv = [cpol, 1 - cpol, cpol]
    xs = [wx0, h[1], h[2], wx0 + 3 * hw]
    ys = [hi if v else lo for v in lv] + [hi if lv[-1] else lo]
    ax.add_line(fs.Line2D(xs, ys, color="#303030", lw=2.0,
                          drawstyle="steps-post", zorder=5))
    s_x = h[1] if ((cpha == 0) == (cpol == 0)) else h[2]
    t_x = h[2] if s_x == h[1] else h[1]
    for xe, txt, col, at_h1 in ((s_x, "sample MISO", fs.GREEN,
                                 ((cpha == 0) == (cpol == 0))),
                                (t_x, "shift MOSI", fs.ORANGE,
                                 ((cpha == 1) == (cpol == 0)))):
        rise = (cpol == 0) if at_h1 else (cpol == 1)
        ax.add_line(fs.Line2D([xe, xe], [lo - 0.36, hi + 0.36], color=col, lw=1.0,
                              ls=(0, (2, 2)), zorder=6))
        fs.dot(ax, xe, hi if rise else lo, r=0.31, fc=col, zorder=7)
        fs.label(ax, xe, 22.30, txt, fs=4.9, color=col, weight="bold")
    fs.label(ax, x0 + CW / 2, 19.55,
             f"idle SCLK = {cpol}   \u00b7   "
             f"{'sample on RISE, shift on FALL' if cpha == 0 else 'sample on FALL, shift on RISE'}",
             fs=5.2, color="#404040" if live else "#808080")
print("L3 modes ok")

# ================= LAYER 4 : datapath — divider, shifters, FIFOs ===========
DP = [
    ("spi_master_tx   (u_txreg)\n"
     "32-b data_int  \u00b7  sdo0 = data_int[31]\n"
     "MSB first, no byte swap \u2014 the word's\n"
     "bits 31:24 reach the wire first\n"
     "TX FIFO 32 b \u00d7 10 deep  (BUFFER_DEPTH)", "write"),
    ("spi_master_clkgen  (u_clkgen)\n"
     "8-bit counter, reload on clk_div_valid\n"
     "toggles when counter == counter_trgt\n"
     "half period = clk_div + 1 HCLK\n"
     "spi_rise / spi_fall = 1-clk strobes", "ctrl"),
    ("spi_master_rx   (u_rxreg)\n"
     "32-b shift-in, MSB first\n"
     "latched on spi_rise  (rx_edge)\n"
     "RX FIFO 32 b \u00d7 10 deep  (BUFFER_DEPTH)\n"
     "FIFO full \u2192 clk_en_o = 0, SCLK stalls", "req"),
    ("THE ONLY BACK-PRESSURE IN THE IP\n"
     "spi_clock_en = tx_clk_en  (DATA_TX)\n"
     "no word ready \u2192 tx_clk_en = 0 \u2192 SCLK STALLS\n"
     "CHIP SELECT \u2014 4 targets, active low\n"
     "spi_csnN = ~spi_csreg[N] | spi_cs, low from\n"
     "the request cycle in IDLE until the FSM returns", "write"),
]
for i, (txt, kind) in enumerate(DP):
    x0, x1 = D_X[i]
    fs.block(ax, x0, DP_Y, x1 - x0, DP_H, txt, kind=kind,
             fs=4.8 if i == 3 else 5.0, bold=True)
fs.wire(ax, (D_X[1][0], 31.0), (D_X[0][1], 31.0), label="spi_fall", label_fs=5.0)
fs.wire(ax, (D_X[1][1], 31.0), (D_X[2][0], 31.0), label="spi_rise", label_fs=5.0)
fs.wire(ax, (106.0, ROWB_Y), (106.0, DP_Y + DP_H), color=fs.MID, lw=1.4)
fs.onwire(ax, 102.3, 35.4, "state \u2260 IDLE", fs=5.2, color=fs.MID)

fs.eqbox(ax, EQ_X, EQ_Y, EQ_W, EQ_H,
         "SCLK = HCLK / 2 \u00b7 (clk_div + 1)\n"
         "half period = clk_div + 1 HCLK\n"
         "clk_div = 0 \u2192 HCLK/2 (reset value)\n"
         "clk_div = 255 \u2192 HCLK/512\n"
         "the clock parks only at spi_clk = 0", fs=5.6)
print("L4 datapath ok")

# ============== LAYER 5 : one full-duplex byte on the wire ==================
# DATA_TX with data_len = 8 bits.  CS# low from the request cycle, SCLK comes
# up from the idle LOW, one clock per bit: rise = rx_edge (sample), fall =
# tx_edge (shift).  The 8th fall raises done = (counter == 7) && spi_fall.
MOSI = ["1", "0", "1", "0", "0", "1", "0", "1"]        # TX word 0xA5A5A5A5, b31..b24
MISO = ["0", "1", "0", "1", "1", "0", "1", "0"]        # RX word 0x5A5A5A5A
XCELL = 10                                                # 1 idle + 8 bits + 1 post
ROWS = [("cs", "CS#  spi_csn0..3", "active low, mask bit spi_csreg[N]"),
        ("sclk", "SCLK  spi_clk", "idle LOW, one clock per bit"),
        ("mosi", "MOSI  spi_sdo0", "TX word 0xA5A5A5A5, bits 31:24 first"),
        ("miso", "MISO  spi_sdi0", "RX word 0x5A5A5A5A, latched on spi_rise")]
ax, ys, u = fs.lanes(fig, ROWS, WX0, WX0 + XCELL * WU, unit=WU,
                     lane_gap=WAVE_GAP, left_pad=1.0, label_fs=7.6, sub_fs=6.3)
assert abs(u - WU) < 1e-9
CY = {k: ys[k] for k, _, _ in ROWS}
AX_ = {k: CY[k] - 0.85 for k in CY}                    # wave low level
BX_ = {k: CY[k] + 0.85 for k in CY}                    # wave high level

# out-of-frame bands (CS# high, clock parked) + the 8 sampling instants
for i in (0, XCELL - 1):
    ax.add_patch(fs.Rectangle((WX0 + i * WU, 2.55), WU, 15.5, facecolor="#F2F2F2",
                              edgecolor="none", zorder=1))
for i in range(1, 9):
    ax.add_patch(fs.Rectangle((WX0 + (i + 0.5) * WU - 1.25, 2.55), 2.5, 15.5,
                              facecolor="#DFF0DC", edgecolor="none", zorder=1))
fs.cycle_guides(ax, WX0, XCELL, u, bottom=2.55, top=17.95, color="#E4E4E4")

# CS# : high, low for the 8 bits, high again half a cell after the last fall
fs.sigwave(ax, WX0, [1, 1] + [0] * 17 + [1], WU / 2, AX_["cs"], BX_["cs"],
           color=fs.RED, lw=2.1)
# SCLK : 20 half cells -- cells 0..8 clock, cell 9 stays parked LOW
fs.sigwave(ax, WX0, [0, 1] * 9 + [0, 0], WU / 2, AX_["sclk"], BX_["sclk"],
           color=fs.ACCENT, lw=2.1)
fs.bus_cells(ax, WX0 + WU, MOSI, u, CY["mosi"], 2.2, fill=fs.S_WRITE,
             ec="#C55A11", color="#843C0C")
fs.bus_cells(ax, WX0 + WU, MISO, u, CY["miso"], 2.2, fill=fs.S_REQ,
             ec=fs.MID, color="#1F3864")
for i in range(1, 9):
    fs.dot(ax, WX0 + (i + 0.5) * WU, 5.55, r=0.3, fc=fs.GREEN, zorder=8)
print("L5 wave ok")

# ---- edge leaders: why CPHA=0 samples on the rise and shifts on the fall
X_RISE, X_FALL, X_LAST = WX0 + 1.5 * WU, WX0 + 2 * WU, WX0 + 9 * WU
fs.arrow2d(ax, (X_RISE, BX_["sclk"] + 0.7), (X_RISE, BX_["sclk"] + 0.06),
           color=fs.GREEN, lw=1.2, head_scale=8.0)
fs.label(ax, X_RISE + 0.9, 14.75,
         "MISO sampled on the RISING edge \u2014 rx_edge = spi_rise", fs=5.5,
         color="#1B5E20", weight="bold", ha="left")
fs.arrow2d(ax, (X_FALL, AX_["sclk"] - 0.7), (X_FALL, AX_["sclk"] - 0.06),
           color=fs.ORANGE, lw=1.2, head_scale=8.0)
fs.label(ax, X_FALL + 1.2, 10.7,
         "MOSI changes on the FALLING edge \u2014 tx_edge = spi_fall", fs=5.5,
         color="#843C0C", weight="bold", ha="left")
fs.label(ax, WX0 + 1.5 * WU, 10.7, "bit 7  \u00b7  MSB first", fs=5.3,
         color=fs.GREY, ha="center")
fs.label(ax, WX0 + 8.5 * WU, 10.7, "bit 0  \u00b7  LSB", fs=5.3,
         color=fs.GREY, ha="center")
fs.label(ax, WX0 + 0.5 * WU, 6.05, "outside\nthe frame", fs=5.0, color="#8C8C8C",
         ha="center")
fs.label(ax, WX0 + 9.5 * WU, 6.05, "eot = 1", fs=5.2, color=fs.RED,
         weight="bold", ha="center")

# ---- the exact bit boundary
ax.add_line(fs.Line2D([X_LAST, X_LAST], [2.6, 14.55], color=fs.RED, lw=1.1,
                      ls=(0, (3, 2)), zorder=3))
fs.arrow2d(ax, (X_LAST, 14.15), (X_LAST, AX_["sclk"] + 0.06), color=fs.RED,
           lw=1.2, head_scale=8.0)
fs.label(ax, X_LAST - 1.0, 14.75,
         "8th falling edge = tx_done:  done = (counter == data_len-1) && spi_fall",
         fs=5.5, color=fs.RED, weight="bold", ha="right")
print("L5 annotations ok")

# ============== LAYER 6 : caption, footer, QA, save =========================
_c4 = fs.chip(ax, 4.5, 1.5, "BAND 4 \u00b7 ONE BYTE ON THE WIRE", fs=6.6)
fs.label(ax, _c4[0] + _c4[2] * 1.07 + 1.8, 1.5,
         "DATA_TX, data_len = 8 bits  \u00b7 MOSI = 0xA5 (TX word bits 31:24, MSB "
         "first, no byte swap)  \u00b7 MISO = 0x5A  \u00b7 shaded column = the "
         "sampling instant (spi_rise)  \u00b7 grey = out of frame\n"
         "MOSI = master-out / slave-in (data out)  \u00b7 MISO = master-in / "
         "slave-out (data in)  \u00b7 SCLK = serial clock  \u00b7 CS# = chip "
         "select, active low  \u00b7 TX / RX = transmit / receive  \u00b7 eot = "
         "end of transaction",
         fs=5.5, color=fs.GREY, ha="left")
fs.footer(fig, "No ACK and no retry: with no handshake on the wire, a CPOL/CPHA "
               "mismatch, a wrong bit order or a wrong CS# boundary all shift the "
               "data silently \u2014\nevery waveform still looks legal and no bus "
               "monitor ever flags it. Only the CS# boundary and a "
               "MOSI\u2192MISO loopback reveal it.")
fs.pad_limits(ax, 0.06)
fs.qa_report(fig)
fs.save(fig, "fig13_spi_master_fsm.png")