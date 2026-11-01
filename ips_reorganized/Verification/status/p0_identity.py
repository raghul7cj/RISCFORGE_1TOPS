#!/usr/bin/env python3
"""P0 Identity and Execution Contract Manifest Generator.

Implements the Rev B Table 21.10 identity recipe and checks ID-1, ID-2, ID-3.
Baseline: RISCFORGE_Verification_Plan_RevB.docx, Section 21, Tables 5.2, 21.10, 21.11.

Generates:
  - Verification/status/P0_MANIFEST.json
  - Verification/status/manifest_rtl.sha256
"""

import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
IPS_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FILELIST_PATH = os.path.join(IPS_ROOT, "RTL_SOC", "soc_subsystem.f")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def compute_h_filelist(filelist_path: str) -> str:
    """Normalize filelist to LF line endings and compute SHA-256."""
    with open(filelist_path, "rb") as f:
        content = f.read()
    # Normalize CRLF to LF
    content = content.replace(b"\r\n", b"\n")
    return sha256_bytes(content)


def parse_filelist(filelist_path: str):
    """Parse filelist into (source_files, incdirs, tool_flags, raw_entries)."""
    source_files = []
    incdirs = []
    flags = []
    unresolved = []
    absolute = []

    with open(filelist_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue

            # Tool flags
            if line.startswith("-"):
                flags.append(line)
                continue

            # Include directories
            if line.startswith("+incdir+"):
                incdir = line[len("+incdir+"):].strip()
                posix_inc = incdir.replace("\\", "/")
                if os.path.isabs(incdir) or ":" in incdir:
                    absolute.append((line_num, incdir))
                resolved = os.path.normpath(os.path.join(IPS_ROOT, incdir))
                if not os.path.isdir(resolved):
                    unresolved.append((line_num, incdir))
                incdirs.append(posix_inc)
                continue

            # Source file
            posix_path = line.replace("\\", "/")
            if os.path.isabs(line) or ":" in line:
                absolute.append((line_num, line))

            resolved_file = os.path.normpath(os.path.join(IPS_ROOT, line))
            if not os.path.isfile(resolved_file):
                unresolved.append((line_num, line))
            else:
                source_files.append((posix_path, resolved_file))

    return source_files, incdirs, flags, unresolved, absolute


def check_id1_divergent_files():
    """Check ID-1: duplicate file basenames across repository with divergent content."""
    divergent_groups = []
    seen = {}

    for root, _, files in os.walk(IPS_ROOT):
        # Exclude artifacts, xsim.dir, git, backup directories
        rel_root = os.path.relpath(root, IPS_ROOT).replace("\\", "/")
        if any(ign in rel_root for ign in [".git", "xsim.dir", "artifacts", "build", ".agents", "old files"]):
            continue

        for f in files:
            if not (f.endswith(".v") or f.endswith(".sv") or f.endswith(".svh")):
                continue
            full_path = os.path.join(root, f)
            h = sha256_file(full_path)
            seen.setdefault(f, []).append((full_path, h))

    for fname, instances in seen.items():
        if len(instances) > 1:
            hashes = {h for _, h in instances}
            if len(hashes) > 1:
                divergent_groups.append({
                    "filename": fname,
                    "instances": [{"path": os.path.relpath(p, IPS_ROOT).replace("\\", "/"), "sha256": h} for p, h in instances]
                })

    return divergent_groups


def generate_manifest():
    print(f"[P0-IDENTITY] Parsing master filelist: {os.path.relpath(FILELIST_PATH, IPS_ROOT)}")
    source_files, incdirs, flags, unresolved, absolute = parse_filelist(FILELIST_PATH)

    id2_unresolved_count = len(unresolved)
    id3_absolute_count = len(absolute)

    if id2_unresolved_count > 0:
        print(f"[ERROR] ID-2 violation: {id2_unresolved_count} unresolved entries:")
        for lnum, p in unresolved:
            print(f"  Line {lnum}: {p}")
        sys.exit(1)

    if id3_absolute_count > 0:
        print(f"[ERROR] ID-3 violation: {id3_absolute_count} absolute paths:")
        for lnum, p in absolute:
            print(f"  Line {lnum}: {p}")
        sys.exit(1)

    # Compute H_filelist
    h_filelist = compute_h_filelist(FILELIST_PATH)
    print(f"[P0-IDENTITY] H_filelist: {h_filelist}")

    # Compute raw file hashes
    file_hashes = []
    for posix_path, full_path in source_files:
        h = sha256_file(full_path)
        file_hashes.append((posix_path, h))

    # Sort byte-wise by POSIX path (ASCII order) per Rev B Table 21.10
    file_hashes.sort(key=lambda x: x[0].encode("utf-8"))

    # Emit <sha256><two spaces><path> with LF line endings
    manifest_lines = [f"{h}  {path}" for path, h in file_hashes]
    manifest_bytes = ("\n".join(manifest_lines) + "\n").encode("utf-8")

    manifest_sha_path = os.path.join(HERE, "manifest_rtl.sha256")
    with open(manifest_sha_path, "wb") as f:
        f.write(manifest_bytes)

    # Compute H_rtl (SHA-256 over the exact byte sequence of manifest_rtl.sha256)
    h_rtl = sha256_bytes(manifest_bytes)
    print(f"[P0-IDENTITY] H_rtl: {h_rtl} (across {len(file_hashes)} design files)")

    # Check ID-1
    divergent_groups = check_id1_divergent_files()
    id1_count = len(divergent_groups)
    print(f"[P0-IDENTITY] ID-1 divergent file groups: {id1_count}")
    for g in divergent_groups:
        print(f"  Divergent: {g['filename']}")

    # Build P0 Manifest Record
    manifest_record = {
        "manifest_version": "1.0",
        "phase": "P0",
        "description": "RISCFORGE P0 Bring-up Execution Contract & Golden Identity Manifest",
        "contract": {
            "golden_filelist": os.path.relpath(FILELIST_PATH, IPS_ROOT).replace("\\", "/"),
            "canonical_filelist": os.path.relpath(FILELIST_PATH, IPS_ROOT).replace("\\", "/"),
            "tool_pins": {
                "simulator": "AMD Vivado XSim v2022.2 (64-bit, SW Build 3671981)",
                "toolchain": "GNU RISC-V GCC 13.2.0 (riscv64-unknown-elf-gcc via WSL Ubuntu)",
                "python": "CPython 3.12"
            },
            "parameters": {
                "boot_mode": "WARM",
                "timeout_cycles": 1000000,
                "seed": "none"
            },
            "pass_predicates": {
                "g0_harness_integrity": {
                    "unresolved_modules": 0,
                    "extra_modules": 0,
                    "artifact_write_test": "PASS",
                    "build_logs_retained": "YES"
                },
                "g1_stimulus_reached_dut": {
                    "instructions_retired_gt_0": True,
                    "axi_transfers_gt_0": True,
                    "apb_transfers_gt_0": True,
                    "attestation_words_written_gt_0": True
                }
            }
        },
        "identity": {
            "H_rtl": h_rtl,
            "H_filelist": h_filelist,
            "ID_1_divergent_reachable_groups": id1_count,
            "ID_2_unresolved_entries": id2_unresolved_count,
            "ID_3_absolute_path_entries": id3_absolute_count,
            "design_files_count": len(file_hashes),
            "manifest_file": os.path.relpath(manifest_sha_path, IPS_ROOT).replace("\\", "/")
        },
        "divergent_groups_detail": divergent_groups,
        "empirical_proof_baseline": {
            "run_id": "20261024_stage3_monitor_count",
            "verdict": "PASSED",
            "retired_instructions": 5551,
            "axi_reads": 14,
            "axi_writes": 4,
            "apb_transfers": 18,
            "fw_attestation": "0x0004000e",
            "attestation_words_written": 1,
            "fatal_checks": 0
        }
    }

    manifest_json_path = os.path.join(HERE, "P0_MANIFEST.json")
    with open(manifest_json_path, "w", encoding="utf-8") as f:
        json.dump(manifest_record, f, indent=2)

    print(f"[P0-IDENTITY] Stamped P0 Manifest: {os.path.relpath(manifest_json_path, IPS_ROOT)}")
    return manifest_record


if __name__ == "__main__":
    generate_manifest()
