#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - build the Pong demo firmware and its flash image.

    python build.py                      # board image (115200 baud, 30 fps at 40 MHz)
    python build.py --sim                # simulation image, written to sim_build/
    python build.py --toolchain <bin>    # explicit toolchain bin directory

Same flow as ../montest/build.py, reusing ../regtest/startup.S and link.ld.

--sim builds the same pong.c with UART_DIV = 2 (32 clocks per bit) and
FRAME_CYC = 40000, so soc_pong_tb.sv can boot it and run tens of frames in a
few million cycles. Its outputs go to sim_build/ so they can never be confused
with the board image; run.f selects it with +incdir+../mem/pong/sim_build.

Steps
  1. gcc: ../regtest/startup.S + pong.c -> pong.elf  (rv32i_zicsr)
  2. objdump -> pong.dump, and a check of the instruction mix:
       - no M-extension instructions (mul/div/rem)
       - no byte/half-word loads or stores anywhere
  3. objcopy -O verilog (byte-wide) -> split into
       pong_imem.hex   ISRAM words, one 32-bit word per line (0x0001_0000)
       pong_dmem.hex   DSRAM words, one 32-bit word per line (0x0002_0000)
  4. pong_flash.mem    flash byte stream, little-endian, ISRAM then DSRAM
  5. fw_params.svh     word counts, image paths, UART divisor and frame period
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

# Board clock: the Nexys 4 DDR top runs the SoC at 40 MHz (fpga/nexys4ddr).
CLK_HZ, BAUD, FPS = 40_000_000, 115_200, 30
BOARD_CFG = dict(uart_div=(CLK_HZ + 8 * BAUD) // (16 * BAUD), frame_cyc=CLK_HZ // FPS)
SIM_CFG = dict(uart_div=2, frame_cyc=40_000)

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
    ap.add_argument("--sim", action="store_true",
                    help="fast UART / frame rate for soc_pong_tb.sv, output in sim_build/")
    args = ap.parse_args()
    bin_dir = args.toolchain or os.environ.get("RISCV_TOOLCHAIN_BIN")

    cfg = SIM_CFG if args.sim else BOARD_CFG
    out = HERE / "sim_build" if args.sim else HERE
    rel = "../mem/pong/sim_build" if args.sim else "../mem/pong"
    out.mkdir(exist_ok=True)

    if not (REGTEST / "startup.S").is_file() or not (REGTEST / "link.ld").is_file():
        sys.exit(f"Error: expected startup.S and link.ld in {REGTEST}")

    gcc = find_tool("gcc", bin_dir)
    objdump = find_tool("objdump", bin_dir)
    objcopy = find_tool("objcopy", bin_dir)

    elf, dump, vh = out / "pong.elf", out / "pong.dump", out / "pong.vh"
    defines = [f"-DUART_DIV={cfg['uart_div']}u", f"-DFRAME_CYC={cfg['frame_cyc']}u"]
    ldflags = ["-nostdlib", "-nostartfiles", "-Wl,--no-relax",
               "-T", str(REGTEST / "link.ld"), f"-Wl,-Map={out / 'pong.map'}"]

    print(f"[1] compile + link ({'SIMULATION' if args.sim else 'board'}: "
          f"UART_DIV={cfg['uart_div']}, FRAME_CYC={cfg['frame_cyc']})")
    run([gcc, *CFLAGS, *defines, *ldflags, str(REGTEST / "startup.S"), "pong.c",
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

    (out / "pong_imem.hex").write_text("".join(f"{w:08X}\n" for w in instr))
    (out / "pong_dmem.hex").write_text("".join(f"{w:08X}\n" for w in data))

    print("[4] flash image")
    with open(out / "pong_flash.mem", "w") as f:
        for w in instr + data:
            for k in range(4):
                f.write(f"{(w >> (8 * k)) & 0xFF:02X}\n")

    print("[5] testbench parameters")
    # Image paths are relative to ips/RTL_SOC/sim/.
    (out / "fw_params.svh").write_text(
        "// Generated by ips/RTL_SOC/mem/pong/build.py - do not edit.\n"
        "// `included inside module soc_pong_tb.\n"
        f"localparam int unsigned FW_NUM_INSTR_WORDS = {len(instr)};\n"
        f"localparam int unsigned FW_NUM_DATA_WORDS  = {len(data)};\n"
        f"localparam logic [31:0] FW_RESULT_ADDR       = 32'h{RESULT_ADDR:08X};\n"
        f"localparam int unsigned FW_UART_DIV          = {cfg['uart_div']};\n"
        f"localparam int unsigned FW_FRAME_CYC         = {cfg['frame_cyc']};\n"
        "localparam string       FW_NAME              = \"pong\";\n"
        f"localparam string       FW_FLASH_IMAGE       = \"{rel}/pong_flash.mem\";\n"
        f"localparam string       FW_IMEM_HEX          = \"{rel}/pong_imem.hex\";\n"
        f"localparam string       FW_DMEM_HEX          = \"{rel}/pong_dmem.hex\";\n")

    vh.unlink()

    print()
    print("=====================================================")
    print(" RISCFORGE Pong demo - " + ("SIMULATION image (do not flash)" if args.sim
                                       else "board image ready"))
    print("=====================================================")
    print(f" Output dir                    : {out}")
    print(f" ISRAM words (NUM_INSTR_WORDS) : {len(instr):5d}  ({4 * len(instr)} B)")
    print(f" DSRAM words (NUM_DATA_WORDS)  : {len(data):5d}  ({4 * len(data)} B)")
    print(f" Flash bytes                   : {4 * (len(instr) + len(data))}")
    print(" Outputs: pong.elf  pong.dump  pong.map  pong_imem.hex")
    print("          pong_dmem.hex  pong_flash.mem  fw_params.svh")
    print("=====================================================")


if __name__ == "__main__":
    main()
