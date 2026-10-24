"""fig08 -- OBI 16550 UART (RISCFORGE APB[2] @ 0x4000_2000):
TX bit sequencer vs RX mid-bit sampler, and the frame they put on the wire.

RTL read:
  rtl/ips/apb_uart-main/rtl/apb_uart.sv              (APB wrapper)
  rtl/ips/apb_uart-main/rtl/apb_uart_wrap.sv        (apb_to_obi + obi_uart)
  rtl/ips/apb_uart-main/include/obi/obi_uart_tx.sv  (state_type_tx_e)
  rtl/ips/apb_uart-main/include/obi/obi_uart_rx.sv  (state_type_rx_e)
  rtl/ips/apb_uart-main/include/obi/obi_uart_baudgen.sv (divisor)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:                                    # QA text contains arrows
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# --------------------------------------------------------------- coordinates
ROW_Y, ROW_H = 44.5, 9.0          # main state row   44.5 .. 53.5
LANE1_Y = 41.9                    # optional-stage bypass lane
LANE2_Y = 34.8                    # extra-state lane (TX back-to-back / RX resync)
SUB_Y, SUB_H = 36.0, 4.4          # caption strip beside the extra-state lane
EQ_Y, EQ_H = 29.4, 3.6            # formula strip under the two halves
SEP_Y = 28.5                      # panel separator

BW, BG = 10.8, 1.1                # state box width / gap
TX_X = [1.5 + i * (BW + BG) for i in range(5)]     # 1.5 .. 59.9
RX_X = [64.6 + i * (BW + BG) for i in range(5)]    # 64.6 .. 123.0
BOX_MID = ROW_Y + ROW_H / 2.0

# waveform grid (bottom panel)
WX0, WU = 25.5, 6.6
NCELL = 12
LANE_GAP = 4.9

TITLE = ("The transmitter is a free-running bit counter and the receiver is a "
         "mid-bit sampler \u2014 that single difference is the whole of UART")
SUB = ("Panel 1: the TX and RX bit sequencers, side by side.   Panel 2: the "
       "same frame at bit level.   TX drives a whole bit from one edge; RX "
       "reads it in the middle.")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
print("canvas:", round(XW, 2), "x", round(YH, 2))
print("TX row:", TX_X, "->", round(TX_X[-1] + BW, 2))
print("RX row:", RX_X, "->", round(RX_X[-1] + BW, 2))
print("wave grid:", WX0, "..", round(WX0 + NCELL * WU, 2))

# panel-1 entry point -- the numbered header tells the eye which row to read first
fs.chip(ax, 1.5, 58.0,
        "PANEL 1 \u00b7 THE TWO BIT SEQUENCERS \u2014 read them side by side: "
        "five states each, opposite tick sources", fs=7.4)

# L2 -- TX main state row (obi_uart_tx.sv, case(state_q) at line 165)
fs.chip(ax, 1.5, 56.4, "TX \u00b7 obi_uart_tx.sv \u00b7 state_type_tx_e")
fs.label(ax, 1.5, 54.6,
         "a real FSM \u2014 but the bit itself comes from a parallel shift "
         "register:  txd_q = tsr_q[tsr_count_q]",
         fs=6.4, color=fs.GREY, ha="left")

TX_STATES = [
    ("TXIDLE", "periph",
     "txd=1 \u00b7 idle high\nexit: !fifo_empty\n& baud_edge_i"),
    ("TXSTART", "write",
     "txd=0 \u00b7 start bit\n1 full bit time\nexit: baud_edge_i"),
    ("TXDATA", "ctrl",
     "txd=tsr_q[count]\nLSB out first\nexit: tsr_finish"),
    ("TXPAR", "plain",
     "txd = ^tsr_q (even)\nexit: baud_edge_i\nskipped if par_en=0"),
    ("TXSTOP1", "periph",
     "txd=1 \u00b7 stop bit\nexit: baud_edge_i\n2 stop bits \u2192 TXIDLE"),
]
tx_b = [fs.block(ax, x, ROW_Y, BW, ROW_H, nm, kind=k, fs=8.5, sub=su,
                 sub_fs=5.9)
        for x, (nm, k, su) in zip(TX_X, TX_STATES)]
for a, b in zip(tx_b, tx_b[1:]):
    fs.wire(ax, a["e"], b["w"], color=fs.MID, lw=1.7, arrow=True, zorder=3)

# L3a -- TX lane 1: optional parity stage bypassed (LCR = 0x03, 8N1)
fs.wire(ax, (TX_X[2] + BW / 2, ROW_Y), (TX_X[4] + BW / 2, ROW_Y),
        via=[(TX_X[2] + BW / 2, LANE1_Y)], color=fs.MID, lw=1.6, back=True,
        label="LCR.PAR_EN = 0  \u00b7  TXPAR bypassed", label_at=(43.2, LANE1_Y),
        label_fs=7.0)

# L3b -- TX lane 2: back-to-back byte -> TXSTOP2, the return edge to TXIDLE
b_stop2 = fs.block(ax, TX_X[3], LANE2_Y - 3.0, BW, 6.0, "TXSTOP2",
                   kind="mux", fs=8.5, bold=True,
                   sub="extra high bit time\n\u2192 TXIDLE, no edge\n1.5 stop if 5 bits",
                   sub_fs=5.9)
fs.wire(ax, (57.5, ROW_Y), (TX_X[3] + BW, LANE2_Y),
        via=[(57.5, LANE2_Y)], color=fs.MID, lw=1.6,
        label="baud_edge_i", label_at=(52.75, LANE2_Y), label_fs=6.5)
fs.wire(ax, b_stop2["w"], (TX_X[0] + BW / 2, ROW_Y),
        via=[(TX_X[0] + BW / 2, LANE2_Y)], color=fs.MID, lw=1.6, back=True,
        label="no baud edge needed", label_at=(22.0, LANE2_Y), label_fs=6.6)

# L3c -- RX main state row (obi_uart_rx.sv, case(state_q) at line 360)
fs.chip(ax, 64.6, 56.4, "RX \u00b7 obi_uart_rx.sv \u00b7 state_type_rx_e")
fs.label(ax, 64.6, 54.6,
         "opposite tick: RXIDLE leaves on filtered_rxd_q & ~sync_rxd, "
         "every later state waits for timing_bit_center_edge",
         fs=6.4, color=fs.GREY, ha="left")

RX_STATES = [
    ("RXIDLE", "periph",
     "idle, line high\nexit: falling edge\non filtered_rxd", 5.9),
    ("RXSTART", "write",
     "half-bit wait\ntiming_count == 8\nlow \u2192 RXDATA", 5.9),
    ("RXDATA", "bus",
     "rsr[bitcount]=rxd\n1 bit per centre\nexit: count == len", 5.9),
    ("RXPAR", "plain",
     "xor vs ^rsr_q\nexit @ bit centre\n\u2192 parity_err_q", 5.9),
    ("RXSTOP", "resp",
     "exit @ bit centre\nrxd low = frame err\n\u2192 RXRESYNCHRONIZE", 5.4),
]
rx_b = [fs.block(ax, x, ROW_Y, BW, ROW_H, nm, kind=k, fs=8.5, sub=su,
                 sub_fs=sf)
        for x, (nm, k, su, sf) in zip(RX_X, RX_STATES)]
for a, b in zip(rx_b, rx_b[1:]):
    fs.wire(ax, a["e"], b["w"], color=fs.MID, lw=1.7, arrow=True, zorder=3)

# L3d -- RX lane 1: parity bypass, RX lane 2: framing-error recovery
fs.wire(ax, (RX_X[2] + BW / 2, ROW_Y), (RX_X[4] + BW / 2, ROW_Y),
        via=[(RX_X[2] + BW / 2, LANE1_Y)], color=fs.MID, lw=1.6, back=True,
        label="LCR.PAR_EN = 0  \u00b7  RXPAR bypassed",
        label_at=(105.7, LANE1_Y), label_fs=7.0)

b_res = fs.block(ax, RX_X[3], LANE2_Y - 3.0, BW, 6.0,
                 "RXRESYNCHRONIZE", kind="mux",
                 fs=fs.fit_fs(ax, "RXRESYNCHRONIZE", 9.4, 8.5), bold=True,
                 sub="hunt for a new start\nfall edge \u2192 RXSTART",
                 sub_fs=5.9)
fs.wire(ax, (123.4, ROW_Y), (RX_X[3] + BW, LANE2_Y),
        via=[(123.4, LANE2_Y)], color=fs.RED, lw=1.6,
        label="framing_err_d = 1", label_at=(117.25, LANE2_Y),
        label_fs=6.5, label_color=fs.RED)
fs.wire(ax, b_res["w"], (RX_X[1] + BW / 2, ROW_Y),
        via=[(RX_X[1] + BW / 2, LANE2_Y)], color=fs.MID, lw=1.6, back=True,
        label="repeat-start hunt", label_at=(91.1, LANE2_Y), label_fs=6.6)

# L4 -- bit-level waveform panel ------------------------------------------------
ax.add_line(fs.Line2D([1.0, 124.3], [SEP_Y, SEP_Y], color="#C8C8C8", lw=1.0,
                      zorder=1))
ax.add_line(fs.Line2D([62.2, 62.2], [31.0, 57.2], color="#E0E0E0", lw=1.0,
                      ls=(0, (3, 3)), zorder=1))

fs.chip(ax, 1.5, 26.6,
        "PANEL 2 \u00b7 FRAME AT BIT LEVEL \u00b7 LCR = 0x03 (8N1 = 8 data, "
        "no parity, 1 stop) \u00b7 FIFO on \u00b7 0x41 'A' goes out LSB first")

rows = [("txd", "SOUT \u00b7 txd_o", "transmitted frame"),
        ("tst", "state_q \u00b7 obi_uart_tx", "TX chain"),
        ("rxd", "SIN \u00b7 rxd_i", "receiver view"),
        ("rst", "state_q \u00b7 obi_uart_rx", "RX chain")]
ax, ys, u = fs.lanes(fig, rows, WX0, WX0 + NCELL * WU, unit=WU,
                     lane_gap=LANE_GAP, left_pad=1.0, label_fs=8.0, sub_fs=6.6)
fs.cycle_guides(ax, WX0, NCELL, u, bottom=1.5, top=23.2)

# bit-position captions above the cells
CAPS = [(0, "START", "#7F1010"), (9, "STOP", "#3F6228"),
        (10, "extra high", "#6E6E6E"), (11, "next START", "#7F1010")]
for i in range(1, 9):
    CAPS.append((i, "D%d" % (i - 1), "#7F6000"))
for i, nm, c in CAPS:
    fs.label(ax, WX0 + (i + 0.5) * WU, 21.9, nm, fs=6.6, color=c, weight="bold")

# transmitted frame: start(low) 8 data LSB-first, stop(high), TXSTOP2 gap
DATA = "10000010"                       # 0x41, bit0 first
BITS = ["0"] + list(DATA) + ["1", "1", "0"]
fs.bus_cells(ax, WX0, BITS[:1], u, ys["txd"], 2.6, fill=fs.S_ALARM, ec=fs.RED,
              color="#7F1010")
fs.bus_cells(ax, WX0 + 1 * u, BITS[1:9], u, ys["txd"], 2.6, fill=fs.S_ADDR,
              ec="#BF8F00", color="#7F6000")
fs.bus_cells(ax, WX0 + 9 * u, BITS[9:10], u, ys["txd"], 2.6, fill=fs.S_RESP,
              ec="#548235", color="#3F6228")
fs.bus_cells(ax, WX0 + 10 * u, BITS[10:11], u, ys["txd"], 2.6, fill="#EDEDED",
              ec="#BFBFBF", color="#6E6E6E")
fs.bus_cells(ax, WX0 + 11 * u, BITS[11:12], u, ys["txd"], 2.6, fill=fs.S_ALARM,
              ec=fs.RED, color="#7F1010")

# L4b -- state strips + RX view
# TX state strip -- the counter runs, the state does not change
fs.phase_bar(ax, WX0, NCELL, ys["tst"], 2.0,
             [(0, 1, "TXSTART", fs.S_ALARM),
              (1, 9, "TXDATA  \u00b7  tsr_count_q = 0\u20267  \u00b7  "
                    "txd_q = tsr_q[tsr_count_q]", fs.S_ADDR),
              (9, 10, "TXSTOP1", fs.S_RESP),
              (10, 11, "TXSTOP2", "#EDEDED"),
              (11, 12, "next frame", "#F7F7F7")], fs=7.0, unit=u)

# receiver view: same wire, plus the one instant each bit is sampled
fs.bus_cells(ax, WX0, BITS[:1], u, ys["rxd"], 2.6, fill="#FBE4E4",
              ec=fs.RED, color="#7F1010")
fs.bus_cells(ax, WX0 + 1 * u, BITS[1:9], u, ys["rxd"], 2.6, fill=fs.S_REQ,
              ec=fs.MID, color=fs.TXT)
fs.bus_cells(ax, WX0 + 9 * u, BITS[9:10], u, ys["rxd"], 2.6, fill=fs.S_RESP,
              ec="#548235", color="#3F6228")
fs.bus_cells(ax, WX0 + 10 * u, BITS[10:11], u, ys["rxd"], 2.6, fill="#EDEDED",
              ec="#BFBFBF", color="#6E6E6E")
fs.bus_cells(ax, WX0 + 11 * u, BITS[11:12], u, ys["rxd"], 2.6, fill="#FBE4E4",
              ec=fs.RED, color="#7F1010")
for i in range(10):
    fs.dot(ax, WX0 + (i + 0.5) * u, ys["rxd"] + 1.55, r=0.34, fc=fs.GREEN)

fs.phase_bar(ax, WX0, NCELL, ys["rst"], 2.0,
             [(0, 1, "RXSTART", fs.S_ALARM),
              (1, 9, "RXDATA  \u00b7  rsr_q[bitcount_q] = filtered_rxd_q, "
                    "one bit per bit centre", fs.S_REQ),
              (9, 10, "RXSTOP", fs.S_RESP),
              (10, 12, "RXIDLE", "#F7F7F7")], fs=7.0, unit=u)

fs.label(ax, WX0, 24.2,
         "green dot = the single instant the RX latches the bit "
         "(timing_bit_center_edge = timing_count == 5'b01000, "
         "8 of 16 oversamples = mid-bit)",
         fs=6.4, color=fs.GREY, ha="left")

# bit period / frame time live in the formula box on the right

# L5a -- the two ticks, side by side: this IS the sentence the title makes, so
# it gets the largest type on the canvas outside the state boxes themselves.
fs.eqbox(ax, 1.5, 28.6, 33.0, 4.8,
         "TX tick = baud_rate_edge_i  (1 clk pulse per bit)\n"
         "TX has no clock-phase freedom: txd_q is loaded once,\n"
         "then held for a whole bit.", fs=7.2)
fs.eqbox(ax, 64.6, 28.6, 32.0, 4.8,
         "RX tick = timing_bit_center_edge\n"
         "= (timing_count == 5'b01000)  \u2014  never a data line\n"
         "RX reads once, in the middle of the bit.", fs=7.2)

# L5b -- captions beside the two extra-state lanes
fs.note(ax, 8.6, SUB_Y, 25.9, SUB_H,
        "Back-to-back: TXSTOP2 \u2192 TXIDLE costs no edge,\n"
        "yet TXIDLE \u2192 TXSTART waits one more, so two\n"
        "frames sit TWO high bit-times apart (cell 10).",
        fs=6.0, valign="center")
fs.note(ax, 64.6, SUB_Y, 16.8, SUB_H,
        "Stop bit low = framing\n"
        "error \u2192 LSR[3]; RX parks\n"
        "in RXRESYNCHRONIZE",
        fs=6.0, valign="center")

# L5c -- right-hand note column of the waveform panel
fs.note(ax, 106.0, 20.0, 18.3, 6.0,
         "oversample \u00d7 16\nbit period = 16 \u00d7 {DLM,DLL} clk\n"
         "{DLM,DLL} = 54 \u2192 864 clk = 8.64 \u00b5s\n"
         "@ 100 MHz = 115741 baud (+0.47 %)\n"
         "1 byte = 10 bit times = 86.4 \u00b5s", fs=6.0)
fs.note(ax, 105.4, 8.8, 18.9, 10.6,
        "WATCH OUT \u2014 Sw/bsp/uart_min.h\n"
        "uart_init() writes IER, LCR\n"
        "and FCR, never DLL/DLM.\n"
        "Per baudgen.sv the divisor\n"
        "resets to 0, so {DLM,DLL}-1 =\n"
        "0xFFFF \u2192 1 bit = 16 \u00d7 65536 clk\n"
        "\u2248 95 baud @ 100 MHz until SW\n"
        "sets DLAB (LCR[7]) and\n"
        "programs the divisor.",
        fs=5.9, pad_x=0.8, valign="center")

# cell-colour key: one thin strip spanning the lanes it explains, so it sits
# under the cells instead of competing with the two state chains above.
fs.note(ax, 1.5, 0.5, 102.0, 1.9,
        "Cell colours:  pink = start bit   yellow = data bit (TX)   "
        "blue = data bit (RX)   green = stop bit   grey = idle high.   "
        "D0..D7 are sent LSB first, so D0 = bit 0 of 0x41.",
        fs=6.4, pad_x=0.9, valign="center")

# L5d -- sign-off
fs.footer(fig, "Failure mode: a stop bit sampled low is a framing error "
               "(LSR[3], frame_err) and RX parks in RXRESYNCHRONIZE; "
               "back-to-back bytes cost two high bit-times, because TXIDLE "
               "waits one more baud_rate_edge after TXSTOP2.")
# No pad_limits(): it rescales the data units, which makes every
# kernel-measured item (fs.chip boxes, fitted cell fonts, onwire pads)
# ~6% narrower than the text it holds.  Content is laid out inside
# 1.0 .. 124.3 (x) and 1.0 .. 57.4 (y) of the 125.3 x 59.1 canvas instead.
fs.qa_report(fig)
fs.save(fig, "fig08_uart_tx_rx_fsm.png")
