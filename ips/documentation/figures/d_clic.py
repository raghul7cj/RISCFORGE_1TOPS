"""fig15 - CLIC (clic.sv / clic_target.sv / clic_gateway.sv) internals."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs  # noqa: E402

TITLE = ("The CLIC resolves priority only when software asks \u2014 hardware claims "
         "the ID, software owns the critical section")
SUB = ("read left to right — 1 sources · 2 gateway · 3 encoder · 4 IRQ bus · "
       "5 threshold · 6 claim/complete + vector; the dashed column = what the "
       "SoC builds today, the CLIC is NOT instantiated")

# h_in 6.6 (not the 7.3 default): the tallest content is y=50.8, so a 7.3 in
# canvas left a 228 px dead band between the subtitle rule and the first row.
fig, ax = fs.slide(TITLE, SUB, h_in=6.6)
X, Y = fs.canvas(ax)
print(f"canvas: {X:.1f} x {Y:.1f} units   title_w={fs.text_w(ax, TITLE, 11.0, 'bold'):.1f}"
      f"  sub_w={fs.text_w(ax, SUB, 8.6):.1f}")

# ---------------------------------------------------------------- lane budget
BAND_TOP = 50.8          # ceiling of the upper content band
COL = {
    "src":  (1.5, 19.5),      # A  interrupt sources table
    "nc":   (1.5, 19.5),      # A' sources NOT connected today
    "gwy":  (30.0, 48.0),     # B  clic_gateway
    "enc":  (54.0, 74.0),     # C  clic_target priority encoder
    "thr":  (54.0, 74.0),     # C' threshold / claim / complete
    "eq":   (54.0, 74.0),     # C'' mintvec eqbox
    "core": (81.0, 100.0),    # D  delivery to core
    "fsm":  (81.0, 100.0),    # D' FSM inset
    "reg":  (1.5, 40.0),      # register bank (A+B)
    "soc":  (103.0, 124.0),   # E  dashed in-core gateway/arbiter
    "note": (103.0, 124.0),   # E' honesty note
}
LANES = [
    (52.7, "perimeter return lane : claim_o[255:0]  CLAIM -> gateway ip clear"),
    (BAND_TOP, "band-1 ceiling (sources / gateway / encoder / core delivery)"),
    (46.0, "fan-in bus  intr_src_i[255:0] + sw_i (ip_sw) -> gateway"),
    (33.0, "irq bus  irq_valid_o / irq_ready_i / irq_id_o -> core"),
    (28.0, "band-2 ceiling : tie-break callout / threshold / FSM"),
    (20.5, "L3 register bank + L4 threshold/claim + L6 FSM"),
    (10.0, "L5 mintvec eqbox + software-critical-section note"),
    (4.5, "free margin (footer strip below 4.0)"),
]
print("LANE BUDGET (y-units):")
for y, what in LANES:
    print(f"  y={y:5.1f}   {what}")
print(f"columns x: " + "  ".join(f"{k}={v[0]}..{v[1]}" for k, v in COL.items()))

_W = {}


def bw(s, fs_=6.4, w="normal"):
    """Cached rendered text width in canvas units (calibrates my estimates)."""
    k = (s, fs_, w)
    if k not in _W:
        _W[k] = fs.text_w(ax, s, fs_, w)
    return _W[k]


def bx(name, y0, y1):
    """(x, y, w, h) for a COL span."""
    x0, x1 = COL[name]
    return (x0, y0, x1 - x0, y1 - y0)


# calibrate once
print("calib  'Timer1 ch1 ovf'@6.4 = %.2f   'mip[27]'@6.4 = %.2f   "
      "'intr_src_i[255:0]'@7.0 = %.2f" % (bw("Timer1 ch1 ovf", 6.4),
                                          bw("mip[27]", 6.4),
                                          bw("intr_src_i[255:0]", 7.0)))
# ---- entry point: the first step, and every acronym used below ------------
_s1 = fs.chip(ax, 1.5, 52.1, "1  SOURCES", fs=7.0, fc=fs.ACCENT, tc="white")
_g1 = fs.chip(ax, _s1[0] + _s1[2] * 1.07 + 2.4, 52.1,
              "CLIC = Core-Local Interrupt Controller  \u00b7  mip = machine "
              "interrupt-pending  \u00b7  le = level-enable (1 = edge)",
              fs=7.0, fc="#FFFFFF", ec=fs.GREY, tc="#404040")
fs.chip(ax, _g1[0] + _g1[2] * 1.07 + 2.4, 52.1,
        "U / S / M = user / supervisor / machine  \u00b7  shv / vsid / v_* = "
        "virtual-priority fields",
        fs=7.0, fc="#FFFFFF", ec=fs.GREY, tc="#404040")

# ============================================================ L2 : gateway in
# Real source list = riscforge_soc_subsystem.sv:1236-1248 fast_irq_i[11:0]
# (bit index = CLIC interrupt ID; the CLIC itself just names bits of
#  intr_src_i[255:0] - clic.sv:54 - there is no peripheral name table.)
SRCS = [
    (0, "GPIO  global", 16, 0), (1, "I2C   done/err", 17, 0),
    (2, "SPI   event", 18, 0), (3, "UART  rx/tx", 19, 0),
    (4, "Timer0 ch0 ovf", 20, 0), (5, "Timer0 ch1 ovf", 21, 0),
    (6, "Timer0 ch1 cmp", 22, 1), (7, "Timer1 ch0 ovf", 23, 0),
    (8, "Timer1 ch0 cmp", 24, 1), (9, "Timer1 ch1 ovf", 25, 0),
    (10, "Timer1 ch1 cmp", 26, 1), (11, "SPI   end-of-xfr", 27, 1),
]
fs.block(ax, *bx("src", 31.6, 50.8), "", kind="periph", lw=1.3)
for xx, hh, aa in ((2.2, "ID", "left"), (3.7, "SOURCE", "left"),
                   (13.6, "mip", "right"), (16.0, "le", "right"),
                   (19.2, "mode", "right")):
    fs.label(ax, xx, 49.6, hh, fs=5.8, weight="bold", ha=aa, color=fs.GREY)
for i, (iid, nm, mp, le) in enumerate(SRCS):
    yy = 48.3 - i * 1.42
    fs.label(ax, 2.2, yy, str(iid), fs=5.8, ha="left", color=fs.ACCENT,
             weight="bold")
    fs.label(ax, 3.7, yy, nm, fs=5.8, ha="left")
    fs.label(ax, 13.6, yy, "%d" % mp, fs=5.8, ha="right")
    fs.label(ax, 16.0, yy, "le=%d" % le, fs=5.8, ha="right")
    fs.label(ax, 19.2, yy, "edge" if le else "level", fs=5.8, ha="right",
             color=fs.RED if le else fs.TXT, weight="bold" if le else "normal")
    assert 3.7 + bw(nm, 5.8) < 12.4, (nm, 3.7 + bw(nm, 5.8))

fs.block(ax, *bx("nc", 18.6, 27.5), "", kind="plain", ls=(0, (4, 2.4)), lw=1.0)
fs.label(ax, 2.2, 26.5, "NOT AN INTERRUPT SOURCE TODAY", fs=5.4,
         weight="bold", ha="left", color=fs.RED)
NC = ["MEIP  ext_irq_i = 1'b0  (no PLIC)",
      "MSIP  sw_irq_i = 1'b0  (no CLINT)",
      "APB/AXI timeout sticky: observation",
      "   only - CPU sees access fault",
      "   mcause 5/7, not an interrupt",
      "AON wake: aon_timer/ not in the SoC"]
for i, s in enumerate(NC):
    assert bw(s, 5.8) < 15.9, (s, bw(s, 5.8))
    fs.label(ax, 2.2, 25.1 - i * 1.13, s, fs=5.8, ha="left", color=fs.GREY)

b_gwy = fs.block(ax, *bx("gwy", 30.0, 50.8), "", kind="ctrl", lw=1.3)
GX0, GX1 = COL["gwy"]


def _div(y):
    ax.plot([GX0 + 0.9, GX1 - 0.9], [y, y], color="#BF8F00", lw=0.7,
            alpha=0.7, zorder=4)


fs.label(ax, 39.0, 49.6, "2   clic_gateway", fs=8.4, weight="bold", color=fs.ACCENT)
fs.label(ax, 39.0, 48.3, "N_SOURCE = 256  \u00b7  ID == bit index", fs=6.3,
         color=fs.GREY)
_div(46.9)
for yy, ss, cl in ((45.5, "src_q[i], sw_q[i] = 1-cycle delayed copy", fs.TXT),
                   (43.9, "set[i] = (src_i&~src_q) | (sw_i&~sw_q)", fs.TXT),
                   (41.1, "le=1 EDGE: ip[i] <= (ip[i]|set&~ip[i])", fs.RED),
                   (39.6, "              & ~(ip[i] & claim[i])", fs.RED),
                   (38.0, "le=0 LEVEL: ip[i] <= src_i[i]  (claim no-op)",
                    fs.GREEN)):
    assert bw(ss, 5.4) < 16.3, (ss, bw(ss, 5.8))
    fs.label(ax, 31.0, yy, ss, fs=5.4, ha="left", color=cl)
_div(36.6)
fs.label(ax, 31.0, 34.9, "ip_o[255:0] = ip  pending bits", fs=6.4, ha="left",
         weight="bold")
for yy, ss in ((33.2, "sw_i = ip_sw : software edge trigger"),
               (31.5, "set has no effect until claim (Rtl comment)")):
    assert bw(ss, 5.4) < 16.3, (ss, bw(ss, 5.8))
    fs.label(ax, 31.0, yy, ss, fs=5.4, ha="left", color=fs.GREY)

fs.wire(ax, (19.5, 40.4), (30.0, 40.4), lw=2.8, color=fs.ACCENT,
        label="intr_src_i[255:0]", label_at=(24.75, 40.4), label_fs=6.6)
print("L2 ok  src rows=%d  widest-internal=%.2f"
      % (len(SRCS), max(bw(s, 5.8) for s in NC)))

# ================================================== L3 : pending/enable/prio bank
# clic.sv:106-116 address map; clicint_reg_pkg.sv:16-35 real field bit offsets;
# clic_reg_adapter.sv:61-68 the hw bindings.  CLICINT_STRIDE = 4 B per source.
RX0, RX1 = COL["reg"]
fs.block(ax, *bx("reg", 7.2, 17.0), "", kind="addr", lw=1.3)
fs.label(ax, 2.4, 16.2, "CLIC REGISTER BANK", fs=6.8, ha="left",
         weight="bold", color=fs.ACCENT)
# --- mcliccfg block
fs.block(ax, RX0 + 1.0, 7.2, 9.4, 8.2, "", kind="ctrl", lw=1.0)
fs.label(ax, 7.2, 14.55, "mcliccfg", fs=5.8, weight="bold", color=fs.ACCENT)
for i, s in enumerate(("@ CLIC+0x00000",
                       "mnlbits[1:0] -> level",
                       "nmbits[1:0] -> priv")):
    fs.label(ax, 3.0, 13.4 - i * 1.15, s, fs=5.6, ha="left", color=fs.TXT)
ax.plot([2.6, 10.8], [9.9, 9.9], color="#BF8F00", lw=0.7, alpha=0.7, zorder=4)
fs.label(ax, 3.0, 8.8, "mscratchcfg", fs=5.6, ha="left", color=fs.GREY)
# --- clicint block, one per source ID
fs.block(ax, RX0 + 11.6, 7.2, 26.6, 8.2, "", kind="ctrl", lw=1.0)
_ct = "clicint[id]  @ 0x01000 + 4*id .. 0x04FFF"
_ctw = bw(_ct, 5.8, "bold") * 1.07          # pre-pad measure, +pad_limits slack
_ctx = (RX0 + 11.6 + 39.7) / 2.0            # centre of the clicint sub-box
assert _ctx - _ctw / 2.0 > 13.6 and _ctx + _ctw / 2.0 < 39.2, (_ctx, _ctw)
fs.label(ax, _ctx, 14.55, _ct, fs=5.8, weight="bold", color=fs.ACCENT)
FIELDS = [(13.8, 16.6, "[14:7]", "ctl / intctl", "8-bit prio"),
          (13.8, 16.6, "[6:5]", "attr_mode", "0=U 1=S 3=M"),
          (13.8, 16.6, "[4:3]", "attr_trig", "bit0 -> le_o"),
          (28.6, 31.6, "[2]", "attr_shv", "SHV"),
          (28.6, 31.6, "[1]", "ie", "intenable"),
          (28.6, 31.6, "[0]", "ip", "-> ip_o")]
for i, (bx_, nx_, bits, nmm, nott) in enumerate(FIELDS):
    yy = 13.6 - (i % 3) * 1.2
    fs.label(ax, bx_, yy, bits, fs=5.6, ha="left", color=fs.RED, weight="bold")
    fs.label(ax, nx_, yy, nmm, fs=5.6, ha="left", weight="bold")
    nx2 = nx_ + bw(nmm, 5.6, "bold") + 0.8
    assert nx2 + bw(nott, 5.4) < 38.9, (nmm, nott, nx2 + bw(nott, 5.4))
    fs.label(ax, nx2, yy, nott, fs=5.4, ha="left", color=fs.GREY)
ax.plot([13.8, 37.8], [10.4, 10.4], color="#BF8F00", lw=0.7, alpha=0.7,
        zorder=4)
for i, s in enumerate(("le_o[i] = clicint.attr_trig.q[0]     "
                       "ie_o[i] = clicint.ie.q",
                       "intctl_o[i] = clicint.ctl.q          "
                       "ip_sw_o[i] = clicint.ip.q")):
    assert bw(s, 5.2) < 24.0, (s, bw(s, 5.2))
    fs.label(ax, 13.8, 9.4 - i * 1.15, s, fs=5.2, ha="left", color=fs.TXT)
# ================================== L4a : priority encoder + tie-break rule
# clic_target.sv:88-182 - max_tree[511] binary tree; sel at line 150.
EX0, EX1 = COL["enc"]
fs.block(ax, EX0, 27.5, EX1 - EX0, 50.8 - 27.5, "", kind="cpu", lw=1.3)
EC = (EX0 + EX1) / 2.0
fs.label(ax, EC, 49.7, "3   PRIORITY ENCODER", fs=7.6, weight="bold",
         color="white")
fs.label(ax, EC, 48.3, "clic_target.sv:88-182  binary max-tree, 511 nodes",
         fs=5.5, color="#D6E4F0")
fs.label(ax, EC, 47.2, "leaf: is_tree[id] = ip_i[id] & ie_i[id]", fs=5.6,
         color="white")

for i, xx in enumerate((55.6, 59.7, 63.8, 67.9)):
    fs.block(ax, xx, 44.3, 3.5, 1.7, "id %d" % i, kind="periph", fs=5.4,
             rounding=0.3)
fs.block(ax, 57.6, 41.2, 5.2, 1.7, "C0  max", kind="ctrl", fs=5.4, rounding=0.3)
fs.block(ax, 65.2, 41.2, 5.2, 1.7, "C1  max", kind="ctrl", fs=5.4, rounding=0.3)
fs.block(ax, 60.0, 38.2, 8.0, 1.8, "ROOT", kind="req", fs=5.6, rounding=0.3)
for lx, lyt, nx, ny in ((57.35, 43.9, 60.2, 42.9), (61.45, 43.5, 60.2, 42.9),
                        (65.55, 43.9, 67.8, 42.9), (69.65, 43.5, 67.8, 42.9)):
    fs.wire(ax, (lx, lyt), (nx, ny), lw=1.1, color=fs.MID, arrow=False)
fs.wire(ax, (60.2, 42.9), (60.2, 41.0), via=[(64.0, 41.0)], lw=1.1,
        color=fs.MID, arrow=False)
fs.wire(ax, (67.8, 42.9), (67.8, 40.6), via=[(64.0, 40.6)], lw=1.1,
        color=fs.MID, arrow=False)
fs.wire(ax, (60.2, 41.0), (64.0, 41.0), lw=1.1, color=fs.MID, arrow=False)
fs.wire(ax, (67.8, 40.6), (64.0, 40.6), lw=1.1, color=fs.MID, arrow=False)
fs.wire(ax, (64.0, 41.0), (64.0, 40.0), lw=1.1, color=fs.MID)
for yy, ss, ff, bd in ((37.4, "node: sel = max[C1] > max[C0]  (STRICT >)",
                         5.4, True),
                        (36.3, "root valid = (max_tree[0] > 0) ? "
                         "is_tree[0] : 0", 5.4, False),
                        (35.2, "key = {mode[1:0], vsprio, prio[7:0]}"
                         "  (mode is MSB)", 5.4, False),
(34.1, "S&~intv -> 2'b10:  order M > HS > VS > U",
                         5.4, False)):
    f2 = fs.fit_fs(ax, ss, 18.0, fs=ff, floor=4.9)
    fs.label(ax, EC, yy, ss, fs=f2, color="white", weight="bold" if bd
             else "normal")
fs.note(ax, 55.0, 27.6, 18.0, 5.2,
        "TIE-BREAK RULE (clic_target.sv:150)\n"
        "sel compares with a STRICT '>' - on an\n"
        "equal {mode, vsprio, prio} key the C0\n"
        "child wins: LOWEST ID WINS, not highest.",
        fs=5.1, kind="alarm", valign="top", zorder=6, pad_y=0.55)
fs.wire(ax, (48.0, 45.0), (54.0, 45.0), lw=2.4, color=fs.MID,
        label="ip[255:0]", label_at=(51.0, 45.0), label_fs=6.6)
# ================================ L4b : threshold + claim / complete + wiring
# clic.sv:730-776 mnlbits -> irq_level_o ; clic_target.sv:242-246 CLAIM pulse.
fs.block(ax, EX0, 14.6, EX1 - EX0, 10.4, "", kind="resp", lw=1.3)
fs.label(ax, EC, 24.1, "5   THRESHOLD  (mnlbits)", fs=7.2,
         weight="bold", color=fs.GREEN)
for yy, ss in (
        (22.6, "mnlbits = mcliccfg.mnlbits, saturated at",
         ),
        (21.4, "INTCTLBITS = 8 (clic.sv:734)"),
        (20.1, "irq_level_o = 8'hff, then the top mnlbits"),
        (18.9, "bits are taken from irq_max = winner's prio"),
        (17.7, "mnlbits = 0 -> level 0xff: no threshold, so"),
        (16.5, "takeover is purely level-sensitive (CLICMODE 0)")):
    fs.label(ax, EC, yy, ss, fs=fs.fit_fs(ax, ss, 18.2, 5.6, floor=4.9),
             color=fs.TXT)
ax.plot([EX0 + 0.9, EX1 - 0.9], [15.9, 15.9], color="#548235", lw=0.7,
        alpha=0.8, zorder=4)
fs.label(ax, EC, 15.2, "higher prio \u2192 higher level \u2192 preemption", fs=5.4,
         color=fs.GREEN, weight="bold")

# --- claim / complete, its own block under the threshold box
fs.block(ax, EX0, 4.2, EX1 - EX0, 8.3, "", kind="write", lw=2.8)
fs.label(ax, EC, 11.6, "6   CLAIM  \u2192  COMPLETE", fs=7.8, weight="bold",
         color="#C55A11")
for yy, ss, cl in (
        (10.4, "CLAIM: claim_o[irq_id_q] = 1'b1 for exactly", fs.TXT),
        (9.3, "one cycle (clic_target.sv:243) \u2192 the gateway's "
         "ip bit is cleared", fs.TXT),
        (7.1, "COMPLETE: there is NO hardware register. The", fs.RED),
        (5.9, "handler must write clicint.ip = 0 (W1C); if it", fs.RED),
        (4.8, "does not, the same ID re-pends and re-claims.", fs.RED)):
    f2 = fs.fit_fs(ax, ss, 17.8, 5.6, floor=4.9)
    fs.label(ax, EX0 + 0.95, yy, ss, fs=f2, ha="left", color=cl)
ax.plot([EX0 + 0.9, EX1 - 0.9], [8.2, 8.2], color="#C55A11", lw=0.7,
        alpha=0.8, zorder=4)
# --- config wires out of the register bank
fs.wire(ax, (40.0, 9.5), (54.0, 16.5), via=[(51.0, 9.5)], lw=1.4,
        color=fs.MID, label="mnlbits", label_at=(45.5, 9.5), label_fs=6.0)
fs.wire(ax, (43.0, 17.0), (54.0, 27.6), via=[(43.0, 27.6)], lw=1.6,
        color=fs.MID, label="ie / ctl / mode / shv / vsid",
        label_at=(46.9, 27.6), label_fs=5.4)
fs.wire(ax, (26.0, 17.0), (31.0, 30.0), via=[(26.0, 26.4), (31.0, 26.4)],
        lw=1.6, color=fs.MID, label="le[255:0] / ip_sw",
        label_at=(26.0, 21.6), label_fs=5.8)
fs.wire(ax, (64.0, 27.2), (64.0, 25.0), lw=1.6, color=fs.GREEN,
        label="irq_max[7:0]", label_at=(64.0, 26.25), label_fs=6.0)
# ============================ L5 : claimed ID -> core, and the mintvec formula
DX0, DX1 = COL["core"]
DC = (DX0 + DX1) / 2.0
fs.block(ax, DX0, 40.0, DX1 - DX0, 10.8, "", kind="cpu", lw=1.3)
fs.label(ax, DC, 49.8, "4   IRQ BUS  ->  CORE", fs=7.4, weight="bold", color="white")
for yy, ss in ((48.3, "irq_valid_o / irq_ready_i   ready/valid handshake"),
               (47.1, "irq_id_o[7:0]      = winning ID"),
               (45.9, "irq_level_o[7:0]   = mnlbits slice of prio"),
               (44.7, "irq_priv_o[1:0]    = M_MODE (nmbits=0)"),
               (43.5, "irq_shv_o, irq_v_o, irq_vsid_o[5:0]"),
               (42.3, "irq_kill_req_o / irq_kill_ack_i  (back)")):
    fs.label(ax, DX0 + 0.9, yy, ss, fs=fs.fit_fs(ax, ss, 17.2, 5.4, floor=4.8),
             ha="left", color="white")
fs.wire(ax, (74.0, 47.5), (81.0, 47.5), lw=2.4,
        color=fs.MID, label="irq_valid_o", label_at=(77.5, 47.5), label_fs=5.6)
fs.wire(ax, (90.5, 36.5), (90.5, 40.0), lw=2.0, color=fs.MID,
        label="claim handshake\nvalid/ready + id", label_at=(90.5, 38.25),
        label_fs=5.2)

# --- the vector is computed by software, not by clic.sv
fs.eqbox(ax, DX0 + 0.6, 15.4, 18.0, 3.4,
         "mintvec  =  ID * 4  +  base", fs=8.4)
for yy, ss, cl in ((13.6, "clic.sv / clic_target.sv contain NO mintvec,", fs.RED),
                   (12.4, "mintstatus or mtval register: grep over all", fs.RED),
                   (11.2, "rtl/**/*.sv returns 0 hits. Hardware only", fs.RED),
                   (10.0, "hands the ID over irq_id_o; the CLIC-spec", fs.TXT),
                   (8.8, "rule above is the handler's job.", fs.TXT)):
    fs.label(ax, DC, yy, ss, fs=fs.fit_fs(ax, ss, 18.2, 5.4, floor=4.8),
             color=cl)
# ============================ L6a : FSM inset  (clic_target.sv:186-251)
fs.block(ax, DX0, 22.5, DX1 - DX0, 14.0, "", kind="req", lw=1.3)
fs.label(ax, DC, 35.75, "irq_state_e FSM", fs=7.0,
         weight="bold", color=fs.ACCENT)
fs.label(ax, DC, 34.75, "{ IDLE, ACK, CLAIM }", fs=5.4,
         weight="bold", color=fs.MID)
ROWS = [("IDLE", 32.2, "periph",
         "latch id / max / vsid / shv,\nset irq_valid_o, next state ACK"),
        ("ACK", 28.3, "ctrl",
         "hold irq_valid_o; exits in this order:\n"
         "1  !le[id] && !ip[id]   ->   IDLE\n"
         "2  valid && ready   ->   CLAIM\n"
         "3  higher_irq   ->   kill handshake"),
        ("CLAIM", 24.5, "write",
         "claim_o[id] = 1'b1 for one cycle,\n"
         "then straight back to IDLE - clears ip[id]")]
for nm, yy, kd, txt in ROWS:
    fs.block(ax, 82.0, yy, 5.0, 1.8, "", kind=kd, lw=1.0)
    fs.label(ax, 84.5, yy + 0.9, "S_" + nm, fs=5.8, weight="bold",
             color="#FFFFFF")
    _ls = txt.split("\n")
    _sp = 0.88 if len(_ls) >= 4 else 0.95
    for k, ln in enumerate(_ls):
        fs.label(ax, 87.6, yy + 0.9 - (k - (len(_ls) - 1) / 2.0) * _sp, ln,
                 fs=fs.fit_fs(ax, ln, 11.7, 4.9, floor=4.0),
                 ha="left", color=fs.TXT)
fs.wire(ax, (84.5, 32.2), (84.5, 30.1), lw=1.3, color=fs.MID)
fs.wire(ax, (84.5, 28.3), (84.5, 26.3), lw=1.3, color=fs.MID)
fs.wire(ax, (84.5, 24.5), (84.5, 23.5), lw=1.3, color=fs.ORANGE, back=True)
fs.label(ax, 87.8, 23.4, "default: -> IDLE", fs=5.0, ha="left",
         color=fs.RED, weight="bold")
fs.label(ax, 87.6, 26.9, "kill: kill_req_o <-> kill_ack_i", fs=4.9,
         ha="left", color=fs.ORANGE, weight="bold")
fs.wire(ax, (90.5, 22.5), (90.5, 20.5), lw=1.8, color=fs.RED,
        label="claimed ID", label_at=(90.5, 21.5), label_fs=5.4)
# ================== L6b : claim return edge (perimeter), SoC truth, footer
CLM = ["claim_o[id] = 1'b1 for one cycle  \u2192  gateway clears ip[id]"]
cx_ = 41.0
fs.wire(ax, (96.0, 22.5), (101.5, 21.0), via=[(96.0, 21.0)], lw=1.5,
        color=fs.RED, back=True, arrow=False)
fs.wire(ax, (101.5, 21.0), (101.5, 1.8), lw=1.5, color=fs.RED, back=True,
        arrow=False)
fs.wire(ax, (101.5, 1.8), (cx_, 1.8), lw=1.5, color=fs.RED, back=True,
        arrow=False)
fs.wire(ax, (cx_, 1.8), (cx_, 30.0), lw=1.5, color=fs.RED, arrow=True)
fs.onwire(ax, 62.0, 1.8, CLM[0], fs=5.6, color=fs.RED, ec=fs.RED)
fs.dot(ax, cx_, 1.8, r=0.36, fc=fs.RED)
fs.label(ax, 40.0, 19.4, "CLAIM RETURN PATH", fs=5.6, weight="bold",
         ha="right", color=fs.RED)

# --- what the SoC actually builds today (dashed, NOT the CLIC)
SX0, SX1 = COL["soc"]
fs.block(ax, SX0, 33.0, SX1 - SX0, 17.8, "", kind="plain", ls=(0, (5, 3)),
         lw=1.2)
fs.label(ax, (SX0 + SX1) / 2, 49.8, "WHAT THE SOC BUILDS TODAY", fs=6.8,
         weight="bold", color=fs.GREY)
fs.label(ax, (SX0 + SX1) / 2, 48.5, "(dashed = not the CLIC)", fs=5.6,
         color=fs.RED, weight="bold")
IN = ["fast_irq_i[15:0]  (top.v:58)", "  [11:0] used, [15:12] tied 0",
      "  irq_raw = {f[11], timer,", "          f[3:0]}   (top.v:207)"]
for i, s in enumerate(IN):
    fs.label(ax, SX0 + 0.9, 47.2 - i * 0.9, s, fs=5.0, ha="left",
             color=fs.TXT)
fs.block(ax, SX0 + 0.8, 40.4, 19.4, 2.6, "", kind="periph", lw=1.0)
fs.label(ax, (SX0 + SX1) / 2, 42.1, "in-core irq_gateway", fs=5.8,
         weight="bold", color=fs.TXT)
fs.label(ax, (SX0 + SX1) / 2, 41.2, "edge / pulse capture", fs=5.0,
         color=fs.GREY)
fs.block(ax, SX0 + 0.8, 35.4, 19.4, 4.4, "", kind="periph", lw=1.0)
fs.label(ax, (SX0 + SX1) / 2, 39.0, "in-core irq_arbiter  (6 sources)", fs=5.8,
         weight="bold", color=fs.TXT)
for i, s in enumerate(["Cls2 fixed: WD(27) > Timer0(7)",
                       "Cls1 round-robin: UART(19) <-> SPI(18)",
                       "Cls0 round-robin: I2C(17) <-> GPIO(16)"]):
    fs.label(ax, SX0 + 1.6, 38.1 - i * 0.95, s, fs=4.9, ha="left",
             color=fs.GREY)
fs.label(ax, (SX0 + SX1) / 2, 34.3, "-> mip[16..27]: no claim, no ID, no mintvec",
         fs=5.0, color=fs.RED, weight="bold")

fs.note(ax, SX0, 5.6, SX1 - SX0, 27.0,
        "SOC INTEGRATION: INTENDED, NOT LIVE\n"
        "\n"
        "1. riscforge_soc_subsystem.sv never\n"
        "   instantiates `clic`. Line 1164:\n"
        "   'replaces CLIC at this APB slot'.\n"
        "   ext_irq_i / sw_irq_i = 1'b0\n"
        "   (1250-1251: 'no platform PLIC',\n"
        "   'no CLINT').\n"
        "\n"
        "2. So no CLIC path reaches the core.\n"
        "   The dashed block above is the whole\n"
        "   of today's intake: in-core gateway +\n"
        "   2-class arbiter, 6 sources, mip[16..27].\n"
        "\n"
        "3. Everything left of here is real,\n"
        "   elaborated lowRISC Clic RTL from\n"
        "   clic-master/ (Apache-2.0) - just not\n"
        "   connected to this SoC.\n"
        "\n"
        "4. For software today: interrupts land\n"
        "   pre-masked in mip, there is no claim\n"
        "   step, and mcause carries mip[16..27].",
        fs=5.0, kind="note", valign="top")
fs.footer(fig, "Claim-then-complete replaces level-sensitive nesting hardware: "
         "hardware clears ip only on the one-cycle claim pulse, so the handler's "
         "critical section is the whole correctness argument.")
fs.legend_row(ax, 2.4, 5.4, [("line", fs.MID, "data / register config"),
                             ("line", fs.RED, "claim return (peripheral)")],
              fs=6.0)
fs.legend_row(ax, 2.4, 3.4, [("dash", fs.GREY, "NOT instantiated today"),
                             ("box", "alarm", "tie-break: LOWEST id wins")],
              fs=6.0)
fs.pad_limits(ax, 0.06)
print("footer width %.1f units (canvas %.1f)"
      % (fs.text_w(ax, "Claim-then-complete replaces level-sensitive nesting "
             "hardware: hardware clears ip only on the one-cycle claim pulse, "
             "so the handler's critical section is the whole correctness "
             "argument.", 8.0, style="italic"), X))
fs.qa_report(fig)
fs.save(fig, "fig15_clic_internals.png")


