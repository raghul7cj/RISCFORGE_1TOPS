#!/usr/bin/env python3
"""
validate_filelists.py — Rigorous validator for RISCFORGE 1TOPS 3-tier filelists.
Validates:
1. 100% path existence on disk for files and +incdir+ directories.
2. POSIX separator convention ('/') without Windows backslashes.
3. No absolute paths (all relative to rtl/ips).
4. Case sensitivity integrity against Windows filesystem.
5. Crosswalk alignment with TESTBENCH_CROSSWALK.csv.
"""

import os
import sys
import csv
import re

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FILELISTS_DIR = os.path.join(BASE_DIR, "Verification", "filelists")
CROSSWALK_CSV = os.path.join(FILELISTS_DIR, "TESTBENCH_CROSSWALK.csv")

def get_real_case_path(root, rel_path):
    """
    Traverse path components from root checking actual on-disk casing.
    Returns (matches_case: bool, real_rel_path: str, exists: bool)
    """
    parts = rel_path.replace("\\", "/").split("/")
    curr = root
    real_parts = []
    for part in parts:
        if not part or part == ".":
            continue
        if part == "..":
            curr = os.path.dirname(curr)
            real_parts.append("..")
            continue
        try:
            entries = os.listdir(curr)
        except OSError:
            return False, rel_path, False
        
        # Check exact case
        if part in entries:
            real_parts.append(part)
            curr = os.path.join(curr, part)
        else:
            # Check case-insensitive match
            lower_map = {e.lower(): e for e in entries}
            if part.lower() in lower_map:
                real_name = lower_map[part.lower()]
                real_parts.append(real_name)
                curr = os.path.join(curr, real_name)
            else:
                return False, rel_path, False
                
    real_rel = "/".join(real_parts)
    matches = (real_rel == rel_path)
    return matches, real_rel, True

def parse_filelist(f_path):
    """Parses a .f file into include dirs, source files, and options."""
    inc_dirs = []
    src_files = []
    options = []
    
    with open(f_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
            
        if line.startswith("+incdir+"):
            d = line[len("+incdir+"):].strip()
            inc_dirs.append(d)
        elif line.startswith("-incdir") or line.startswith("-i"):
            parts = line.split(maxsplit=1)
            if len(parts) > 1:
                inc_dirs.append(parts[1].strip())
        elif line.startswith("-") or line.startswith("+"):
            options.append(line)
        else:
            # File path
            src_files.append(line)
            
    return inc_dirs, src_files, options

def main():
    print(f"==================================================================")
    print(f"RISCFORGE 1TOPS — 3-Tier Forwarding Filelists Validation")
    print(f"Root: {BASE_DIR}")
    print(f"==================================================================")
    
    # 1. Check Crosswalk CSV
    if not os.path.isfile(CROSSWALK_CSV):
        print(f"[FATAL] TESTBENCH_CROSSWALK.csv not found at {CROSSWALK_CSV}")
        sys.exit(1)
        
    with open(CROSSWALK_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        crosswalk_rows = list(reader)
        
    print(f"Crosswalk targets found: {len(crosswalk_rows)}")
    
    total_files_checked = 0
    total_incdirs_checked = 0
    total_remote_prereqs = 0
    total_errors = 0
    case_warnings = 0
    
    tier_stats = {"tier1_unit": 0, "tier2_subsystem": 0, "tier3_soc": 0}
    
    for row in crosswalk_rows:
        test_id = row["test_id"]
        tier = row["tier"]
        fl_rel = row["filelist_path"]
        bench_path = row["bench_path"]
        elaboration_top = row["elaboration_top"]
        notes = row.get("notes", "")
        
        tier_stats[tier] = tier_stats.get(tier, 0) + 1
        
        fl_abs = os.path.join(BASE_DIR, fl_rel)
        if not os.path.isfile(fl_abs):
            print(f"[{test_id}] [ERROR] Filelist does not exist: {fl_rel}")
            total_errors += 1
            continue
            
        inc_dirs, src_files, options = parse_filelist(fl_abs)
        print(f"\n--- [{tier}] {test_id} ({fl_rel}) ---")
        print(f"  Includes: {len(inc_dirs)} | Sources: {len(src_files)} | Flags: {len(options)}")
        
        # Check bench_path if not design-only
        if bench_path != "none" and not os.path.isabs(bench_path):
            bench_abs = os.path.join(BASE_DIR, bench_path)
            if not os.path.exists(bench_abs):
                print(f"  [ERROR] Crosswalk bench_path missing on disk: {bench_path}")
                total_errors += 1
        
        is_remote_eda_prereq_target = "remote OpenTitan prim library" in notes
        
        # Validate IncDirs
        for d in inc_dirs:
            total_incdirs_checked += 1
            if "\\" in d:
                print(f"  [ERROR] Windows backslash in incdir: {d}")
                total_errors += 1
            if os.path.isabs(d):
                print(f"  [ERROR] Absolute path in incdir: {d}")
                total_errors += 1
            d_norm = d.replace("\\", "/")
            match_case, real_path, exists = get_real_case_path(BASE_DIR, d_norm)
            if not exists:
                if is_remote_eda_prereq_target and "watchdog" in d:
                    print(f"  [REMOTE PREREQ] Remote EDA include directory: {d}")
                    total_remote_prereqs += 1
                else:
                    print(f"  [ERROR] Missing include directory: {d}")
                    total_errors += 1
            elif not match_case:
                print(f"  [WARN] Case mismatch in include directory: '{d}' (on disk: '{real_path}')")
                case_warnings += 1
                
        # Validate Source Files
        for s in src_files:
            total_files_checked += 1
            if "\\" in s:
                print(f"  [ERROR] Windows backslash in source file: {s}")
                total_errors += 1
            if os.path.isabs(s):
                print(f"  [ERROR] Absolute path in source file: {s}")
                total_errors += 1
            s_norm = s.replace("\\", "/")
            match_case, real_path, exists = get_real_case_path(BASE_DIR, s_norm)
            if not exists:
                if is_remote_eda_prereq_target and "watchdog" in s:
                    # Documented remote OpenTitan primitive on CentOS
                    total_remote_prereqs += 1
                else:
                    print(f"  [ERROR] Missing source file: {s}")
                    total_errors += 1
            elif not match_case:
                print(f"  [WARN] Case mismatch in source file: '{s}' (on disk: '{real_path}')")
                case_warnings += 1

    print(f"\n==================================================================")
    print(f"Validation Summary:")
    print(f"  Total Targets: {len(crosswalk_rows)} (Tier 1: {tier_stats['tier1_unit']}, Tier 2: {tier_stats['tier2_subsystem']}, Tier 3: {tier_stats['tier3_soc']})")
    print(f"  Total Source Files Checked: {total_files_checked}")
    print(f"  Total Include Dirs Checked: {total_incdirs_checked}")
    print(f"  Documented Remote EDA Prereqs (CentOS OpenTitan): {total_remote_prereqs}")
    print(f"  Case Warnings: {case_warnings}")
    print(f"  Total Errors: {total_errors}")
    print(f"==================================================================")
    
    if total_errors == 0:
        print("[SUCCESS] 100% of forwarding filelists and local referenced assets are VALID!")
        return 0
    else:
        print(f"[FAIL] {total_errors} errors encountered.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
