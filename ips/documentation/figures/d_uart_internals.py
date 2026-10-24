"""fig07 -- APB UART internals (apb_uart.sv -> apb_uart_wrap -> obi_uart)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

try:                                    # QA text contains arrows
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# This figure carries ONE idea: the data path.  The software-facing side
# (full register map, LSR bit table, ISR/IIR priority encoder, reset/flush)
# is a second, separate lesson -- see the split proposal in the report.
TITLE = ("One baud edge per bit time drives both shift registers \u2014 the "
         "FIFOs only decouple the APB side from the wire")
SUB = ("APB UART (Advanced Peripheral Bus) data path, obi_uart, base "
       "0x4000_2000 \u2014 APB[2], 4 KB.   Read DOWN: the one clock source, "
       "then the TX chain, then the RX chain, then the registers they touch.")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
L, R = 2.4, 122.9                       # content x span (pad 0.02 later)

# ---------------------------------------------------- 0  register strip header
fs.label(ax, L, 55.2, "START HERE \u2193   the eight registers this data path "
         "touches", fs=7.4, color=fs.ACCENT, weight="bold", ha="left")
fs.label(ax, R, 55.2, "PADDR[2:0] is a WORD address  \u00b7  offsets step by 4",
         fs=7.0, color=fs.GREY, ha="right")
fs.legend_row(ax, 42.0, 55.2, [("box", "write", "APB data port"),
                               ("box", "ctrl", "config"),
                               ("box", "resp", "read-only"),
                               ("box", "plain", "pin")], fs=6.4)

REGS = [
    ("RHR / THR", "write", "0x4000_2000  char_rx / char_tx"),
    ("IER", "ctrl", "0x4000_2004  interrupt enable"),
    ("ISR : FCR", "ctrl", "0x4000_2008  FIFO control"),
    ("LCR", "ctrl", "0x4000_200C  DLAB, word_len"),
    ("MCR", "ctrl", "0x4000_2010  loopback, rts"),
    ("LSR", "resp", "0x4000_2014  8 live status bits"),
    ("MSR", "resp", "0x4000_2018  modem status"),
    ("SPR", "plain", "0x4000_201C  writes ignored"),
]
CW, CG = 14.3, 0.83
for i, (nm, kd, sb) in enumerate(REGS):
    fs.block(ax, 2.55 + i * (CW + CG), 49.2, CW, 4.6, nm, kind=kd, fs=7.6,
             sub=sb, sub_fs=6.2)

fs.note(ax, L, 43.9, R - L, 4.4,
        "DLAB = LCR[7] re-decodes the SAME 3-bit word address:   DLAB=0 \u2192 "
        "RHR/THR + IER      DLAB=1 \u2192 DLL + DLM, the 16-bit divisor latch "
        "used in section 1.\n"
        "ISR/FCR[0] = fifo_en;  FCR[2] / FCR[1] are self-clearing 1-cycle "
        "TX / RX FIFO-flush strobes \u2014 they read back as 0.",
        fs=6.9, pad_y=0.7)

fs.qa_report(fig)

# ====================================================== 1  THE ONE CLOCK SOURCE
fs.label(ax, L, 42.9, "1   THE ONE CLOCK SOURCE   obi_uart_baudgen.sv \u2014 "
         "fixed 16\u00d7 oversample, no prescaler;  one edge per bit time clocks "
         "BOTH shift registers", fs=7.6, color=fs.ACCENT, weight="bold",
         ha="left")

BD = [(2.4, 14.5, "DLL / DLM", "ctrl", "latched only when DLAB=1\n"
       "16-bit {dlm, dll}"),
      (23.7, 15.5, "divisor", "ctrl", "{dlm, dll} - 16'd1\n"
       "divisor_valid = !(divisor==0)"),
      (46.9, 17.5, "oversample_count", "periph", "16-bit counter, counts up\n"
       "on every CLK"),
      (69.8, 15.5, "baud_count", "periph", "4-bit, enabled by\noversample_"
       "is_divisor")]
b = [fs.block(ax, x, 35.7, w, 6.4, tx, kind=k, fs=7.4, sub=s, sub_fs=6.1)
     for x, w, tx, k, s in BD]
for a2, b2, lb in zip(b, b[1:], ["dll/dlm", "compare", "\u00f716"]):
    fs.wire(ax, a2["e"], b2["w"], label=lb, label_fs=6.2, color=fs.ACCENT)

fs.eqbox(ax, 92.2, 35.7, R - 92.2, 6.4,
         "baud_rate_edge = CLK / (16 \u00d7 {DLM,DLL})\n"
         "oversample_rate_edge = (count=='0) & divisor_valid\n"
         "CLK = 50 MHz \u00b7 115200 8N1 (8 data, no parity, 1 stop)\n"
         "   \u2192 {DLM,DLL} = 0x001B = 27 \u2192 115 740 baud, +0.47 %\n"
         "   9600 \u2192 0x0145 \u2192 9615 baud", fs=6.1)
fs.wire(ax, b[3]["e"], (92.2, 38.9), label="per bit", label_fs=6.2,
        color=fs.ACCENT)
fs.qa_report(fig)

# ================================================================ 2  TX CHAIN
fs.label(ax, L, 34.8, "2   TX CHAIN   APB write \u2192 TX FIFO \u2192 "
         "transmit shift register (TSR) \u2192 pin", fs=7.6, color=fs.ACCENT,
         weight="bold", ha="left")

TX = [(2.4, 13.0, 6.6, "APB write\nTHR", "write",
       "obi_write_thr\nPWDATA[7:0]"),
      (23.7, 17.5, 6.6, "TX FIFO", "mem", "fifo_v3  DEPTH = 16\n"
       "DATA_WIDTH = 8"),
      (50.2, 17.5, 6.6, "TSR", "periph", "transmit shift register\n"
       "tsr_q[7:0] \u00b7 tsr_count_q[2:0]"),
      (73.7, 11.0, 4.8, "SOUT", "plain", "txd_o")]
t = [fs.block(ax, x, 27.6 - h / 2.0, w, h, tx, kind=k, fs=7.8, sub=s,
              sub_fs=6.1)
     for x, w, h, tx, k, s in TX]
for a, b, lb in zip(t, t[1:], ["fifo_push", "baud_edge", "txd_d"]):
    fs.wire(ax, a["e"], b["w"], label=lb, label_fs=6.6, color=fs.ACCENT)

fs.note(ax, 89.4, 24.3, R - 89.4, 6.6,
        "frame sequencer:  TXIDLE \u2192 TXSTART \u2192 TXDATA \u2192 TXPAR\n"
        "\u2192 TXSTOP1 (2 bits if LCR[2]=1)\n"
        "txd_d = tsr_q[tsr_count_q], LSB first\nparity LCR[5:4]:  00 odd = "
        "~(^tsr_q)  01 even", fs=6.3, pad_y=0.5)

fs.qa_report(fig)

# ================================================================ 3  RX CHAIN
fs.label(ax, L, 22.8, "3   RX CHAIN   pin \u2192 2-stage sync + 3-sample "
         "majority \u2192 bit-centre alignment \u2192 receive shift register "
         "(RSR) \u2192 RX FIFO \u2192 APB read", fs=7.6, color=fs.ACCENT,
         weight="bold", ha="left")

RX = [(2.4, 11.0, "SIN", "plain", "rxd_i\nidle HIGH"),
      (16.6, 21.5, "sync + majority", "periph", "sync STAGES=2 \u2192 "
       "sync_rxd\n3 samples in oversample cycles 6,7,8\n\u22652 high \u2192 "
       "filtered_rxd"),
      (46.1, 20.0, "RSR + align", "periph", "timing_count[4:0] 0\u201315 ovs\n"
       "bit centre @ count == 8\nrsr_q[7:0] \u00b7 bitcount_q[2:0]"),
      (74.5, 23.0, "RX FIFO", "mem", "fifo_v3  DEPTH = 16  DATA_WIDTH = 11\n"
       "{par_err, frame_err,\nbreak_ind, rsr_q[7:0]}"),
      (104.8, 17.0, "RHR read", "write", "fifo_pop + rhr_full_q\n"
       "LSR[0] data_ready")]
r = [fs.block(ax, x, 15.4, w, 6.6, rx, kind=k, fs=7.8, sub=s, sub_fs=6.1)
     for x, w, rx, k, s in RX]
for a, b, lb in zip(r, r[1:], [None, "fall edge", "write_init",
                              "fifo_pop"]):
    fs.wire(ax, a["e"], b["w"], label=lb, label_fs=6.2, color=fs.ACCENT)

# ============================================ 4  WHAT THE TWO CHAINS LOOK LIKE
fs.label(ax, L, 13.4, "4   THE TWO CHAINS, AND THE ONLY THINGS THAT CAN GO "
         "WRONG ON THEM", fs=7.6, color=fs.ACCENT, weight="bold", ha="left")

fs.note(ax, L, 2.9, 59.6, 9.6,
        "TX CHAIN   APB write \u2192 TX FIFO (16 deep) \u2192 TSR \u2192 SOUT.\n"
        "   One baud_rate_edge per bit; the TSR is drained 8 edges after\n"
        "   the first, so the FIFO \u2014 not the FSM \u2014 absorbs bursts.\n"
        "RX CHAIN   SIN \u2192 sync + majority \u2192 RSR \u2192 RX FIFO "
        "(16 deep, 11 bit) \u2192 APB read.\n"
        "   One timing_bit_center_edge per bit, at the MIDDLE of the bit;\n"
        "   the FIFO \u2014 not the wire \u2014 absorbs the inter-character gap.",
        fs=7.0, pad_y=0.7)

fs.note(ax, 63.4, 2.9, R - 63.4, 9.6,
        "WHAT CAN GO WRONG   RX: a stop bit sampled LOW is a framing error,\n"
        "   a data bit that disagrees with the LCR[5:4] parity mode is a\n"
        "   parity error, and 8 low bits raise break_ind.  All three ride\n"
        "   into the RX FIFO beside the 8 data bits and surface only in\n"
        "   LSR[2] / [3] / [4].\n"
        "   TX: nothing can corrupt a byte already in the TSR.  The only\n"
        "   user-caused hazard is a FULL TX FIFO \u2014 the THR write is\n"
        "   silently dropped and only LSR[5] thr_empty says so afterwards.",
        fs=6.8, pad_y=0.7)

fs.footer(fig,
          "The FIFO depth is invisible to firmware: it cannot read either FIFO, "
          "only LSR and ISR \u2014 so a full TX FIFO silently drops the THR "
          "write and a full RX FIFO latches LSR[1]. The status bits are the "
          "entire contract with software.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig07_uart_internals.png")
