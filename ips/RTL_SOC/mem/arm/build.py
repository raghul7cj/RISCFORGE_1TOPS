#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - build the robotic arm demo firmware and its flash image.

    python build.py                      # board image (SoC 32 MHz, Dynamixel bus 1 Mbps)
    python build.py --toolchain <bin>    # explicit toolchain bin directory

Same flow as ../pong/build.py, reusing ../regtest/startup.S and link.ld.
There is no simulation image: arm.c has no testbench yet.

Steps
  1. gcc: ../regtest/startup.S + arm.c -> arm.elf  (rv32i_zicsr)
  2. objdump -> arm.dump, and a check of the instruction mix:
       - no M-extension instructions (mul/div/rem)
       - no byte/half-word loads or stores anywhere
  3. objcopy -O verilog (byte-wide) -> split into
       arm_imem.hex    ISRAM words, one 32-bit word per line (0x0001_0000)
       arm_dmem.hex    DSRAM words, one 32-bit word per line (0x0002_0000)
  4. arm_flash.mem     flash byte stream, little-endian, ISRAM then DSRAM
  5. fw_params.svh     word counts and image paths (read by top_arm.sv)
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

# Board clock: the Nexys 4 DDR arm top runs the SoC at 32 MHz (fpga/nexys4ddr/arm);
# UART divisor 2 = 1 Mbps, the servos' baud rate. Both are fixed in arm.c.
CLK_HZ, BAUD = 32_000_000, 1_000_000
UART_DIV = CLK_HZ // (16 * BAUD)

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

SUBWORD_OPS = {"lb", "lh", "lbu", "lhu", "sb", "sh"}
M_EXT_OPS = {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"}


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
    """Fail on M-extension ops and on any sub-word memory op."""
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
        if op in SUBWORD_OPS:
            errors.append(f"{op} at 0x{addr} in <{func}> (sub-word access)")
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

    out = HERE
    rel = "../mem/arm"

    if not (REGTEST / "startup.S").is_file() or not (REGTEST / "link.ld").is_file():
        sys.exit(f"Error: expected startup.S and link.ld in {REGTEST}")

    gcc = find_tool("gcc", bin_dir)
    objdump = find_tool("objdump", bin_dir)
    objcopy = find_tool("objcopy", bin_dir)

    elf, dump, vh = out / "arm.elf", out / "arm.dump", out / "arm.vh"
    ldflags = ["-nostdlib", "-nostartfiles", "-Wl,--no-relax",
               "-T", str(REGTEST / "link.ld"), f"-Wl,-Map={out / 'arm.map'}"]

    print(f"[1] compile + link (board: CLK_HZ={CLK_HZ}, UART_DIV={UART_DIV})")
    run([gcc, *CFLAGS, *ldflags, str(REGTEST / "startup.S"), "arm.c",
         "-lgcc", "-o", str(elf)])

    print("[2] disassemble + instruction-mix check")
    with open(dump, "w") as f:
        res = subprocess.run([objdump, "-d", "-M", "no-aliases", str(elf)],
                             cwd=HERE, stdout=f)
    if res.returncode != 0:
        sys.exit("Error: objdump failed")
    errors, counts = check_instruction_mix(dump)
    if errors:
        print("Instruction-mix check FAILED:")
        for e in errors:
            print("   " + e)
        sys.exit(1)
    print(f"    ok: {sum(counts.values())} instructions, no M-extension, no sub-word access")

    print("[3] split image")
    run([objcopy, "-O", "verilog", str(elf), str(vh)])
    mem = parse_verilog_hex(vh)
    stray = [a for a in mem
             if not (ISRAM_BASE <= a < ISRAM_BASE + ISRAM_SIZE
                     or DSRAM_BASE <= a < DSRAM_BASE + DSRAM_SIZE)]
    if stray:
        sys.exit(f"Error: {len(stray)} loadable bytes outside ISRAM/DSRAM, e.g. 0x{min(stray):08X}")

    instr = words_from(mem, ISRAM_BASE, ISRAM_SIZE)
    data = words_from(mem, DSRAM_BASE, DSRAM_SIZE)
    if not instr:
        sys.exit("Error: no instruction words")

    (out / "arm_imem.hex").write_text("".join(f"{w:08X}\n" for w in instr))
    (out / "arm_dmem.hex").write_text("".join(f"{w:08X}\n" for w in data))

    print("[4] flash image")
    with open(out / "arm_flash.mem", "w") as f:
        for w in instr + data:
            for k in range(4):
                f.write(f"{(w >> (8 * k)) & 0xFF:02X}\n")

    print("[5] testbench parameters")
    # Image paths are relative to ips/RTL_SOC/sim/.
    (out / "fw_params.svh").write_text(
        "// Generated by ips/RTL_SOC/mem/arm/build.py - do not edit.\n"
        "// `included inside module top_arm.\n"
        f"localparam int unsigned FW_NUM_INSTR_WORDS = {len(instr)};\n"
        f"localparam int unsigned FW_NUM_DATA_WORDS  = {len(data)};\n"
        f"localparam logic [31:0] FW_RESULT_ADDR       = 32'h{RESULT_ADDR:08X};\n"
        f"localparam int unsigned FW_UART_DIV          = {UART_DIV};\n"
        "localparam string       FW_NAME              = \"arm\";\n"
        f"localparam string       FW_FLASH_IMAGE       = \"{rel}/arm_flash.mem\";\n"
        f"localparam string       FW_IMEM_HEX          = \"{rel}/arm_imem.hex\";\n"
        f"localparam string       FW_DMEM_HEX          = \"{rel}/arm_dmem.hex\";\n")

    vh.unlink()

    print()
    print("=====================================================")
    print(" RISCFORGE robotic arm demo - board image ready")
    print("=====================================================")
    print(f" Output dir                    : {out}")
    print(f" ISRAM words (NUM_INSTR_WORDS) : {len(instr):5d}  ({4 * len(instr)} B)")
    print(f" DSRAM words (NUM_DATA_WORDS)  : {len(data):5d}  ({4 * len(data)} B)")
    print(f" Flash bytes                   : {4 * (len(instr) + len(data))}")
    print(" Outputs: arm.elf  arm.dump  arm.map  arm_imem.hex")
    print("          arm_dmem.hex  arm_flash.mem  fw_params.svh")
    print("=====================================================")


if __name__ == "__main__":
    main()
