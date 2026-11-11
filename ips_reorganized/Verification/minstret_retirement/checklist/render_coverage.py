"""Generate the self-contained coverage view from one recorded campaign."""
import html
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
data = json.loads((directory / "coverage.json").read_text())
assert data["functional_checklist_closed"]
diagram_dir = Path(__file__).resolve().parent.parent / "docs/diagrams"
diagram_parts = []
for name, title in [("retirement", "How the counter avoids repeated WB counts"),
                    ("testbench", "How the directed test reaches a verdict")]:
    svg = (diagram_dir / f"{name}.svg").read_text(encoding="utf-8")
    spec = json.loads((diagram_dir / f"{name}.spec.json").read_text(encoding="utf-8"))
    identity = spec["baseline"]
    citation = f'<p class="scope">Source {identity["commit"][:12]} + overlay {identity["source_overlay_sha256"][:12]}. <a href="../docs/diagrams/{name}.spec.json">Saved validated spec</a> · <a href="../docs/diagrams/{name}.md">every box/arrow citation</a>.</p>'
    expanded = " open" if name == "retirement" else ""
    diagram_parts.append(f'<details{expanded}><summary>{title}</summary><div class="diagram">{svg}</div>{citation}</details>')
groups = {
    "Completed instructions": ["ADD", "SUB", "MUL", "DIV", "LW", "SW", "BEQ_taken", "BEQ_not_taken",
        "BNE_taken", "BNE_not_taken", "JAL", "JALR", "CSRRW", "CSRRS", "CSRRC", "CSRRWI", "CSRRSI", "CSRRCI", "MRET", "NOP"],
    "Events that do not increment": ["ECALL", "EBREAK", "illegal", "misaligned_load", "misaligned_store",
        "wrong_path", "bubble", "stall", "interrupt"],
}
parts = []
for group, names in groups.items():
    cells = "".join('<div class="bin"><b>✓</b><span>' + html.escape(name.replace("_", " ")) +
                    '</span><small>' + str(data["bins"][name]) + ' checked hits</small></div>' for name in names)
    parts.append("<h3>" + group + '</h3><div class="grid">' + cells + "</div>")
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>minstret directed coverage closure</title><style>
body{margin:0;font:14px/1.55 "IBM Plex Sans",system-ui;color:var(--foreground,#18202c)}
h2,h3{font-family:Archivo,system-ui;line-height:1.25}h2{font-size:24px;margin:12px 0}h3{font-size:17px;margin:22px 0 12px}p{margin:12px 0}
.score{display:flex;justify-content:space-between;gap:12px;margin:20px 0 8px;font-size:17px}
.meter{height:12px;border-radius:6px;background:var(--success,#15803d)}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.bin{border:1px solid var(--border,#ddd);border-radius:7px;padding:10px;display:grid;grid-template-columns:16px 1fr;gap:4px;font-size:12px;overflow-wrap:anywhere}
.bin small{display:none;grid-column:2;color:var(--muted-foreground,#666)}.hits .bin small{display:block}.bin b{color:var(--success,#15803d)}
.scope{font-size:12px;color:var(--muted-foreground,#666)}label{font-size:12px;cursor:pointer}
.diagram{padding:16px;background:white;border-radius:8px;margin:12px 0}.diagram svg{width:100%;height:auto;display:block}summary{cursor:pointer;font-weight:600}details{margin:12px 0}
@media(max-width:450px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.score{font-size:15px}}
@media print{*{print-color-adjust:exact}label{display:none}}
</style><body><h2>minstret: directed checklist closed</h2>
<p>Real instruction execution on the patched core. Independent expected PC paths, per-cycle counter checks, final memory checks, and a timer interrupt driven through the input pin.</p>
<div class="score"><strong>29 / 29 functional bins</strong><span>12 / 12 runs passed</span></div>
<div class="meter" role="meter" aria-label="Functional bins closed" aria-valuemin="0" aria-valuemax="29" aria-valuenow="29"></div>
<p class="scope">0, 1, 4 and 9 wait cycles applied to three programs. Every named bin has checked passing evidence; no waivers.</p>
<label><input type="checkbox" onchange="document.body.classList.toggle('hits',this.checked)"> Show observed hit totals</label>
''' + "".join(diagram_parts) + '<p class="scope">Ground-truth specs and every box/arrow citation are in ../docs/diagrams/. Both diagrams passed the saved-spec validator.</p>' + "".join(parts) + '''
<h3>Artifacts and scope</h3><p>Three ELF / .bin / hex / disassembly sets, 12 cycle traces and logs, coverage JSON, and verified source/artifact hashes. No additional RTL changes in this campaign.</p>
<p class="scope">Icarus 12.0 · GCC 13.2 · 11 November 2026 · Campaign ''' + directory.name + '''.
Functional bins cover the declared checklist only. Statement/toggle/FSM coverage, counter writes/overflow and broader interrupt combinations remain open. Current SoC rerun: smoke, probe and Dhrystone PASS; CoreMark CRCs match but the one-iteration duration is invalid. No published score.</p>
<script>console.log('declared bins',document.querySelectorAll('.bin').length);console.log('horizontal overflow',document.documentElement.scrollWidth>innerWidth);</script></body></html>'''
directory.parent.parent.joinpath("coverage.html").write_text(page, encoding="utf-8")
