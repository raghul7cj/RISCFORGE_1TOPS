#!/usr/bin/env python3
"""Validate a diagram spec against source files, then render Mermaid.

Usage:  python3 diagram_tool.py SPEC.json --root PATH_TO_CHECKOUT [--out DIR]

Exit code 0 only if every drawn element is backed by ground truth.
Stdlib only. The rendered diagram contains nothing that is not in the spec.
"""
import argparse, hashlib, json, os, re, sys

STATUS = {"present", "planned", "absent", "uninspected"}
WINDOW = 3  # a cited symbol must occur within +/- WINDOW lines of the cited line


def check_source(src, root, errs, where, need_symbol=True):
    path = src.get("path")
    if not path:
        errs.append(f"{where}: source.path missing"); return
    full = os.path.join(root, path)
    if not os.path.isfile(full):
        errs.append(f"{where}: file not found: {path}"); return
    text = open(full, encoding="utf-8", errors="ignore").read().splitlines()
    sym, line = src.get("symbol"), src.get("line")
    if need_symbol and not sym:
        errs.append(f"{where}: source.symbol missing"); return
    if sym:
        if line:
            lo, hi = max(0, line - 1 - WINDOW), min(len(text), line + WINDOW)
            if not any(sym in l for l in text[lo:hi]):
                errs.append(f"{where}: symbol {sym!r} not within +/-{WINDOW} lines of {path}:{line}")
        elif not any(sym in l for l in text):
            errs.append(f"{where}: symbol {sym!r} not found in {path}")


def validate(spec, root):
    errs = []
    for k in ("title", "scope", "baseline", "nodes", "edges"):
        if k not in spec:
            errs.append(f"spec: missing '{k}'")
    if errs:
        return errs
    if not spec["baseline"].get("commit"):
        errs.append("baseline.commit missing (a diagram must name the source identity)")
    ids = set()
    for n in spec["nodes"]:
        w = f"node {n.get('id')}"
        if n.get("id") in ids:
            errs.append(f"{w}: duplicate id")
        ids.add(n.get("id"))
        st = n.get("status")
        if st not in STATUS:
            errs.append(f"{w}: status must be one of {sorted(STATUS)}"); continue
        if st == "present":
            check_source(n.get("source", {}), root, errs, w)
        elif st == "planned":
            check_source(n.get("source", {}), root, errs, w + " (plan doc)", need_symbol=True)
        elif st == "absent" and not n.get("note"):
            errs.append(f"{w}: absent needs a 'note' naming what was searched")
    for e in spec["edges"]:
        w = f"edge {e.get('from')}->{e.get('to')}"
        if e.get("from") not in ids or e.get("to") not in ids:
            errs.append(f"{w}: endpoint is not a declared node"); continue
        st = e.get("status")
        if st not in STATUS:
            errs.append(f"{w}: status must be one of {sorted(STATUS)}"); continue
        if st in ("present", "planned"):
            check_source(e.get("source", {}), root, errs, w)
        if st == "present":
            for end in (e["from"], e["to"]):
                nn = next(x for x in spec["nodes"] if x["id"] == end)
                if nn["status"] != "present":
                    errs.append(f"{w}: a present edge cannot touch a {nn['status']} node ({end})")
    return errs


def mm_id(s):
    return re.sub(r"\W", "_", s)


def render(spec):
    L = ["```mermaid", "flowchart LR"]
    for n in spec["nodes"]:
        tag = {"present": "", "planned": " (planned)", "absent": " (absent)", "uninspected": " (?)"}[n["status"]]
        lab = (n["label"] + tag).replace('"', "'")
        L.append(f'  {mm_id(n["id"])}["{lab}"]:::{n["status"]}')
    for e in spec["edges"]:
        a, b = mm_id(e["from"]), mm_id(e["to"])
        lab = e.get("label", "").replace('"', "'")
        arrow = "-->" if e["status"] == "present" else "-.->"
        L.append(f'  {a} {arrow}|"{lab}"| {b}' if lab else f"  {a} {arrow} {b}")
    L += ["  classDef present fill:#e8f1ff,stroke:#2b6cb0,color:#111",
          "  classDef planned fill:#fff8e1,stroke:#b7791f,stroke-dasharray:5 3,color:#111",
          "  classDef absent fill:#fdecea,stroke:#c53030,stroke-dasharray:2 2,color:#111",
          "  classDef uninspected fill:#f2f2f2,stroke:#888,stroke-dasharray:2 4,color:#444",
          "```"]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec"); ap.add_argument("--root", required=True); ap.add_argument("--out")
    a = ap.parse_args()
    raw = open(a.spec, encoding="utf-8").read()
    spec = json.loads(raw)
    errs = validate(spec, a.root)
    if errs:
        print("REJECTED: diagram is not fully backed by ground truth")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    h = hashlib.sha256(raw.encode()).hexdigest()[:12]
    b = spec["baseline"]
    parts = [f"# {spec['title']}", "", f"Scope: {spec['scope']}", "", render(spec), "",
             f"Source identity: `{b.get('repo','')}` @ `{b['commit']}`. Spec: `{os.path.basename(a.spec)}` (sha256 `{h}`).",
             "", "| Element | Status | Source | Symbol |", "|---|---|---|---|"]
    for kind, items in (("node", spec["nodes"]), ("edge", spec["edges"])):
        for x in items:
            name = x["id"] if kind == "node" else f"{x['from']} -> {x['to']}"
            s = x.get("source", {})
            loc = f"{s.get('path','')}:{s['line']}" if s.get("line") else s.get("path", x.get("note", "-"))
            parts.append(f"| {name} | {x['status']} | `{loc}` | `{s.get('symbol','')}` |")
    if spec.get("unknowns"):
        parts += ["", "Unknown / not inspected (deliberately not drawn as fact):"] + [f"- {u}" for u in spec["unknowns"]]
    out = "\n".join(parts) + "\n"
    if a.out:
        os.makedirs(a.out, exist_ok=True)
        p = os.path.join(a.out, os.path.splitext(os.path.basename(a.spec))[0].replace(".spec", "") + ".md")
        open(p, "w", encoding="utf-8").write(out); print("OK", p)
    else:
        print(out)


if __name__ == "__main__":
    main()
