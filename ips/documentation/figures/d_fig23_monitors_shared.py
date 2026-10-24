"""fig23 -- what the AXI-Lite and APB timeout monitors SHARE.

Split out of d_monitors.py (fig05), the shared bottom band -- promoted to a
figure of its own, because it is what earns the parent figure its title.
Content is unchanged: golden rule, saturation rule, both thresholds, both
escalation chains.  fig21 = the AXI-Lite monitor, fig22 = the APB monitor.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

# ------------------------------------------------------------------ real RTL
TC_APB, CNT_APB = 16, 4
TC_AXI_APB, TC_AXI_DEF, CNT_AXI = 131072, 64, 17
APB_BASE, APB_END = "0x4000_0000", "0x5000_0000"

fig, ax = fs.slide(
    "Both monitors reset on progress and saturate rather than wrap, and both "
    "end in the same place: a core bus error with mcause = 5 or 7",
    "the contract both monitors obey \u2014 axi_lite_timeout_monitor.sv "
    "(fig21) and apb_timeout_monitor.sv (fig22): two rules, the golden "
    "rule in action, the two thresholds, and the single destination",
)
XW, YH = fs.canvas(ax)


def head(y, n, txt, right=False):
    """numbered panel header with a badge, the way the improved parents do."""
    if right:
        fs.badge(ax, 121.2, y, n, r=1.05, fs=7.0)
        fs.label(ax, 117.4, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="right")
    else:
        fs.badge(ax, 3.6, y, n, r=1.05, fs=7.0)
        fs.label(ax, 6.2, y, txt, fs=8.0, color=fs.ACCENT, weight="bold",
                 ha="left")


# ------------------------------------------------------------- reading order
fs.label(ax, 2.5, 57.2,
         "START HERE \u2193   read TOP to BOTTOM:   1 THE TWO RULES   \u2192   "
         "2 THE GOLDEN RULE IN ACTION   \u2192   3 THE TWO THRESHOLDS   "
         "\u2192   4 THE ONE DESTINATION",
         fs=7.4, color=fs.ACCENT, weight="bold", ha="left")

# ---------------------------------------------------- 1  the two rules, large
head(54.2, 1, "THE TWO RULES \u2014 neither monitor has any other trick")
R1 = fs.block(ax, 2.5, 44.0, 58.0, 9.4, "GOLDEN RULE \u2014 RESET ON PROGRESS",
              kind="resp", fs=8.2,
              sub="the counter clears the moment a handshake happens, so a "
                  "legitimately slow slave that keeps\nadvancing is never "
                  "killed \u2014 16 APB cycles of PREADY low in a row is a "
                  "stall, but a thousand wait-states\npunctuated by a PREADY "
                  "each time round is normal service", sub_fs=6.8)
R2 = fs.block(ax, 65.5, 44.0, 57.0, 9.4,
              "SATURATION RULE \u2014 SATURATE, NEVER WRAP",
              kind="write", fs=8.2,
              sub="both counters hold at their threshold (15 and 131071) "
                  "instead of wrapping to zero, so the verdict can never be a\n"
                  "wrap artefact \u2014 and timeout_sticky_o preserves it after "
                  "the bus has already moved on", sub_fs=6.8)

# ------------------------------------ 2  the golden rule, in action (traces)
head(41.6, 2, "THE GOLDEN RULE IN ACTION \u2014 same monitor, two slaves")
UX, UU, NC = 12.0, 4.6, 8
fs.cycle_guides(ax, UX, NC, UU, bottom=26.0, top=40.2)
fs.label(ax, 10.5, 38.4, "STALLED slave", fs=7.2, color=fs.TXT, weight="bold",
         ha="right", va="bottom")
fs.label(ax, 10.5, 37.6, "PREADY stays low", fs=6.6, color=fs.GREY, ha="right",
         va="top")
fs.sigwave(ax, UX, [0] * NC, UU, 37.6, 39.4, color=fs.RED)
fs.bus_cells(ax, UX, [1, 2, 3, 4, 5, 6, 7, 8], UU, 34.8, 2.8, fill=fs.S_ALARM,
             ec=fs.RED, color="#7F1010", fs=6.8)
fs.label(ax, 10.5, 34.8, "cnt_q", fs=7.0, color=fs.GREY, weight="bold",
         ha="right")
fs.chip(ax, 50.4, 33.9, "cnt_q climbs \u2192 15 \u2192 fire", fc="#FFFFFF",
        ec=fs.RED, tc=fs.RED, fs=6.6)

fs.wire(ax, (2.5, 33.0), (60.5, 33.0), color="#C8C8C8", lw=0.8, arrow=False,
        dashed=(0, (2, 3)))

fs.label(ax, 10.5, 31.4, "SLOW slave", fs=7.2, color=fs.TXT, weight="bold",
         ha="right", va="bottom")
fs.label(ax, 10.5, 30.6, "PREADY low 3, high 1", fs=6.6, color=fs.GREY,
         ha="right", va="top")
fs.sigwave(ax, UX, [0, 0, 0, 1, 0, 0, 0, 1], UU, 30.4, 32.2, color=fs.GREEN)
fs.bus_cells(ax, UX, [1, 2, 3, 0, 1, 2, 3, 0], UU, 27.6, 2.8, fill=fs.S_RESP,
             ec="#548235", color="#1E4D19", fs=6.8)
fs.label(ax, 10.5, 27.6, "cnt_q", fs=7.0, color=fs.GREY, weight="bold",
         ha="right")
fs.chip(ax, 50.4, 26.7, "counter keeps resetting \u2192 never fires",
        fc="#FFFFFF", ec=fs.GREEN, tc=fs.GREEN, fs=6.6)

# ------------------------------------------- 3  the two thresholds, one table
head(41.6, 3, "THE TWO THRESHOLDS", right=True)
fs.eqbox(ax, 65.5, 26.4, 57.0, 13.6,
         "THE ONLY THING THE ADDRESS CHANGES\n"
         f"APB SLOT  (fig22) \u2014 bounded per ACCESS\n"
         f"     timeout = TimeoutCycles = {TC_APB},   "
         f"CntWidth = $clog2({TC_APB}) = {CNT_APB} bit\n"
         f"     expired = (cnt_q == {TC_APB - 1})  \u2192  {TC_APB} idle cycles\n"
         f"AXI-LITE  (fig21) \u2014 bounded per TRANSACTION\n"
         f"     thresh_m1 = apb ? {TC_AXI_APB - 1} : {TC_AXI_DEF - 1},   "
         f"CntWidth = {CNT_AXI} bit\n"
         f"     addr in {APB_BASE} \u2026 {APB_END}  \u2192  {TC_AXI_APB} "
         f"idle cycles,  any other address  \u2192  {TC_AXI_DEF}",
         fs=6.5)

# ---------------------------------------- 4  both chains, one destination
head(21.0, 4, "THE ONE DESTINATION \u2014 SLVERR / PSLVERR are the AXI-Lite "
              "and APB slave-error codes")


def chain(y, head_txt, names, f=6.8, x0=20.0, gap=1.6):
    """one horizontal escalation chain, each step its own chip."""
    fs.label(ax, 2.5, y + 1.4, head_txt, fs=6.9, color=fs.GREY, weight="bold",
             ha="left")
    x, prev = x0, None
    for n in names:
        cx, cy, w, h = fs.chip(ax, x, y, n, fc=fs.S_ALARM, ec=fs.RED,
                               tc="#7F1010", fs=f, padx=0.55)
        if prev is not None:
            fs.wire(ax, (prev, y), (cx, y), color=fs.RED, lw=1.4)
        prev, x = cx + w, cx + w + gap
    return prev


apb_end = chain(13.4, "APB side  (fig22)",
                ["fire \u2192 PSLVERR = 1", "RESP_SLVERR", "core bus error"])
axi_end = chain(6.4, "AXI-Lite side  (fig21)",
                ["wr_fire \u2192 SLVERR", "core bus error"])
fs.wire(ax, (2.5, 11.0), (80.0, 11.0), color="#C8C8C8", lw=0.8, arrow=False,
        dashed=(0, (2, 3)))

dest = fs.block(ax, 84.0, 1.2, 38.5, 17.4, "WHAT SOFTWARE SEES", kind="alarm",
                fs=8.6, sub="a core bus error trap\n"
                           "mcause = 5   load access fault\n"
                           "mcause = 7   store / AMO access fault\n"
                           "timeout_sticky_o keeps the evidence after the "
                           "bus has moved on", sub_fs=6.8)
fs.wire(ax, (apb_end, 14.8), (dest["w"][0], 14.8), color=fs.RED, lw=1.6)
fs.wire(ax, (axi_end, 7.8), (dest["w"][0], 7.8), color=fs.RED, lw=1.6)

fs.footer(fig, "Together these four panels are the whole contract: count idle "
               "cycles, clear the count on every handshake, stop at the "
               "threshold instead of wrapping, and hand the failure to "
               "software as a bus error \u2014 which is the only reason either "
               "monitor exists.")
fs.pad_limits(ax, 0.02)
fs.qa_report(fig)
fs.save(fig, "fig23_monitor_escalation.png")