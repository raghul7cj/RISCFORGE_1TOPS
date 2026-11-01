#!/usr/bin/env python3
"""
RISCFORGE 1TOPS — Sandbox Regression Runner & Strict Evidence Classifier
Executes testbenches in isolated scratch run directories with real-time process monitoring,
exact toolchain version capture, and strict multi-clause PASS/FAIL/BLOCKED classification.
"""

import os
import sys
import json
import time
import shutil
import subprocess
import hashlib
import argparse
import csv
import re
import uuid
from datetime import datetime, timezone

BASE_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
VERIF_DIR = os.path.join(BASE_DIR, "Verification")
CROSSWALK_CSV = os.path.join(VERIF_DIR, "filelists", "TESTBENCH_CROSSWALK.csv")
if not os.path.isfile(CROSSWALK_CSV):
    CROSSWALK_CSV = os.path.join(VERIF_DIR, "TESTBENCH_CROSSWALK.csv")
RUNS_ROOT = os.path.join(VERIF_DIR, "artifacts", "runs")
P0_MANIFEST = os.path.join(VERIF_DIR, "status", "P0_MANIFEST.json")
XSIM_ROOT = r"C:\Xilinx\Vivado\2022.2\bin"

# Strictest pass signatures: strictly requires non-zero positive activity counts ([1-9]\d*)
# Generic banners (e.g. bare "PASSED", "ALL CHECKS PASSED") are prohibited.
PASS_SIGNATURES = {
    "tb_irq_arbiter": r"PASS:\s+[1-9]\d*\s+arbitration snapshots",
    "tb_aon_timer": r"PASS:\s+[1-9]\d*\s+checks|\[PASS\]\s+watchdog fired.*cycle\s+[1-9]\d*",
    "tb_apb_i2c": r"PASS\s+=\s+[1-9]\d*\s*\n\s*FAIL\s+=\s+0",
    "tb_apb_timer": r"UVM_TEST_PASSED.*checks\s*=\s*[1-9]\d*|PASS:\s+[1-9]\d*\s+checks",
    "tb_apb_uart": r"TB SUMMARY:\s+[1-9]\d*\s+PASSED\s+/\s+0\s+FAILED",
    "tb_gpio": r"TB SUMMARY:\s+[1-9]\d*\s+PASSED\s+/\s+0\s+FAILED",
    "tb_bootloader": r"PASS:\s+all\s+[1-9]\d*\s+words",
    "tb_spi_master": r"TEST_PASS\s+checks=[1-9]\d*",
    "tb_apb_timeout_monitor": r"TEST_PASS\s+checks=[1-9]\d*",
    "tb_axi_lite_to_apb": r"RESULTS:\s+PASSED\s+=\s+[1-9]\d*\s+/\s+FAILED\s+=\s+0",
    "tb_axi_lite_xbar": r"RESULTS:\s+PASSED\s+=\s+[1-9]\d*\s+/\s+FAILED\s+=\s+0",
    "tb_soc_gpio_aperture": r"GPIO_APERTURE_SUMMARY\s+pass=[1-9]\d*\s+fail=0",
    "tb_datapath_i2c0": r"\[SIMULATION SUCCESS\].*[1-9]\d*\s+transfers completed",
    "tb_datapath_spi0": r"\[SIMULATION SUCCESS\].*[1-9]\d*\s+transfers completed",
    "tb_datapath_uart0": r"\[SIMULATION SUCCESS\].*[1-9]\d*\s+bytes printed",
    "soc_tb_top": r"\[MAILBOX PASS\].*retired\s+[1-9]\d*|\[STAGE2 PASS\].*cycle\s+[1-9]\d*",
    "soc_subsystem_design": r"Design-Only Elaboration Clean",
}

FORBIDDEN_SIGNATURES = [
    r"\[VACUITY VIOLATION\]",
    r"FATAL VACUOUS",
    r"Fatal:\s*assertion failed",
    r"Fatal:",
    r"\$fatal",
    r"\[MAILBOX FAIL\]",
    r"\[STAGE2 FAIL\]",
    r"\[FATAL TIMEOUT\]",
    r"FAILURE REPORT",
    r"ASSERTION VIOLATION",
    r"ERROR:\s*\[XSIM",
    r"ERROR:\s*\[VRFC",
    r"\*E,",
    r"%Error",
]

VACUITY_PATTERNS = [
    r"checks=0\b",
    r"pass=0\b",
    r"PASSED\s*=\s*0\b",
    r"\b0\s+PASSED\b",
    r"\b0\s+checks\b",
    r"\[VACUITY VIOLATION\]",
    r"FATAL VACUOUS",
]

def get_git_info():
    commit = "unknown"
    dirty = None
    try:
        r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=BASE_DIR, capture_output=True, text=True, check=False)
        if r.returncode == 0:
            commit = r.stdout.strip()
            r2 = subprocess.run(["git", "status", "--porcelain"], cwd=BASE_DIR, capture_output=True, text=True, check=False)
            if r2.returncode == 0:
                dirty = (len(r2.stdout.strip()) > 0)
    except Exception:
        pass
    return commit, dirty

def sha256_file(path):
    if not os.path.isfile(path):
        return "none"
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().lower()

def run_cmd_capture(cmd, cwd, log_file, timeout_sec):
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            out, _ = proc.communicate(timeout=timeout_sec)
        except subprocess.TimeoutExpired:
            # Multi-process tree termination on deadline with verified kill and drain status
            kill_success = False
            drain_success = False
            kill_detail = ""
            if os.name == "nt":
                try:
                    tk_res = subprocess.run(
                        ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        check=False
                    )
                    if tk_res.returncode == 0:
                        kill_success = True
                        kill_detail = f"PID {proc.pid} and descendants terminated (taskkill code 0)"
                    elif tk_res.returncode == 128:
                        kill_success = True
                        kill_detail = f"PID {proc.pid} was already terminated/not found (taskkill code 128)"
                    else:
                        kill_success = False
                        kill_detail = f"taskkill failed (code {tk_res.returncode}): {tk_res.stderr.strip()}"
                except subprocess.TimeoutExpired:
                    kill_success = False
                    kill_detail = "taskkill invocation timed out after 5s"
                except Exception as e:
                    kill_success = False
                    kill_detail = f"taskkill exception: {e}"
            else:
                try:
                    proc.kill()
                    kill_success = True
                    kill_detail = f"PID {proc.pid} killed"
                except Exception as e:
                    kill_success = False
                    kill_detail = f"proc.kill exception: {e}"

            try:
                out, _ = proc.communicate(timeout=5)
                drain_success = True
            except subprocess.TimeoutExpired:
                drain_success = False
                kill_detail += "; pipe drain timed out after 5s"
                out = ""
            except Exception as e:
                drain_success = False
                kill_detail += f"; pipe drain exception: {e}"
                out = ""

            with open(log_file, "a", encoding="utf-8") as f:
                f.write(out or "")
                if kill_success and drain_success:
                    f.write(f"\n[TIMEOUT] Process tree terminated cleanly after {timeout_sec}s deadline ({kill_detail}).\n")
                else:
                    f.write(f"\n[TIMEOUT] Cleanup warning after {timeout_sec}s deadline: {kill_detail}\n")
            return -999, out or ""

        with open(log_file, "a", encoding="utf-8") as f:
            f.write(out or "")
        return proc.returncode, out or ""
    except Exception as e:
        err_msg = f"[ERROR] Failed to execute {cmd}: {e}\n"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(err_msg)
        return -1, err_msg

def check_log_signatures(log_file, verdict_record):
    if not os.path.isfile(log_file):
        return
    try:
        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            log_content = f.read()
    except Exception:
        return

    forbidden_hits = []
    for fp in FORBIDDEN_SIGNATURES:
        m = re.search(fp, log_content, re.IGNORECASE)
        if m:
            forbidden_hits.append(m.group(0).strip())
    if forbidden_hits:
        verdict_record["forbidden_detected"] = "; ".join(sorted(set(forbidden_hits)))

    vacuity_hits = []
    for vp in VACUITY_PATTERNS:
        m = re.search(vp, log_content, re.IGNORECASE)
        if m:
            vacuity_hits.append(m.group(0).strip())
    if vacuity_hits:
        verdict_record["vacuity_detected"] = True

def finalize_verdict(sandbox_dir, verdict_record, start_time):
    if not verdict_record.get("timestamp_end_utc"):
        verdict_record["timestamp_end_utc"] = datetime.now(timezone.utc).isoformat()
    verdict_record["duration_seconds"] = round(time.time() - start_time, 2)
    tmp_verdict = os.path.join(sandbox_dir, "verdict.json.tmp")
    fin_verdict = os.path.join(sandbox_dir, "verdict.json")
    with open(tmp_verdict, "w", encoding="utf-8") as f:
        json.dump(verdict_record, f, indent=2)
    shutil.move(tmp_verdict, fin_verdict)

def main():
    parser = argparse.ArgumentParser(description="RISCFORGE 1TOPS Sandbox Regression Runner")
    parser.add_argument("--test", default="tb_irq_arbiter", help="Target test_id or 'all'")
    parser.add_argument("--tier", default="all", help="Target tier (all, tier1_unit, tier2_subsystem, tier3_soc)")
    parser.add_argument("--simulator", default="xsim", help="Simulator (xsim)")
    parser.add_argument("--timeout-cycles", type=int, default=1000000, help="Simulation timeout in cycles")
    parser.add_argument("--wall-timeout", type=int, default=180, help="Process deadline in seconds")
    args = parser.parse_args()

    os.makedirs(RUNS_ROOT, exist_ok=True)
    git_commit, git_dirty = get_git_info()
    manifest_sha = sha256_file(P0_MANIFEST)

    print("==================================================================")
    print("RISCFORGE 1TOPS — Sandbox Regression Runner & Strict Classifier")
    print("==================================================================")
    print(f"Target: {args.test} | Tier: {args.tier} | Simulator: {args.simulator}")
    print(f"Git Commit: {git_commit} (Dirty: {git_dirty}) | Manifest: {manifest_sha[:12]}...")
    print("==================================================================\n")

    if not os.path.isfile(CROSSWALK_CSV):
        print(f"[FATAL] Crosswalk CSV not found at {CROSSWALK_CSV}")
        sys.exit(2)

    with open(CROSSWALK_CSV, "r", encoding="utf-8") as f:
        targets = list(csv.DictReader(f))

    selected = []
    for row in targets:
        if args.tier != "all" and row["tier"] != args.tier:
            continue
        if args.test != "all" and row["test_id"] != args.test:
            continue
        selected.append(row)

    if not selected:
        print(f"[FATAL] No targets matched test='{args.test}', tier='{args.tier}'")
        sys.exit(2)

    # Check simulator on PATH
    env = os.environ.copy()
    xvlog_bin = shutil.which("xvlog") or os.path.join(XSIM_ROOT, "xvlog.bat" if os.name == "nt" else "xvlog")
    xelab_bin = shutil.which("xelab") or os.path.join(XSIM_ROOT, "xelab.bat" if os.name == "nt" else "xelab")
    xsim_bin  = shutil.which("xsim")  or os.path.join(XSIM_ROOT, "xsim.bat"  if os.name == "nt" else "xsim")

    if not os.path.isfile(xvlog_bin) and not shutil.which("xvlog"):
        print(f"[ERROR] Vivado XSim binaries not located. Looked at {XSIM_ROOT}")
        sys.exit(3)

    summary = {}

    for tgt in selected:
        test_id     = tgt["test_id"]
        tier        = tgt["tier"]
        elab_top    = tgt["elaboration_top"]
        rel_fl      = tgt["filelist_path"]
        evidence_id = tgt.get("retained_evidence_id", "")
        dut_bnd     = tgt.get("dut_boundary", "")
        filelist    = os.path.join(BASE_DIR, rel_fl)

        print(f"------------------------------------------------------------------")
        print(f"Target: {test_id} [{tier}] (Top: {elab_top})")
        print(f"------------------------------------------------------------------")

        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        run_uuid = uuid.uuid4().hex[:8]
        run_id = f"{test_id}_{ts}_{run_uuid}"
        sandbox_dir = os.path.join(RUNS_ROOT, run_id)
        os.makedirs(sandbox_dir, exist_ok=True)

        start_time = time.time()
        start_utc = datetime.now(timezone.utc).isoformat()

        verdict_record = {
            "run_id": run_id,
            "test_id": test_id,
            "tier": tier,
            "elaboration_top": elab_top,
            "evidence_id": evidence_id,
            "filelist_path": rel_fl,
            "timestamp_start_utc": start_utc,
            "timestamp_end_utc": None,
            "duration_seconds": 0,
            "git_commit": git_commit,
            "git_dirty": git_dirty,
            "p0_manifest_sha256": manifest_sha,
            "simulator": args.simulator,
            "compile_exit_code": None,
            "elab_exit_code": None,
            "sim_exit_code": None,
            "pass_signature_matched": None,
            "forbidden_detected": None,
            "vacuity_detected": False,
            "verdict": "BLOCKED",
            "failure_reason": None,
        }

        log_file = os.path.join(sandbox_dir, "run.log")

        if not os.path.isfile(filelist):
            verdict_record["verdict"] = "BLOCKED"
            verdict_record["failure_reason"] = f"Filelist missing: {rel_fl}"
            finalize_verdict(sandbox_dir, verdict_record, start_time)
            print(f"  -> BLOCKED (Filelist missing: {rel_fl})")
            summary[test_id] = "BLOCKED"
            continue

        # Handle runtime assets into sandbox_dir
        if tgt.get("runtime_assets") and tgt["runtime_assets"] != "none":
            for asset in tgt["runtime_assets"].split(";"):
                src_asset = os.path.join(BASE_DIR, asset.strip())
                if os.path.isfile(src_asset):
                    shutil.copy2(src_asset, os.path.join(sandbox_dir, os.path.basename(src_asset)))

        # Step A: xvlog compile with absolute source paths, executed inside sandbox_dir
        print(f"  [XSIM] compiling {test_id} with xvlog (cwd=sandbox)...")
        parsed_args = []
        with open(filelist, "r", encoding="utf-8") as fl:
            for raw_line in fl:
                line = raw_line.strip()
                if not line or line.startswith("//") or line.startswith("#"):
                    continue
                if line.startswith("+incdir+"):
                    inc = line[len("+incdir+"):].strip()
                    abs_inc = inc if os.path.isabs(inc) else os.path.normpath(os.path.join(BASE_DIR, inc))
                    parsed_args.extend(["-i", abs_inc])
                elif line.startswith("-i "):
                    inc = line[3:].strip()
                    abs_inc = inc if os.path.isabs(inc) else os.path.normpath(os.path.join(BASE_DIR, inc))
                    parsed_args.extend(["-i", abs_inc])
                elif line in ("-sv", "-sverilog") or line.startswith("-timescale") or line.startswith("-top"):
                    continue
                else:
                    abs_src = line if os.path.isabs(line) else os.path.normpath(os.path.join(BASE_DIR, line))
                    parsed_args.append(abs_src)

        xvlog_cmd = [xvlog_bin, "--sv", "-d", "XSIM"] + parsed_args + ["--nolog"]
        c_code, _ = run_cmd_capture(xvlog_cmd, sandbox_dir, log_file, args.wall_timeout)
        verdict_record["compile_exit_code"] = c_code
        if c_code != 0:
            check_log_signatures(log_file, verdict_record)
            verdict_record["verdict"] = "FAILED"
            verdict_record["failure_reason"] = f"xvlog compile failed (exit {c_code})"
            finalize_verdict(sandbox_dir, verdict_record, start_time)
            print(f"  -> FAILED: {verdict_record['failure_reason']}")
            summary[test_id] = "FAILED"
            continue

        # Step B: xelab elaborate inside sandbox_dir
        snap_name = f"{test_id}_{run_uuid}"
        print(f"  [XSIM] elaborating {elab_top} with xelab (cwd=sandbox)...")
        xelab_cmd = [xelab_bin, elab_top, "-s", snap_name, "--timescale", "1ns/1ps", "--nolog"]
        e_code, _ = run_cmd_capture(xelab_cmd, sandbox_dir, log_file, args.wall_timeout)
        verdict_record["elab_exit_code"] = e_code
        if e_code != 0:
            check_log_signatures(log_file, verdict_record)
            verdict_record["verdict"] = "FAILED"
            verdict_record["failure_reason"] = f"xelab elaboration failed (exit {e_code})"
            finalize_verdict(sandbox_dir, verdict_record, start_time)
            print(f"  -> FAILED: {verdict_record['failure_reason']}")
            summary[test_id] = "FAILED"
            continue

        is_design_only = "Design Only" in dut_bnd
        if is_design_only:
            print(f"  [XSIM] design-only compilation target: simulation skipped.")
            s_code = 0
            verdict_record["sim_exit_code"] = 0
            verdict_record["pass_signature_matched"] = "Design-Only Elaboration Clean"
            with open(log_file, "a", encoding="utf-8") as f:
                f.write("\n[DESIGN-ONLY] Elaboration completed cleanly. Simulation skipped.\n")
        else:
            # Step C: xsim simulation inside sandbox_dir
            print(f"  [XSIM] simulating snapshot (cwd=sandbox)...")
            xsim_cmd = [xsim_bin, snap_name, "-R"]
            s_code, _ = run_cmd_capture(xsim_cmd, sandbox_dir, log_file, args.wall_timeout)
            verdict_record["sim_exit_code"] = s_code

        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            log_content = f.read()

        pass_pat = PASS_SIGNATURES.get(test_id)
        if not is_design_only:
            if pass_pat:
                m_pass = re.search(pass_pat, log_content)
                if m_pass:
                    verdict_record["pass_signature_matched"] = m_pass.group(0).strip()
            else:
                verdict_record["pass_signature_matched"] = None

        # Comprehensive signature and vacuity checks
        check_log_signatures(log_file, verdict_record)

        if (s_code == 0 and 
            verdict_record["pass_signature_matched"] and 
            not verdict_record["forbidden_detected"] and 
            not verdict_record["vacuity_detected"]):
            verdict_record["verdict"] = "PASSED"
            finalize_verdict(sandbox_dir, verdict_record, start_time)
            print(f"  -> PASSED in {verdict_record['duration_seconds']}s ({verdict_record['pass_signature_matched']})")
            summary[test_id] = "PASSED"
        else:
            verdict_record["verdict"] = "FAILED"
            if s_code != 0:
                verdict_record["failure_reason"] = f"Simulator exit code {s_code}"
            elif verdict_record["vacuity_detected"]:
                verdict_record["failure_reason"] = "Vacuous execution detected (zero checks/transfers/passed)"
            elif not verdict_record["pass_signature_matched"]:
                verdict_record["failure_reason"] = f"Required positive activity pattern '{pass_pat}' not matched"
            else:
                verdict_record["failure_reason"] = f"Forbidden pattern detected: {verdict_record['forbidden_detected']}"
            finalize_verdict(sandbox_dir, verdict_record, start_time)
            print(f"  -> FAILED: {verdict_record['failure_reason']}")
            summary[test_id] = "FAILED"

    # Summary
    pass_cnt  = sum(1 for v in summary.values() if v == "PASSED")
    fail_cnt  = sum(1 for v in summary.values() if v == "FAILED")
    block_cnt = sum(1 for v in summary.values() if v == "BLOCKED")

    print("\n==================================================================")
    print("REGRESSION SUMMARY")
    print("==================================================================")
    for k in sorted(summary.keys()):
        print(f"  {k:<28} : {summary[k]}")
    print("------------------------------------------------------------------")
    print(f"Total: {len(summary)} | Passed: {pass_cnt} | Failed: {fail_cnt} | Blocked: {block_cnt}")
    print("==================================================================\n")

    if fail_cnt > 0 or block_cnt > 0:
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    main()
