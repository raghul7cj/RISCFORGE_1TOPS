"""Build, execute and collect the user's minstret retirement checklist.

Run from repository root under WSL/Linux. Generated artifacts go to a unique
campaign directory; failed runs are retained and never contribute passing bins.
The software reference supports only the instructions needed by these tests.
It is not a general RISC-V ISS or an architectural certification suite.
"""
import csv
import datetime
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RTL = HERE.parents[2] / "riscv_core/rtl"
BINS = ["ADD", "SUB", "MUL", "DIV", "LW", "SW", "BEQ_taken", "BEQ_not_taken",
        "BNE_taken", "BNE_not_taken", "JAL", "JALR", "CSRRW", "CSRRS", "CSRRC",
        "CSRRWI", "CSRRSI", "CSRRCI", "MRET", "ECALL", "EBREAK", "illegal",
        "misaligned_load", "misaligned_store", "wrong_path", "bubble", "stall",
        "NOP", "interrupt"]


def signed(value, bits=32):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def execute_reference(words, labels):
    """Execute the actual assembled test image, excluding exception instructions.

    Records the expected ordered retired PCs, traps and final memory. Interrupts
    are external stimuli: their known two-instruction handler is inserted by the
    TB at the precise interrupted PC, and must replay that interrupted instruction.
    """
    regs, memory, csrs = [0] * 32, {}, {}
    pc = labels["_start"]
    retired, traps = [], []
    for _ in range(1000):
        word = words[(pc - 0x80000000) // 4]
        op, rd, f3, a, b, f7 = word & 127, (word >> 7) & 31, (word >> 12) & 7, (word >> 15) & 31, (word >> 20) & 31, word >> 25
        imm = signed(word >> 20, 12)
        next_pc, value, cause = pc + 4, None, None
        if word == 0x00000073:
            cause = 11
        elif word == 0x00100073:
            cause = 3
        elif word == 0xffffffff:
            cause = 2
        elif word == 0x30200073:
            next_pc = csrs[0x341]
        elif op == 0x37:
            value = word & 0xfffff000
        elif op == 0x17:
            value = pc + (word & 0xfffff000)
        elif op == 0x13 and f3 == 0:
            value = regs[a] + imm
        elif op == 0x33:
            if f7 == 0 and f3 == 0:
                value = regs[a] + regs[b]
            elif f7 == 32 and f3 == 0:
                value = regs[a] - regs[b]
            elif f7 == 1 and f3 == 0:
                value = regs[a] * regs[b]
            elif f7 == 1 and f3 == 4:
                lhs, rhs = signed(regs[a]), signed(regs[b])
                value = -1 if rhs == 0 else (abs(lhs) // abs(rhs)) * (-1 if (lhs < 0) != (rhs < 0) else 1)
            else:
                raise ValueError(f"unsupported register op {word:08x}")
        elif op == 3 and f3 == 2:
            address = (regs[a] + imm) & 0xffffffff
            if address & 3:
                cause = 4
            else:
                value = memory.get(address, 0)
        elif op == 0x23 and f3 == 2:
            offset = signed(((word >> 25) << 5) | ((word >> 7) & 31), 12)
            address = (regs[a] + offset) & 0xffffffff
            if address & 3:
                cause = 6
            else:
                memory[address] = regs[b]
        elif op == 0x63 and f3 in [0, 1]:
            offset = signed(((word >> 31) << 12) | (((word >> 7) & 1) << 11) |
                            (((word >> 25) & 63) << 5) | (((word >> 8) & 15) << 1), 13)
            taken = (regs[a] == regs[b]) if f3 == 0 else (regs[a] != regs[b])
            if taken:
                next_pc = pc + offset
        elif op == 0x6f:
            offset = signed(((word >> 31) << 20) | (((word >> 12) & 255) << 12) |
                            (((word >> 20) & 1) << 11) | (((word >> 21) & 1023) << 1), 21)
            value, next_pc = pc + 4, pc + offset
        elif op == 0x67 and f3 == 0:
            value, next_pc = pc + 4, (regs[a] + imm) & ~1
        elif op == 0x73 and f3 in [1, 2, 3, 5, 6, 7]:
            address = word >> 20
            old = len(retired) if address == 0xb02 else csrs.get(address, 0)
            operand = a if f3 & 4 else regs[a]
            value = old
            if f3 & 3 == 1:
                csrs[address] = operand
            elif operand:
                csrs[address] = (old | operand) if f3 & 3 == 2 else old & ~operand
        else:
            raise ValueError(f"unsupported instruction {word:08x} pc={pc:08x}")
        if cause is not None:
            traps.append({"pc": pc, "cause": cause})
            csrs[0x341] = pc
            next_pc = csrs[0x305] & ~3
        else:
            retired.append(pc)
            if value is not None and rd:
                regs[rd] = value & 0xffffffff
        if pc == labels["done"]:
            return {"retired_pcs": retired, "traps": traps, "memory": memory}
        pc = next_pc & 0xffffffff
    raise RuntimeError("reference watchdog")


def collect_bins(rows, labels, output):
    bins = {name: 0 for name in BINS}
    retired = [row for row in rows if row["event"] == "retired"]
    for i, row in enumerate(retired):
        pc, word = int(row["pc"], 16), int(row["instruction"], 16)
        op, f3, f7 = word & 127, (word >> 12) & 7, word >> 25
        name = None
        if word == 0x13:
            name = "NOP"
        elif word == 0x30200073:
            name = "MRET"
        elif op == 0x33:
            name = {(0, 0): "ADD", (32, 0): "SUB", (1, 0): "MUL", (1, 4): "DIV"}.get((f7, f3))
        elif op in [3, 0x23, 0x6f, 0x67]:
            name = {3: "LW", 0x23: "SW", 0x6f: "JAL", 0x67: "JALR"}[op]
        elif op == 0x63:
            taken = i + 1 < len(retired) and int(retired[i + 1]["pc"], 16) != pc + 4
            name = ("BEQ" if f3 == 0 else "BNE") + ("_taken" if taken else "_not_taken")
        elif op == 0x73:
            name = {1: "CSRRW", 2: "CSRRS", 3: "CSRRC", 5: "CSRRWI", 6: "CSRRSI", 7: "CSRRCI"}.get(f3)
        if name:
            bins[name] += 1
    for row in rows:
        event = row["event"]
        if event in ["bubble", "interrupt"]:
            bins[event] += 1
        elif event == "held":
            bins["stall"] += 1
        elif event == "exception":
            name = {11: "ECALL", 3: "EBREAK", 2: "illegal", 4: "misaligned_load", 6: "misaligned_store"}.get(int(row["cause"]))
            if name:
                bins[name] += 1
    # Require observed poison instructions in a flushed decode slot, and ensure
    # none appears in the retired path. Merely assembling poison is not a hit.
    poison = [labels[name] for name in ["poison0", "poison1", "poison2"] if name in labels]
    if poison:
        assert not set(poison) & {int(row["pc"], 16) for row in retired}
        observed = {int(pc, 16) for pc in re.findall(r"SQUASH pc=([0-9a-fA-F]+)", output)}
        assert observed & set(poison), "no observed flushed poison instruction"
        bins["wrong_path"] = len(observed & set(poison))
    return bins


def main():
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    campaign = HERE / "campaigns" / stamp
    campaign.mkdir(parents=True)

    def run(command, logfile):
        result = subprocess.run([str(x) for x in command], cwd=campaign, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        logfile.write_text(result.stdout)
        return result

    sources = sorted(RTL.glob("*.v")) + [HERE / "tb_checklist.sv"]
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sources + list(HERE.glob("*.S")) + [Path(__file__).resolve()]}
    result = run(["iverilog", "-g2012", "-s", "tb_checklist", "-o", "checklist.vvp", *sources], campaign / "compile.log")
    if result.returncode:
        raise RuntimeError(result.stdout)
    summary = {"campaign": str(campaign), "scope": "29 declared functional bins; not code coverage or architectural signoff",
               "source_sha256": source_hashes, "runs": {}, "bins": {name: 0 for name in BINS}}
    for case in ["operations", "exceptions", "interrupt"]:
        directory = campaign / case
        directory.mkdir()
        image = directory / "program"
        result = run(["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-nostdlib",
                      "-Wl,-Ttext=0x80000000", "-Wl,--no-relax", "-o", image.with_suffix(".elf"), HERE / f"{case}.S"], directory / "build.log")
        assert result.returncode == 0, result.stdout
        result = run(["riscv64-unknown-elf-objcopy", "-O", "binary", "-j", ".text", image.with_suffix(".elf"), image.with_suffix(".bin")], directory / "objcopy.log")
        assert result.returncode == 0, result.stdout
        result = run(["riscv64-unknown-elf-objdump", "-d", image.with_suffix(".elf")], image.with_suffix(".dis"))
        assert result.returncode == 0, result.stdout
        result = run(["riscv64-unknown-elf-nm", "-n", image.with_suffix(".elf")], directory / "symbols.log")
        labels = {a[2]: int(a[0], 16) for line in result.stdout.splitlines() if len(a := line.split()) == 3}
        words = [x[0] for x in struct.iter_unpack("<I", image.with_suffix(".bin").read_bytes())]
        assert len(words) <= 1024
        image.with_suffix(".hex").write_text("\n".join(f"{word:08x}" for word in words + [0x13] * (1024 - len(words))) + "\n")
        reference = execute_reference(words, labels)
        (directory / "reference.json").write_text(json.dumps(reference, indent=2) + "\n")
        (directory / "reference.hex").write_text("\n".join(f"{pc:08x}" for pc in reference["retired_pcs"]) + "\n")
        handler = list(range(labels["handler"], labels["handler_end"], 4)) if case == "interrupt" else []
        if handler:
            (directory / "handler.hex").write_text("\n".join(f"{pc:08x}" for pc in handler) + "\n")
        for wait in [0, 1, 4, 9]:
            trace = directory / f"wait{wait}.csv"
            command = ["vvp", campaign / "checklist.vvp", f"+HEX={image.with_suffix('.hex')}",
                       f"+REFERENCE={directory / 'reference.hex'}", f"+COUNT={len(reference['retired_pcs'])}",
                       f"+DONE={labels['done']:x}", f"+WAIT={wait}", f"+TRACE={trace}",
                       f"+MEM0={reference['memory'].get(0x80001000, 0):x}",
                       f"+MEM1={reference['memory'].get(0x80001004, 0):x}"]
            if handler:
                command += ["+IRQ=1", f"+HANDLER={directory / 'handler.hex'}", f"+HANDLER_COUNT={len(handler)}",
                            f"+TRIGGER={labels['irq_trigger']:x}", f"+IRQ_END={labels['irq_end']:x}"]
            result = run(command, directory / f"wait{wait}.log")
            passed = result.returncode == 0 and "PASS retired=" in result.stdout
            error = None
            bins = {name: 0 for name in BINS}
            if passed:
                try:
                    rows = list(csv.DictReader(trace.open()))
                    traps = [{"pc": int(r["pc"], 16), "cause": int(r["cause"])} for r in rows if r["event"] == "exception"]
                    assert traps == reference["traps"], (traps, reference["traps"])
                    interrupts = [r for r in rows if r["event"] == "interrupt"]
                    assert len(interrupts) == (1 if handler else 0), "missing/extra interrupt"
                    retired = [r for r in rows if r["event"] == "retired"]
                    assert len(retired) == len(reference["retired_pcs"]) + len(handler)
                    bins = collect_bins(rows, labels, result.stdout)
                except Exception as exc:
                    passed, error = False, repr(exc)
            summary["runs"][f"{case}/wait{wait}"] = {"pass": passed, "exit_code": result.returncode,
                "error": error, "bins": bins, "log": str((directory / f"wait{wait}.log").relative_to(campaign))}
            if passed:
                for name in BINS:
                    summary["bins"][name] += bins[name]
            print(case, wait, "PASS" if passed else "FAIL", error or "", flush=True)
    summary["open_bins"] = [name for name in BINS if not summary["bins"][name]]
    summary["closed_bins"] = len(BINS) - len(summary["open_bins"])
    summary["all_runs_pass"] = all(r["pass"] for r in summary["runs"].values())
    summary["functional_checklist_closed"] = summary["all_runs_pass"] and not summary["open_bins"]
    summary["artifact_sha256"] = {str(p.relative_to(campaign)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in campaign.rglob("*") if p.is_file() and p.name != "checklist.vvp"}
    (campaign / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("Campaign:", campaign)
    print("Closed:", summary["closed_bins"], "/", len(BINS), "Open:", summary["open_bins"])
    if not summary["functional_checklist_closed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
