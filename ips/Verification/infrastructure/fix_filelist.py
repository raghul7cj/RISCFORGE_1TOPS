#!/usr/bin/env python3
"""Validate and auto-fix every file path in soc_verification.f against the tree."""
import os, re, sys

INFRA = os.path.dirname(os.path.abspath(__file__))
REPO  = os.path.abspath(os.path.join(INFRA, "..", ".."))
FLIST = os.path.join(INFRA, "soc_verification.f")

def resolve(rel):
    return os.path.normpath(os.path.join(INFRA, rel))

def find_basename(basename):
    hits = []
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in
                   ("xsim.dir", ".git", "old files", "chall_run", "node_modules")]
        for f in files:
            if f == basename:
                hits.append(os.path.relpath(os.path.join(root, f), INFRA))
    return hits

out, fixed, missing = [], [], []
for line in open(FLIST, encoding="utf-8", errors="replace").read().splitlines():
    s = line.strip()
    if not s or s.startswith("//") or s.startswith("+"):
        out.append(line); continue
    if resolve(s.replace("\\", "/")).replace("\\", "/") and os.path.isfile(resolve(s)):
        out.append(line); continue
    base = os.path.basename(s)
    hits = find_basename(base)
    if len(hits) == 1:
        out.append(hits[0].replace("\\", "/"))
        fixed.append((s, hits[0]))
    elif len(hits) > 1:
        # Prefer a hit that is not inside a testbench directory
        pref = [h for h in hits if os.sep + "tb" + os.sep not in h]
        if len(pref) == 1:
            out.append(pref[0].replace("\\", "/")); fixed.append((s, pref[0]))
        else:
            missing.append((s, hits)); out.append(line)
    else:
        missing.append((s, [])); out.append(line)

open(FLIST, "w", encoding="utf-8").write("\n".join(out) + "\n")

print(f"REPAIRED {len(fixed)} path(s):")
for a, b in fixed:
    print(f"   {a}\n -> {b}")
if missing:
    print(f"\nUNRESOLVED {len(missing)} (not present anywhere in the tree):")
    for a, hits in missing:
        print(f"   {a}   candidates={hits}")
else:
    print("\nAll filelist paths resolve.")
