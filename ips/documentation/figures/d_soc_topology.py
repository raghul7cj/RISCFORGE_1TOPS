#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fig01_soc_topology  --  RISCFORGE 1TOPS SoC topology (left-to-right, 4 columns).

Every value below is taken from rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv :
  :233-248     AXI_ADDR/DATA_WIDTH=32, NUM_APB_SLAVES=6, BOOTROM_NUM_WORDS=16
  :419-439     NUM_SLV_PORTS=2 (core+bootloader), NUM_MST_PORTS=3, 3 xbar rules
  :463-470     APB_TIMEOUT_CYCLES per slot {16,16,16,16,65536,16}
  :476-477     AXI_TIMEOUT_SRAM=64, AXI_TIMEOUT_APB=131072
  :483-486     ISRAM/DSRAM_NUM_WORDS=8192 (32 KB), SRAM_ADDR_WIDTH=13
  :678-690     xbar_addr_map[0..2] and apb_addr_map[0..5]
  :706-726     boot_rom + instr_fetch_demux, RESET_PC=0x0000_0000
  :1205-1252   core ports; fast_irq_i[11:0] FLI map; timer_irq_i=MTIP, MEIP/MSIP=0
  :1262-1294   hybrid_mem_interface: DSRAM direct (mux port 0), MMIO over AXI-Lite
  :1310-1330   axi_lite_timeout_monitor on the core master port
  :1339-1372   bootloader = xbar SLV[1] and APB slot 4 passthrough to the SPI master
NOT in this RTL: no CLIC instance (APB slot 5 is a second timer) and no AON timer.
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

TITLE = ("One RV32 core, one SRAM pair, one crossbar, six APB peripherals — "
         "every address is decoded in exactly one place")
SUBTITLE = ("Read left to right:  ① core  →  ② crossbar + SRAM  →  "
            "③ APB bridge  →  ④ APB targets.   "
            "Red dashed = interrupt return.  Bottom band = the decode rule "
            "and the interrupt fan-in.")

FOOTER = ("Failure mode this prevents \u2014 a second decoder: one aperture owned by two "
          "blocks, so a hole silently aliases a live peripheral. The crossbar owns 3 rules, "
          "the APB bridge owns 6, everything else returns SLVERR.")

# ---------------------------------------------------------------- layout grid
C1X, C1W = 3.5, 29.5          # column 1: core + in-core interrupt capture
C2X, C2W = 41.0, 30.0         # column 2: crossbar (memories are 6 units narrower)
MEMX, MEMW = 41.0, 24.0       # memory column, leaves a right gutter for the drops
C3X, C3W = 78.0, 21.0         # column 3: AXI-Lite -> APB bridge
C4X, C4W = 104.0, 18.0        # column 4: the six APB targets in one tall block
KEY_W = (C4X + C4W) - C3X     # 44.0 : full-width band for the key below the bus
Y_BAND = 46.5                 # centre line of the interconnect band
Y_TOP = 53.0                  # top of the interconnect band
Y_IRQ = 57.2                  # top lane: interrupt return
X_CORE_R = C1X + C1W          # 33.0  core east edge
X_XBAR_W = C2X                # 41.0  crossbar west edge
X_XBAR_R = C2X + C2W          # 71.0  crossbar east edge
X_BOOT_X = 36.5               # boot-fetch corridor (inside the col1|col2 gap)
X_IRQ_RISER = 123.5          # IRQ riser, in the right margin clear of every box

# Reading order: four numbered column captions, one per column, same y.
COLS = ((C1X, C1W, "①  CORE"),
        (C2X, C2W, "②  CROSSBAR  +  SRAM"),
        (C3X, C3W, "③  APB BRIDGE"),
        (C4X, C4W, "④  APB TARGETS"))
Y_CAP, H_CAP = 53.8, 2.2      # caption strip sits above the blocks, under the IRQ lane


# ------------------------------------------------------- column 1: the core
def draw_core_column(ax):
    # The core is the subject of the title, so it is the only dark box on the
    # canvas and it is top-aligned with the interconnect band.
    fs.block(ax, C1X, 39.0, C1W, 14.0, "RISC-V core   RV32IM_Zicsr", kind="cpu",
             sub_fs=6.6,
             sub="imem_sram_en / addr / rdata -> instr_fetch_demux\n"
                 "lsu_mem_req/we/addr/wdata/be/rdata/stall/err\n"
                 "-> hybrid_mem_interface:\n"
                 "     DSRAM direct,  MMIO over AXI-Lite")

    # No CLIC exists in this SoC: the peripheral IRQ lines are flattened into
    # the core's own fast_irq_i[11:0] (fast interrupt line, FLI) and captured
    # by these two in-core blocks.
    fs.block(ax, C1X, 23.0, C1W, 9.0, "irq_gateway + irq_arbiter  (in-core)",
             kind="plain", ls="--", lw=1.0, sub_fs=6.6,
             sub="fast_irq_i[11:0] = FLI[0..11]\n"
                 "(FLI = fast interrupt line)\n"
                 "timer_irq_i = MTIP,  ext_irq_i / sw_irq_i = 0")

    fs.wire(ax, (18.25, 32.0), (18.25, 39.0), color=fs.GREY, lw=1.2,
            dashed=True, arrow=True)


# ------------------------------- column 2: interconnect + memory, column 3/4: APB
def draw_interconnect_and_peripherals(ax):
    fs.block(ax, C2X, Y_TOP - 13.0, C2W, 13.0, "axi_lite_xbar", kind="bus",
             sub_fs=6.9,
             sub="2 slave ports (slave [0] core, slave [1] bootloader)\n"
                 "x 3 master ports, 3 address rules — the only SRAM\n"
                 "decoder in the SoC:\n"
                 "  master 0   0x0001_0000   ISRAM\n"
                 "  master 1   0x0002_0000   DSRAM\n"
                 "  master 2   0x4000_0000   APB bridge (to 0x5000_0000)")


    fs.block(ax, MEMX, 30.5, MEMW, 8.5, "ISRAM   32 KB", kind="mem",
             sub="0x0001_0000 - 0x0001_7FFF")
    fs.block(ax, MEMX, 20.5, MEMW, 8.5, "DSRAM   32 KB", kind="mem",
             sub="0x0002_0000 - 0x0002_7FFF\n"
                 "core-direct + crossbar master 1")
    fs.block(ax, MEMX, 10.0, MEMW, 9.5, "BootROM   64 B", kind="mem",
             sub_fs=6.6,
             sub="0x0000_0000 - 0x0000_003F\n"
                 "core_instr_req / imem_sram_en ->\n"
                 "instr_fetch_demux -> boot_rom, 16 words\n"
                 "core-only, off the crossbar")

    # The IP exists in rtl/ips/aon_timer but this SoC never instantiates it, so
    # it gets one recessive line instead of a box of its own.
    fs.label(ax, MEMX, 8.4,
             "not in this SoC:  the AON (always-on) timer IP exists in "
             "rtl/ips/aon_timer but is not instantiated",
             fs=6.4, color=fs.GREY, ha="left")
    fs.label(ax, C4X + C4W, 8.4,
             "source: rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv",
             fs=6.4, color=fs.GREY, ha="right")

    fs.block(ax, C3X, Y_TOP - 13.0, C3W, 13.0, "axi_lite_to_apb", kind="bus",
             sub="AXI-Lite -> APB, 6 address rules\n"
                 "one access = one APB transfer\n"
                 "APB slot 4 = SPI, reached via bootloader\n"
                 "no match -> RESP_SLVERR")

    fs.note(ax, C4X, Y_TOP - 13.0, C4W, 13.0,
            "APB targets (6 rules)\n"
            "APB0 I2C    0x4000_0000\n"
            "APB1 Timer0  0x4000_1000\n"
            "APB2 UART    0x4000_2000\n"
            "APB3 GPIO    0x4000_3000\n"
            "APB4 SPI     0x4000_4000\n"
            "APB5 Timer1  0x4000_5000",
            fs=6.8, kind="periph", valign="top")


def draw_wires(ax):
    # MMIO path: core -> crossbar -> APB bridge -> APB targets
    fs.wire(ax, (X_CORE_R, Y_BAND), (X_XBAR_W, Y_BAND), color=fs.MID,
            label="AXI-Lite", label_fs=7.4)
    fs.wire(ax, (X_XBAR_R, Y_BAND), (C3X, Y_BAND), color=fs.MID,
            label="APB", label_fs=7.4)
    fs.wire(ax, (C3X + C3W, Y_BAND), (C4X, Y_BAND), color=fs.MID)

    # SRAM drops from the crossbar: master 0 straight down, master 1 down the
    # right-hand gutter of the memory column.
    fs.wire(ax, (53.0, Y_TOP - 13.0), (53.0, 39.0), color=fs.MID)
    fs.wire(ax, (69.0, Y_TOP - 13.0), (MEMX + MEMW, 24.75),
            via=[(69.0, 24.75)], color=fs.MID)

    # Fetch path: core -> instr_fetch_demux -> BootROM.  Grey, because this is
    # structure (it is off the crossbar), not a numbered step of a sequence.
    fs.wire(ax, (X_CORE_R, 38.0), (MEMX, 14.75),
            via=[(X_BOOT_X, 38.0), (X_BOOT_X, 14.75)], route="h",
            color=fs.GREY, lw=1.4)

    # Interrupt return: peripheral IRQ lines -> fast_irq_i[11:0].  It runs up the
    # right margin, across the top lane and back down the LEFT margin into the
    # core, so it never crosses the numbered column captions.  Thin on purpose:
    # this is a side path, the spine below it is the subject of the title.
    fs.wire(ax, (C4X + C4W, 49.0), (C1X, Y_BAND),
            via=[(X_IRQ_RISER, 49.0), (X_IRQ_RISER, Y_IRQ),
                 (1.0, Y_IRQ), (1.0, Y_BAND)],
            color=fs.RED, lw=1.25, dashed=True,
            label="peripheral IRQ lines  ->  fast_irq_i[11:0]  "
                  "(level-captured in-core)",
            label_at=(62.0, Y_IRQ), label_fs=7.0, label_color=fs.RED)


def draw_captions(ax):
    """Numbered column captions: the entry point and the reading order."""
    for cx, cwd, txt in COLS:
        fs.block(ax, cx, Y_CAP, cwd, H_CAP, txt, kind="plain", fs=7.4,
                 bold=True, tc=fs.ACCENT, box_alpha="#EDF3F9")


def draw_key_and_decode(ax):
    """Bottom evidence band: the decode rule on the left, its IRQ fan-in right."""
    fs.eqbox(ax, C1X, 0.5, 58.5, 7.0,
             "the only decode in the SoC\n"
             "hit = (addr >= start_addr) && (addr < end_addr)\n"
             "3 crossbar rules + 6 APB rules, exactly one hit\n"
             "no hit -> RESP_SLVERR / RESP_DECERR, never an alias\n"
             "GPIO is the odd one out: 2 KB, 0x4000_3000 - 0x4000_37FF",
             fs=7.0)

    # Where the 12 fast-interrupt lines actually come from (riscforge:1236-1251)
    fs.block(ax, 65.0, 0.5, 57.0, 7.0,
             "Interrupt fan-in  —  no CLIC (CLIC = common local interrupt "
             "controller) exists in this SoC", kind="plain", ls="--", lw=1.0,
             fs=7.0,
             sub="FLI[11] SPI EOT  FLI[10..7] Timer 1  FLI[6..4] Timer 0\n"
                 "FLI[3] UART  FLI[2] SPI  FLI[1] I2C  FLI[0] GPIO")


def new_canvas():
    fig, ax = fs.slide(TITLE, SUBTITLE)
    X, Y = fs.canvas(ax)
    assert X > 123.0, "slide canvas too narrow for the 4-column band: %.1f" % X
    return fig, ax


def finish(fig, ax):
    fs.footer(fig, FOOTER)
    fs.pad_limits(ax, 0.055)
    fig._qaname = "fig01_soc_topology"
    fs.qa_report(fig)
    fs.save(fig, "fig01_soc_topology.png")


def main():
    fig, ax = new_canvas()
    draw_captions(ax)
    draw_core_column(ax)
    draw_interconnect_and_peripherals(ax)
    draw_wires(ax)
    draw_key_and_decode(ax)
    finish(fig, ax)


if __name__ == "__main__":
    main()