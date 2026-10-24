"""fig24 -- the software-visible contract of the APB UART, extracted from fig07.

Parent fig07 (d_uart_internals.py) is FROZEN; this file copies only its
register strip / DLAB note / status-contract footer and gives them the whole
canvas.

RTL read (same IP the parent used):
  apb_uart-main/include/obi/obi_uart_pkg.sv          reg offsets, bit fields
  apb_uart-main/include/obi/obi_uart_register.sv     DLAB decode, SPR, read side
  apb_uart-main/include/obi/obi_uart_interrupts.sv   IIR priority encoder
  apb_uart-main/include/obi/obi_uart_rx.sv / _tx.sv  what sets/clears LSR
  apb_uart-main/rtl/apb_uart.sv                      PADDR = {PADDR,2'b0}
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs
from matplotlib.patches import Rectangle

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

TITLE = ("Eight registers, and only two of them \u2014 LSR and ISR \u2014 tell "
         "firmware anything at all")
SUB = ("START HERE at (1), the register map: every byte of UART state lives "
       "there.   Then (2) the DLAB alias, (3) the 8-bit LSR, (4) the interrupt "
       "priority encoder, (5) FCR flush + reset.")

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
L, R = 2.4, 122.9
W = R - L


def band(y, h, fc="#F7FAFD", ec="#C9D6E4", lw=0.9, z=1):
    ax.add_patch(Rectangle((L, y), W, h, facecolor=fc, edgecolor=ec,
                           linewidth=lw, zorder=z))


def secnum(x, y, n, s, f=7.4):
    fs.badge(ax, x, y, n, r=1.05, fs=6.8)
    fs.label(ax, x + 1.9, y, s, fs=f, color=fs.ACCENT, weight="bold",
             ha="left")


# ============================================== 1  THE EIGHT-REGISTER MAP
secnum(3.0, 57.3, 1, "THE REGISTER MAP \u2014 APB (Advanced Peripheral Bus) slave 2, base "
      "0x4000_2000.   PADDR[2:0] is a WORD address.")
fs.label(ax, R, 57.3, "offsets step by 4  \u00b7  read DOWN  \u00b7  column 4 "
         "is the same word re-decoded", fs=6.4, color=fs.GREY, ha="right")

CX = [L, 9.4, 31.4, 56.4, 76.4, 93.4, R]
AH, RH = 1.9, 1.55
AY = 41.9
ax.add_patch(Rectangle((L, AY), W, AH + 8 * RH, facecolor="#FFFFFF",
                       edgecolor=fs.MID, linewidth=1.1, zorder=2))
ax.add_patch(Rectangle((L, AY + 8 * RH), W, AH, facecolor=fs.S_ADDR,
                       edgecolor=fs.MID, linewidth=1.0, zorder=3))
for x in CX[1:-1]:
    ax.add_patch(Rectangle((x, AY), CX[-1] - x, AH + 8 * RH, facecolor="none",
                           edgecolor="#B9C9DA", linewidth=0.7, zorder=4))

HEAD = ["OFFSET", "BYTE ADDRESS", "REGISTER \u2014 DLAB = 0",
        "SAME WORD \u2014 DLAB = 1", "ACCESS", "WHAT FIRMWARE USES IT FOR"]
for i, s in enumerate(HEAD):
    fs.label(ax, (CX[i] + CX[i + 1]) / 2.0, AY + 8 * RH + AH / 2.0, s,
             fs=6.6, color="#7F6000", weight="bold")

ROWS = [
 ("0x00", "0x4000_2000", "RHR / THR", "DLL", "R / W",
  "receive holding / transmit holding register: the data port"),
 ("0x04", "0x4000_2004", "IER", "DLM", "R / W",
  "IER = interrupt enable register: 5 enables, all clear at reset"),
 ("0x08", "0x4000_2008", "ISR  (read-only)", "FCR  (write-only)", "R / W",
  "read = which interrupt is pending; write = FIFO control"),
 ("0x0C", "0x4000_200C", "LCR", "\u2014 APB error", "R / W",
  "DLAB = LCR[7] plus word length, parity, stop bits"),
 ("0x10", "0x4000_2010", "MCR", "\u2014 APB error", "R / W",
  "loopback, RTS, DTR, OUT1/OUT2 \u2014 modem control"),
 ("0x14", "0x4000_2014", "LSR  (read-only)", "\u2014 APB error", "read-only",
  "THE ONLY LIVE STATUS: 8 bits, full table in (3)"),
 ("0x18", "0x4000_2018", "MSR  (read-only)", "\u2014 APB error", "read-only",
  "4 modem lines + 4 delta bits; read clears the deltas"),
 ("0x1C", "0x4000_201C", "SPR", "\u2014 APB error", "write ignored",
  "scratch pad NOT implemented: reads return 0"),
]
for i, r in enumerate(ROWS):
    y = AY + (7 - i) * RH + RH / 2.0
    if i % 2 == 0:
        ax.add_patch(Rectangle((L, y - RH / 2.0), W, RH, facecolor="#F4F8FC",
                               edgecolor="none", zorder=2))
    for j, s in enumerate(r):
        c = fs.ACCENT if j == 2 else fs.TXT
        w = "bold" if j in (0, 1, 2) else "normal"
        fs.label(ax, (CX[j] + CX[j + 1]) / 2.0, y, s, fs=6.5, color=c,
                 weight=w)
fs.qa_report(fig)

# ============================================ 2  THE DLAB ALIAS  (LCR bit 7)
secnum(3.0, 40.2, 2, "THE ONE CONFUSING TRICK \u2014 DLAB = LCR[7] re-decodes "
      "the SAME two words into the 16-bit divisor latch", f=7.2)
band(32.6, 6.8, "#FFFDF5", "#E0C97A")

BIT = [("7", "DLAB"), ("6", "set_break"), ("5", "force_par"),
       ("4", "even_par"), ("3", "par_en"), ("2", "stop_bits"),
       ("1:0", "word_len")]
BW = (34.0 - 6 * 0.12) / 7.0
for i, (bn, nm) in enumerate(BIT):
    fs.block(ax, 2.4 + i * (BW + 0.12), 34.65, BW, 2.7, "bit " + bn + "\n" + nm,
             kind="write" if i == 0 else "plain", fs=5.4)
fs.label(ax, 19.4, 38.7, "LCR \u00b7 line control register \u00b7 offset 0x0C",
         fs=6.6, color=fs.ACCENT, weight="bold")
fs.label(ax, 19.4, 33.3, "bits 6:0 all describe the wire frame \u2014 only bit 7 "
         "changes what firmware is talking to", fs=6.0, color=fs.GREY)

DX = [38.6, 51.1, 67.1, 83.1, R]
HD, DH = 1.4, 2.2
DY = 32.6 + (6.8 - (HD + 2 * DH)) / 2.0
for i, s in enumerate(["LCR[7]", "word 0x00", "word 0x04", "words 0x08 \u2026 0x1C"]):
    ax.add_patch(Rectangle((DX[i], DY + 2 * DH), DX[i + 1] - DX[i], HD,
                           facecolor=fs.S_ADDR, edgecolor="#BF8F00",
                           linewidth=0.8, zorder=3))
    fs.label(ax, (DX[i] + DX[i + 1]) / 2.0, DY + 2 * DH + HD / 2.0, s,
             fs=6.3, color="#7F6000", weight="bold")
ALIAS = [("DLAB = 0\nnormal", "RHR / THR\ndata port", "IER\ninterrupt enable",
          "ISR/FCR, LCR, MCR, LSR, MSR, SPR \u2014 unchanged"),
         ("DLAB = 1\ndivisor latch", "DLL\ndivisor bits 7:0", "DLM\ndivisor bits 15:8",
          "APB PSLVERR \u2014 no register lives there")]
for r, row in enumerate(ALIAS):
    y = DY + (1 - r) * DH
    fc = "#FFFFFF" if r == 0 else "#FBF3D9"
    for i, s in enumerate(row):
        ax.add_patch(Rectangle((DX[i], y), DX[i + 1] - DX[i], DH,
                               facecolor=fc, edgecolor="#BF8F00",
                               linewidth=0.8, zorder=3))
        fs.label(ax, (DX[i] + DX[i + 1]) / 2.0, y + DH / 2.0, s, fs=6.1,
                 color=fs.RED if (r == 1 and i == 3) else fs.TXT,
                 weight="bold" if i == 0 else "normal")
fs.label(ax, 2.4, 31.4, "Software rule:  set LCR[7]=1  \u2192  write DLL  \u2192  "
         "write DLM  \u2192  set LCR[7]=0.    Leave DLAB set and the next THR write "
         "silently becomes the low divisor byte instead of a character.",
         fs=6.3, color=fs.RED, ha="left")
fs.qa_report(fig)

# ======================================= 3  THE COMPLETE 8-BIT LSR (2 halves)
secnum(3.0, 30.0, 3, "THE COMPLETE 8-BIT LSR \u2014 Line Status Register, the one "
      "register that is always telling firmware the truth")
fs.label(ax, R, 30.0, "bits 7:4 left  \u00b7  bits 3:0 right  \u00b7  resets to "
         "0x60, so bits 5 and 6 read 1 before any traffic", fs=6.2, color=fs.GREY,
         ha="right")

LSR_ROWS = [
 ("7", "fifo_err", "RX FIFO holds a flagged word ahead of the data",
  "RHR read pops the flag word out"),
 ("6", "tx_empty", "TSR and TX FIFO both empty \u2014 line is idle",
  "the next THR write, or a TX FIFO flush"),
 ("5", "thr_empty", "nothing left to send: THR and TX FIFO empty",
  "writing THR   (reads 1 at reset \u2014 LSR = 0x60)"),
 ("4", "break_ind", "the line stayed low for a whole character",
  "RHR read \u2014 sticky, it rides out with the byte"),
 ("3", "frame_err", "stop bit sampled low",
  "RHR read \u2014 sticky, rides out with the byte"),
 ("2", "par_err", "data bits disagree with the LCR[5:4] parity mode",
  "RHR read \u2014 sticky, rides out with the byte"),
 ("1", "overrun", "a byte arrived while the previous one was unread",
  "RHR read (FIFO mode: once both words drain)"),
 ("0", "data_ready", "RX FIFO is not empty",
  "RHR read empties the FIFO again"),
]
HD3, RH3 = 1.5, 1.3
TOP3 = 29.1
for half, x0 in ((0, 2.4), (1, 62.9)):
    cw = [4.6, 12.4, 21.5, 21.5] if half == 0 else [5.0, 12.4, 21.3, 21.3]
    xs = [x0]
    for w in cw:
        xs.append(xs[-1] + w)
    bot = TOP3 - (HD3 + 4 * RH3)
    ax.add_patch(Rectangle((x0, bot), sum(cw), HD3 + 4 * RH3,
                           facecolor="#FFFFFF", edgecolor=fs.MID,
                           linewidth=1.0, zorder=2))
    ax.add_patch(Rectangle((x0, TOP3 - HD3), sum(cw), HD3, facecolor=fs.S_RESP,
                           edgecolor=fs.MID, linewidth=0.9, zorder=3))
    for i, s in enumerate(["BIT", "NAME", "WHAT SETS IT", "WHAT CLEARS IT"]):
        fs.label(ax, (xs[i] + xs[i + 1]) / 2.0, TOP3 - HD3 / 2.0, s, fs=6.2,
                 color="#1E5B2A", weight="bold")
    for k in range(4):
        r = LSR_ROWS[k + 4 * half]
        y = TOP3 - HD3 - (k + 0.5) * RH3
        if k % 2 == 0:
            ax.add_patch(Rectangle((x0, y - RH3 / 2.0), sum(cw), RH3,
                                   facecolor="#F4F8F4", edgecolor="none",
                                   zorder=2))
        fs.label(ax, (xs[0] + xs[1]) / 2.0, y, r[0], fs=7.0, color=fs.ACCENT,
                 weight="bold")
        fs.label(ax, (xs[1] + xs[2]) / 2.0, y, r[1], fs=6.2, color=fs.ACCENT,
                 weight="bold")
        fs.label(ax, (xs[2] + xs[3]) / 2.0, y, r[2], fs=6.0, color=fs.TXT)
        fs.label(ax, (xs[3] + xs[4]) / 2.0, y, r[3], fs=6.0, color=fs.TXT)
fs.qa_report(fig)

# ============================== 4  THE INTERRUPT PRIORITY ENCODER (full width)
secnum(3.0, 20.9, 4, "THE INTERRUPT PRIORITY ENCODER \u2014 five latches feed one "
      "ISR/IIR word; the encoder shows only the highest, top to bottom")
fs.label(ax, R, 19.9, "RLS = Receive Line Status  \u00b7  RDA = Receiver Data "
         "Ready  \u00b7  TO = reception Timeout  \u00b7  THRE = Transmit "
         "Holding Register Empty  \u00b7  MSI = Modem Status Interrupt",
         fs=6.2, color=fs.GREY, ha="right")
PX = [L, 10.4, 23.4, 33.4, 66.4, 81.4, R]
HD4, RH4, SUMH = 1.4, 1.2, 2.4
T4 = 19.4
ax.add_patch(Rectangle((L, T4 - (HD4 + 5 * RH4 + SUMH)), W,
                       HD4 + 5 * RH4 + SUMH, facecolor="#FFFFFF",
                       edgecolor=fs.MID, linewidth=1.0, zorder=2))
ax.add_patch(Rectangle((L, T4 - HD4), W, HD4, facecolor=fs.S_ALARM,
                       edgecolor=fs.MID, linewidth=0.9, zorder=3))
for x in PX[1:-1]:
    ax.add_patch(Rectangle((x, T4 - (HD4 + 5 * RH4 + SUMH)), PX[-1] - x,
                           HD4 + 5 * RH4, facecolor="none", edgecolor="#D9C2C2",
                           linewidth=0.7, zorder=4))
for i, s in enumerate(["PRIORITY", "SOURCE", "ISR[3:1]",
                       "WHAT SETS THE LATCH", "ENABLED BY IER",
                       "WHAT FIRMWARE MUST DO \u2014 AND WHAT CLEARS IT"]):
    fs.label(ax, (PX[i] + PX[i + 1]) / 2.0, T4 - HD4 / 2.0, s, fs=6.2,
             color=fs.RED, weight="bold")
PRI = [
 ("1", "RLS", "3'b011", "any of LSR[7:4]: overrun, parity, frame, break",
  "IER[1]  rlstat", "read LSR to clear the latch, then RHR for the byte"),
 ("2", "RDA", "3'b010", "RX data at or above the FCR trigger level",
  "IER[0]  dtr", "read RHR until LSR[0] = 0 \u2014 the only way to clear it"),
 ("3", "TO", "3'b110", "FIFO mode only: line idle, partial char waiting",
  "IER[0]  dtr  (same bit)", "read RHR \u2014 it self-clears, no LSR read needed"),
 ("4", "THRE", "3'b001", "LSR[5] thr_empty: TX FIFO and THR are empty",
  "IER[2]  thr_empty", "write THR \u2014 re-arms it for the next byte"),
 ("5", "MSI", "3'b000", "any of MSR[3:0]: a modem input changed",
  "IER[3]  mstat", "read MSR \u2014 reading clears the delta bits"),
]
for k, row in enumerate(PRI):
    y = T4 - HD4 - (k + 0.5) * RH4
    if k == 0:
        ax.add_patch(Rectangle((L, y - RH4 / 2.0), W, RH4, facecolor="#FDF2F2",
                               edgecolor="none", zorder=2))
    for i, s in enumerate(row):
        fs.label(ax, (PX[i] + PX[i + 1]) / 2.0, y, s, fs=6.1,
                 color=fs.ACCENT if i == 1 else fs.TXT,
                 weight="bold" if i in (0, 1, 2) else "normal")
ys = T4 - HD4 - 5 * RH4 - SUMH / 2.0
ax.add_patch(Rectangle((L, ys - SUMH / 2.0), W, SUMH, facecolor=fs.S_ALARM,
                       edgecolor=fs.RED, linewidth=1.0, zorder=3))
fs.label(ax, (L + R) / 2.0, ys,
         "READING 0x08 CLEARS NOTHING \u2014 ISR / IIR (interrupt status / "
         "identification register) is a pure read:   ISR[7:6] = 11 (FIFOs "
         "present)  \u00b7  ISR[5:4] = 00  \u00b7  ISR[3:1] = the id above  "
         "\u00b7  ISR[0] = status, 0 means an interrupt is pending.\n"
         "Only the action in the last column clears a latch.    A write to 0x08 "
         "is FCR (FIFO control) and always reads back as 0.", fs=5.8, color=fs.RED,
         weight="bold")
fs.qa_report(fig)

# ================================= 5  FCR FLUSH STROBES + RESET / FLUSH BEHAVIOUR
secnum(3.0, 8.7, 5, "FCR \u2014 FIFO CONTROL AT 0x08 (WRITE-ONLY), AND WHAT RESET "
      "THROWS AWAY")
B5Y, B5H = 4.3, 3.8
band(B5Y, B5H, "#FFFFFF", "#C9D6E4")
HW = (W - 1.2) / 2.0
fs.note(ax, L, B5Y, HW, B5H,
        "FCR bits   [0] fifo_en  = 1 to use the FIFOs at all (off = 8250 "
        "behaviour, 1 byte deep)\n"
        "   [2] rx_fifo_rst, [1] tx_fifo_rst  =  self-clearing 1-cycle flush "
        "strobes; write 1 to empty that\n"
        "   FIFO, they read back as 0  \u00b7  [7:6] rx_fifo_tl = the RDA / TO "
        "trigger level",
        fs=5.6, pad_y=0.45)
fs.note(ax, L + HW + 1.2, B5Y, HW, B5H,
        "RESET   every register returns to its 16550 reset value: IER = 0x00 (no "
        "interrupts), LCR = 0x00,\n"
        "   MCR = 0x00, LSR = 0x60, DLL = 0x01, DLM = 0x00.  Both FIFOs are emptied "
        "by the same flush\n"
        "   logic, so any byte already queued in the RX or TX FIFO is DESTROYED "
        "\u2014 and so is the byte sitting in the TSR.",
        fs=5.6, pad_y=0.45)
fs.qa_report(fig)

# ============================ 6  THE PUNCHLINE -- WHAT THE 16-DEEP FIFOs HIDE
ax.add_patch(Rectangle((L, 0.1), W, 3.8, facecolor=fs.S_ALARM,
                       edgecolor=fs.RED, linewidth=1.6, zorder=3))
fs.label(ax, 4.6, 2.9, "6", fs=7.2, color="#FFFFFF", weight="bold",
         ha="center",
         bbox=dict(boxstyle="circle,pad=0.30", fc=fs.RED, ec="none"))
fs.label(ax, (L + R) / 2.0 + 1.2, 2.0,
         "THE FIFOs ARE 16 DEEP AND COMPLETELY INVISIBLE TO SOFTWARE \u2014 "
         "firmware cannot read either FIFO, and no register reports how full "
         "one is.\n"
         "Write THR with the TX FIFO full and the byte is silently swallowed: "
         "no APB error, no interrupt, nothing in ISR \u2014 and LSR[5] "
         "thr_empty = 0 is the only trace, seen only AFTER the loss.\n"
         "So a driver that trusts \"the write returned OK\" instead of polling "
         "LSR[5] has thrown the byte away with no diagnostic of any kind.",
         fs=6.6, color=fs.RED, weight="bold")

fs.footer(fig,
          "Failure mode: treating the 16-deep TX FIFO as safe to write blind. "
          "A full FIFO swallows the THR write \u2014 no APB error, no interrupt "
          "\u2014 and LSR[5] = 0 is the only evidence, read after the fact.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig24_uart_register_map.png")
