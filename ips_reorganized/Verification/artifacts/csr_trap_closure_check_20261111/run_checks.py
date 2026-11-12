"""Run the unchanged CSR/trap sources in isolated XSim work directories."""

from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[4]
OUTPUT = Path(__file__).parent / datetime.now().strftime("run_%H%M%S")
OUTPUT.mkdir(parents=True, exist_ok=False)
EXECUTION = Path(tempfile.mkdtemp(prefix="csrcheck_"))
SNAPSHOT = EXECUTION / "source_snapshot"
BIN = Path(r"C:\Xilinx\Vivado\2022.2\bin")
TOPS = ("tb_csr_corner_unit", "tb_core_csr_trap")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, work, stage, timeout=180):
    record = {"argv": [arg.as_posix() if isinstance(arg, Path) else str(arg)
                       for arg in args], "cwd": str(work)}
    (work / f"{stage}.command.json").write_text(json.dumps(record, indent=2))
    print(f"{work.name}: {stage} starting", flush=True)
    with (work / f"{stage}.stdout.log").open("w", encoding="utf-8") as stream:
        try:
            result = subprocess.run(record["argv"], cwd=work, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=timeout)
            record["exit_code"] = result.returncode
        except subprocess.TimeoutExpired:
            record["exit_code"] = None
            record["error"] = "timeout"
        except OSError as error:
            record["exit_code"] = None
            record["error"] = str(error)
    (work / f"{stage}.result.json").write_text(json.dumps(record, indent=2))
    print(f"{work.name}: {stage} exit={record['exit_code']}", flush=True)
    return record


sources = {}
source_sets = {}
for top in TOPS:
    filelist = ROOT / "ips/Verification/filelists/tier1_unit" / f"{top}.f"
    paths = []
    for line in filelist.read_text().splitlines():
        line = line.split("//", 1)[0].strip()
        if line.endswith((".sv", ".v")):
            paths.append(Path("ips") / line)
    source_sets[top] = paths
    for relative in [filelist.relative_to(ROOT), *paths]:
        original = ROOT / relative
        target = SNAPSHOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        archived = OUTPUT / "source_snapshot" / relative
        archived.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, archived)
        sources[relative.as_posix()] = {
            "sha256": digest(original), "snapshot_sha256": digest(target)
        }

manifest = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "workspace": str(ROOT),
    "git_commit": None,
    "git_dirty": "not established; source hashes identify the executed inputs",
    "simulator": "Vivado XSim 2022.2, local engineering diagnostic",
    "execution_directory": str(EXECUTION),
    "execution_layout": "Short isolated work directories and forward-slash command paths; copied inputs are hash-matched and all work directories are archived. Forward slashes avoid XSim emitting unescaped Windows paths into generated C/Tcl.",
    "sources": sources,
    "network_attempts": {
        "synopsys_saved_session": "FATAL ERROR: Network error: Connection timed out",
        "cadence_saved_session": "FATAL ERROR: Network error: Connection timed out",
        "tcp_5s_checks": {
            "172.31.2.4:8080": "timed out",
            "172.16.33.48:22": "timed out",
            "172.16.33.51:22": "timed out"
        },
        "provenance": "Recorded from parent tool outputs before local execution; no remote tool ran."
    }
}
manifest_path = OUTPUT / "manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
summary = {"artifact_directory": str(OUTPUT), "execution_directory": str(EXECUTION), "benches": {}}
(OUTPUT / "result.json").write_text(json.dumps(summary, indent=2))
print(f"ARTIFACT_DIRECTORY={OUTPUT}", flush=True)

for top in TOPS:
    work = EXECUTION / top
    work.mkdir()
    listed = [SNAPSHOT / path for path in source_sets[top]]
    filelist = work / "sources.xsim.f"
    filelist.write_text("\n".join(f'"{path.as_posix()}"' for path in listed) + "\n")
    stages = {}
    stages["compile"] = command([
        BIN / "xvlog.bat", "-sv", "-i", SNAPSHOT / "ips/riscv_core/rtl",
        "-f", filelist, "-log", "compile.log"
    ], work, "compile")
    if stages["compile"]["exit_code"] == 0:
        coverage = work / "coverage"
        stages["elaborate"] = command([
            BIN / "xelab.bat", "-debug", "typical", "-timescale", "1ns/1ps",
            "-cc_type", "sbct", "-cc_db", top, "-cc_dir", coverage,
            "-cov_db_dir", coverage, "-cov_db_name", top,
            "-s", top + "_snapshot", "work." + top, "-log", "elaborate.log"
        ], work, "elaborate")
        if stages["elaborate"]["exit_code"] == 0:
            script = work / "run.tcl"
            script.write_text("log_wave -r /\nrun all\nquit\n")
            stages["simulate"] = command([
                BIN / "xsim.bat", top + "_snapshot", "-tclbatch", script,
                "-onerror", "quit", "-onfinish", "quit",
                "-sv_seed", "1",
                "-cov_db_dir", coverage, "-cov_db_name", top,
                "-log", "simulation.log"
            ], work, "simulate", timeout=60)
    errors = []
    for log in work.glob("*.stdout.log"):
        for line in log.read_text(errors="replace").splitlines():
            if re.search(r"ERROR|FATAL|SKELETON|INCOMPLETE|Simulation.*complete", line):
                errors.append({"log": log.name, "line": line})
    summary["benches"][top] = {"stages": stages, "diagnostics": errors}
    shutil.copytree(work, OUTPUT / top)
    (OUTPUT / "result.json").write_text(json.dumps(summary, indent=2))

print(f"RESULT_FILE={OUTPUT / 'result.json'}", flush=True)
