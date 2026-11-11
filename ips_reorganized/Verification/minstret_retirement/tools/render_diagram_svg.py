"""Render validated ground-truth JSON specs as accessible, self-contained SVG.

Run diagram_tool.py first. This renderer validates again before drawing. Layout
coordinates are presentation metadata; node/edge labels and citations come only
from the saved spec. The same spec also generates the GitHub Mermaid document.
"""
import argparse
import html
import json
from pathlib import Path
from diagram_tool import validate

parser = argparse.ArgumentParser()
parser.add_argument("spec", type=Path)
parser.add_argument("--root", type=Path, required=True)
args = parser.parse_args()
spec = json.loads(args.spec.read_text(encoding="utf-8"))
errors = validate(spec, str(args.root))
if errors:
    raise SystemExit("\n".join(errors))
nodes = {n["id"]: n for n in spec["nodes"]}
width, height = spec["layout"]["width"], spec["layout"]["height"]
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
       '<title id="title">' + html.escape(spec["title"]) + '</title>',
       '<desc id="desc">' + html.escape(spec["scope"]) + '</desc>',
       '<style>text{font:13px system-ui,sans-serif;fill:#18202c}.box{fill:#eef4fc;stroke:#345e98;stroke-width:1.3}.arrow{stroke:#526879;stroke-width:1.5;fill:none;marker-end:url(#head)}.label{font-size:11px;fill:#475063}</style>',
       '<defs><marker id="head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 Z" fill="#526879"/></marker></defs>']
for edge in spec["edges"]:
    # Explicit waypoints route the layout, without introducing factual elements.
    points = edge["route"]
    path = "M" + " L".join(f"{x},{y}" for x, y in points)
    svg.append(f'<path class="arrow" d="{path}"><title>{html.escape(edge["source"]["path"] + " :: " + edge["source"]["symbol"])}</title></path>')
    x, y = edge["label_at"]
    svg.append(f'<text class="label" x="{x}" y="{y}">{html.escape(edge["label"])}</text>')
for node in spec["nodes"]:
    x, y, w, h = node["box"]
    svg.append(f'<g><title>{html.escape(node["source"]["path"] + " :: " + node["source"]["symbol"])}</title><rect class="box" x="{x}" y="{y}" width="{w}" height="{h}" rx="8"/>')
    for i, line in enumerate(node["label"].split(" / ")):
        svg.append(f'<text x="{x+12}" y="{y+23+i*19}">{html.escape(line)}</text>')
    svg.append('</g>')
svg.append('</svg>')
out = args.spec.with_name(args.spec.name.replace(".spec.json", ".svg"))
out.write_text("\n".join(svg) + "\n", encoding="utf-8")
print("OK", out)
