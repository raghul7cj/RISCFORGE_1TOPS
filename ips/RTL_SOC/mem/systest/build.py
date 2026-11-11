#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - build the system test firmware (systest) and its flash image.

    python build.py                      # toolchain from PATH or the default path
    python build.py --toolchain <bin>    # explicit toolchain bin directory

Steps
  1. gcc: startup.S + systest.c -> systest.elf   (rv32i_zicsr, link.ld)
  2. objdump -> systest.dump, and a check of the instruction mix:
       - no M-extension instructions (mul/div/rem)
       - no byte/half-word loads or stores, except in neg_store8 / neg_store16
         (32-bit MMIO rule, FIRMWARE_RULES.md)
  3. objcopy -O verilog (byte-wide, unambiguous endianness) -> split into
       systest_imem.hex   ISRAM words, one 32-bit word per line (from 0x0001_0000)
       systest_dmem.hex   DSRAM words, one 32-bit word per line (from 0x0002_0000,
                          including the zero-filled result words at the start)
  4. systest_flash.mem    flash byte stream, little-endian, flash address 0 first:
                          ISRAM words then DSRAM words. Same format as
                          gen_flash_image.py / the vendor merge_mem() output, and
                          what the bootloader's 0x03 read + RX byte swap expects.
  5. fw_params.svh        NUM_INSTR_WORDS / NUM_DATA_WORDS + image paths for soc_systest_tb.sv

The bootloader loads the first NUM_INSTR_WORDS image words to ISRAM and the
rest to DSRAM, so the DSRAM image must start exactly at 0x0002_0000.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

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
LDFLAGS = ["-nostdlib", "-nostartfiles", "-Wl,--no-relax", "-T", "link.ld",
           "-Wl,-Map=systest.map"]

SUBWORD_OPS = {"lb", "lh", "lbu", "lhu", "sb", "sh"}
M_EXT_OPS = {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"}
SUBWORD_ALLOWED_IN = set()   # systest uses no sub-word accesses at all


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
    """Fail on M-extension ops and on sub-word memory ops (none allowed in
    systest)."""
    func = "?"
    errors = []
    label_re = re.compile(r"^[0-9a-f]+ <([^>]+)>:")
    insn_re = re.compile(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)")
    counts = {}
    for line in dump_path.read_text().splitlines():
        m = label_re.match(line)
        if m:
            func = m.group(1).split(".")[0]   # drop GCC clone suffixes (.constprop.0 etc.)
            continue
        m = insn_re.match(line)
        if not m:
            continue
        addr, op = m.group(1), m.group(2)
        counts[op] = counts.get(op, 0) + 1
        if op in M_EXT_OPS:
            errors.append(f"{op} at 0x{addr} in <{func}> (M extension not allowed)")
        if op in SUBWORD_OPS and func not in SUBWORD_ALLOWED_IN:
            errors.append(f"{op} at 0x{addr} in <{func}> (sub-word access not allowed)")
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

    gcc = find_tool("gcc", bin_dir)
    objdump = find_tool("objdump", bin_dir)
    objcopy = find_tool("objcopy", bin_dir)

    print("[1] compile + link")
    run([gcc, *CFLAGS, *LDFLAGS, "startup.S", "systest.c", "-lgcc", "-o", "systest.elf"])

    print("[2] disassemble + instruction-mix check")
    with open(HERE / "systest.dump", "w") as f:
        res = subprocess.run([objdump, "-d", "-M", "no-aliases", "systest.elf"],
                             cwd=HERE, stdout=f)
    if res.returncode != 0:
        sys.exit("Error: objdump failed")
    errors, counts = check_instruction_mix(HERE / "systest.dump")
    if errors:
        print("Instruction-mix check FAILED:")
        for e in errors:
            print("   " + e)
        sys.exit(1)
    print(f"    ok: {sum(counts.values())} instructions, no M-extension, "
          "no sub-word loads or stores")

    print("[3] split image")
    run([objcopy, "-O", "verilog", "systest.elf", "systest.vh"])
    mem = parse_verilog_hex(HERE / "systest.vh")
    stray = [a for a in mem
             if not (ISRAM_BASE <= a < ISRAM_BASE + ISRAM_SIZE
                     or DSRAM_BASE <= a < DSRAM_BASE + DSRAM_SIZE)]
    if stray:
        sys.exit(f"Error: {len(stray)} loadable bytes outside ISRAM/DSRAM, e.g. 0x{min(stray):08X}")

    instr = words_from(mem, ISRAM_BASE, ISRAM_SIZE)
    data = words_from(mem, DSRAM_BASE, DSRAM_SIZE)
    if not instr:
        sys.exit("Error: no instruction words")

    (HERE / "systest_imem.hex").write_text("".join(f"{w:08X}\n" for w in instr))
    (HERE / "systest_dmem.hex").write_text("".join(f"{w:08X}\n" for w in data))

    print("[4] flash image")
    with open(HERE / "systest_flash.mem", "w") as f:
        for w in instr + data:
            for k in range(4):
                f.write(f"{(w >> (8 * k)) & 0xFF:02X}\n")

    print("[5] testbench parameters")
    # Same file name in every firmware folder: run.f selects the firmware with
    # +incdir+../mem/<fw> alone. Image paths are relative to ips/RTL_SOC/sim/.
    (HERE / "fw_params.svh").write_text(
        "// Generated by ips/RTL_SOC/mem/systest/build.py - do not edit.\n"
        "// `included inside module soc_systest_tb.\n"
        f"localparam int unsigned FW_NUM_INSTR_WORDS = {len(instr)};\n"
        f"localparam int unsigned FW_NUM_DATA_WORDS  = {len(data)};\n"
        f"localparam logic [31:0] FW_RESULT_ADDR       = 32'h{RESULT_ADDR:08X};\n"
        "localparam string       FW_NAME              = \"systest\";\n"
        "localparam string       FW_FLASH_IMAGE       = \"../mem/systest/systest_flash.mem\";\n"
        "localparam string       FW_IMEM_HEX          = \"../mem/systest/systest_imem.hex\";\n"
        "localparam string       FW_DMEM_HEX          = \"../mem/systest/systest_dmem.hex\";\n")

    (HERE / "systest.vh").unlink()

    print()
    print("=====================================================")
    print(" RISCFORGE system test - image ready")
    print("=====================================================")
    print(f" ISRAM words (NUM_INSTR_WORDS) : {len(instr):5d}  ({4 * len(instr)} B)")
    print(f" DSRAM words (NUM_DATA_WORDS)  : {len(data):5d}  ({4 * len(data)} B)")
    print(f" Flash bytes                   : {4 * (len(instr) + len(data))}")
    print(" Outputs: systest.elf  systest.dump  systest.map  systest_imem.hex")
    print("          systest_dmem.hex  systest_flash.mem  fw_params.svh")
    print("=====================================================")


if __name__ == "__main__":
    main()
