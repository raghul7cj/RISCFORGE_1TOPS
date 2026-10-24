# Brief 2 — PRESENTABILITY & FLOW pass (human comprehension)

Read this in full before doing anything. It is a DIFFERENT job from the first pass.

---

## 0. The situation

All 18 figures in this directory are already **collision-free**: every generator
calls `fs.qa_report()` and reports `clean`. Geometry bugs are gone.

They are now failing a different test: **a human cannot tell what is going on.**
They are cluttered, the reading path is not obvious, everything has equal visual
weight, and several figures carry two or three separate ideas at once.

Your job is **comprehension**, not geometry.

---

## 1. The two tests you must apply

### The 5-second test
Cover the caption. Look only at the figure. Can you say **what kind of thing
this is** and **which way to read it**? (e.g. "a datapath, left to right: core →
crossbar → bridge → peripherals"). If you cannot, the figure has no entry point.

### The 30-second test
Read it properly. Can you state **one sentence** that the figure is making —
the thing you would say out loud to a colleague? If you finish reading and could
summarise it two different ways, it is carrying more than one idea.

### The newcomer test
You have never seen this RTL. Is there any element whose purpose you had to
guess? Is any group of elements unlabelled? Is any acronym used before it is
expanded? (e.g. "CC", "C0/C1", "f_i/b_i", "M/W" with no legend.)

---

## 2. What actually makes a technical figure fail to communicate

Diagnose against these specifically:

**No flow / no reading order**
- No clear entry point — the eye has nowhere to start.
- The reading path zig-zags: left→right, then up, then back left.
- Direction of travel is not encoded (no consistent left-to-right or top-to-bottom).
- The "main" path and the "side" paths look identical.

**No visual hierarchy**
- 15 elements all at the same size, weight and colour ⇒ nothing is important.
- Notes and callouts are as visually loud as the datapath they explain.
- A legend competes with the content it explains.
- The subject of the title is not the most prominent thing in the figure.

**Clutter**
- Two or three separate ideas on one canvas. This is the single most common
  failure in this set and the one most worth fixing.
- Detail that belongs in a table crammed into a block diagram (or vice versa).
- Colour used decoratively instead of semantically, so colour carries no meaning.
- Grid lines, swimlane boxes, headers and dividers that add no information.

**Abstraction mixing**
- A system-level block sitting in the same visual register as a gate-level net.
- Behaviour (timing/sequence) and structure (datapath) on the same canvas.

**Density**
- Text below ~6.5 pt that must be read to understand the main point.
- More than ~7 boxes competing for the same first glance.

---

## 3. The fix: GRANULARITY IS WELCOME

**Splitting a figure into two or three focused figures is the preferred fix.**
Do not cram to avoid splitting. Do not delete verified technical content just to
make room — move it to the new figure.

Rules for a split:
- Each resulting figure gets **exactly one job** and its own one-sentence
  takeaway, which becomes its title.
- Each figure repeats the small amount of context it needs to stand alone
  (its own input and output, its own legend) so it works without the others.
- Keep the same drawing kernel and palette; the split parts must look like one
  family.
- A figure that genuinely cannot be split should instead get an explicit
  reading order: a numbered path or a clearly marked "start here".

**IMPORTANT — file naming is assigned centrally, not by you.**
- If a figure needs splitting, DO NOT create the new files yourself and DO NOT
  rename anything. Instead, report a split proposal in your final message with
  the exact proposed filenames and the title/one-sentence for each part. The
  orchestrator will assign numbers and dispatch a worker to build them.
- Fix IN PLACE (same filename) everything that is not a split.

---

## 4. Hard constraints

- **Do not edit `_figstyle.py`.** If you believe it needs a change, say so in
  your report instead.
- **Do not renumber or rename existing files.**
- **Do not change verified technical content** — no new signal names, register
  offsets, addresses, state names, bit values, or cycle counts. You may move
  content, reword it for clarity, and change its visual prominence. If you
  believe a technical statement is wrong, report it; do not silently "fix" it.
- **`fs.qa_report(fig)` must print `clean`** at the end, and you must **read the
  PNG back as an image** and confirm the flow now reads clearly.
- **BUILD RULE:** never put more than ~55 lines in a single tool call. Build any
  restructuring incrementally, running the script between stages. Oversized
  single-shot writes are the single most common way this work gets lost.

## 5. Kernel cheat sheet (unchanged from brief 1)

`import _figstyle as fs` — `slide(title, subtitle)`, `block(ax,x,y,w,h,text,kind=,sub=)`,
`bus`, `bundle`, `wire(..., via=, label=, label_at=, back=, dashed=)`, `onwire`,
`label`, `note`, `eqbox`, `badge`, `dot`, `chip`, `legend_row`, `brace_v/brace_h`,
`lanes`/`cycle_guides`/`sigwave`/`bus_cells`/`phase_bar`/`txn_mark`, `footer`,
`pad_limits`, `qa_report`, `save`. Run Python as `py -3`. Grep `^def ` in
`_figstyle.py` for signatures.

Palette kinds: `cpu` `bus` `periph` `ctrl` `req` `addr` `write` `resp` `mem`
`mux` `alarm` `note` `plain` `dark`. Colours `fs.ACCENT MID GREEN RED ORANGE
GREY S_REQ S_ADDR S_WRITE S_RESP S_ALARM`. Canvas: 1 unit = 0.1 inch; a slide
canvas is about 125 x 59 units.

---

## 6. Final message format

Per figure, in this order:
1. **Verdict** — one of: `flows`, `cluttered`, `unclear`, `needs split`.
2. **Diagnosis** — 2-4 bullets, each naming the *specific* thing that fails
   (e.g. "no entry point: the eye lands on the note box, not the datapath").
3. **Action taken in place** — what you changed, or "none".
4. **Split proposal** (only if needed) — proposed filenames, and for each: the
   one-sentence takeaway that becomes its title.

Then a final line: QA status.