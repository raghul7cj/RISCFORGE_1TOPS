# d_trap_fsm.py -> fig18_trap_mret_fsm.png (+ .svg)
# RV32 trap / mret commit controller: FSM, priority, CSR bundle, flush waveform.
# RTL: riscv_core/rtl/wb_trap_mret_commit_controller.sv  +  riscv_core/rtl/top.v
import os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs

TITLE = ("A trap is a state machine, not an exception \u2014 cause, tval and PC latch "
         "together in writeback, so the handler never sees a half-updated context")
SUB = ("read A the trap decision, left to right  \u2192  B where the PC lands  "
       "\u2192  C when two exceptions collide  \u2192  D what lands in the CSRs  "
       "\u2192  E the same trap on a timeline")

# ---------------------------------------------------------------- lane budget
BUDGET = [
    ("T0", "50.0 - 59.1", "title + subtitle + rule (fs.slide, automatic)"),
    ("R1", "49.3", "perimeter return: trap_target_o -> fetch_cycle PC (top.v:301)"),
    ("M",  "44.0 (h=6)", "MAIN CHAIN 4 states, x=18..106, y=41..47"),
    ("E1", "39.5", "mret_commit return lane (back=True) -> re-enters box 3 from below"),
    ("B1", "34.0", "branch lane: trap_is_interrupt_o=1  -> clear_gateway one-hot"),
    ("B2", "28.5", "branch lane: trap_is_interrupt_o=0  -> mtval valid"),
    ("B3", "23.0", "branch lane: normal commit -> retire side-effects, no flush"),
    ("LC", "21.0 - 38.5", "LEFT col x=1.5..16: fetch-PC block + 2 fs.note callouts"),
    ("SK", "per-lane", "RIGHT sink column x=104..123: per-lane result blocks"),
    ("P",  " 2.5 - 17.0", "lower band: waveform | eqboxes | priority table | CSR bundle"),
    ("F",  " 0.5 -  2.2", "footer (fs.footer)"),
]

# ---------------------------------------------------------------- geometry
MY, MH = 44.5, 6.0            # main chain row: y = 41.5 .. 47.5
R1 = 49.8                     # perimeter return lane (over the top)
E1, B1, B2, B3 = 40.0, 34.6, 29.0, 23.4
BH = 4.0                      # branch box height
SINKX, SINKW = 104.0, 19.0    # right-hand result column
CHAIN = [
    (18.0, 16.0, "mux", "WB_IDLE", "valid_W = 0 \u00b7 bubble", 1),
    (38.0, 20.0, "alarm", "trap_commit", "valid_W & exc_valid_W", 2),
    (62.0, 20.0, "write", "wb_trap_redirect_o", "trap_commit | mret_commit", 3),
    (86.0, 20.0, "write", "flush_pipeline_onehot_o", "= 4'b1111 \u00b7 IF/ID/EX/MEM", 4),
]


def fit(ax, lines, w, h, f0=7.2, floor=4.6):
    """Shrink font until the widest line fits the box."""
    fs_ = f0
    while fs_ > floor and max(fs.text_w(ax, l, fs=fs_, weight="bold") for l in lines) > w - 1.4:
        fs_ -= 0.2
    return fs_


def draw_chain(ax):
    for x, w, kind, name, sub, n in CHAIN:
        f = fit(ax, [name, sub], w, MH)
        fs.block(ax, x, MY - MH / 2, w, MH, name, kind=kind, sub=sub, fs=f)
        fs.badge(ax, x + 1.4, MY + MH / 2 - 0.7, n)
    for i in range(len(CHAIN) - 1):
        a, b = CHAIN[i][0] + CHAIN[i][1], CHAIN[i + 1][0]
        fs.wire(ax, (a, MY), (b, MY), color=fs.MID, lw=1.5)


def draw_lanes(ax):
    """Rectangular route on its own lane + labelled result block in the sink column."""
    def lane(xs, y_edge, y_run, txt, sink, kind, color, n, back=False):
        fs.wire(ax, (xs, y_edge), (SINKX, y_run), via=[(xs, y_run)],
                color=color, lw=1.5, back=back)
        # badge sits just left of the lane elbow, clear of the wire itself: a
        # 3-line sink body reaches into its top-left corner and the badge
        # would clip the first character of the block text
        fs.badge(ax, xs - 1.9, y_run, n, fc=color)
        fs.onwire(ax, (xs + SINKX) / 2, y_run, txt, fs=6.3, color=color,
                  ec=color)
        f = fit(ax, sink, SINKW, BH, f0=6.2)
        fs.block(ax, SINKX, y_run - BH / 2, SINKW, BH, "\n".join(sink), kind=kind, fs=f)

    # E1: mret_commit returns into wb_trap_redirect_o (feedback, hollow head)
    # riser at x=30 (not 26) so it does not overdraw the B3 lane drop at x=26
    fs.wire(ax, (30.0, MY - MH / 2), (72.0, MY - MH / 2),
            via=[(30.0, E1), (72.0, E1)], color=fs.GREEN, lw=1.6, back=True)
    fs.onwire(ax, 49.0, E1, "mret_commit  =  valid_W & is_mret_W & ~exc_valid_W", fs=6.4,
              color=fs.GREEN, ec=fs.GREEN)
    # B1..B3: the three terminal outcomes, each with its own lane and sink block
    lane(42.0, MY - MH / 2, B1,
         "exc_cause_W[5] = 1  \u2192  trap_is_interrupt_o",
         ["clear_gateway_r[5:0]", "one-hot: 27,7,19,18,17,16", "wb_commit_irq_o pulse"],
         "cpu", fs.ACCENT, 5)
    lane(54.0, MY - MH / 2, B2,
         "exc_cause_W[5] = 0  \u2192  trap_addr_valid_o",
         ["mcause = {25'b0, cause[4:0]}", "mepc = exc_pc_W", "mtval = exc_tval_W"],
         "write", fs.ORANGE, 6)
    lane(26.0, MY - MH / 2, B3,
         "~exc_valid_W & ~is_mret_W  \u2192  retire",
         ["RegWriteW_gated = 1", "csr_write_en_W_gated = 1", "no flush, no redirect"],
         "mux", fs.MID, 7)


# ------------------------------------------------- R1 perimeter + left column
def draw_redirect(ax):
    fs.wire(ax, (72.0, MY + MH / 2), (8.75, 49.0),
            via=[(72.0, R1), (8.75, R1)], color=fs.ACCENT, lw=1.6)
    fs.onwire(ax, 45.0, R1,
              "trap_target_o  =  {mtvec_i[31:2], 2'b00}  |  {mepc_i[31:2], 2'b00}",
              fs=6.5, color=fs.ACCENT, ec=fs.ACCENT)
    fs.block(ax, 1.5, 44.0, 14.5, 5.0, "fetch_cycle PC", kind="bus",
             sub="top.v:301 \u00b7 beats PCSrcE", fs=6.8)


def draw_notes(ax):
    fs.note(ax, 1.0, 31.3, 12.5, 11.4,
            "A wrong mepc\nloops forever\n\nmepc = exc_pc_W, the\nfaulting instruction,\nnot the next one. One\nword too high re-traps\nat the same PC and\nmret is never reached.", fs=6.1)
    fs.note(ax, 1.0, 19.6, 12.5, 11.4,
            "Interrupt vs\nexception\n\nirq_accept_E is gated\nby ~new_exc_valid_E &\n~exc_valid_E, so a\nfaulting instruction\ncan never also take\nan interrupt.", fs=6.1)


# ------------------------------------------------------- explicit reading order
def draw_sections(ax):
    """The letters named in the subtitle. Every region on the canvas is claimed
    by exactly one letter, so a newcomer can enter at A and stop at any band."""
    fs.label(ax, 1.5, 51.9, "A  \u00b7  THE TRAP DECISION \u2014 one writeback cycle, "
             "three possible outcomes", fs=7.4, color=fs.ACCENT, weight="bold",
             ha="left", va="center")
    for x, t in ((52.0, "B  \u00b7 where the PC lands"),
                 (73.0, "C  \u00b7 when two exceptions collide"),
                 (97.0, "D  \u00b7 what lands in the CSRs"),
                 (1.0, "E  \u00b7 timeline")):
        fs.label(ax, x, 18.6, t, fs=6.6, color=fs.ACCENT, weight="bold",
                 ha="left", va="center")


# ------------------------------------------------------------------ L4 panels
P_TOP, P_BOT = 17.8, 3.8      # lower band
PRI = [("1", "new_exc_valid_E", "inst misalign  c=0", 0),
       ("2", "exc_valid_E", "illegal 2 / ifetch 1", 1),
       ("3", "irq_accept_E", "machine int. 64+cause", 2),
       ("\u2014", "is_mret_W", "MRET (loses to exc.)", 3)]


def draw_priority(ax):
    x0, w, rh = 73.0, 22.0, 1.60
    fs.chip(ax, x0 + w / 2, P_TOP - 0.85, "exception priority \u2014 highest first")
    rows = [("#", "RTL signal", "mcause code", 6.3)] + [list(r) for r in PRI]
    y = P_TOP - 2.05
    for i, (a, b, c, _z) in enumerate(rows):
        bg = "#FFFFFF" if i == 0 else (fs.S_ALARM if i == 4 else
                                      ("#EDF1F7" if i % 2 else "#DCE4EF"))
        ax.add_patch(fs.Rectangle((x0, y - rh), w, rh, facecolor=bg,
                                  edgecolor=fs.MID, lw=0.6, zorder=3))
        fs.label(ax, x0 + 1.0, y - rh / 2, a, fs=6.3, weight="bold", ha="left",
                 color=fs.GREY if i == 0 else fs.ACCENT)
        fs.label(ax, x0 + 3.2, y - rh / 2, b, fs=6.1, ha="left",
                 color=fs.GREY if i == 0 else fs.TXT,
                 weight="normal" if i == 0 else "bold")
        fs.label(ax, x0 + w - 0.8, y - rh / 2, c, fs=6.1, ha="right", color=fs.GREY)
        y -= rh
    fs.label(ax, x0, y - 1.0, "MATCHES spec: sync exc > interrupt",
             fs=6.2, color=fs.GREEN, weight="bold", ha="left")
    fs.label(ax, x0, y - 2.4, "DIFFERS: 2-level chain, no compare",
             fs=6.2, color=fs.RED, weight="bold", ha="left")


# CSR register / field positions exactly as the RTL states them
CSR_A = [("mcause  0x342", "= {int_i, cause[4:0]}", "\u2014"),
         ("mepc    0x341", "= exc_pc_W", "{mepc[31:2],2'b00}"),
         ("mtval   0x343", "= exc_tval_W", "\u2014")]
CSR_B = [("[3]  MIE", "1", "0", "MPIE_old"),
         ("[7]  MPIE", "0", "MIE_old", "1"),
         ("[12:11]  MPP", "2'b11", "2'b11", "2'b11")]
RH = 1.42


def _row(ax, x0, w, y, cells, f=6.0, bg="#FFFFFF", fg=None, bold=False, colw=None):
    ax.add_patch(fs.Rectangle((x0, y - RH), w, RH, facecolor=bg,
                              edgecolor=fs.MID, lw=0.55, zorder=3))
    xx = x0
    for c, cw in zip(cells, colw):
        fs.label(ax, xx + 0.5, y - RH / 2, c, fs=f, ha="left",
                 color=(fg or fs.TXT), weight="bold" if bold else "normal")
        xx += cw


def draw_csr(ax):
    x0, w = 97.0, 26.0
    fs.chip(ax, x0 + w / 2, P_TOP - 0.85, "CSR bundle \u2014 one cycle")
    cwa, cwb = [6.9, 9.8, 8.8], [6.4, 5.0, 6.8, 7.8]
    y = P_TOP - 2.05
    _row(ax, x0, w, y, ["CSR / field", "trap ENTRY (port A)", "MRET (port C)"],
         5.5, bg=fs.S_ADDR, fg="#7F6000", bold=True, colw=cwa)
    y -= RH
    for i, (a, b, c) in enumerate(CSR_A):
        _row(ax, x0, w, y, [a, b, c], 5.9, "#FFFFFF" if i % 2 else "#F2F5FA", colw=cwa)
        y -= RH
    y -= 0.45
    fs.label(ax, x0 + 0.5, y - 0.5, "mstatus 0x300 \u2014 the only bundle PORT C writes",
             fs=6.0, weight="bold", ha="left", color=fs.ACCENT)
    y -= 1.05
    _row(ax, x0, w, y, ["field", "before", "trap ENTRY", "on MRET"], 6.0,
         bg=fs.S_RESP, fg="#1F6B3A", bold=True, colw=cwb)
    y -= RH
    for i, r in enumerate(CSR_B):
        _row(ax, x0, w, y, list(r), 5.9, "#FFFFFF" if i % 2 else "#F1F8F3", colw=cwb)
        y -= RH
    fs.label(ax, x0, y - 0.75, "PORT C writes 0x300 only \u00b7 one port per event",
             fs=6.0, color=fs.GREY, weight="bold", ha="left")


# ------------------------------------------------------------------ L5 timing
WX0, WU, WN, WG = 17.0, 3.6, 9, 3.05    # 9 cycles; lanes land at WG,2WG..5WG
WROW = [("v", "valid_W", None),
        ("e", "exc_valid_W", None),
        ("r", "wb_trap_redirect_o", None),
        ("f", "flush_pipeline", None),
        ("p", "PC", None)]
LV = [1, 1, 0, 1, 1, 1, 1, 1, 1]                      # valid_W
LE = [0, 1, 0, 0, 0, 0, 0, 0, 0]                      # exc_valid_W  (trap at c1)
LR = [0, 1, 0, 0, 0, 0, 1, 0, 0]                      # wb_trap_redirect_o (trap, mret)
LF = [0, 1, 0, 0, 0, 0, 1, 0, 0]                      # flush_pipeline_onehot_o
LP = ["0x10", "0x14", "0x80", "0x84", "0x88", "0x8C", "0x90", "0x14", "0x18"]
EQS = [("mepc  =  exc_pc_W", "PC of the faulting instruction", fs.S_ALARM),
       ("PC  =  {mtvec_i[31:2], 2'b00}", "direct mode, any exception", fs.S_ADDR),
       ("PC  =  mtvec_base + 4*cause", "vectored mode, interrupts only", fs.S_ADDR),
       ("PC  =  {mepc_i[31:2], 2'b00}", "mret_commit only", fs.S_RESP)]


def draw_eqs(ax):
    x0, w = 52.0, 19.0
    for i, (a, b, col) in enumerate(EQS):
        y = P_TOP - 4.2 - i * 3.35
        fs.eqbox(ax, x0, y, w, 3.05, a, fs=6.4, fc=col, ec=fs.MID, color=fs.TXT)
        fs.label(ax, x0 + w / 2, y + 0.55, b, fs=5.9, color=fs.GREY, ha="center")


def draw_waves(ax, fig):
    axl, ys, u = fs.lanes(fig, WROW, WX0, WX0 + WN * WU, unit=WU, lane_gap=WG,
                          label_fs=6.5)
    # fs.lanes draws its lane separators all the way to xmax, which would run
    # them straight through the eqboxes, priority table and CSR table.
    for ln in axl.lines:
        if ln.get_color() == "#C8C8C8":
            xd = list(ln.get_xdata())
            ln.set_xdata([max(xd[0], WX0 - 6.5), WX0 + WN * WU + 1.3])
    fs.cycle_guides(axl, WX0, WN, u, bottom=WG - 1.15, top=5 * WG + 1.25)
    for key, lv, col, dash in (("v", LV, fs.ACCENT, False),
                               ("e", LE, fs.RED, False),
                               ("r", LR, fs.GREEN, True),
                               ("f", LF, fs.ORANGE, True)):
        fs.sigwave(axl, WX0, lv, u, ys[key] - 0.60, ys[key] + 0.60,
                   color=col, dashed=dash)
    fs.bus_cells(axl, WX0, LP, u, ys["p"] - 0.76, 1.52,
                 fill=fs.S_REQ, ec=fs.MID, color=fs.TXT)
    # txn_mark hard-codes a green label colour; the c1 TRAP marker is a red
    # event (red dot, red border, pink fill) so recolour its text to match.
    fs.txn_mark(axl, WX0 + 1.5 * u, ys["v"] + 0.62,
                "c1 TRAP \u00b7 flush 4'b1111 \u00b7 PC:=0x80",
                xytext=(0, 16), fs=6.8, color=fs.RED,
                fc="#FCE4E4", ec=fs.RED).set_color(fs.RED)
    fs.txn_mark(axl, WX0 + 6.5 * u, ys["v"] + 0.62,
                "c6 MRET \u00b7 PC := mepc = 0x14", xytext=(0, 16), fs=6.8)
    fs.label(ax, WX0 + 1.5 * WU, ys["p"] - 2.8, "mepc := 0x14", fs=6.6,
             color=fs.RED, weight="bold")
    return ys, u


def main():
    fig, ax = fs.slide(TITLE, SUB)
    X, Y = fs.canvas(ax)
    print("canvas = %.2f x %.2f units" % (X, Y))
    print("--- LANE BUDGET (%d bands) ---" % len(BUDGET))
    for tag, yy, what in BUDGET:
        print("  %-3s y=%-13s %s" % (tag, yy, what))
    draw_chain(ax)
    draw_lanes(ax)
    draw_priority(ax)
    draw_csr(ax)
    draw_eqs(ax)
    draw_waves(ax, fig)
    draw_redirect(ax)
    draw_notes(ax)
    draw_sections(ax)
    fs.footer(fig, "The trap decision must resolve in writeback, not execute: WB is the "
                   "only stage where the faulting instruction is provably the oldest "
                   "in flight, so mepc, mcause, mtval and mstatus can be latched in one "
                   "cycle before the flush empties every younger stage.")
    fs.pad_limits(ax, 0.06)
    fs.qa_report(fig)
    fs.save(fig, "fig18_trap_mret_fsm.png")


if __name__ == "__main__":
    main()
