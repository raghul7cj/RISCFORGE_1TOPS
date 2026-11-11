"""Export selected XSim signals to VCD and count observable clocked activity.

This is diagnostic collection, not functional-bin definition or a reference model.
"""
from collections import defaultdict
from datetime import datetime
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
OUTPUT = HERE / datetime.now().strftime("external_activity_%H%M%S")
OUTPUT.mkdir(exist_ok=False)
previous = json.loads((HERE / "result.json").read_text())
execution = Path(previous["execution_directory"])
manual = "https://docs.amd.com/r/2022.2-English/ug900-vivado-logic-simulation/Using-the-Value-Change-Dump-Feature"

config = {
    "tb_csr_corner_unit": {
        "clock": "clk", "reset_n": "dut/rst_n_i",
        "signals": {
            "normal_csr_write": "dut/csr_write_en_normal_i",
            "trap_input": "dut/trap_valid_i",
            "mret_input": "dut/mret_commit_i",
            "retirement_input": "dut/instr_retired_i",
            "fast_irq_input": "dut/fast_intr_i",
            "timer_irq_input": "dut/timer_intr_i",
            "external_irq_input": "dut/ext_intr_i",
            "software_irq_input": "dut/msft_intr_i"
        }
    },
    "tb_core_csr_trap": {
        "clock": "clk", "reset_n": "core/rst",
        "signals": {
            "trap_commit": "core/trap_commit_valid",
            "mret_commit": "core/mret_commit",
            "writeback_valid": "core/valid_W",
            "writeback_exception": "core/exc_valid_W",
            "gpr_write": "core/RegWriteW_gated",
            "csr_write": "core/csr_write_en_W_gated",
            "memory_request": "core/lsu_mem_req",
            "memory_write": "core/lsu_mem_we",
            "fast_irq_input": "core/fast_irq_i",
            "timer_irq_input": "core/timer_irq_i",
            "external_irq_input": "core/ext_irq_i",
            "software_irq_input": "core/sw_irq_i"
        }
    }
}


def parse_vcd(path, top, selected):
    text = path.read_text()
    boundary = re.search(r"\$enddefinitions\s+\$end", text)
    if boundary is None:
        raise RuntimeError("VCD header is incomplete")
    header, body = text[:boundary.start()], text[boundary.end():]
    scale = re.search(r"\$timescale\s+(\d+)\s*(s|ms|us|ns|ps|fs)\s+\$end", header)
    assert scale is not None, "Missing VCD timescale"
    ns_per_tick = int(scale.group(1)) * {
        "s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1, "ps": 1e-3, "fs": 1e-6
    }[scale.group(2)]
    scopes, variables = [], {}
    for line in header.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "$scope":
            scopes.append(fields[2])
        elif fields[0] == "$upscope":
            scopes.pop()
        elif fields[0] == "$var":
            variables["/".join(scopes + [fields[4]])] = fields[3]
    paths = {"clock": selected["clock"], "reset_n": selected["reset_n"],
             **selected["signals"]}
    ids = {}
    for name, relative in paths.items():
        full = top + "/" + relative
        if full not in variables:
            raise RuntimeError("Required signal absent from VCD: " + full)
        ids[name] = variables[full]
    values, pending = {}, {}
    counts = {"clock_rising_samples": 0, "active_clock_samples": 0,
              "reset_held_clock_samples": 0, "reset_unknown_clock_samples": 0}
    signal_counts = {name: {"nonzero_clock_samples": 0,
                            "nonzero_active_samples": 0,
                            "unknown_clock_samples": 0}
                     for name in selected["signals"]}
    timestamp, last_timestamp = 0, 0

    def apply_group():
        old_clock = values.get(ids["clock"], "x")
        values.update(pending)
        if old_clock != "0" or values.get(ids["clock"]) != "1":
            return
        counts["clock_rising_samples"] += 1
        reset = values.get(ids["reset_n"], "x").lower()
        active = reset == "1"
        if active:
            counts["active_clock_samples"] += 1
        elif reset == "0":
            counts["reset_held_clock_samples"] += 1
        else:
            counts["reset_unknown_clock_samples"] += 1
        for name, record in signal_counts.items():
            value = values.get(ids[name], "x").lower()
            if "x" in value or "z" in value:
                record["unknown_clock_samples"] += 1
            elif int(value, 2) != 0:
                record["nonzero_clock_samples"] += 1
                record["nonzero_active_samples"] += int(active)

    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("$"):
            continue
        if line.startswith("#"):
            apply_group()
            pending.clear()
            timestamp = int(line[1:])
            last_timestamp = timestamp
        elif line[0] in "bB":
            value, identifier = line[1:].split()
            pending[identifier] = value.lower()
        elif line[0] in "01xXzZ":
            pending[line[1:]] = line[0].lower()
    apply_group()
    return {"duration_ns": last_timestamp * ns_per_tick,
            "vcd_timescale": scale.group(1) + scale.group(2),
            "sample_phase": "Values after applying all VCD changes at each rising-clock timestamp. Counts are high/nonzero samples, not unique architectural transaction counts.",
            "counts": counts, "signals": signal_counts,
            "reset_n_final": values.get(ids["reset_n"], "unobserved")}


results = {"manual": manual, "scope": "External diagnostic activity counts; no new functional coverage bins or expected behavior.",
           "source_manifest_sha256": hashlib.sha256((HERE / "manifest.json").read_bytes()).hexdigest(),
           "benches": {}}
for top, selected in config.items():
    work = execution / top
    out = work / OUTPUT.name
    out.mkdir()
    paths = [selected["clock"], selected["reset_n"], *selected["signals"].values()]
    vcd = out / "activity.vcd"
    script = out / "collect.tcl"
    lines = [f"open_vcd {{{vcd.as_posix()}}}"]
    for path in paths:
        full = "/" + top + "/" + path
        lines += [f"set signal [get_objects {{{full}}}]",
                  f'if {{[llength $signal] != 1}} {{error "Missing observation signal: {full}"}}',
                  "log_vcd $signal"]
    lines += ["run all", "close_vcd", 'puts "ACTIVITY_CAPTURE_COMPLETE"', "quit"]
    script.write_text("\n".join(lines) + "\n")
    argv = ["C:/Xilinx/Vivado/2022.2/bin/xsim.bat", top + "_snapshot",
            "-tclbatch", script.as_posix(), "-onerror", "quit", "-onfinish", "stop",
            "-sv_seed", "1", "-cov_db_dir", (out / "functional_db").as_posix(),
            "-cov_db_name", top, "-log", (out / "simulation.log").as_posix()]
    with (out / "stdout.log").open("w", encoding="utf-8") as stream:
        proc = subprocess.run(argv, cwd=work, stdout=stream,
                              stderr=subprocess.STDOUT, timeout=60)
    record = {"argv": argv, "cwd": str(work), "exit_code": proc.returncode}
    (out / "command.json").write_text(json.dumps(record, indent=2))
    shutil.copytree(out, OUTPUT / top)
    stdout = (out / "stdout.log").read_text(errors="replace")
    if proc.returncode != 0 or "ACTIVITY_CAPTURE_COMPLETE" not in stdout:
        raise RuntimeError("Capture did not complete; inspect " + str(out / "stdout.log"))
    record["metrics"] = parse_vcd(vcd, top, selected)
    results["benches"][top] = record
    print(top, json.dumps(record["metrics"]), flush=True)

(OUTPUT / "activity.json").write_text(json.dumps(results, indent=2))
with (OUTPUT / "activity.csv").open("w", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["bench", "metric", "value"])
    for top, record in results["benches"].items():
        metrics = record["metrics"]
        writer.writerow([top, "duration_ns", metrics["duration_ns"]])
        for name, value in metrics["counts"].items():
            writer.writerow([top, name, value])
        for signal, counts in metrics["signals"].items():
            for name, value in counts.items():
                writer.writerow([top, signal + "." + name, value])
print("ACTIVITY_OUTPUT=" + str(OUTPUT))
