#!/usr/bin/env python3
# =============================================================================
# run_regression.py — Regression runner for RV32I LSU UVM Verification Project
# Runs all tests × seeds through Cadence Xcelium (run_xrun.sh), parses the
# logs and prints a summary report.
#
# Usage:
#   python3 run_regression.py            # run full regression
#   python3 run_regression.py --clean    # delete all simulation outputs
#
# All artifacts live under sim/<test>_<seed>/ (created by run_xrun.sh).
# =============================================================================

import subprocess
import os
import glob
import re
import sys
import shutil
from datetime import datetime

# ── Configuration ─────────────────────────────────────────────────────────────
TESTS = [
    "lsu_smoke_test",
    "lsu_coverage_test",
    "lsu_stress_test",
    "lsu_regression_test",
]

SEEDS = [1001, 2002, 3003, 4004, 5005]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SIM_ROOT = os.path.join(SCRIPT_DIR, "sim")

CLEAN_PATHS = [
    SIM_ROOT,
    os.path.join(SCRIPT_DIR, "xcelium.d"),
    os.path.join(SCRIPT_DIR, "cov_work"),
    os.path.join(SCRIPT_DIR, "work"),
]
CLEAN_GLOBS = ["xrun_*.log", "xrun_*.history", "vsim_*.log", "transcript"]

# ── Log parser ────────────────────────────────────────────────────────────────
def parse_log(path):
    """Return (passed:bool, errors:list[str])."""
    if not os.path.exists(path):
        return False, ["Log file missing"]

    errors   = []
    all_pass = False

    with open(path) as f:
        for line in f:
            if "ALL FUNCTIONAL AND ALIGNMENT CHECKS PASSED" in line or "ALL CHECKS PASSED" in line:
                all_pass = True
            if "*F," in line:
                all_pass = False
                errors.append(line.strip())
            if re.search(r"UVM_ERROR\s*:\s+[1-9]", line) or re.search(r"UVM_FATAL\s*:\s+[1-9]", line):
                all_pass = False
                errors.append(line.strip())
            if "UVM_ERROR" in line and "REPORT SUMMARY" not in line and "Report counts" not in line \
               and not re.search(r"UVM_ERROR\s*:\s+0", line):
                m = re.search(r'(UVM_ERROR)\s+\S+.*?:\s+(.*)', line)
                if m:
                    all_pass = False
                    errors.append(f"{m.group(1)}: {m.group(2).strip()}")

    return all_pass, errors

# ── Helpers ───────────────────────────────────────────────────────────────────
def run(cmd):
    return subprocess.run(cmd, shell=True, cwd=SCRIPT_DIR).returncode

def print_report(results):
    ts     = datetime.now().strftime("%Y-%m-%d %H:%M")
    total  = len(results)
    passed = sum(1 for v in results.values() if v[0])
    failed = total - passed

    bar = "=" * 62
    print(f"\n{bar}")
    print(f"  RV32I LSU REGRESSION REPORT   {ts}")
    print(bar)
    print(f"  Total: {total}   PASS: {passed}   FAIL: {failed}")
    print(bar)

    for test in TESTS:
        t_pass = sum(1 for s in SEEDS if results.get((test, s), (False,))[0])
        print(f"\n  [{t_pass}/{len(SEEDS)}]  {test}")
        for seed in SEEDS:
            ok, errs = results.get((test, seed), (False, ["not run"]))
            tag = "PASS" if ok else "FAIL"
            print(f"         seed={seed}  {tag}")
            for e in errs[:2]:
                print(f"           !! {e}")

    print(f"\n{bar}")
    if failed == 0:
        print("  >>> ALL RV32I LSU TESTS PASSED <<<")
    else:
        print(f"  >>> {failed} TESTS FAILED <<<")
    print(f"{bar}\n")

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    if "--clean" in sys.argv:
        print("Cleaning simulation outputs...")
        for p in CLEAN_PATHS:
            if os.path.isdir(p):
                shutil.rmtree(p)
        for pattern in CLEAN_GLOBS:
            for p in glob.glob(os.path.join(SCRIPT_DIR, pattern)):
                os.remove(p)
        print("Done. Removed: sim/, xcelium.d/, cov_work/, work/, stray logs")
        return

    print("[1/2] Running regression via Cadence Xcelium (run_xrun.sh)...")
    print(f"[2/2] Running {len(TESTS)} tests × {len(SEEDS)} seeds...\n")
    results = {}

    for test in TESTS:
        for seed in SEEDS:
            print(f"  {test}  seed={seed}", end="  ", flush=True)
            run(f"./run_xrun.sh {test} {seed} > /dev/null 2>&1")
            log  = os.path.join(SIM_ROOT, f"{test}_{seed}", f"xrun_{test}_{seed}.log")
            ok, errs = parse_log(log)
            results[(test, seed)] = (ok, errs)
            print("PASS" if ok else "FAIL")

    print_report(results)

if __name__ == "__main__":
    main()
