"""Distinguish coverage-enabled code generation failure from basic execution."""
from pathlib import Path
import json
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
summary = json.loads((HERE / "result.json").read_text())
execution = Path(summary["execution_directory"])
binary = Path(r"C:\Xilinx\Vivado\2022.2\bin")

for top, record in summary["benches"].items():
    work = execution / top
    snapshot = top + "_no_codecov"
    attempts = []
    cmds = [
        ("elaborate_without_coverage", [binary / "xelab.bat", "-debug", "typical",
         "-timescale", "1ns/1ps", "-s", snapshot, "work." + top,
         "-log", "elaborate_without_coverage.log"]),
        ("simulate_without_coverage", [binary / "xsim.bat", snapshot,
         "-tclbatch", work / "run_without_coverage.tcl", "-onerror", "quit",
         "-onfinish", "quit", "-log", "simulation_without_coverage.log"])
    ]
    (work / "run_without_coverage.tcl").write_text("log_wave -r /\nrun all\nquit\n")
    for stage, argv in cmds:
        metadata = {"argv": list(map(str, argv)), "cwd": str(work),
                    "coverage": "disabled for code-generation isolation only"}
        with (work / f"{stage}.stdout.log").open("w", encoding="utf-8") as stream:
            try:
                result = subprocess.run(metadata["argv"], cwd=work,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=90)
                metadata["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                metadata["exit_code"] = None
                metadata["error"] = "timeout"
        (work / f"{stage}.result.json").write_text(json.dumps(metadata, indent=2))
        attempts.append(metadata)
        print(top, stage, metadata["exit_code"], flush=True)
        if metadata["exit_code"] != 0:
            break
    record["diagnostic_without_coverage"] = attempts
    shutil.copytree(work, HERE / top, dirs_exist_ok=True)
    (HERE / "result.json").write_text(json.dumps(summary, indent=2))
