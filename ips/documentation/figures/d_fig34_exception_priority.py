# d_fig34_exception_priority.py -> fig34_exception_priority.png (+ .svg)
# Split of fig18 (d_trap_fsm.py) section C: the exception-priority chain.
# RTL: riscv_core/rtl/execute_cycle.v + riscv_core/rtl/wb_trap_mret_commit_controller.v
#      riscv_core/rtl/csr_regfile.v  (mtval suppression, one clause only)
# PARENT d_trap_fsm.py IS FROZEN - this file only copies from it.
import os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

TITLE = ("A synchronous exception always outranks an interrupt, "
         "and mret deliberately loses to both")
SUB = ("Two exception sources can present in the same cycle and they do not compare "
       "like for like \u2014 read 1 the three contenders  \u2192  2 the first-match ladder  "
       "\u2192  3 why there is no priority encoder  \u2192  4 mret loses  "
       "\u2192  5 interrupt is a sub-mode of trap")

# ---------------------------------------------------------------- lane budget
BUDGET = [
    ("T0", "49.0 - 59.1", "title + subtitle + rule (fs.slide, automatic)"),
    ("O",  "48.0 - 50.6", "reading-order strip: START HERE + 1..5"),
    ("H",  "47.4 - 48.0", "three column headers"),
    ("L",  "26.2 - 46.2", "LADDER: 4 contender rows (h=4.4, gap 0.8), top = highest priority"),
    ("P",  " 7.8 - 25.0", "three panels: 3 no encoder | 4 mret loses | 5 sub-mode"),
    ("G",  " 2.2 -  6.8", "glossary strip"),
    ("F",  " 0.5 -  2.2", "footer (fs.footer)"),
]

# ---------------------------------------------------------------- geometry
RH = 4.4                       # contender row height
AX, AW = 4.0, 30.0             # contender block column
MUXX, MUXW = 44.0, 26.0        # priority-mux column
OUTX, OUTW = 72.5, 23.5        # winner column
PRVX = 100.0                   # provenance column
C1, C2, C3, C4 = 44.0, 38.8, 33.6, 28.4   # contender row centres (top = best)
SPAN = (31.4, 14.8)            # mux / winner vertical span (rows 1..3)

# contender: (n, y, signal, kind, sub, provenance)
ROW = [
    (1, C1, "new_exc_valid_E", "alarm",
     "instruction-address-misaligned  \u00b7  mcause code 0\n"
     "branch_taken_raw & target_misaligned_E  \u00b7  bit[5]=0, synchronous",
     "execute_cycle.v : 480"),
    (2, C2, "exc_valid_E", "ctrl",
     "illegal instruction (2)  \u00b7  instruction-fetch fault (1)\n"
     "raised in ID/IF, carried into EX  \u00b7  bit[5]=0, synchronous",
     "raised in ID/IF, held in EX\n(decode_cycle.v / fetch_cycle.v)"),
    (3, C3, "irq_accept_E", "bus",
     "machine interrupt  \u00b7  mcause = {1'b1, irq_id_i[4:0]} = 64+id\n"
     "bit[5]=1, asynchronous  \u00b7  gated by ~new_exc_valid_E & ~exc_valid_E",
     "execute_cycle.v : 459"),
    (4, C4, "is_mret_W", "mux",
     "MRET \u2014 a contender for the same writeback slot,\n"
     "but NOT an exception source  \u00b7  never enters the ladder",
     "wb_trap_mret_commit_\ncontroller.v : 65"),
]


def fit(ax, lines, w, f0=6.8, floor=5.0):
    """Shrink font until the widest line fits the box."""
    f = f0
    while f > floor and max(fs.text_w(ax, l, fs=f, weight="bold")
                            for l in lines) > w - 1.6:
        f -= 0.2
    return f


ORDER = ("START HERE  \u25ba  badge 1, top left  \u00b7  read DOWN the ladder 1 \u2192 2 \u2192 3, "
         "then RIGHT along 2, then DOWN to panels 3, 4, 5  \u00b7  RTL: execute_cycle.v "
         "+ wb_trap_mret_commit_controller.v")


def draw_order(ax):
    """The only thing on the canvas above the ladder: how to enter and read it."""
    fs.note(ax, 1.0, 48.0, 123.3, 2.6, ORDER, fs=6.6, kind="req", weight="bold")
    for x, t in ((AX, "1 \u00b7 CONTENDERS  \u2014  up to three in the same cycle"),
                 (MUXX, "2 \u00b7 THE LADDER"),
                 (PRVX, "VERIFIED WHERE")):
        fs.label(ax, x, 47.2, t, fs=6.6, color=fs.ACCENT, weight="bold",
                 ha="left", va="center")


def draw_rows(ax):
    """The four contender blocks, top row = highest priority, plus provenance."""
    for n, y, sig, kind, sub, prov in ROW:
        f = fit(ax, [sig] + sub.split("\n"), AW, f0=7.6)
        fs.block(ax, AX, y - RH / 2, AW, RH, sig, kind=kind, sub=sub, fs=f,
                 sub_fs=min(f - 1.1, 6.3))
        fs.badge(ax, AX + 1.6, y + RH / 2 - 0.75, n,
                 fc=fs.GREY if n == 4 else fs.ACCENT)
        fs.note(ax, PRVX, y - 1.35, 26.0, 2.7, prov, fs=5.9, kind="plain",
                pad_x=0.6, pad_y=0.2)


MUX_TXT = ("PRIORITY MUX  \u2014  first match wins, top row first\n"
           "next_exc_valid_E =\n"
           "    new_exc_valid_E | exc_valid_E | irq_accept_E\n"
           "next_exc_cause_E =\n"
           "    new_exc_valid_E ? new_exc_cause_E :\n"
           "    exc_valid_E     ? exc_cause_E     :\n"
           "    irq_accept_E    ? {1'b1, irq_id_i[4:0]} : 6'd0")

OUT_TXT = ("WINNER\n"
           "next_exc_cause_E \u2014\n"
           "one packet out of the\n"
           "ladder, carried to WB.\n"
           "next_exc_tval_E and\n"
           "next_exc_pc_E ride the\n"
           "same three-way choice.")


def draw_ladder(ax):
    """Rows 1-3 feed the mux; the mux feeds a single winner. Row 4 is blocked."""
    my, mh = SPAN
    f = fit(ax, MUX_TXT.split("\n"), MUXW, f0=6.0, floor=4.8)
    fs.block(ax, MUXX, my, MUXW, mh, MUX_TXT, kind="cpu", fs=f)
    for n, y, _s, _k, _sub, _p in ROW[:3]:
        fs.wire(ax, (AX + AW, y), (MUXX, y), color=fs.MID, lw=1.5)
    fs.block(ax, OUTX, my, OUTW, mh, OUT_TXT, kind="ctrl", fs=6.0)
    fs.wire(ax, (MUXX + MUXW, my + mh / 2), (OUTX, my + mh / 2), color=fs.MID,
            lw=1.5)
    # row 4: MRET is routed to the mux and stopped dead by ~exc_valid_W
    fs.wire(ax, (AX + AW, C4), (49.0, C4), via=[(49.0, my)],
            color=fs.RED, lw=1.5, dashed=True)
    fs.onwire(ax, 49.0, (C4 + my) / 2, "blocked", fs=6.2, color=fs.RED,
              ec=fs.RED)
    fs.note(ax, 60.0, C4 - 1.7, 63.0, 3.4,
            "MRET does not raise an exception, so it has no cause code and no "
            "ladder entry.\nIt wants the same writeback slot \u2014 and is gated "
            "off: see panel 4.", fs=6.2, kind="alarm")


# ------------------------------------------------------------------ panels 3-5
PY, PH = 7.8, 17.2
PW, PX = 40.0, (1.0, 42.5, 84.0)
IN_X = 1.2                                  # inner left pad
TITLE_Y, EQ_Y, EQ_H = 23.4, 19.0, 3.2
BODY_Y, CONC_Y, SRC_Y = 18.4, 13.8, 8.8

P3 = dict(
    head="3 \u00b7 NO PRIORITY ENCODER",
    eq="irq_accept_E = valid_E & irq_pending_i\n"
       "               & ~new_exc_valid_E & ~exc_valid_E",
    eqc=(fs.S_ALARM, fs.RED, "#7F1010"),
    body=["No numeric compare on exc_cause exists anywhere in the commit",
          "controller \u2014 it only ANDs and ORs one-hot event signals, so the",
          "priority is set one stage earlier, in EX, by mux order:"],
    conc=["The two ~ terms ARE the RISC-V rule: an instruction that faults",
          "can never also accept an interrupt. The order lives in the wiring",
          "\u2014 there is no encoder, and no tie-break to reason about."],
    src="execute_cycle.v : 459, 466-478")

P4 = dict(
    head="4 \u00b7 MRET DELIBERATELY LOSES",
    eq="mret_commit = valid_W & is_mret_W\n                & ~exc_valid_W",
    eqc=(fs.S_WRITE, fs.ORANGE, "#7F3F00"),
    body=["The ~exc_valid_W term is the demotion. If the MRET instruction",
          "itself faults, trap_commit takes the writeback slot instead, and",
          "flush_pipeline_onehot_o = 4'b1111 squashes the pipeline:"],
    conc=["wb_trap_redirect_o still asserts (trap_commit | mret_commit), so the",
          "MRET never retires. And because mepc is the faulting instruction's",
          "PC, the handler re-runs the MRET rather than stepping past it."],
    src="wb_trap_mret_commit_controller.v : 64, 65, 67")

P5 = dict(
    head="5 \u00b7 INTERRUPT IS A SUB-MODE, NOT A PEER",
    eq="trap_is_interrupt_o = exc_cause_W[5] & exc_valid_W\n"
       "trap_addr_valid_o   = trap_commit & ~exc_cause_W[5]",
    eqc=(fs.S_REQ, fs.MID, fs.ACCENT),
    body=["Both outputs are functions of the same 6-bit exc_cause_W: bit[5]",
          "is the interrupt flag, bits[4:0] the code. There is only one kind",
          "of trap event, and bit[5] says which flavour it is:"],
    conc=["Consequence: mtval is meaningless for an interrupt, so it is",
          "suppressed \u2014 trap_addr_valid_o = 0 and csr_regfile.v writes",
          "mtval <= 32'h0 in the same cycle the other CSRs are written."],
    src="wb_trap_mret_commit_controller.v : 71, 76\ncsr_regfile.v : 168")


def draw_panels(ax):
    for i, P in enumerate((P3, P4, P5)):
        x = PX[i]
        fs.note(ax, x, PY, PW, PH, "", kind="plain")
        fs.badge(ax, x + IN_X + 1.4, TITLE_Y, i + 3)
        fs.label(ax, x + IN_X + 3.6, TITLE_Y, P["head"], fs=7.0, color=fs.ACCENT,
                 weight="bold", ha="left")
        fs.eqbox(ax, x + IN_X, EQ_Y, PW - 2 * IN_X, EQ_H, P["eq"], fs=6.0,
                 fc=P["eqc"][0], ec=P["eqc"][1], color=P["eqc"][2])
        fs.label(ax, x + IN_X + 0.2, BODY_Y, "\n".join(P["body"]), fs=5.9,
                 color=fs.TXT, ha="left", va="top")
        fs.label(ax, x + IN_X + 0.2, CONC_Y, "\n".join(P["conc"]), fs=5.9,
                 color=fs.GREY, ha="left", va="top")
        fs.label(ax, x + IN_X + 0.2, SRC_Y, P["src"], fs=5.5, color=fs.MID,
                 ha="left", weight="bold")


GLOSS = (
    "GLOSSARY   \u00b7   exc_cause_W  [5:0]  bit[5] = interrupt flag, bits[4:0] = code "
    "(0 instr-addr-misaligned, 1 ifetch fault, 2 illegal instruction,\n"
    "64+id machine interrupt).   new_exc_valid_E / exc_valid_E / irq_accept_E  \u2014  the "
    "three one-hot contenders of the ladder, all resolved in EX.\n"
    "trap_commit / mret_commit  \u2014  the two writeback events; WB = writeback, the last "
    "pipeline stage.   flush_pipeline_onehot_o  [3:0]  squash of IF/ID/EX/MEM.")


def draw_glossary(ax):
    fs.note(ax, 1.0, 2.0, 123.3, 5.0, GLOSS, fs=5.9, kind="note", pad_x=1.2,
            pad_y=0.7)


def main():
    fig, ax = fs.slide(TITLE, SUB)
    X, Y = fs.canvas(ax)
    print("canvas = %.2f x %.2f units" % (X, Y))
    print("--- LANE BUDGET (%d bands) ---" % len(BUDGET))
    for tag, yy, what in BUDGET:
        print("  %-3s y=%-13s %s" % (tag, yy, what))
    draw_order(ax)
    draw_rows(ax)
    draw_ladder(ax)
    draw_panels(ax)
    draw_glossary(ax)
    fs.footer(fig, "Priority here is structural, not numeric. The RTL never compares "
                   "cause codes: it wires a fixed first-match chain, so a synchronous "
                   "exception outranks an interrupt by construction, and MRET is gated "
                   "off by ~exc_valid_W whenever the same instruction also faults.")
    fs.pad_limits(ax, 0.06)
    fig._qaname = "fig34_exception_priority.png"
    fs.qa_report(fig)
    fs.save(fig, "fig34_exception_priority.png")


if __name__ == "__main__":
    main()