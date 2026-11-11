"""Extract settled pre-rising-edge core signals from an XSim VCD.

Read-only waveform analysis. Does not infer retirement from repeated PC alone.
Usage: py -3 extract_cycles.py path/to/run_directory
"""
import csv
import json
import sys
from pathlib import Path

CORE = "soc_benchmark_tb.dut.i_riscv_core."
SIGNALS = (
    "rst PCD InstrD PCE PC_M PC_W valid_E valid_M valid_W exc_valid_W "
    "StallE StallM FlushE FlushM FlushW stallMUL mem_stall_out "
    "RD_E RD_M RDW RegWriteM RegWriteW RegWriteW_gated ResultW ALU_ResultM "
    "RS1_E RS2_E ForwardAE ForwardBE RD1_E RD2_E "
    "Execute.m_valid_out Execute.result_M Execute.rd_me Execute.ResultE "
    "Execute.Src_A Execute.Src_B_interim Execute.start_M "
    "csr_file.minstret_r csr_file.instr_retired_i "
    "trap_commit_valid trap_commit_pc trap_commit_cause trap_commit_addr"
).split()


def extract(run):
    names = {CORE + name: name for name in SIGNALS}
    names["soc_benchmark_tb.clk_i"] = "clk"
    scopes, codes, values, samples = [], {}, {}, []
    timestamp = 0
    changes = {}

    def flush():
        # Preserve the values BEFORE the clock edge, including CSR state.
        if changes.get("clk") == 1 and values.get("clk") == 0:
            samples.append({"time_ps": timestamp, **values})
        values.update(changes)
        changes.clear()

    with (run / "waves.vcd").open() as stream:
        for line in stream:
            fields = line.split()
            if line.startswith("$scope"):
                scopes.append(fields[2])
            elif line.startswith("$upscope"):
                scopes.pop()
            elif line.startswith("$var"):
                name = ".".join(scopes + [fields[4]])
                if name in names:
                    codes.setdefault(fields[3], []).append(names[name])
            elif line.startswith("#"):
                flush()
                timestamp = int(line[1:])
            elif line and line[0] in "01xXzZbB":
                if line[0] in "bB":
                    bits, code = fields[0][1:], fields[1]
                else:
                    bits, code = line[0], line[1:].strip()
                if code in codes:
                    value = None if any(c in bits.lower() for c in "xz") else int(bits, 2)
                    for name in codes[code]:
                        changes[name] = value
        flush()
    found = {name for aliases in codes.values() for name in aliases}
    columns = ["time_ps"] + [name for name in SIGNALS if name in found]
    with (run / "core_cycles.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(samples)
    summary = {"sampling": "settled values immediately before rising clock edge",
               "timescale": "1ps (XSim VCD header)",
               "samples": len(samples), "missing_signals": sorted(set(SIGNALS) - found)}
    (run / "trace_extraction.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(run.name, summary)


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        extract(Path(argument))
