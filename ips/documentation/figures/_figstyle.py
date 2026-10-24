"""
figstyle -- shared matplotlib style + drawing helpers for RISCFORGE figures.

Design contract
---------------
* Data coordinates are a "canvas grid": 1 unit == U_IN inches == 7.2 pt,
  axes are square-inches and aspect is forced equal.  Circles stay circles,
  arrowheads stay undistorted.
* Everything registers itself into a per-axes wire/text registry so that
  ``qa_report()`` can machine-check text-vs-wire and text-vs-text collisions
  and clipped labels.  Run it before saving; fix every warning.
* All routing is orthogonal with rounded corners.  No diagonals.

Usage
-----
    import _figstyle as fs
    fig, ax = fs.slide("Takeaway title", "subtitle")
    ... draw ...
    fs.qa_report(fig)
    fs.save(fig, "name")
"""

from __future__ import annotations

import os
import numpy as np
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import (
    Circle,
    FancyArrowPatch,
    FancyBboxPatch,
    Polygon,
    Rectangle,
)
from matplotlib.transforms import Bbox

# --------------------------------------------------------------------- palette
ACCENT = "#1F4E79"   # dark blue
MID = "#2E75B6"      # mid blue
GREEN = "#1E7D32"
RED = "#C00000"
ORANGE = "#B45F06"
GREY = "#595959"
LIGHT = "#F2F2F2"
TXT = "#12395C"      # dark navy body text on light fills

S_REQ = "#DDEBF7"    # request / decode  blue
S_ADDR = "#FFF2CC"   # address           yellow
S_WRITE = "#FCE4D6"  # write-wait        peach
S_RESP = "#E2EFDA"   # response          green
S_ALARM = "#FBE4E4"  # fault / timeout   pink
S_NOTE = "#F2F2F2"   # neutral note      grey

FS_BODY = 8.5
FS_TITLE = 11.0
DPI = 220
U_IN = 0.1  # inches per data unit

FS_LANE = 8.0
FS_CELL = 8.0
FS_NOTE = 7.6

_WIRES: dict[int, list] = {}
_TEXTS: dict[int, list] = {}

plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "font.size": FS_BODY,
        "axes.titlesize": FS_TITLE,
        "axes.labelsize": FS_BODY,
        "figure.dpi": 110,
        "savefig.dpi": DPI,
        "axes.linewidth": 0.8,
        "hatch.linewidth": 0.6,
        "legend.frameon": True,
        "legend.fontsize": 7.4,
        "path.simplify": False,
        "xtick.labelsize": 7.2,
        "ytick.labelsize": 7.2,
    }
)

# kind -> (facecolor, edgecolor, textcolor, default weight)
KIND = {
    "cpu": (ACCENT, ACCENT, "white", "bold"),
    "bus": (S_REQ, MID, TXT, "bold"),
    "periph": (S_RESP, GREEN, TXT, "bold"),
    "ctrl": (S_ADDR, "#BF8F00", TXT, "bold"),
    "req": (S_REQ, MID, TXT, "bold"),
    "addr": (S_ADDR, "#BF8F00", TXT, "bold"),
    "write": (S_WRITE, "#C55A11", TXT, "bold"),
    "resp": (S_RESP, "#548235", TXT, "bold"),
    "mem": (S_WRITE, "#C55A11", TXT, "bold"),
    "mux": ("#EDEDED", GREY, TXT, "normal"),
    "alarm": (S_ALARM, RED, "#7F1010", "bold"),
    "note": (S_NOTE, "#BFBFBF", "#3F3F3F", "normal"),
    "plain": ("#FFFFFF", ACCENT, TXT, "normal"),
    "dark": (GREY, GREY, "white", "bold"),
}


# ----------------------------------------------------------------- figure frame
def _ax_key(ax) -> int:
    return id(ax)


def slide(title=None, subtitle=None, w_in=13.0, h_in=7.3, bg="#FFFFFF"):
    """Create a 16:9 slide figure.  Axes spans the free area below title/footer."""
    fig = plt.figure(figsize=(w_in, h_in), facecolor=bg)
    left, right = 0.022, 0.014
    top, bottom = 0.108, 0.082
    axw = w_in * (1.0 - left - right)
    axh = h_in * (1.0 - top - bottom)
    ax = fig.add_axes([left, bottom, 1.0 - left - right, 1.0 - top - bottom])
    ax.set_facecolor(bg)
    # No set_aspect(): x/y limits are chosen so that 1 unit == U_IN inches on
    # BOTH axes, which makes the data->display scale isotropic anyway while
    # leaving matplotlib free to keep the requested axes box intact.
    ax.set_xlim(0.0, axw / U_IN)
    ax.set_ylim(0.0, axh / U_IN)
    # Axes.add_line() feeds the datalim and would otherwise re-autoscale the
    # canvas on every draw -- freeze the limits, layout is manual.
    ax.set_autoscale_on(False)
    ax.axis("off")
    if title:
        title_block(fig, title, subtitle)
    return fig, ax


def page(title=None, subtitle=None, w_in=11.2, h_in=7.4, bg="#FFFFFF"):
    """A4-report shaped figure frame."""
    return slide(title, subtitle, w_in=w_in, h_in=h_in, bg=bg)


def title_block(fig, title, subtitle=None):
    fig.text(
        0.5, 0.972, title, ha="center", va="top",
        fontsize=FS_TITLE, fontweight="bold", color=ACCENT,
    )
    if subtitle:
        fig.text(
            0.5, 0.930, subtitle, ha="center", va="top",
            fontsize=8.6, color=GREY,
        )
    fig.add_artist(
        Line2D([0.035, 0.965], [0.905, 0.905], transform=fig.transFigure,
               color=MID, lw=1.1, alpha=0.75, zorder=0)
    )


def footer(fig, text, rule=True):
    if rule:
        fig.add_artist(
            Line2D([0.035, 0.965], [0.048, 0.048], transform=fig.transFigure,
                   color="#BFBFBF", lw=0.8, zorder=0)
        )
    fig.text(
        0.5, 0.026, text, ha="center", va="center",
        fontsize=8.0, style="italic", color="#404040",
    )


def canvas(ax):
    """Return (x_units, y_units) of the axes data area."""
    return ax.get_xlim()[1], ax.get_ylim()[1]


def upu(ax):
    """
    Current DATA UNITS PER PIXEL for this axes.

    Measurement helpers must use this, never the nominal U_IN, because
    pad_limits() shrinks the axes box and therefore changes the data scale.
    Assuming U_IN after a pad would make every measured width ~6% short.
    """
    ax.figure.canvas.draw()
    bb = ax.patch.get_extents()
    xr = ax.get_xlim()[1] - ax.get_xlim()[0]
    px = float(bb.width)
    return (xr / px) if px > 0 else (1.0 / (ax.figure.dpi * U_IN))


def pad_limits(ax, pad=0.055):
    """
    Add visual padding WITHOUT rescaling the data units.

    Shrinking the axes box (instead of widening xlim/ylim) keeps
    1 unit == U_IN inches true, so every measurement the kernel took
    while drawing -- chip widths, fitted cell fonts, arrow-head sizes --
    stays correct.
    """
    pos = ax.get_position()
    d = float(pad)
    ax.set_position(Bbox.from_bounds(
        pos.x0 + pos.width * d / 2.0,
        pos.y0 + pos.height * d / 2.0,
        pos.width * (1.0 - d),
        pos.height * (1.0 - d),
    ))


# --------------------------------------------------------------------- blocks
def block(ax, x, y, w, h, text="", kind="ctrl", fs=FS_BODY, bold=None,
          tc=None, ls="-", lw=1.15, rounding=0.10, sub=None, sub_fs=7.0,
          zorder=3, anchor="c", va="center", ha="center", alpha=1.0,
          box_alpha=None, register=True):
    """Rounded box with pre-checked centered text.  Returns an anchor dict."""
    fc, ec, txtc, weight = KIND.get(kind, KIND["plain"])
    if bold is not None:
        weight = "bold" if bold else "normal"
    ba = fc if box_alpha is None else box_alpha
    pat = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0,rounding_size={min(rounding, min(w, h) / 2.6)}",
        linewidth=lw, edgecolor=ec, facecolor=ba, linestyle=ls,
        alpha=alpha, zorder=zorder,
    )
    ax.add_patch(pat)
    cx, cy = x + w / 2.0, y + h / 2.0
    ty = cy if sub is None else cy + h * 0.17
    t = ax.text(
        cx, ty, text, ha="center", va=va, fontsize=fs,
        fontweight=weight, color=tc or txtc, zorder=zorder + 2, linespacing=1.35,
    )
    if sub:
        st = ax.text(
            cx, cy - h * 0.21, sub, ha="center", va="center",
            fontsize=sub_fs, color=tc or txtc, alpha=0.92, zorder=zorder + 2,
        )
        _reg(ax, st)
        st._box_patch = pat
    _reg(ax, t)
    t._box_patch = pat
    ax.add_patch(Circle((0, 0), 0.0))  # no-op guard for patch stacking
    ax.patches[-1].set_visible(False)
    return {
        "patch": pat, "x": x, "y": y, "w": w, "h": h,
        "c": (cx, cy), "n": (cx, y + h), "s": (cx, y),
        "e": (x + w, cy), "w": (x, cy),
        "ne": (x + w, y + h), "nw": (x, y + h),
        "se": (x + w, y), "sw": (x, y),
        "text": t,
    }


def label(ax, x, y, s, fs=FS_BODY, color=TXT, weight="normal", ha="center",
          va="center", bbox=None, zorder=6, style="normal", rot=0,
          clip_on=False, linespacing=1.35, register=True):
    """Free text.  ``bbox`` = dict(fc=, ec=, pad=, boxstyle=) to break wires."""
    t = ax.text(x, y, s, fontsize=fs, color=color, fontweight=weight,
                ha=ha, va=va, bbox=bbox, zorder=zorder, style=style,
                rotation=rot, clip_on=clip_on, linespacing=linespacing)
    _reg(ax, t)
    return t


# Module-level alias: brace_v/brace_h take a `label=` parameter that would
# otherwise shadow this function inside their own bodies.
_TXT = label


def onwire(ax, x, y, s, fs=FS_LANE, color=ACCENT, weight="bold",
           fc="#FFFFFF", ec=MID, pad=0.9, zorder=6, ha="center"):
    """White-backed label that sits ON a wire and breaks it cleanly."""
    t = label(
        ax, x, y, s, fs=fs, color=color, weight=weight, ha=ha, zorder=zorder,
        bbox=dict(fc=fc, ec=ec, lw=0.9, pad=pad,
                  boxstyle="round,pad=0.25,rounding_size=0.6"),
    )
    t._onwire = True  # exempt from TEXT/WIRE QA: the white pad breaks the line
    return t


def note(ax, x, y, w, h, s, fs=FS_NOTE, ha="left", align="left",
         pad_x=1.1, pad_y=1.0, kind="note", weight="normal", zorder=2,
         valign="center"):
    fc, ec, txtc, _ = KIND[kind]
    box = Rectangle((x, y), w, h, facecolor=fc, edgecolor=ec,
                    linewidth=0.9, zorder=zorder)
    ax.add_patch(box)
    if valign == "center":
        ty, va = y + h / 2.0, "center"
    elif valign == "top":
        ty, va = y + h - pad_y, "top"
    else:
        ty, va = y + pad_y, "bottom"
    t = ax.text(x + pad_x, ty, s, ha=ha, va=va, fontsize=fs, color=txtc,
                fontweight=weight, zorder=zorder + 2, linespacing=1.42)
    _reg(ax, t)
    t._box_patch = box
    return box, t


def badge(ax, x, y, n, r=1.15, fc=ACCENT, tc="white", fs=7.8, zorder=7):
    """White bold number on dark fill."""
    ax.add_patch(Circle((x, y), r, facecolor=fc, edgecolor=fc,
                        linewidth=0.8, zorder=zorder))
    t = ax.text(x, y, str(n), ha="center", va="center", fontsize=fs,
                fontweight="bold", color=tc, zorder=zorder + 1)
    _reg(ax, t)
    return t


def dot(ax, x, y, r=0.42, fc=GREEN, zorder=8, ec="#FFFFFF", lw=0.8):
    ax.add_patch(Circle((x, y), r, facecolor=fc, edgecolor=ec,
                        linewidth=lw, zorder=zorder))
    return None


def text_w(ax, s, fs=FS_BODY, weight="normal", style="normal"):
    """Width of a string in canvas units (1 unit == 0.1 inch)."""
    fig = ax.figure
    fig.canvas.draw()
    tmp = ax.text(0, -1e5, s, fontsize=fs, fontweight=weight, style=style,
                  clip_on=False)
    bb = tmp.get_window_extent(renderer=fig.canvas.get_renderer())
    tmp.remove()
    return bb.width * upu(ax)


def text_h(ax, s, fs=FS_BODY, weight="normal"):
    fig = ax.figure
    fig.canvas.draw()
    tmp = ax.text(0, -1e5, s, fontsize=fs, fontweight=weight, clip_on=False)
    bb = tmp.get_window_extent(renderer=fig.canvas.get_renderer())
    tmp.remove()
    return bb.height * upu(ax)


def fit_fs(ax, s, max_w, fs=FS_CELL, weight="bold", floor=4.6):
    """Largest font size <= fs whose rendered width fits max_w."""
    w = text_w(ax, s, fs, weight)
    if w <= max_w or w <= 0:
        return fs
    return max(floor, fs * max_w / w)


def chip(ax, x, y, s, fc="#FFFFFF", ec=MID, tc=ACCENT, fs=7.0, padx=0.7,
         pady=0.34, lw=0.9, weight="bold", zorder=8, ha="left"):
    """Small legend/annotation chip sized to its text."""
    fig = ax.figure
    fig.canvas.draw()
    rend = fig.canvas.get_renderer()
    tmp = ax.text(0, -1e5, s, fontsize=fs, fontweight=weight, clip_on=False)
    bb = tmp.get_window_extent(renderer=rend)
    tmp.remove()
    w = bb.width * upu(ax) + 2 * padx
    h = bb.height * upu(ax) + 2 * pady
    x0 = x if ha == "left" else x - w / 2.0
    ax.add_patch(FancyBboxPatch(
        (x0, y - h / 2.0), w, h,
        boxstyle=f"round,pad=0,rounding_size={min(0.5, h / 2.6)}",
        facecolor=fc, edgecolor=ec, linewidth=lw, zorder=zorder,
    ))
    t = ax.text(x0 + w / 2.0, y, s, ha="center", va="center", fontsize=fs,
                color=tc, fontweight=weight, zorder=zorder + 1)
    _reg(ax, t)
    return x0, y - h / 2.0, w, h


def legend_row(ax, x, y, entries, gap=0.9, fs=7.0, vertical=False, step=3.0):
    """entries = [(style, color, text), ...] style in {'box','line','dash'}."""
    fig = ax.figure
    fig.canvas.draw()
    rend = fig.canvas.get_renderer()
    cx, cy = x, y
    for style, color, text in entries:
        if style == "box":
            fc, ec, tc, _ = KIND.get(color, (color, color, TXT, "normal"))
            ax.add_patch(Rectangle((cx, cy - 0.62), 1.7, 1.25, facecolor=fc,
                                   edgecolor=ec, linewidth=0.9, zorder=6))
            wpx, hpx = 1.7, 1.25
        else:
            ls = "-" if style == "line" else (0, (3, 2))
            ax.add_line(Line2D([cx, cx + 2.2], [cy, cy], color=color, lw=1.7,
                               ls=ls, zorder=6))
            wpx, hpx = 2.2, 1.25
        tmp = ax.text(0, -1e5, text, fontsize=fs, clip_on=False)
        bb = tmp.get_window_extent(renderer=rend)
        tmp.remove()
        tw = bb.width * upu(ax)
        th = bb.height * upu(ax)
        ax.text(cx + wpx + 0.55, cy, text, ha="left", va="center",
                fontsize=fs, color=TXT, zorder=7)
        if vertical:
            cy -= max(th, 1.3) + gap
        else:
            cx += wpx + 0.55 + tw + gap
    return cx, cy


# ---------------------------------------------------------------------- wires
def _reg(ax, t):
    _TEXTS.setdefault(_ax_key(ax), []).append(t)
    return t


def _elbow(p, q, route="auto"):
    px, py = p
    qx, qy = q
    if abs(px - qx) < 1e-9 or abs(py - qy) < 1e-9:
        return [p, q]
    if route == "h":
        return [p, (qx, py), q]
    if route == "v":
        return [p, (px, qy), q]
    return [p, (qx, py), q] if abs(qx - px) >= abs(qy - py) else [p, (px, qy), q]


def _orth_path(pts, route="auto"):
    out = [tuple(pts[0])]
    for i in range(len(pts) - 1):
        seg = _elbow(tuple(pts[i]), tuple(pts[i + 1]), route)
        out.extend(seg[1:])
    return out


def _round_corners(pts, frac=0.26):
    """Insert quadratic-bezier approximations at each interior vertex."""
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p, v, n = pts[i - 1], pts[i], pts[i + 1]
        v = np.array(v, dtype=float)
        a = np.array(p, dtype=float)
        b = np.array(n, dtype=float)
        la = np.linalg.norm(v - a)
        lb = np.linalg.norm(b - v)
        if la < 1e-9 or lb < 1e-9:
            out.append(tuple(v))
            continue
        ca = min(frac * la, frac * lb, 6.0)
        s = v + (a - v) / la * ca
        e = v + (b - v) / lb * ca
        out.append(tuple(s))
        for k in range(1, 7):
            u = k / 6.0
            q = (1 - u) ** 2 * s + 2 * (1 - u) * u * v + u ** 2 * e
            out.append(tuple(q))
    out.append(pts[-1])
    ded = [out[0]]
    for p in out[1:]:
        if abs(p[0] - ded[-1][0]) > 1e-9 or abs(p[1] - ded[-1][1]) > 1e-9:
            ded.append(p)
    return ded


def _head(ax, p_prev, p_end, color, lw, scale, zorder):
    """Undistorted arrow head via FancyArrowPatch (display-space sized)."""
    (x0, y0), (x1, y1) = p_prev, p_end
    if abs(x1 - x0) < 1e-9 and abs(y1 - y0) < 1e-9:
        return
    dx, dy = x1 - x0, y1 - y0
    d = np.hypot(dx, dy)
    if d < 1e-9:
        return
    ux, uy = dx / d, dy / d
    cap = min(d * 0.85, scale * U_IN * 1.5)
    fx, fy = x1 - ux * cap, y1 - uy * cap
    ap = FancyArrowPatch(
        (fx, fy), (x1, y1), arrowstyle="-|>", mutation_scale=scale,
        linewidth=0.0, color=color, shrinkA=0.0, shrinkB=0.0,
        joinstyle="miter", capstyle="butt", zorder=zorder + 1,
    )
    ax.add_patch(ap)


def wire(ax, p0, p1, via=None, route="auto", color=MID, lw=1.7, arrow=True,
         label=None, label_at=None, label_dy=0.0, label_fs=FS_LANE,
         label_color=None, label_box=True, label_ec=None, back=False,
         head_scale=11.0, zorder=3, dashed=False, ls_dash=(4, 2.4),
         bend=0.26, sizeless=False, alpha=1.0, register=True):
    """
    Orthogonal polyline with rounded corners and a clean arrow head.

    via     : explicit intermediate waypoints (list of (x, y)).
    route   : 'auto' | 'h' (h-then-v) | 'v' (v-then-h)
    back    : draw with a hollow head style (feedback / return edges)
    """
    pts = [tuple(p0)] + [tuple(v) for v in (via or [])] + [tuple(p1)]
    raw = _orth_path(pts, route)
    dense = _round_corners(raw, bend)

    xs = [p[0] for p in dense]
    ys = [p[1] for p in dense]
    ln = Line2D(xs, ys, color=color, lw=lw, solid_capstyle="round",
                solid_joinstyle="round", zorder=zorder,
                linestyle=(0, ls_dash) if dashed else "solid", alpha=alpha)
    ax.add_line(ln)
    if arrow:
        if back:
            _head(ax, dense[-2], dense[-1], color, lw, head_scale * 0.92,
                  zorder)
            _head_open(ax, dense[-2], dense[-1], color, lw, zorder)
        else:
            _head(ax, dense[-2], dense[-1], color, lw, head_scale, zorder)
    _WIRES.setdefault(_ax_key(ax), []).append(
        {"pts": dense, "color": color, "line": ln, "raw": raw}
    )

    if label:
        if label_at is None:
            best, bi = None, 0
            for i in range(len(raw) - 1):
                seg = abs(raw[i + 1][0] - raw[i][0]) + abs(raw[i + 1][1] - raw[i][1])
                if best is None or seg > best:
                    best, bi = seg, i
            lx = (raw[bi][0] + raw[bi + 1][0]) / 2.0
            ly = (raw[bi][1] + raw[bi + 1][1]) / 2.0
            if abs(raw[bi + 1][1] - raw[bi][1]) > abs(raw[bi + 1][0] - raw[bi][0]):
                ly += label_dy
            else:
                ly += label_dy
        else:
            lx, ly = label_at
        if label_box:
            onwire(ax, lx, ly, label, fs=label_fs,
                   color=label_color or color, ec=label_ec or color)
        else:
            t = label(ax, lx, ly, label, fs=label_fs,
                      color=label_color or TXT, weight="bold", zorder=6)
            t._onwire = True
    return ln


def _head_open(ax, p_prev, p_end, color, lw, zorder):
    (x0, y0), (x1, y1) = p_prev, p_end
    dx, dy = x1 - x0, y1 - y0
    d = np.hypot(dx, dy)
    ux, uy = dx / d, dy / d
    L = 1.25 * U_IN * 11.0
    W = 0.42 * U_IN * 11.0
    tip = np.array([x1, y1])
    b = tip - L * np.array([ux, uy])
    p = np.array([-uy, ux])
    a1 = b + W * p
    a2 = b - W * p
    ax.add_line(Line2D([tip[0], a1[0]], [tip[1], a1[1]], color=color,
                       lw=lw * 1.15, zorder=zorder + 1, solid_capstyle="round"))
    ax.add_line(Line2D([tip[0], a2[0]], [tip[1], a2[1]], color=color,
                       lw=lw * 1.15, zorder=zorder + 1, solid_capstyle="round"))


def bus(ax, p0, p1, via=None, route="auto", color=ACCENT, lw=6.0,
        label=None, label_at=None, label_fs=FS_LANE, zorder=2,
        fill="#FFFFFF"):
    """Single thick bus line with a light core, plus optional white-backed tag."""
    pts = [tuple(p0)] + [tuple(v) for v in (via or [])] + [tuple(p1)]
    raw = _orth_path(pts, route)
    ax.add_line(Line2D([p[0] for p in raw], [p[1] for p in raw], color=color,
                       lw=lw, solid_capstyle="butt", solid_joinstyle="round",
                       zorder=zorder))
    ax.add_line(Line2D([p[0] for p in raw], [p[1] for p in raw], color=fill,
                       lw=max(lw * 0.28, 1.0), solid_capstyle="butt",
                       solid_joinstyle="round", zorder=zorder + 1, alpha=0.85))
    _WIRES.setdefault(_ax_key(ax), []).append(
        {"pts": raw, "color": color, "line": None, "raw": raw}
    )
    if label:
        if label_at is None:
            i, best = 0, -1
            for k in range(len(raw) - 1):
                seg = abs(raw[k + 1][0] - raw[k][0]) + abs(raw[k + 1][1] - raw[k][1])
                if seg > best:
                    best, i = seg, k
            label_at = ((raw[i][0] + raw[i + 1][0]) / 2.0,
                        (raw[i][1] + raw[i + 1][1]) / 2.0)
        onwire(ax, label_at[0], label_at[1], label, fs=label_fs, color=color,
               ec=color, zorder=zorder + 4)
    return raw


def bundle(ax, p0, p1, lines, n=None, spread=0.90, color=ACCENT, lw=1.05,
           names=None, label=None, label_at=None, route="auto", via=None,
           zorder=2):
    """Multi-line bus bundle drawn as n parallel wires in a free lane."""
    n = n or len(lines)
    p0 = np.array(p0, dtype=float)
    p1 = np.array(p1, dtype=float)
    if via:
        return [wire(ax, p0, p1, via=via, route=route, color=color, lw=lw,
                     arrow=False, zorder=zorder) for _ in range(n)]
    d = p1 - p0
    L = float(np.hypot(d[0], d[1])) or 1.0
    u = d / L
    nn = np.array([-u[1], u[0]])
    out = []
    for i in range(n):
        off = (i - (n - 1) / 2.0) * spread
        a = tuple(p0 + nn * off)
        b = tuple(p1 + nn * off)
        out.append(wire(ax, a, b, color=color, lw=lw, arrow=False,
                        zorder=zorder))
    if names:
        for i, nm in enumerate(names):
            off = (i - (n - 1) / 2.0) * spread
            onwire(ax, p0[0] + nn[0] * off - u[0] * 2.6,
                   p0[1] + nn[1] * off - u[1] * 2.6, nm, fs=6.8,
                   color=color, ec="#FFFFFF", zorder=zorder + 4)
    if label:
        if label_at is None:
            label_at = tuple((p0 + p1) / 2.0)
        onwire(ax, label_at[0], label_at[1], label, fs=FS_LANE, color=color,
               ec=color, zorder=zorder + 4)
    return out


def tap(ax, x, y, h, color=GREEN, lw=1.7, zorder=4):
    ax.add_line(Line2D([x, x], [y, y + h], color=color, lw=lw,
                       solid_capstyle="round", zorder=zorder))


def arrow2d(ax, p0, p1, color=MID, lw=1.7, head_scale=11.0, zorder=4,
            dashed=False, ls_dash=(4, 2.4), bend=0.26, route="auto", via=None):
    """Explicitly-diagonal arrow (use only for annotation callouts)."""
    pts = [tuple(p0)] + [tuple(v) for v in (via or [])] + [tuple(p1)]
    if len(pts) == 2 and route != "straight":
        pts = _orth_path(pts, route)
        pts = _round_corners(pts, bend)
    ax.add_line(Line2D([p[0] for p in pts], [p[1] for p in pts], color=color,
                       lw=lw, solid_capstyle="round", solid_joinstyle="round",
                       zorder=zorder,
                       linestyle=(0, ls_dash) if dashed else "solid"))
    _head(ax, pts[-2], pts[-1], color, lw, head_scale, zorder)
    _WIRES.setdefault(_ax_key(ax), []).append(
        {"pts": pts, "color": color, "line": None, "raw": pts}
    )
    return pts


def brace_v(ax, x, y0, y1, label=None, color=GREY, lw=1.0, fs=7.0,
            side="right", tick=0.7):
    """Vertical curly-ish brace for grouping (orthogonal, not curved)."""
    if side == "right":
        pts = [(x, y0), (x + tick, y0), (x + tick, (y0 + y1) / 2.0),
               (x, (y0 + y1) / 2.0), (x + tick, (y0 + y1) / 2.0),
               (x + tick, y1), (x, y1)]
    else:
        pts = [(x, y0), (x - tick, y0), (x - tick, (y0 + y1) / 2.0),
               (x, (y0 + y1) / 2.0), (x - tick, (y0 + y1) / 2.0),
               (x - tick, y1), (x, y1)]
    ax.add_line(Line2D([p[0] for p in pts], [p[1] for p in pts], color=color,
                       lw=lw, solid_capstyle="round", zorder=3))
    # Register so qa_report() catches a brace slicing through a label.
    _WIRES.setdefault(_ax_key(ax), []).append(
        {"pts": pts, "color": color, "line": None, "raw": pts}
    )
    if label:
        lx = x + (tick + 0.6) * (1 if side == "right" else -1)
        _TXT(ax, lx, (y0 + y1) / 2.0, label, fs=fs, color=color,
              ha="left" if side == "right" else "right", rot=90, zorder=6)


def brace_h(ax, y, x0, x1, label=None, color=GREY, lw=1.0, fs=7.0,
            side="top", tick=0.7):
    if side == "top":
        pts = [(x0, y), (x0, y + tick), ((x0 + x1) / 2.0, y + tick),
               ((x0 + x1) / 2.0, y), (x1, y + tick), (x1, y + tick), (x1, y)]
        pts = [(x0, y), (x0, y + tick), ((x0 + x1) / 2.0, y + tick),
               ((x0 + x1) / 2.0, y), ((x0 + x1) / 2.0, y + tick),
               (x1, y + tick), (x1, y)]
    else:
        pts = [(x0, y), (x0, y - tick), ((x0 + x1) / 2.0, y - tick),
               ((x0 + x1) / 2.0, y), ((x0 + x1) / 2.0, y - tick),
               (x1, y - tick), (x1, y)]
    ax.add_line(Line2D([p[0] for p in pts], [p[1] for p in pts], color=color,
                       lw=lw, solid_capstyle="round", zorder=3))
    _WIRES.setdefault(_ax_key(ax), []).append(
        {"pts": pts, "color": color, "line": None, "raw": pts}
    )
    if label:
        _TXT(ax, (x0 + x1) / 2.0, y + (tick + 0.7) * (1 if side == "top" else -1),
              label, fs=fs, color=color, zorder=6)


# ------------------------------------------------------------------- waveform
def lanes(fig, rows, x0, x1, unit=None, cycle_names=None, left_pad=1.0,
          label_fs=FS_LANE, dashed=True, lane_gap=None, sub_fs=6.8,
          right_pad=1.2, reverse=True):
    """
    Draw waveform lane scaffolding.  Returns (ax, y_positions dict, unit).

    rows      : list of (key, lane_title, subtitle or None)
    reverse   : True  -> rows[0] is the TOP lane (reading order, default)
                False -> rows[0] is the bottom lane
    """
    ax = fig.axes[0] if fig.axes else fig.add_subplot(111)
    xmin, xmax = ax.get_xlim()
    span = xmax - xmin
    unit = unit or (span * 0.88) / (x1 - x0 + left_pad + right_pad)
    left = x0 - left_pad * unit
    cy = 0.0
    ys = {}
    gap = lane_gap if lane_gap is not None else 3.0
    order = list(rows)[::-1] if reverse else list(rows)
    for key, title, sub in order:
        cy += gap
        ys[key] = cy
        ax.add_line(Line2D([left - 0.6, xmax], [cy - gap / 2.0, cy - gap / 2.0],
                           color="#C8C8C8", lw=0.7, ls=(0, (2, 3)), zorder=1))
        if title:
            t = label(ax, left - 1.0, cy + 0.55, title, fs=label_fs,
                      color=TXT, weight="bold", ha="right", va="bottom",
                      zorder=8)
            if sub:
                label(ax, left - 1.0, cy - 0.95, sub, fs=sub_fs, color=GREY,
                      ha="right", va="top", zorder=8)
        ys["__left"] = left
    ys["__unit"] = unit
    ys["__x0"] = x0
    return ax, ys, unit


def cycle_guides(ax, x0, n, unit, bottom=0.0, top=None, color="#DCDCDC",
                 fs=6.6, names=None, name_fs=6.6):
    top = top if top is not None else ax.get_ylim()[1]
    for i in range(n + 1):
        x = x0 + i * unit
        ax.add_line(Line2D([x, x], [bottom, top], color=color, lw=0.7,
                           ls=(0, (2, 3)), zorder=1))
    if names:
        for i, nm in enumerate(names):
            if nm:
                onwire(ax, x0 + (i + 0.5) * unit, bottom - 1.0, nm,
                       fs=name_fs, color=GREY, ec="#FFFFFF", zorder=7)


def sigwave(ax, x0, levels, unit, y_low, y_high, color=ACCENT, dashed=False,
            lw=1.7, zorder=5, y_offset=0.0, dash=(3.2, 2.2)):
    """
    Canonical step waveform.  levels is a per-cycle list of 0/1 (or floats).
    Returns the polyline.
    """
    n = len(levels)
    x = [x0 + i * unit for i in range(n + 1)]
    y = [y_offset + (y_high if v else y_low) for v in levels] + [
        y_offset + (y_high if levels[-1] else y_low)
    ]
    assert len(x) == len(y), (len(x), len(y))
    ax.add_line(Line2D(x, y, color=color, lw=lw, drawstyle="steps-post",
                       solid_capstyle="round", solid_joinstyle="round",
                       zorder=zorder, linestyle=(0, dash) if dashed else "solid"))
    return list(zip(x, y))


def bus_cells(ax, c0, values, unit, y, h, fill=S_ADDR, ec="#BF8F00",
              fs=FS_CELL, color="#7F6000", zorder=4, radius=0.35,
              dashes=None, blank="", min_fs=None):
    """Shaded, bold-text cells: one cell per cycle.  Values hold for the cell."""
    from matplotlib.patches import FancyBboxPatch as _FB
    for i, v in enumerate(values):
        x = c0 + i * unit
        ax.add_patch(_FB(
            (x + unit * 0.03, y - h / 2.0), unit * 0.94, h,
            boxstyle=f"round,pad=0,rounding_size={min(radius, h / 2.6)}",
            facecolor=fill, edgecolor=ec, linewidth=0.9, zorder=zorder,
        ))
        if dashes and dashes[i]:
            t = ax.text(x + unit / 2.0, y, str(v), ha="center", va="center",
                        fontsize=fs, color=color, zorder=zorder + 2,
                        alpha=0.28, rotation=0)
        elif str(v) != blank:
            use_fs = fit_fs(ax, str(v), unit * 0.86, fs)
            label(ax, x + unit / 2.0, y, str(v), fs=use_fs, color=color,
                  weight="bold", zorder=zorder + 2)


def phase_bar(ax, x0, x1_unit, y, h, spans, fs=7.2, zorder=4, unit=None):
    """spans = [(c0, c1, text, color), ...] in cycle coordinates."""
    unit = unit or 1.0
    for c0, c1, text, col in spans:
        xa = x0 + c0 * unit
        w = (c1 - c0) * unit
        ax.add_patch(Rectangle((xa + 0.04, y), w - 0.08, h, facecolor=col,
                               edgecolor="#7F7F7F", linewidth=0.8,
                               zorder=zorder))
        if text:
            label(ax, xa + w / 2.0, y + h / 2.0, text, fs=fs, color="#202020",
                  weight="bold", zorder=zorder + 2)


def txn_mark(ax, x, y, text, xytext=(0, 18), fs=7.4, color=GREEN,
             fc="#E2EFDA", ec=GREEN, ha="center", va="bottom", lw=1.2,
             zorder=9, arrow=False):
    """Green dot on a handshake cycle + offset boxed annotation."""
    dot(ax, x, y, r=0.42, fc=color, zorder=zorder)
    t = ax.annotate(
        text, xy=(x, y), xytext=xytext, textcoords="offset points",
        ha=ha, va=va, fontsize=fs, color="#1B5E20", zorder=zorder + 1,
        bbox=dict(fc=fc, ec=ec, lw=lw, pad=2.0,
                  boxstyle="round,pad=0.3,rounding_size=1.0"),
        arrowprops=(dict(arrowstyle="-", color=ec, lw=0.9, shrinkA=0,
                         shrinkB=2) if arrow else None),
    )
    _reg(ax, t)
    return t


def eqbox(ax, x, y, w, h, s, fs=7.6, fc="#FFF2CC", ec="#BF8F00", color="#7F6000",
          zorder=5):
    ax.add_patch(Rectangle((x, y), w, h, facecolor=fc, edgecolor=ec,
                           linewidth=0.9, zorder=zorder))
    t = ax.text(x + w / 2.0, y + h / 2.0, s, ha="center", va="center",
                fontsize=fs, color=color, linespacing=1.45, zorder=zorder + 1)
    _reg(ax, t)
    t._box_patch = ax.patches[-1]
    return t


# ------------------------------------------------------------------ QA / save
def _rect_overlap(b1, b2, tol=1.0):
    ox = min(b1.x1, b2.x1) - max(b1.x0, b2.x0)
    oy = min(b1.y1, b2.y1) - max(b1.y0, b2.y0)
    return ox, oy


def qa_report(fig, ax=None, check_wires=True, check_canvas=True,
              verbose=True, strict=False):
    """
    Machine-check the figure.  Returns a list of human-readable warnings.

    Checks
      * text boxes overlapping other text boxes
      * text colliding with any registered wire (labels marked _onwire are
        exempt, they are *meant* to sit on a wire)
      * text not fully inside the box it belongs to
      * text clipped by the figure canvas
    """
    fig.canvas.draw()
    rend = fig.canvas.get_renderer()
    axes = [ax] if ax is not None else fig.axes
    issues = []
    for a in axes:
        texts = list(_TEXTS.get(_ax_key(a), []))
        boxes = []
        for t in texts:
            try:
                bb = t.get_window_extent(renderer=rend)
            except Exception:
                continue
            if bb.width <= 0 and bb.height <= 0:
                continue
            boxes.append((t, bb))

        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                t1, b1 = boxes[i]
                t2, b2 = boxes[j]
                ox, oy = _rect_overlap(b1, b2)
                if ox > 1.2 and oy > 1.2:
                    issues.append(
                        f"TEXT/TEXT overlap {ox:.1f}x{oy:.1f}px :: "
                        f"{t1.get_text()[:26]!r} <-> {t2.get_text()[:26]!r}"
                    )

        wires = _WIRES.get(_ax_key(a), []) if check_wires else []
        for t, bb in boxes:
            if getattr(t, "_onwire", False):
                continue
            for w in wires:
                disp = np.array([[p[0], p[1]] for p in w["pts"]])
                d = a.transData.transform(disp)
                n = len(d)
                seg_hit = False
                for k in range(n - 1):
                    x0, y0 = d[k]
                    x1, y1 = d[k + 1]
                    steps = max(int(np.hypot(x1 - x0, y1 - y0)), 1)
                    for s in range(steps + 1):
                        f = s / steps
                        px = x0 + (x1 - x0) * f
                        py = y0 + (y1 - y0) * f
                        if (bb.x0 - 1.5 <= px <= bb.x1 + 1.5 and
                                bb.y0 - 1.5 <= py <= bb.y1 + 1.5):
                            seg_hit = True
                            break
                    if seg_hit:
                        break
                if seg_hit:
                    issues.append(
                        f"TEXT/WIRE collision :: {t.get_text()[:34]!r}"
                    )

            bp = getattr(t, "_box_patch", None)
            if bp is not None:
                try:
                    pb = bp.get_window_extent(renderer=rend)
                    if (bb.x0 < pb.x0 - 1.0 or bb.x1 > pb.x1 + 1.0 or
                            bb.y0 < pb.y0 - 1.0 or bb.y1 > pb.y1 + 1.0):
                        issues.append(
                            f"TEXT OUTSIDE ITS BOX :: {t.get_text()[:34]!r}"
                        )
                except Exception:
                    pass

        if check_canvas:
            fb = fig.bbox
            for t, bb in boxes:
                if (bb.x0 < -1 or bb.y0 < -1 or bb.x1 > fb.x1 + 1
                        or bb.y1 > fb.y1 + 1):
                    issues.append(f"TEXT CLIPPED BY CANVAS :: {t.get_text()[:34]!r}")

    if verbose:
        print("=" * 78)
        print(f"QA: {os.path.basename(getattr(fig, '_qaname', 'figure'))}  "
              f"issues={len(issues)}")
        for s in dict.fromkeys(issues):
            print("  ! " + s)
        if not issues:
            print("  clean")
        print("=" * 78)
    return issues


def save(fig, name, outdir=None, vector=True, tight=True, facecolor=None):
    """Save PNG (220 dpi) plus SVG + PDF for Word / PowerPoint / Visio."""
    outdir = outdir or os.path.dirname(os.path.abspath(__file__))
    os.makedirs(outdir, exist_ok=True)
    base = os.path.splitext(name)[0]
    path = os.path.join(outdir, base + ".png")
    fig.savefig(path, dpi=DPI, bbox_inches="tight" if tight else None,
                facecolor=facecolor or fig.get_facecolor(),
                edgecolor="none", pad_inches=0.06)
    if vector:
        try:
            fig.savefig(os.path.join(outdir, base + ".svg"),
                        bbox_inches="tight" if tight else None,
                        facecolor=facecolor or fig.get_facecolor(),
                        edgecolor="none")
        except Exception:
            pass
    print("saved:", path)
    return path