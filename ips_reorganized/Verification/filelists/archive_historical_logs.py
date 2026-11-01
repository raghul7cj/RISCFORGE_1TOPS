#!/usr/bin/env python3
"""
archive_historical_logs.py — Safely archives loose historical simulation logs
from IP component folders into Verification/artifacts/historical_logs/
with SHA-256 verification and an immutable JSON provenance manifest.
"""

import os
import sys
import shutil
import hashlib
import json
from datetime import datetime, timezone

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARCHIVE_ROOT = os.path.join(BASE_DIR, "Verification", "artifacts", "historical_logs")

# Candidate historical log files to archive from component folders
CANDIDATE_LOGS = [
    # gpio-master
    "gpio-master/xrun_v1.log",
    "gpio-master/xrun_v2.log",
    "gpio-master/xrun_v3.log",
    "gpio-master/xrun_v4.log",
    "gpio-master/xrun.log",
    "gpio-master/xvlog.log",
    "gpio-master/xvlog.pb",
    # aon_timer
    "aon_timer/xrun_1.log",
    "aon_timer/xrun_2.log",
    "aon_timer/xrun_full_1.log",
    "aon_timer/xrun_full_2.log",
    "aon_timer/xrun_full_3.log",
    "aon_timer/xrun_full_4.log",
    "aon_timer/xrun_fullv2_1.log",
    "aon_timer/xrun_fullv2_2.log",
    "aon_timer/xrun_fullv2_3.log",
    "aon_timer/xrun_fullv2_4.log",
    # apb_i2c-master
    "apb_i2c-master/directed.log.txt",
    "apb_i2c-master/xrun.log",
    # bootloader
    "bootloader/xrun_after_linting.log",
    "bootloader/xrun_bootloader_basic_tb.log",
    "bootloader/xrun_bootloader_tb_all_testcases.log",
    "bootloader/xrun_bootloader_tb_barebone.log",
]

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def main():
    print(f"Archiving loose historical component logs to: {ARCHIVE_ROOT}")
    os.makedirs(ARCHIVE_ROOT, exist_ok=True)
    
    manifest_records = []
    migrated_count = 0
    errors = 0
    
    for rel_path in CANDIDATE_LOGS:
        src_path = os.path.join(BASE_DIR, rel_path)
        if not os.path.isfile(src_path):
            continue
            
        dest_rel = os.path.join(ARCHIVE_ROOT, rel_path)
        os.makedirs(os.path.dirname(dest_rel), exist_ok=True)
        
        src_hash = sha256_file(src_path)
        src_size = os.path.getsize(src_path)
        
        # Copy file
        shutil.copy2(src_path, dest_rel)
        dest_hash = sha256_file(dest_rel)
        
        if src_hash != dest_hash:
            print(f"[ERROR] Hash mismatch copying {rel_path}!")
            errors += 1
            continue
            
        # Remove original loose file after verified copy
        os.remove(src_path)
        
        record = {
            "original_path": rel_path.replace("\\", "/"),
            "archive_path": os.path.relpath(dest_rel, BASE_DIR).replace("\\", "/"),
            "sha256": src_hash,
            "bytes": src_size,
            "archived_at_utc": datetime.now(timezone.utc).isoformat()
        }
        manifest_records.append(record)
        migrated_count += 1
        print(f"  [ARCHIVED] {record['original_path']} -> {record['archive_path']} ({src_size} bytes)")
        
    manifest_data = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "total_archived_files": migrated_count,
        "files": manifest_records
    }
    
    manifest_file = os.path.join(ARCHIVE_ROOT, "MANIFEST.json")
    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2)
        
    print(f"\nManifest written to: {manifest_file}")
    print(f"Total files archived: {migrated_count} | Errors: {errors}")
    return errors

if __name__ == "__main__":
    sys.exit(main())
