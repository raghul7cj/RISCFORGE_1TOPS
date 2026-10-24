#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fig02_soc_address_map  --  RISCFORGE SoC memory map + APB aperture decode.

Every value below is taken from the RTL:
  * rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv:678-690   xbar_addr_map / apb_addr_map
  * rtl/ips/RTL_SOC/instr_fetch_demux.sv:24-34           BOOTROM/ISRAM windows, RESET_PC
  * rtl/ips/axi_lite_to_apb/axi_lite_to_apb.sv:267-299addr_decode + SLVERR default
  * common_cells/addr_decode_dync.sv:103-119            32-bit range compare, dec_error
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

FOOTER = ("Failure mode this prevents — address aliasing: two live peripherals sharing one "
          "aperture, or a hole that decodes onto its neighbour instead of erroring.  "
          "addr_decode asserts $onehot0(matched_rules) plus non-overlapping rules, so an "
          "overlapping apb_addr_map fails simulation instead of shipping silently.")

TITLE = ("Decode is a 4 KB-aligned compare chain \u2014 every unmapped hole "
         "returns an AXI error instead of aliasing onto a live peripheral")
SUBTITLE = ("Read in three steps:   (1) the map   \u2192   (2) how one address "
            "becomes one APB select   \u2192   (3) one address walked "
            "end to end.")

# --------------------------------------------------------------------------- data
# (name, owner/source, base, end, size, rule, hole)
REGIONS = [
    ("BootROM", "boot_rom.sv", "0x0000_0000", "0x0000_003F", "64 B", "no rule", False),
    ("hole", "nothing decodes", "0x0000_0040", "0x0000_FFFF", "64 KB", "\u2192 DECERR", True),
    ("ISRAM", "imem_sram_wrapper", "0x0001_0000", "0x0001_7FFF", "32 KB", "xbar[0]", False),
    ("hole", "nothing decodes", "0x0001_8000", "0x0001_FFFF", "32 KB", "\u2192 DECERR", True),
    ("DSRAM", "axi_lite_sram_if", "0x0002_0000", "0x0002_7FFF", "32 KB", "xbar[1]", False),
    ("hole", "nothing decodes", "0x0002_8000", "0x3FFF_FFFF", "1 GB", "\u2192 DECERR", True),
    ("APB0  I2C", "apb_i2c-master", "0x4000_0000", "0x4000_0FFF", "4 KB", "apb[0]", False),
    ("APB1  Timer0", "apb_timer-master", "0x4000_1000", "0x4000_1FFF", "4 KB", "apb[1]", False),
    ("APB2  UART", "apb_uart-main", "0x4000_2000", "0x4000_2FFF", "4 KB", "apb[2]", False),
    ("APB3  GPIO", "gpio-master", "0x4000_3000", "0x4000_37FF", "2 KB", "apb[3]", False),
    ("hole", "no apb rule hits", "0x4000_3800", "0x4000_3FFF", "2 KB", "\u2192 SLVERR", True),
    ("APB4  SPI", "spi_master_ip", "0x4000_4000", "0x4000_4FFF", "4 KB", "apb[4]", False),
    ("APB5  Timer1", "apb_timer-master", "0x4000_5000", "0x4000_5FFF", "4 KB", "apb[5]", False),
    ("hole", "no apb rule hits", "0x4000_6000", "0x4FFF_FFFF", "256 MB", "\u2192 SLVERR", True),
]

# ladder geometry ------------------------------------------------------------
C_NAME = (2.0, 13.0)
C_OWN = (15.3, 11.6)
C_BASE = (27.2, 8.2)
C_END = (35.7, 8.2)
C_SIZE = (44.2, 5.0)
C_RULE = (49.5, 8.3)
COLS = (C_NAME, C_OWN, C_BASE, C_END, C_SIZE, C_RULE)
ROW_H, ROW_P = 2.15, 2.38
HDR_LBL, TOP_Y = 51.6, 48.8
RX, RW = 60.0, 63.0          # right-hand column

fig, ax = fs.slide(TITLE, SUBTITLE)
X, Y = fs.canvas(ax)


def row_y(i):
    return TOP_Y - i * ROW_P


# badge geometry: one size for every step marker in the figure
BADGE_R, BADGE_FS = 0.9, 7.2

# --------------------------------------------------------------------------- R1
CMP_XY = (60.0, 43.8, 30.0, 11.8)      # x, y, w, h
EQB_XY = (92.5, 43.8, 30.5, 11.8)
WIRE_Y = 41.3
STEP2_HDR = (60.0, 56.6, 63.0, 2.0)    # step-2 caption bar, right column

CMP_TXT = (
    "addr_decode  #( .NoIndices(6), .NoRules(6) )\n"
    "  NoRules(6)   = compare against 6 windows\n"
    "  NoIndices(6) = return the winner as a 3-bit index\n"
    "rule_t = { int unsigned idx;\n"
    "           addr_t start_addr; addr_t end_addr; }\n"
    "match[i] = (addr >= start_addr[i])\n"
    "       && (addr <  end_addr[i])\n"
    "        full 32-bit compare \u2014 no mask, no NAPOT"
)

EQB_TXT = (
    "psel[i] = 1  \u21d4  paddr >= apb_addr_map[i].start_addr\n"
    "              && paddr <  apb_addr_map[i].end_addr\n"
    "\n"
    "all six apb windows are 4 KB aligned  \u21d2\n"
    "paddr[31:12] == 12'h400000 + n      (n = 0..5)\n"
    "except apb[3] GPIO: 0x800 \u2192 a 2 KB half-window"
)


def draw_compare():
    """Step 2a: the decode comparator and its aperture-alignment formula."""
    hx, hy, hw, hh = STEP2_HDR
    fs.block(ax, hx, hy, hw, hh,
             "STEP 2  ·  how one address becomes one APB select",
             kind="plain", ls="-", lw=1.0, fs=7.6, bold=True,
             tc=fs.ACCENT, box_alpha="#EDF3F9")
    cx, cy, cw, ch = CMP_XY
    fs.block(ax, cx, cy, cw, ch, CMP_TXT, kind="ctrl", fs=6.9, bold=False)
    ex, ey, ew, eh = EQB_XY
    fs.eqbox(ax, ex, ey, ew, eh, EQB_TXT, fs=6.9)
    fs.badge(ax, cx + 1.7, cy + ch - 1.7, 1, r=BADGE_R, fs=BADGE_FS)


# --------------------------------------------------------------------------- R2
CH_Y, CH_H = 29.0, 11.8
CH = [(81.0, 20.0), (104.0, 19.0)]

CH_TXT = (
    "apb_sel_idx : sel_idx_t\n"
    "$clog2(6) = 3 bits wide\n"
    "= rule_t'(apb_addr_map[i].idx)\n"
    "Timer0 window  →  3'b001",
    "pselx_o = psel[5:0]\n"
    "  PSEL = APB per-slave select,\n"
    "  one bit per APB slave\n"
    "sel_t = logic [NoApbSlaves-1:0]\n"
    "       = logic [5:0]\n"
    "PSEL[1] alone → apb_timer.sv",
)

ERR_XY = (60.0, 20.5, 63.0, 5.0)
ERR_TXT = ("dec_error_o = 1  (en_default_idx_i = 1'b0)   →   APB Setup phase is skipped\n"
           "axi_rresp = RESP_SLVERR,   rdata = 32'hDEA110C8   —   "
           "a hole is never silently routed to a neighbour")


def draw_chain():
    """R2: comparator -> APB index -> PSEL, plus the no-match error branch."""
    cx, cy, cw, ch = CMP_XY
    # hit path: out of the comparator, down, across, into the index block
    ix, iw = CH[0]
    fs.wire(ax, (cx + 9.0, cy), (ix + iw / 2.0, CH_Y + CH_H),
            via=[(cx + 9.0, WIRE_Y), (ix + iw / 2.0, WIRE_Y)],
            color=fs.ACCENT, lw=1.7)
    fs.onwire(ax, (cx + 9.0 + ix + iw / 2.0) / 2.0, WIRE_Y,
              "dec_valid_o = 1", fs=6.6)
    for i, ((bx, bw), txt) in enumerate(zip(CH, CH_TXT)):
        kind = ("mux", "periph")[i]
        fs.block(ax, bx, CH_Y, bw, CH_H, txt, kind=kind, fs=6.9, bold=False)
        fs.badge(ax, bx - 1.55, CH_Y + CH_H - 1.8, i + 2, r=BADGE_R, fs=BADGE_FS)
    px, pw = CH[1]
    fs.wire(ax, (ix + iw, CH_Y + CH_H / 2.0), (px, CH_Y + CH_H / 2.0),
            color=fs.ACCENT, lw=1.7)
    # no-match branch: its own lane straight down the left of the column
    ex, ey, ew, eh = ERR_XY
    fs.wire(ax, (cx + 3.0, cy), (cx + 3.0, ey + eh), color=fs.RED, lw=1.5,
            dashed=True)
    fs.label(ax, cx + 4.4, 34.0, "no rule matches", fs=6.8, color=fs.RED,
             weight="bold", ha="left")
    fs.eqbox(ax, ex, ey, ew, eh, ERR_TXT, fs=7.0,
             fc="#FDECEA", ec="#C0504D", color="#7F1010")


# --------------------------------------------------------------------------- R3
EX_HDR = (2.0, 14.0, 121.0, 2.0)
EX_Y, EX_H = 4.6, 7.4
EX = [(3.0, 38.0), (43.5, 38.0), (84.0, 38.0)]

EX_TXT = (
    "core issues a 32-bit load\n"
    "to  0x4000_1234\n"
    "xbar rule [2] fires first:\n"
    "0x4000_0000 .. 0x5000_0000\n"
    "→ APB bridge",
    "the page number is what\n"
    "the APB rules compare:\n"
    "paddr[31:12] = 0x400001\n"
    "rule[1] = 0x4000_1000\n"
    "  .. 0x4000_2000  (HIT)",
    "idx_o = 1\n"
    "apb_sel_idx = 3'b001\n"
    "pselx_o = 6'b000010\n"
    "PSEL[1] only\n"
    "apb_timer.sv  (Timer 0)",
)


def draw_example():
    """R3: one address walked all the way through the decode chain."""
    hx, hy, hw, hh = EX_HDR
    fs.block(ax, hx, hy, hw, hh,
             "STEP 3  ·  worked example \u2014 one core load to 0x4000_1234, end to end",
             kind="plain", ls="-", lw=1.0, fs=7.6, bold=True,
             tc=fs.ACCENT, box_alpha="#EDF3F9")
    cy = EX_Y + EX_H / 2.0
    for i, ((bx, bw), txt) in enumerate(zip(EX, EX_TXT)):
        kind = ("bus", "ctrl", "periph")[i]
        fs.block(ax, bx, EX_Y, bw, EX_H, txt, kind=kind, fs=6.9, bold=False)
        fs.badge(ax, bx + bw / 2.0, 13.1, i + 4, r=BADGE_R,
                 fs=BADGE_FS)
    for i in range(2):
        x0 = EX[i][0] + EX[i][1]
        fs.wire(ax, (x0, cy), (EX[i + 1][0], cy), color=fs.ACCENT, lw=1.7)


# --------------------------------------------------------------------------- R0
LAYER_XY = (2.0, 53.0, 55.8, 5.6)
LAYER_TXT = (
    "Two error codes, two layers.  DECERR = AXI decode error, raised by the crossbar's\n"
    "default slave for a hole outside every crossbar (xbar) rule.  SLVERR = AXI slave error, raised\n"
    "by the APB bridge instead, for a hole inside xbar rule [2] but outside every apb rule."
)

STEP1_TTL = ("STEP 1  ·  the map — every region, who owns it, and the "
             "rule that claims it")


def draw_layers():
    """Step 1 caption: what the table is, and which layer raises which error."""
    lx, ly, lw, lh = LAYER_XY
    fs.block(ax, lx, ly, lw, lh, STEP1_TTL, kind="plain", ls="-", lw=1.0,
             fs=7.6, bold=True, tc=fs.ACCENT, box_alpha="#EDF3F9",
             sub=LAYER_TXT, sub_fs=6.6)


def main():
    # ---- table header
    for (cx, cwd), cap in zip(
            COLS, ("region", "owner block", "base", "end (excl.)", "size",
                   "rule")):
        fs.label(ax, cx + cwd / 2.0, HDR_LBL, cap, fs=7.0,
                 color=fs.GREY, weight="bold")

    # ---- ladder rows
    for i, (nm, own, base, end, size, rule, hole) in enumerate(REGIONS):
        y = row_y(i)
        if hole:
            kind = "note"
        elif nm.startswith("APB"):
            kind = "periph"
        elif nm in ("ISRAM", "DSRAM"):
            kind = "mem"
        else:
            kind = "ctrl"
        b = fs.block(ax, C_NAME[0], y, C_NAME[1], ROW_H, nm, kind=kind,
                     fs=7.4, bold=True)
        if hole:
            b["patch"].set_hatch("///")
            b["patch"].set_edgecolor("#C6C6C6")
            b["patch"].set_linewidth(0.6)
            ax.texts[-1].set_bbox(dict(fc="#FFFFFF", ec="none", pad=1.4))
        fs.block(ax, C_OWN[0], y, C_OWN[1], ROW_H, own, kind="plain", fs=6.6)
        for (cx, cwd), txt in ((C_BASE, base), (C_END, end),
                               (C_SIZE, size), (C_RULE, rule)):
            hot = txt[:1] == chr(0x2192)
            fs.block(ax, cx, y, cwd, ROW_H, txt, kind="plain", fs=7.0,
                     tc="#7F1010" if hot else None, bold=hot)

    draw_layers()
    draw_compare()
    draw_chain()
    draw_example()
    fs.footer(fig, FOOTER)
    fs.pad_limits(ax, 0.055)
    fig._qaname = "fig02_soc_address_map"
    fs.qa_report(fig)
    fs.save(fig, "fig02_soc_address_map.png")


if __name__ == "__main__":
    main()