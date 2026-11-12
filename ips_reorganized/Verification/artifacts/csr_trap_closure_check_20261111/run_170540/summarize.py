"""Save a source-identified closure record without changing RTL or checks."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SNAPSHOT = HERE / "source_snapshot"
manifest_path = HERE / "manifest.json"
manifest = json.loads(manifest_path.read_text())
results = json.loads((HERE / "result.json").read_text())
identity = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
changed = [path for path, record in manifest["sources"].items()
           if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != record["sha256"]]
assert not changed, changed

unit = "ips/Verification/infrastructure/tb/tb_csr_corner_unit.sv"
core = "ips/Verification/infrastructure/tb/tb_core_csr_trap.sv"
env = "ips/Verification/infrastructure/tb/csr_trap/csr_trap_env_pkg.sv"

def source(path, symbol):
    lines = (SNAPSHOT / path).read_text().splitlines()
    line = next(index + 1 for index, text in enumerate(lines) if symbol in text)
    return {"path": path, "symbol": symbol, "line": line}

spec = {
    "title": "CSR trap closure-check scope",
    "scope": "Static DUT and environment connections for the executed source snapshot. Reset remains asserted; these edges do not claim functional activity or checking.",
    "baseline": {
        "repo": "RISCFORGE_1TOPS-main/rtl source archive",
        "commit": "unavailable; executed source manifest SHA256 " + identity
    },
    "nodes": [
        {"id": "U", "label": "CSR unit top", "status": "present", "source": source(unit, "module tb_csr_corner_unit")},
        {"id": "R", "label": "CSR DUT", "status": "present", "source": source("ips/riscv_core/rtl/csr_regfile.v", "module csr_regfile")},
        {"id": "C", "label": "Core bench top", "status": "present", "source": source(core, "module tb_core_csr_trap")},
        {"id": "D", "label": "Actual core DUT", "status": "present", "source": source("ips/riscv_core/rtl/top.v", "module top #(")},
        {"id": "E", "label": "OOP environment", "status": "present", "source": source(env, "class corner_env")},
        {"id": "M", "label": "Independent reference checks", "status": "absent", "note": "Inspected trap_scoreboard.consume/model_and_check and unit extend_reference_model: empty USER_REF_MODEL hooks."},
        {"id": "F", "label": "Functional coverage bins", "status": "absent", "note": "Inspected both bench tops, coverage class, interfaces and assertion stub: no covergroup definitions or bins."}
    ],
    "edges": [
        {"from": "U", "to": "R", "label": "named DUT ports", "status": "present", "source": source(unit, ".clk_i(clk)")},
        {"from": "C", "to": "D", "label": "actual core instance", "status": "present", "source": source(core, "top #(.RESET_PC(RESET_PC)) core")},
        {"from": "C", "to": "E", "label": "construct environment", "status": "present", "source": source(core, "environment = new(core_if)")},
        {"from": "E", "to": "M", "label": "checking deferred", "status": "absent"},
        {"from": "E", "to": "F", "label": "bins deferred", "status": "absent"}
    ],
    "unknowns": ["Git commit/branch/dirty state not established; exact source hashes and snapshots retained.", "VCS and Cadence hosts unreachable during this check.", "Full architecture behavior and any coverage closure remain unverified."]
}
diagram_dir = HERE / "diagrams"
diagram_dir.mkdir(exist_ok=True)
spec_path = diagram_dir / "closure_scope.spec.json"
spec_path.write_text(json.dumps(spec, indent=2))
validator = ROOT / ".agents/skills/rtl-verification-documentation/tools/diagram_tool.py"
run = subprocess.run(["py", str(validator), str(spec_path), "--root", str(SNAPSHOT),
                      "--out", str(diagram_dir)], capture_output=True, text=True)
(diagram_dir / "validation.log").write_text(run.stdout + run.stderr)
assert run.returncode == 0, run.stdout + run.stderr
diagram = (diagram_dir / "closure_scope.md").read_text()
mermaid = re.search(r"```mermaid.*?```", diagram, re.S).group(0)

lines = [
    "# CSR/trap coverage and closure check — 2026-11-11", "",
    "**Verdict: OPEN / NOT CLOSED.** Both current benches compile, elaborate and execute locally. They execute only the reset-held skeleton and perform no functional checking; no functional coverage bins are implemented.", "",
    "## Executed evidence", "",
    "Tool: local Vivado XSim 2022.2, seed 1. Sources copied unchanged from the local workspace; source/filelist SHA-256 hashes and execution copies are retained in [manifest.json](manifest.json) and `source_snapshot/`. Git commit/dirty state is unavailable. All inspected workspace inputs still match their recorded hashes.", "",
    "| Bench | SV compile | Coverage-enabled elaboration | Simulation | Functional verdict |",
    "| --- | --- | --- | --- | --- |",
    "| tb_csr_corner_unit | exit 0 | exit 0 | exit 0; finishes at 25 ns | SKELETON/INCOMPLETE; no checks |",
    "| tb_core_csr_trap | exit 0 | exit 0 | exit 0; finishes at 30 ns | SKELETON/INCOMPLETE; checks=0 |", "",
    "Both runs retain active-low reset asserted and IRQs low. XSim explicitly reports: `The Functional Coverage Database has not been updated during simulation.` A zero process exit is not a functional PASS.", "",
    "## Coverage and checking", "",
    "- Reference model/checker bodies: unimplemented USER_REF_MODEL hooks.",
    "- Functional covergroups/bins: unimplemented USER_COVERAGE hooks. A closure percentage is undefined; there is no implemented functional-bin denominator.",
    "- Directed hazard/exception/IRQ programs and schedules: unimplemented USER_STIMULUS hooks.",
    "- Assertion module: extension stub; no checking properties implemented.",
    "- Memory shells: placeholder NOP and zero/no-error/no-stall responses; no functional latency/error/effect model.",
    "- Code instrumentation: requested statement, branch, condition and toggle (`-cc_type sbct`). Both runs wrote an `xsim.CCInfo` database. Reset-only activity does not establish feature coverage.",
    "- Code report generation: XCRG restores both databases, then exits with Windows status `3221226356` (`0xC0000374`) while generating HTML. A retry with XILINX_VIVADO configured and relative report paths fails identically. Partial HTML is retained but is not accepted as a completed report or closure evidence.", "",
    "## Warnings and preserved negative evidence", "",
    "The core elaboration retains multiplier port-width mismatches (`co` and `shift`) and unconnected `imem_stall`, `csr_valid_o` and ALU `Zero` warnings. These are findings for engineer review, not diagnosed functional defects or waived warnings. No RTL or bench source was changed by this run.", "",
    "The first two attempts (`../run_170245/` and `../run_170343/`) failed during generated-C compilation with XSIM 43-3409/43-3915. The generated file contains an unescaped Windows coverage directory. Forward-slash command paths resolve that failure in this run. Shortening paths alone did not resolve it.", "",
    "The coverage-disabled diagnostic attempt in `../run_170343/` elaborated but its Tcl script path was misinterpreted; despite process exit 0, the requested script did not execute. It is not counted as a simulation pass. Its logs are preserved.", "",
    "Remote VCS and Cadence attempts returned `Network error: Connection timed out`; direct SSH and campus-proxy TCP probes also timed out. No remote tool or licensed VCS run occurred. Local XSim results are engineering diagnostics and do not replace the checklist's VCS evidence requirement.", "",
    "## Source-backed scope diagram", "", mermaid, "",
    "Source identity: source archive; Git commit unavailable. Manifest SHA-256: `" + identity + "`.",
    "Diagram [spec](diagrams/closure_scope.spec.json), [validated rendering and source citations](diagrams/closure_scope.md), [validation log](diagrams/validation.log). This static diagram shows connections and absent checking/coverage; it does not depict an exercised trap path.", "",
    "## Evidence files", "",
    "- [Machine-readable stage commands/results](result.json)",
    "- [CSR simulation log](tb_csr_corner_unit/simulation.log)",
    "- [Core simulation log](tb_core_csr_trap/simulation.log)",
    "- [Core elaboration warnings](tb_core_csr_trap/elaborate.log)",
    "- [CSR report-generator failure](tb_csr_corner_unit/coverage_report.stdout.log)",
    "- [Core report-generator failure](tb_core_csr_trap/coverage_report.stdout.log)",
    "- Waveforms: each bench directory retains the generated `.wdb` and code-coverage database.", "",
    "## What remains before closure", "",
    "1. Engineer reviews/signs off the reference behavior and coverage-bin contract, including unresolved interrupt/CSR ordering policies.",
    "2. Implement checks and bins, then directed stimulus and functional memory behavior as agreed. The engineer retains the previously assigned ownership.",
    "3. Execute checked exception/IRQ/hazard scenarios, demonstrate checker-negative controls, inspect unhit bins/code and dispose warnings/defects with evidence.",
    "4. Retain accepted-tool reports for the exact candidate and satisfy the agreed closure criteria. No gate approval or waiver is assigned here.", ""
]
(HERE / "CLOSURE_STATUS.md").write_text("\n".join(lines), encoding="utf-8")
print("REPORT=" + str(HERE / "CLOSURE_STATUS.md"))
print("SOURCE_HASHES_UNCHANGED=" + str(len(manifest["sources"])))
print(run.stdout.strip())
