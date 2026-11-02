#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - build the bus timeout monitor test firmware and flash image.

    python build.py                      # toolchain from PATH or the default path
    python build.py --toolchain <bin>    # explicit toolchain bin directory

Same flow as ../regtest/build.py, and it deliberately reuses that directory's
startup.S and link.ld: the trap record layout (g_trap) and the result words at the
DSRAM base must stay identical for soc_montest_tb.sv to read them.

Steps
  1. gcc: ../regtest/startup.S + montest.c -> montest.elf  (rv32i_zicsr)
  2. objdump -> montest.dump, and a check of the instruction mix:
       - no M-extension instructions (mul/div/rem)
       - no byte/half-word loads or stores anywhere. Unlike regtest.c this
         program has no sub-word negative test, so the allow-list is empty.
  3. objcopy -O verilog (byte-wide) -> split into
       montest_imem.hex   ISRAM words, one 32-bit word per line (0x0001_0000)
       montest_dmem.hex   DSRAM words, one 32-bit word per line (0x0002_0000,
                          including the zero-filled result words at the start)
  4. montest_flash.mem    flash byte stream, little-endian, ISRAM then DSRAM
  5. fw_params.svh        NUM_INSTR_WORDS / NUM_DATA_WORDS + image paths for soc_montest_tb.sv
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REGTEST = HERE.parent / "regtest"

ISRAM_BASE, ISRAM_SIZE = 0x0001_0000, 32 * 1024
DSRAM_BASE, DSRAM_SIZE = 0x0002_0000, 32 * 1024
RESULT_ADDR = 0x0002_0000

PREFIXES = ("riscv-none-elf-", "riscv32-unknown-elf-", "riscv64-unknown-elf-")
DEFAULT_BIN = Path("D:/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin")

CFLAGS = [
    "-march=rv32i_zicsr", "-mabi=ilp32", "-mcmodel=medlow",
    "-Os", "-g",
    "-ffreestanding", "-fno-builtin", "-fno-tree-loop-distribute-patterns",
    "-fno-asynchronous-unwind-tables", "-fno-unwind-tables",
    "-mno-relax", "-mstrict-align",
    "-Wall", "-Wextra",
]
LDFLAGS = ["-nostdlib", "-nostartfiles", "-Wl,--no-relax",
           "-T", str(REGTEST / "link.ld"), "-Wl,-Map=montest.map"]

SUBWORD_OPS = {"lb", "lh", "lbu", "lhu", "sb", "sh"}
M_EXT_OPS = {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"}
SUBWORD_ALLOWED_IN = set()


def find_tool(name, bin_dir):
    if bin_dir:
        for prefix in PREFIXES:
            cand = Path(bin_dir) / (prefix + name)
            for ext in ("", ".exe"):
                if Path(str(cand) + ext).is_file():
                    return str(cand) + ext
        sys.exit(f"Error: no {name} with prefixes {PREFIXES} in {bin_dir}")
    for prefix in PREFIXES:
        found = shutil.which(prefix + name)
        if found:
            return found
    if DEFAULT_BIN.is_dir():
        return find_tool(name, DEFAULT_BIN)
    sys.exit(f"Error: {name} not found on PATH; pass --toolchain <bin dir>")


def run(cmd):
    print("  $ " + " ".join(str(c) for c in cmd))
    res = subprocess.run(cmd, cwd=HERE)
    if res.returncode != 0:
        sys.exit(f"Error: command failed ({res.returncode})")


def check_instruction_mix(dump_path):
    func = "?"
    errors = []
    label_re = re.compile(r"^[0-9a-f]+ <([^>]+)>:")
    insn_re = re.compile(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)")
    counts = {}
    for line in dump_path.read_text().splitlines():
        m = label_re.match(line)
        if m:
            func = m.group(1).split(".")[0]
            continue
        m = insn_re.match(line)
        if not m:
            continue
        addr, op = m.group(1), m.group(2)
        counts[op] = counts.get(op, 0) + 1
        if op in M_EXT_OPS:
            errors.append(f"{op} at 0x{addr} in <{func}> (M extension not allowed)")
        if op in SUBWORD_OPS and func not in SUBWORD_ALLOWED_IN:
            errors.append(f"{op} at 0x{addr} in <{func}> (sub-word MMIO access)")
    return errors, counts


def parse_verilog_hex(path):
    mem = {}
    addr = None
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            addr = int(line[1:], 16)
            continue
        for tok in line.split():
            mem[addr] = int(tok, 16)
            addr += 1
    return mem


def words_from(mem, base, size):
    addrs = [a for a in mem if base <= a < base + size]
    if not addrs:
        return []
    n = (max(addrs) - base) // 4 + 1
    words = []
    for i in range(n):
        a = base + 4 * i
        w = 0
        for k in range(4):
            w |= mem.get(a + k, 0) << (8 * k)
        words.append(w)
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--toolchain", help="toolchain bin directory")
    args = ap.parse_args()
    bin_dir = args.toolchain or os.environ.get("RISCV_TOOLCHAIN_BIN")

    if not (REGTEST / "startup.S").is_file() or not (REGTEST / "link.ld").is_file():
        sys.exit(f"Error: expected startup.S and link.ld in {REGTEST}")

    gcc = find_tool("gcc", bin_dir)
    objdump = find_tool("objdump", bin_dir)
    objcopy = find_tool("objcopy", bin_dir)

    print("[1] compile + link (startup.S and link.ld shared with ../regtest)")
    run([gcc, *CFLAGS, *LDFLAGS, str(REGTEST / "startup.S"), "montest.c",
         "-lgcc", "-o", "montest.elf"])

    print("[2] disassemble + instruction-mix check")
    with open(HERE / "montest.dump", "w") as f:
        res = subprocess.run([objdump, "-d", "-M", "no-aliases", "montest.elf"],
                             cwd=HERE, stdout=f)
    if res.returncode != 0:
        sys.exit("Error: objdump failed")
    errors, counts = check_instruction_mix(HERE / "montest.dump")
    if errors:
        print("Instruction-mix check FAILED:")
        for e in errors:
            print("   " + e)
        sys.exit(1)
    print(f"    ok: {sum(counts.values())} instructions, no M-extension, no sub-word access")

    print("[3] split image")
    run([objcopy, "-O", "verilog", "montest.elf", "montest.vh"])
    mem = parse_verilog_hex(HERE / "montest.vh")
    stray = [a for a in mem
             if not (ISRAM_BASE <= a < ISRAM_BASE + ISRAM_SIZE
                     or DSRAM_BASE <= a < DSRAM_BASE + DSRAM_SIZE)]
    if stray:
        sys.exit(f"Error: {len(stray)} loadable bytes outside ISRAM/DSRAM, e.g. 0x{min(stray):08X}")

    instr = words_from(mem, ISRAM_BASE, ISRAM_SIZE)
    data = words_from(mem, DSRAM_BASE, DSRAM_SIZE)
    if not instr:
        sys.exit("Error: no instruction words")

    (HERE / "montest_imem.hex").write_text("".join(f"{w:08X}\n" for w in instr))
    (HERE / "montest_dmem.hex").write_text("".join(f"{w:08X}\n" for w in data))

    print("[4] flash image")
    with open(HERE / "montest_flash.mem", "w") as f:
        for w in instr + data:
            for k in range(4):
                f.write(f"{(w >> (8 * k)) & 0xFF:02X}\n")

    print("[5] testbench parameters")
    # Same file name in every firmware folder: run.f selects the firmware with
    # +incdir+../mem/<fw> alone. Image paths are relative to ips/RTL_SOC/sim/.
    (HERE / "fw_params.svh").write_text(
        "// Generated by ips/RTL_SOC/mem/montest/build.py - do not edit.\n"
        "// `included inside module soc_montest_tb.\n"
        f"localparam int unsigned FW_NUM_INSTR_WORDS = {len(instr)};\n"
        f"localparam int unsigned FW_NUM_DATA_WORDS  = {len(data)};\n"
        f"localparam logic [31:0] FW_RESULT_ADDR       = 32'h{RESULT_ADDR:08X};\n"
        "localparam string       FW_NAME              = \"montest\";\n"
        "localparam string       FW_FLASH_IMAGE       = \"../mem/montest/montest_flash.mem\";\n"
        "localparam string       FW_IMEM_HEX          = \"../mem/montest/montest_imem.hex\";\n"
        "localparam string       FW_DMEM_HEX          = \"../mem/montest/montest_dmem.hex\";\n")

    (HERE / "montest.vh").unlink()

    print()
    print("=====================================================")
    print(" RISCFORGE bus timeout monitor test - image ready")
    print("=====================================================")
    print(f" ISRAM words (NUM_INSTR_WORDS) : {len(instr):5d}  ({4 * len(instr)} B)")
    print(f" DSRAM words (NUM_DATA_WORDS)  : {len(data):5d}  ({4 * len(data)} B)")
    print(f" Flash bytes                   : {4 * (len(instr) + len(data))}")
    print(" Outputs: montest.elf  montest.dump  montest.map  montest_imem.hex")
    print("          montest_dmem.hex  montest_flash.mem  fw_params.svh")
    print("=====================================================")


if __name__ == "__main__":
    main()
