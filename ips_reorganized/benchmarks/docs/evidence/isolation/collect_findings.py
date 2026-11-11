"""Preserve focused waveform windows and check observed failure conditions.

Run from repository root after extract_cycles.py. These are diagnostic evidence
checks on real SoC runs, not a replacement for architectural verification.
"""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
RUNS = ROOT / "ips/benchmarks/runs/isolation"
SELECTED = {
    "smoke": "smoke_20261104T113155Z_f7e5a503",
    "coremark": "coremark_20261104T113222Z_030e35af",
    "dhrystone": "dhrystone_20261104T113308Z_2036a556",
}
WINDOWS = {
    "smoke": [(6085000, 6115000), (7685000, 7785000), (8115000, 8145000)],
    "coremark": [(41755000, 41775000), (42105000, 42155000),
                 (42245000, 42355000), (42985000, 43015000), (43405000, 43455000)],
    "dhrystone": [(223955000, 223975000), (224305000, 224395000),
                  (224715000, 224755000), (225135000, 225235000)],
}


def main():
    report = {"sampling": "pre-rising-edge; times in ps", "runs": {}}
    for benchmark, name in SELECTED.items():
        directory = RUNS / name
        with (directory / "core_cycles.csv").open() as stream:
            reader = csv.DictReader(stream)
            columns = reader.fieldnames
            rows = [{k: int(v) if v else None for k, v in row.items()} for row in reader]
        focused = [r for r in rows if any(lo <= r["time_ps"] <= hi
                                         for lo, hi in WINDOWS[benchmark])]
        with (OUT / f"{benchmark}_windows.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns)
            writer.writeheader()
            writer.writerows(focused)
        completions = []
        overlaps = []
        repeated = []
        pending = None
        for i, row in enumerate(rows[:-2]):
            if row["Execute.start_M"] == 1:
                pending = {k: row[k] for k in ["time_ps", "PCE", "RD_E",
                                              "Execute.Src_A", "Execute.Src_B_interim"]}
            if row["Execute.m_valid_out"] == 1:
                after, wb = rows[i + 1:i + 3]
                completions.append({"issue": pending,
                    "completion_time_ps": row["time_ps"],
                    "result": row["Execute.result_M"], "destination": row["Execute.rd_me"],
                    "valid_E": row["valid_E"], "StallM": row["StallM"],
                    "FlushM": row["FlushM"], "next_valid_M": after["valid_M"],
                    "wb_valid": wb["valid_W"], "wb_write_enable": wb["RegWriteW_gated"],
                    "wb_destination": wb["RDW"], "wb_result": wb["ResultW"]})
                pending = None
            if row["rst"] == 1 and row["StallM"] == 1 and row["FlushM"] == 1 and row["valid_M"] == 1:
                overlaps.append({"time_ps": row["time_ps"], "older_pc": row["PC_M"],
                    "younger_pc": row["PCE"], "older_destination": row["RD_M"],
                    "older_address": row["ALU_ResultM"],
                    "next_valid_M": rows[i + 1]["valid_M"],
                    "next_pc_M": rows[i + 1]["PC_M"]})
            if row["rst"] == 1 and row["StallM"] == 1 and row["valid_W"] == 1 and row["exc_valid_W"] == 0:
                nxt, later = rows[i + 1:i + 3]
                if nxt["PC_W"] == row["PC_W"] and nxt["valid_W"] == 1:
                    repeated.append({"time_ps": row["time_ps"], "pc_W": row["PC_W"],
                        "minstret_before": row["csr_file.minstret_r"],
                        "minstret_next": nxt["csr_file.minstret_r"],
                        "minstret_later": later["csr_file.minstret_r"],
                        "next_retirement_input": nxt["csr_file.instr_retired_i"]})
        assert completions and all(c["valid_E"] == 0 and c["next_valid_M"] == 0
                                   and c["wb_valid"] == 0 and c["wb_write_enable"] == 0
                                   and c["wb_result"] == c["result"]
                                   and c["wb_destination"] == c["destination"] for c in completions)
        assert repeated and all(e["minstret_next"] == e["minstret_before"] + 1
                                and e["minstret_later"] == e["minstret_next"] + 1
                                for e in repeated)
        report["runs"][benchmark] = {"directory": str(directory.relative_to(ROOT)),
            "result": json.loads((directory / "result.json").read_text()),
            "mdu_completions": completions, "flush_stall_overlaps": overlaps,
            "held_wb_increments": repeated,
            "hashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
                       [directory / file for file in ["program.elf", "program.dis", "waves.vcd",
                                                      "core_cycles.csv", "result.json", "source_hashes.json"]]}}
    baseline = json.loads((ROOT / "ips/benchmarks/docs/design_baseline.json").read_text())["hashes"]
    differences = [name for name, digest in baseline.items()
                   if hashlib.sha256((ROOT / "ips" / name).read_bytes()).hexdigest() != digest]
    report["design_baseline"] = {"checked": len(baseline), "differences": differences}
    assert not differences, differences
    (OUT / "findings.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Diagnostic evidence checks passed; design baseline unchanged.")
    for name, data in report["runs"].items():
        print(name, "lost completions:", len(data["mdu_completions"]),
              "flush/stall overlaps:", len(data["flush_stall_overlaps"]),
              "held-WB increments:", len(data["held_wb_increments"]))


if __name__ == "__main__":
    main()
