#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fig19_soc_boot_sequence  --  the cold-boot order: ROM fetch, then DMA, then release.

Merged/extracted from the boot content of two FROZEN parents (values unchanged):
  * d_soc_topology.py   (fig01)  - boot_rom + instr_fetch_demux block, RESET_PC,
                                    the core-only fetch wire that misses the crossbar,
                                    bootloader as xbar slave [1], ISRAM 32 KB
  * d_soc_addressmap.py (fig02)  - REGIONS rows: BootROM "no rule", the
                                    0x0000_0040-0x0000_FFFF hole -> DECERR,
                                    ISRAM xbar[0]

Confirmed in the same RTL those two scripts cite:
  RTL_SOC/instr_fetch_demux.sv:24-34,68-74  BOOTROM/ISRAM windows, RESET_PC,
                                            sel_rom / sel_isram, always-grant ROM
  RTL_SOC/riscforge_soc_subsystem.sv:238,706-738,1367-1371
                                            BOOTROM_NUM_WORDS=16, demux on core_rst_n,
                                            bootloader drives boot_done_o
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

TITLE = ("Cold reset parks the core in the 64-byte BootROM; the bootloader DMAs the "
         "image into ISRAM and only then does the fetch leave the ROM")

SUBTITLE = ("Read left to right \u2014 the ORDER is the lesson:   "
            "1 reset  \u2192  2 fetch from the ROM  \u2192  3 DMA copy into ISRAM  \u2192  "
            "4 release reset, fetch from ISRAM.")

FOOTER = ("Failure mode this prevents \u2014 booting from a ROM nobody can write: the ROM has no "
          "crossbar rule, so if reset were released before the image was in ISRAM the core "
          "would run out of a window nothing can load into \u2014 and a load at 0x0000_0040 or "
          "above returns DECERR (decode error), never ROM data.")

# ------------------------------------------------------------------ layout grid
X0, CW, GAP = 3.4, 28.6, 1.2
COLX = (X0, X0 + CW + GAP, X0 + 2 * (CW + GAP), X0 + 3 * (CW + GAP))
Y_CAP, H_CAP = 52.6, 3.6      # numbered step caption bars
H_BOX = 5.4                    # box height: main label + ONE sub line only
BOXS = ((46.2, H_BOX), (39.6, H_BOX), (33.0, H_BOX))
Y_NOTE, H_NOTE = 29.0, 3.0     # per-step recessive callout
Y_TL, H_TL = 25.0, 2.8         # time axis band
X_TL0 = X0 - 0.6                 # so each band's centre lands on its column
Y_BOT, H_BOT = 1.0, 21.8       # bottom band: address inset + glossary
INSET = (3.4, 1.0, 56.6, 21.8)
GLOSS = (62.0, 1.0, 59.4, 21.8)

CAPS = ("COLD RESET", "FETCH FROM THE ROM",
        "DMA COPY INTO ISRAM", "RELEASE RESET")

TL_SPANS = [(0, 1, "t0   reset asserted", fs.S_ALARM),
            (1, 2, "t1   core fetches ROM", fs.S_REQ),
            (2, 3, "t2   words copied in", fs.S_ADDR),
            (3, 4, "t3   boot_done_o", fs.S_RESP)]

# Per step: three blocks (top to bottom) + one recessive callout strip.
#   (kind, main label, sub text)
STEPS = [
    [("cpu",   "core held in reset", "core_rst_n = 0, the only state reset forces"),
     ("ctrl",  "RESET_PC", "reset vector constant baked into the core"),
     ("mem",   "BootROM   64 B", "16 words at 0x0000_0000 - 0x0000_003F")],
    [("req",   "core_instr_req + imem_sram_en",
                "instruction fetch, from the core only"),
     ("mux",   "instr_fetch_demux",
                "sel_rom = addr < 0x40, ROM always grants"),
     ("mem",   "boot_rom", "the reset vector is word 0 of 16")],
    [("periph", "bootloader", "crossbar slave port [1], not the core"),
     ("bus",   "crossbar rule [0]", "0x0001_0000 - 0x0001_7FFF, 32 KB"),
     ("mem",   "ISRAM   32 KB", "8192 words, filled by the bootloader")],
    [("ctrl",  "boot_done_o = 1", "bootloader output"),
     ("ctrl",  "resets released", "core_rst_n = 1, periph_rst_n = 1"),
     ("mux",   "fetch leaves the ROM",
                "instr_fetch_demux now selects ISRAM")],
]

CALLOUTS = [
    "the ROM has NO crossbar rule \u2014 so no load\nand no DMA can ever reach it",
    "core-only path: it never touches the crossbar,\nso it is not a normal instruction fetch",
    "DMA = direct memory access: the bootloader\ncopies the flash image word by word",
    "a core load at 0x0000_0040 or above returns\nDECERR (decode error), never ROM data",
]


def new_canvas():
    fig, ax = fs.slide(TITLE, SUBTITLE)
    X, Y = fs.canvas(ax)
    assert X > 122.0, "slide canvas too narrow for 4 step columns: %.1f" % X
    return fig, ax


def draw_step_frame(ax):
    """Caption bar + number badge + the recessive callout strip per column."""
    for i, cx in enumerate(COLX):
        fs.block(ax, cx, Y_CAP, CW, H_CAP, CAPS[i], kind="plain", ls="-",
                 lw=1.2, fs=7.6, bold=True, tc=fs.ACCENT,
                 box_alpha="#EDF3F9")
        fs.badge(ax, cx + 1.9, Y_CAP + H_CAP / 2.0, i + 1, r=1.05, fs=8.0)
    # NB: phase_bar's 2nd positional (x1_unit) is dead in the kernel - the
    # band scale comes only from unit=, which defaults to 1.0.
    fs.phase_bar(ax, X_TL0, CW + GAP, Y_TL, H_TL, TL_SPANS, fs=7.4,
                 unit=CW + GAP)


def draw_steps(ax):
    """Three blocks per column, wired top to bottom, plus its callout strip."""
    for i, cx in enumerate(COLX):
        for j, (by, bh) in enumerate(BOXS):
            kind, main, sub = STEPS[i][j]
            fs.block(ax, cx, by, CW, bh, main, kind=kind, fs=7.6, bold=True,
                     sub=sub, sub_fs=6.6)
            if j:                      # arrow from the block above
                fs.wire(ax, (cx + CW / 2.0, BOXS[j - 1][0]),
                        (cx + CW / 2.0, by + bh), color=fs.MID, lw=1.5)
        fs.note(ax, cx, Y_NOTE, CW, H_NOTE, CALLOUTS[i], fs=6.8,
                kind="note", valign="center")
        fs.wire(ax, (cx + CW / 2.0, BOXS[-1][0]), (cx + CW / 2.0, Y_NOTE + H_NOTE),
                color=fs.GREY, lw=1.2, dashed=True)


def draw_inset(ax):
    """Address-space position of the two fetchable windows (inset, bottom left)."""
    fs.block(ax, INSET[0], 20.0, INSET[2], 2.8,
             "WHERE IN MEMORY  -  the fetch can land in only two of these windows",
             kind="plain", ls="-", lw=1.2, fs=7.4, bold=True, tc=fs.ACCENT,
             box_alpha="#EDF3F9")
    rows = ((16.1, "mem", "BootROM   0x0000_0000 - 0x0000_003F   64 B",
             "fetched at t1", fs.GREEN, "#E2EFDA"),
            (12.3, "note", "hole        0x0000_0040 - 0x0000_FFFF   64 KB",
             "not fetchable", fs.RED, "#FBE4E4"),
            (8.5, "mem", "ISRAM       0x0001_0000 - 0x0001_7FFF   32 KB",
             "written at t2, fetched at t3", fs.GREEN, "#E2EFDA"),
            (4.7, "plain", "DSRAM       0x0002_0000 - 0x0002_7FFF   32 KB",
             "data only, never fetched", fs.GREY, "#F2F2F2"))
    for y, kind, txt, chip_s, cc, cfc in rows:
        fs.note(ax, 5.6, y, 32.0, 2.9, txt, fs=7.0, kind=kind)
        fs.chip(ax, 38.8, y + 1.45, chip_s, fc=cfc, ec=cc, tc=cc, fs=6.6)
    fs.brace_v(ax, 56.0, 8.5, 19.0, "these 2 rows only",
               color=fs.GREY, fs=6.8)
    fs.note(ax, INSET[0], 1.2, INSET[2], 3.0,
            "instr_fetch_demux compares the full 32-bit address: addr < 0x40 selects\n"
            "the ROM, 0x0001_0000 - 0x0001_7FFF selects ISRAM, nothing else fetches.",
            fs=6.8, kind="note")


def draw_glossary(ax):
    """The four terms a newcomer needs, expanded (bottom right)."""
    fs.block(ax, GLOSS[0], 20.0, GLOSS[2], 2.8,
             "GLOSSARY  -  the four terms this figure rests on",
             kind="plain", ls="-", lw=1.2, fs=7.4, bold=True, tc=fs.ACCENT,
             box_alpha="#EDF3F9")
    terms = (
        (15.4, "DMA  (direct memory access)  -  the bootloader copies the flash\n"
               "image into ISRAM itself, word by word. The CPU is not part of the\n"
               "transfer; it is still sitting in the BootROM while this happens."),
        (10.6, "RESET_PC  -  the reset vector constant built into the core.\n"
               "Here 0x0000_0000, the first word of the BootROM, so a cold reset\n"
               "always lands in the ROM and never in ISRAM."),
        (5.8, "DECERR  (decode error)  -  the AXI error the crossbar returns when\n"
              "no address rule matches, so a load can never silently alias onto\n"
              "another region or read back as ROM data."),
        (1.0, "ISRAM  -  instruction SRAM: 32 KB = 8192 words at 0x0001_0000,\n"
              "the crossbar rule [0] window. The bootloader writes it, then the\n"
              "core re-fetches from it once reset is released."),
    )
    for y, s in terms:
        fs.note(ax, GLOSS[0], y, GLOSS[2], 4.0, s, fs=7.2, kind="note",
                pad_x=1.2)


def finish(fig, ax):
    fs.footer(fig, FOOTER)
    fs.pad_limits(ax, 0.055)
    fig._qaname = "fig19_soc_boot_sequence"
    fs.qa_report(fig)
    fs.save(fig, "fig19_soc_boot_sequence.png")


def main():
    fig, ax = new_canvas()
    draw_step_frame(ax)
    draw_steps(ax)
    draw_inset(ax)
    draw_glossary(ax)
    finish(fig, ax)


if __name__ == "__main__":
    main()
