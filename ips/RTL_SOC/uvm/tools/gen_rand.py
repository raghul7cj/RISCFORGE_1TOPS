import random
import sys

M32 = 0xFFFFFFFF
POOL = [r for r in range(1, 27)]
BASE_REG = 27
TMP_REG = 28
MEM_BYTES = 256
MEM_BASE = 0x00021000


def s32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


class Cpu:
    def __init__(self):
        self.x = [0] * 32
        self.mem = bytearray(MEM_BYTES)

    def set(self, rd, v):
        if rd:
            self.x[rd] = v & M32

    def ld(self, off, size, signed):
        v = int.from_bytes(self.mem[off:off + size], "little")
        return sext(v, size * 8) & M32 if signed else v

    def st(self, off, size, v):
        self.mem[off:off + size] = (v & ((1 << (size * 8)) - 1)).to_bytes(size, "little")


def alu(op, a, b):
    sa, sb = s32(a), s32(b)
    if op == "add": return a + b
    if op == "sub": return a - b
    if op == "and": return a & b
    if op == "or": return a | b
    if op == "xor": return a ^ b
    if op == "sll": return a << (b & 31)
    if op == "srl": return (a & M32) >> (b & 31)
    if op == "sra": return sa >> (b & 31)
    if op == "slt": return int(sa < sb)
    if op == "sltu": return int((a & M32) < (b & M32))
    if op == "mul": return sa * sb
    if op == "mulh": return (sa * sb) >> 32
    if op == "mulhu": return ((a & M32) * (b & M32)) >> 32
    if op == "mulhsu": return (sa * (b & M32)) >> 32
    if op == "div":
        if sb == 0: return -1
        if sa == -(1 << 31) and sb == -1: return sa
        q = abs(sa) // abs(sb)
        return q if (sa < 0) == (sb < 0) else -q
    if op == "divu":
        return M32 if b == 0 else (a & M32) // (b & M32)
    if op == "rem":
        if sb == 0: return sa
        if sa == -(1 << 31) and sb == -1: return 0
        r = abs(sa) % abs(sb)
        return r if sa >= 0 else -r
    if op == "remu":
        return a if b == 0 else (a & M32) % (b & M32)
    raise ValueError(op)


R_OPS = ["add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu",
         "mul", "mulh", "mulhu", "mulhsu", "div", "divu", "rem", "remu"]
I_OPS = {"addi": "add", "andi": "and", "ori": "or", "xori": "xor", "slti": "slt", "sltiu": "sltu"}
SH_OPS = {"slli": "sll", "srli": "srl", "srai": "sra"}
LOADS = {"lw": (4, True), "lh": (2, True), "lhu": (2, False), "lb": (1, True), "lbu": (1, False)}
STORES = {"sw": 4, "sh": 2, "sb": 1}
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


def br_taken(op, a, b):
    sa, sb = s32(a), s32(b)
    return {"beq": a == b, "bne": a != b, "blt": sa < sb, "bge": sa >= sb,
            "bltu": a < b, "bgeu": a >= b}[op]


def gen(seed, count):
    rnd = random.Random(seed)
    cpu = Cpu()
    out = ['#include "common.h"', "", ".section .text.init", ".globl _start", "_start:"]
    out.append(f"  li   x{BASE_REG}, 0x{MEM_BASE:08X}")
    for off in range(0, MEM_BYTES, 4):
        v = rnd.getrandbits(32)
        cpu.st(off, 4, v)
        out.append(f"  li   x{TMP_REG}, 0x{v:08X}")
        out.append(f"  sw   x{TMP_REG}, {off}(x{BASE_REG})")
    for r in POOL:
        v = rnd.choice([0, 1, M32, 0x80000000, 0x7FFFFFFF, rnd.getrandbits(32), rnd.getrandbits(8)])
        cpu.set(r, v)
        out.append(f"  li   x{r}, 0x{v:08X}")

    recent = []

    def src():
        if recent and rnd.random() < 0.6:
            return rnd.choice(recent[-3:])
        return rnd.choice(POOL + [0])

    prog = []
    for _ in range(count):
        k = rnd.random()
        rd = rnd.choice(POOL)
        if k < 0.40:
            op = rnd.choice(R_OPS)
            prog.append(("r", op, rd, src(), src()))
        elif k < 0.55:
            op = rnd.choice(list(I_OPS))
            prog.append(("i", op, rd, src(), rnd.randint(-2048, 2047)))
        elif k < 0.62:
            op = rnd.choice(list(SH_OPS))
            prog.append(("s", op, rd, src(), rnd.randint(0, 31)))
        elif k < 0.66:
            prog.append(("lui", "lui", rd, 0, rnd.getrandbits(20)))
        elif k < 0.80:
            op = rnd.choice(list(LOADS))
            size = LOADS[op][0]
            prog.append(("ld", op, rd, BASE_REG, rnd.randrange(0, MEM_BYTES, size)))
        elif k < 0.90:
            op = rnd.choice(list(STORES))
            size = STORES[op]
            prog.append(("st", op, 0, src(), rnd.randrange(0, MEM_BYTES, size)))
        else:
            prog.append(("br", rnd.choice(BRANCHES), 0, src(), src(), rnd.randint(1, 3)))
        if prog[-1][0] in ("r", "i", "s", "lui", "ld"):
            recent.append(rd)

    labels = {}
    for idx, ins in enumerate(prog):
        if ins[0] == "br":
            tgt = min(idx + 1 + ins[5], len(prog))
            labels.setdefault(tgt, f"L{seed}_{tgt}")

    out.append(f"rand_body_{seed}:")
    for idx, ins in enumerate(prog):
        if idx in labels:
            out.append(f"{labels[idx]}:")
        t = ins[0]
        if t == "r":
            out.append(f"  {ins[1]:6} x{ins[2]}, x{ins[3]}, x{ins[4]}")
        elif t in ("i", "s"):
            out.append(f"  {ins[1]:6} x{ins[2]}, x{ins[3]}, {ins[4]}")
        elif t == "lui":
            out.append(f"  lui    x{ins[2]}, 0x{ins[4]:05X}")
        elif t == "ld":
            out.append(f"  {ins[1]:6} x{ins[2]}, {ins[4]}(x{BASE_REG})")
        elif t == "st":
            out.append(f"  {ins[1]:6} x{ins[3]}, {ins[4]}(x{BASE_REG})")
        else:
            tgt = min(idx + 1 + ins[5], len(prog))
            out.append(f"  {ins[1]:6} x{ins[3]}, x{ins[4]}, {labels[tgt]}")
    if len(prog) in labels:
        out.append(f"{labels[len(prog)]}:")

    trace = []
    pc = 0
    while pc < len(prog):
        ins = prog[pc]
        t, op = ins[0], ins[1]
        x = cpu.x
        nxt = pc + 1
        if t == "r":
            cpu.set(ins[2], alu(op, x[ins[3]], x[ins[4]]))
        elif t == "i":
            cpu.set(ins[2], alu(I_OPS[op], x[ins[3]], ins[4] & M32))
        elif t == "s":
            cpu.set(ins[2], alu(SH_OPS[op], x[ins[3]], ins[4]))
        elif t == "lui":
            cpu.set(ins[2], ins[4] << 12)
        elif t == "ld":
            size, signed = LOADS[op]
            cpu.set(ins[2], cpu.ld(ins[4], size, signed))
        elif t == "st":
            cpu.st(ins[4], STORES[op], x[ins[3]])
        else:
            if br_taken(op, x[ins[3]], x[ins[4]]):
                nxt = pc + 1 + ins[5]
        if t in ("r", "i", "s", "lui", "ld"):
            trace.append((pc, ins[2], cpu.x[ins[2]], ins))
        pc = nxt
    gen.trace = trace

    for r in POOL:
        out.append(f"  CHECK x{r}, 0x{cpu.x[r]:08X}, {r}")
    for i, off in enumerate(range(0, MEM_BYTES, 4)):
        out.append(f"  lw   x{TMP_REG}, {off}(x{BASE_REG})")
        out.append(f"  CHECK x{TMP_REG}, 0x{cpu.ld(off, 4, False):08X}, {100 + i}")
    out.append("  PASS")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    seed = int(sys.argv[1])
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    sys.stdout.write(gen(seed, count))
