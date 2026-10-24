# Figure brief — RISCFORGE SoC + peripheral internals & state machines

ALL agents read this first. Then read your own task section at the bottom.

## 0. Environment (Windows / PowerShell)

* Python: **`py -3`** (3.12, matplotlib 3.10.8 already installed). `python` does
  not work — always use `py -3`.
* Working directory (all figure work happens here):
  `C:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\documentation\figures\`
* Run your generator script from that directory:
  `py -3 d_<yourscript>.py`
* Repo root for RTL reading:
  `C:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\`

## 1. The shared drawing kernel — use it, do not re-implement

`_figstyle.py` in the figures directory is the validated drawing kernel
(palette, orthogonal routing with rounded corners, undistorted arrow heads,
waveform scaffolding, text measurement, and a collision checker).
**Import it. Do not modify it. Do not copy its palette into your own code.**

```python
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _figstyle as fs
```

### API cheat sheet

| call | purpose |
|---|---|
| `fig, ax = fs.slide(title, subtitle)` | 16:9 slide canvas, returns axes already sized |
| `fig, ax = fs.page(title, subtitle)` | A4-report shaped canvas |
| `X, Y = fs.canvas(ax)` | canvas size in units (slide ≈ 125 × 59) |
| `b = fs.block(ax, x, y, w, h, "TEXT", kind=..., sub="small caption")` | rounded box; returns anchor dict |
| `fs.bus(ax, p0, p1, label=...)` | thick single bus line |
| `fs.bundle(ax, p0, p1, "sig names", n=4, label=...)` | parallel bus-bundle wires |
| `fs.wire(ax, p0, p1, via=[...], label=..., label_at=(x,y), back=False, dashed=False)` | orthogonal wire, optional white-backed label |
| `fs.wire(ax, ..., back=True)` | hollow head, for feedback / return edges |
| `fs.arrow2d(ax, p0, p1)` | annotation leader (place its text in a free gap, not on it) |
| `fs.onwire(ax, x, y, "text")` | white-backed label that breaks a wire |
| `fs.label(ax, x, y, "text", fs=, color=, weight=, ha=, va=, rot=, bbox=dict(...))` | free text |
| `fs.note(ax, x, y, w, h, "callout text")` | grey info/callout box |
| `fs.eqbox(ax, x, y, w, h, "formula")` | formula box |
| `fs.badge(ax, x, y, 1)` | white bold number on dark circle |
| `fs.dot(ax, x, y)` | green marker dot |
| `fs.chip(ax, x, y, "legend text")` | auto-sized chip |
| `fs.legend_row(ax, x, y, [("box","periph","APB slave"),("line",fs.MID,"AXI-Lite")])` | legend |
| `fs.brace_v(ax, x, y0, y1, "group", side="left"/"right")` | grouping brace |
| `ax, ys, u = fs.lanes(fig, rows, x0, x_end, unit=7.4, lane_gap=6.0)` | waveform lanes; `rows=[(key,"SIG","sub")]`; `rows[0]` is the TOP lane |
| `fs.cycle_guides(ax, x0, n, unit, bottom=, top=, names=[...])` | dotted cycle grid |
| `fs.sigwave(ax, x0, [1,1,1,0,...], unit, y_low, y_high, color=, dashed=)` | canonical step waveform |
| `fs.bus_cells(ax, x0, ["0x40","0x40","",...], unit, y, h, fill=, ec=, color=)` | shaded bus cells, bold centred text, auto font shrink |
| `fs.phase_bar(ax, x0, n, y, h, [(0,2,"ADDRESS",fs.S_ADDR), ...], unit=unit)` | transaction phase strip |
| `fs.txn_mark(ax, x, y, "text", xytext=(0,18))` | green dot + offset boxed callout |
| `fs.footer(fig, "italic why-it-matters line")` | bottom strip |
| `fs.pad_limits(ax, 0.06)` | pad canvas 5-10% |
| `fs.qa_report(fig)` | collision checker — **must print `clean`** |
| `fs.save(fig, "figXX_name.png")` | writes PNG @220dpi + SVG |

**Canvas coordinates**: 1 data unit = 0.1 inch = 7.2 pt. On a slide the canvas
is ≈125 × 59 units. Fill it — do not leave a figure floating in white space.
A 9 pt label is ≈1.25 units tall; a 2-line label ≈2.6 units; body text needs
≈2.4 units of vertical clearance; box padding of 1.2 units minimum on all sides.

**Colours** — `kind=` presets: `cpu` (dark blue) `bus` (light blue) `periph`
(green) `ctrl`/`addr` (yellow) `req` (blue) `write` (peach) `resp` (green)
`mem` (peach) `mux` (grey) `alarm` (pink/red) `note` (grey) `plain` (white)
`dark` (grey). Raw colours: `fs.ACCENT fs.MID fs.GREEN fs.RED fs.ORANGE
fs.GREY fs.S_REQ fs.S_ADDR fs.S_WRITE fs.S_RESP fs.S_ALARM`.

## 2. Every figure must teach something

* **Title (bold, 11 pt) = the interview takeaway**, not the topic.
  Weak: "UART Block Diagram". Strong: "The UART is a 2-entry FIFO pair around
  one shared baud divider — back-pressure is invisible to software".
* **Subtitle** = what is actually drawn (datapath, FSM, waveform, phase).
* **Footer (italic)** = why it matters / the failure mode it prevents.
* Annotate with **real values**: `0x4000_1000`, `AWVALID & AWREADY`,
  `baud_div = clk/115200`, `9th clk`, `2^32-1 wrap`. Never label a box with a
  bare name if the RTL gives a width, depth or address.
* Put at least one **formula box** on figures where one exists (wrap boundary,
  divisor, threshold, mask).
* **State nodes carry their exact handshake/exit condition**, e.g.
  `S_WDATA\nWLAST && WREADY`.
* Colour-code consistently: field phase colours must match across a figure
  (e.g. ADDR phase yellow in the phase bar AND yellow in the payload lane).

## 3. Mandatory QA loop — do not skip, do not lie

For every figure, in this exact order:

1. `py -3 d_<script>.py` — the QA block must print `clean`.
   If it lists issues, **fix the layout** (move the box / shorten the label /
   widen the gap / change `label_at`), then re-run. Do not silence a check by
   marking text `_onwire` unless the label genuinely has a white backing that
   breaks a wire.
2. **Read the PNG back as an image with the read tool and actually look at it.**
   Confirm: no text touching a line or box edge, no arrow crossing a box, no
   clipped or truncated label, no dark-on-dark text, no label half-in/half-out
   of a box, no wire passing through a box, nothing touching the frame.
   Machine QA cannot see aesthetic problems — you must look.
3. Repeat 1-2 until both are clean. Only then move on.

A figure that has not been visually inspected is not finished.

## 4. Non-negotiable layout rules

* **Orthogonal routing only** — horizontal/vertical polylines, rounded joins.
  `fs.wire` does this for you. Never a diagonal data path.
* **Feedback / return edges go around the perimeter** (over the top lane or
  under the bottom lane), never through a state and never through a note box.
  Give each return edge its own free lane.
* **Branch wires** (NACK, error, repeated-START) get a rectangular path fully
  above or fully below the main chain, each in its own lane, label centred on
  the horizontal run.
* **Info callouts** (deadlock rules, arbitration limits, stretch handling) go
  in lanes that no wire crosses.
* Size inter-box gaps so the label fits: **gap width > label width + 2 units**.
* Labels on a wire: `fs.onwire` / `wire(..., label=...)` (white backing breaks
  the line). Labels *near* a wire but not on it: `fs.label` placed in a
  pre-checked free gap.
* Minimum gap between parallel wires/lanes: 0.4 units.
* Use `fs.badge(ax, ..., n)` for step numbers — white bold on dark, never
  dark-on-dark.
* Padding: `fs.pad_limits(ax, 0.06)`; keep all content ≥1 unit inside the edge.

## 5. Naming and deliverables

* Script: `d_<topic>.py` in the figures directory. Re-runnable, idempotent.
* Figures: `figNN_<snake_case>.png` (+ auto `.svg`) using the number assigned
  in your task. Numbers are a global sequence — do not renumber.
* Keep every figure to **one idea**. Two figures beat one crowded figure.
* 2 figures per agent unless your task says otherwise. A4/16:9 sized for
  PowerPoint + Word; SVG is generated for crisp Office scaling.

## 6. Reading the RTL

Per `AGENTS.md`, **read at most 1-2 RTL files** per figure. Use
`Grep`/`Select-String` on the specific file to pull localparam state encodings,
register offsets and port widths — do not scan the repo. Prefer what the RTL
actually says over plausible-sounding generic names. If a detail is not in the
RTL, keep the label generic rather than inventing a value.

---

# Task assignments

(fig01-02)  **SYSTEM**     — SoC topology + address map
(fig03-04)  **INTERCONNECT** — AXI-Lite crossbar + AXI-Lite→APB bridge
(fig05-06)  **RESILIENCE**  — bus timeout monitors + APB protocol timing
(fig07-08)  **UART**        — APB UART internals + TX/RX FSM/waveform
(fig09-10)  **TIMERS**      — APB Timer + AON timer
(fig11-12)  **I2C**         — APB I2C master FSM + I2C timing waveform
(fig13-14)  **SPI_GPIO**    — SPI/QSPI master FSM + GPIO controller
(fig15-16)  **CLIC**        — CLIC internals + interrupt arbitration
(fig17-18)  **CORE**        — RV32 5-stage pipeline + trap/mret FSM