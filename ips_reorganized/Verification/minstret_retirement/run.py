"""WSL: python3 ips/Verification/minstret_retirement/run.py

Runs real instruction execution against a static architectural path. Optionally
pass --baseline-top build/top_before.v to demonstrate the original failure.
"""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
RTL = HERE.parents[1] / "riscv_core/rtl"
BUILD = HERE / "build"


def run(command, log):
    result = subprocess.run([str(x) for x in command], cwd=BUILD, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    (BUILD / log).write_text(result.stdout)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-top", type=Path)
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    result = run(["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32",
                  "-nostdlib", "-Wl,-Ttext=0x80000000", "-Wl,--no-relax", "-o",
                  BUILD / "program.elf", HERE / "program.S"], "build.log")
    assert result.returncode == 0, result.stdout
    result = run(["riscv64-unknown-elf-objcopy", "-O", "binary", "-j", ".text",
                  BUILD / "program.elf", BUILD / "program.bin"], "objcopy.log")
    assert result.returncode == 0, result.stdout
    raw = (BUILD / "program.bin").read_bytes()
    words = [x[0] for x in struct.iter_unpack("<I", raw)]
    assert len(words) <= 1024
    words.extend([0x00000013] * (1024 - len(words)))
    (BUILD / "program.hex").write_text("\n".join(f"{word:08x}" for word in words) + "\n")
    result = run(["riscv64-unknown-elf-objdump", "-d", BUILD / "program.elf"], "program.dis")
    assert result.returncode == 0, result.stdout
    result = run(["riscv64-unknown-elf-nm", "-n", BUILD / "program.elf"], "symbols.log")
    assert result.returncode == 0, result.stdout
    labels = {a[2]: int(a[0], 16) for line in result.stdout.splitlines()
              if len(a := line.split()) == 3}
    # Explicit program flow: jump over poison, ECALL does not retire, handler
    # returns once, and the two-instruction loop executes exactly three times.
    pcs = (list(range(labels["_start"], labels["wrong_path"], 4)) +
           list(range(labels["target"], labels["fault"], 4)) +
           list(range(labels["handler"], labels["handler_end"], 4)) +
           list(range(labels["resume"], labels["loop"], 4)) +
           list(range(labels["loop"], labels["loop"] + 8, 4)) * 3 +
           list(range(labels["loop"] + 8, labels["done"] + 4, 4)))
    (BUILD / "reference.hex").write_text("\n".join(f"{pc:08x}" for pc in pcs) + "\n")
    variants = [("patched", RTL / "top.v")]
    if args.baseline_top:
        variants.insert(0, ("baseline", args.baseline_top.resolve()))
    evidence = {"expected_count": len(pcs), "expected_pcs": pcs, "runs": {}, "source_sha256": {}}
    for name, top in variants:
        files = [p for p in sorted(RTL.glob("*.v")) if p.name != "top.v"] + [top]
        evidence["source_sha256"][name] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        result = run(["iverilog", "-g2012", "-s", "tb_minstret", "-o", BUILD / f"{name}.vvp",
                      *files, HERE / "tb_minstret.sv"], f"{name}_compile.log")
        assert result.returncode == 0, result.stdout
        for wait in [0, 1, 4, 9]:
            result = run(["vvp", BUILD / f"{name}.vvp", f"+HEX={BUILD / 'program.hex'}",
                          f"+REFERENCE={BUILD / 'reference.hex'}", f"+COUNT={len(pcs)}",
                          f"+DONE={labels['done']:x}", f"+WAIT={wait}"], f"{name}_wait{wait}.log")
            passed = result.returncode == 0 and "PASS expected_retired=" in result.stdout
            evidence["runs"][f"{name}/wait{wait}"] = {"pass": passed, "exit_code": result.returncode,
                                                        "output": result.stdout}
            print(name, wait, "PASS" if passed else "FAIL", flush=True)
    (BUILD / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    assert all(r["pass"] for k, r in evidence["runs"].items() if k.startswith("patched/"))
    if args.baseline_top:
        assert not evidence["runs"]["baseline/wait4"]["pass"], "baseline failed to reproduce"


if __name__ == "__main__":
    main()
