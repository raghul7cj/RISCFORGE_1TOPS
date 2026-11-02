#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - root-cause report from a soc_tracer log + the firmware ELF.

    python soc_trace.py TRACE.log --elf app.elf               # failures only
    python soc_trace.py TRACE.log --elf app.elf --all         # every MMIO access
    python soc_trace.py TRACE.log --elf app.elf --txn 57 58   # chosen accesses
    python soc_trace.py TRACE.log --elf app.elf --matrix-csv matrix.csv
    python soc_trace.py --elf app.elf --where 0x102a4         # PC -> asm + C line

Every non-DSRAM data access the core makes is one transaction (t=N in the log).
For each one the report walks the path in order and marks every hop OK / FAIL /
WARN / -- (not applicable or no evidence). The FIRST FAIL is the first point
where the SoC diverged from what the instruction asked for:

  SW        C line + compiled instruction (from the ELF) is really a load/store
  IF        word the core fetched for that PC == word in the ELF
  ID        decode produced the right lsunit control (load/store, funct3)
  EX        address == rs1 + imm, store data == rs2 (architectural shadow of
            the register file, rebuilt from the RET lines) -> ALU / forwarding
  LSU       ls_unit byte enables + lane alignment for the access width
  HMI-REQ   hybrid_mem_interface region decode + exactly one AXI request with
            the same address / data / strobe
  TMON-REQ  request passed axi_lite_timeout_monitor unchanged
  XBAR-REQ  axi_lite_xbar routed it to the APB master port unchanged
  BRIDGE    axi_lite_to_apb: one APB SETUP on the right slot, PADDR / PWRITE /
            PWDATA / PSTRB correct, APB protocol respected
  SPI-PT    (SPI only) bootloader passthrough forwarded it to apb_spi_master
  PERIPH    the peripheral answered (PREADY), in reset or not, PSLVERR, data
  BRIDGE-RSP / XBAR-RSP / TMON-RSP / HMI-RSP  response travelled back unchanged
  LSU-FMT   ls_unit sign/zero extension and lane select of the load data
  WB        instruction retired with that value in rd, or trapped with the
            right cause (5 / 7) when the bus answered with an error

Hangs (STUCK / NO_RETIRE / end of run with an access open) print the state of
every hop and the PC in every pipeline stage, each resolved to asm + C line.
"""

import argparse
import csv
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PREFIXES = ("riscv-none-elf-", "riscv32-unknown-elf-", "riscv64-unknown-elf-")
DEFAULT_BIN = Path("D:/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin")
MASK = 0xFFFF_FFFF

# APB slots in riscforge_soc_subsystem (Section 8). Slot NUM_APB in the log is
# the SPI port behind the bootloader passthrough.
SLOT_NAME = {0: "I2C", 1: "TIMER0", 2: "UART", 3: "GPIO", 4: "SPI", 5: "TIMER1"}
SLOT_RESET = {0: "periph", 1: "periph", 2: "periph", 3: "periph", 4: "spi", 5: "periph"}
# How each slave treats PSTRB. axi_lite_to_apb also word-aligns PADDR, so a
# sub-word store reaches the register at (addr & ~3) with the lane-shifted data.
SLOT_STRB = {
    0: "apb_i2c has no PSTRB port: writes all of PWDATA",
    1: "apb_timer has no PSTRB port: writes all of PWDATA",
    2: "apb_uart ties pstrb='1 into apb_to_obi: register takes PWDATA[7:0]",
    3: "gpio_apb_wrap -> apb_to_reg forces wstrb='1: writes all of PWDATA",
    4: "apb_spi_master has no PSTRB port: writes all of PWDATA",
    5: "apb_timer has no PSTRB port: writes all of PWDATA",
}

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1",
       "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
       "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]

EXC_NAME = {0: "instruction address misaligned", 1: "instruction access fault",
            2: "illegal instruction", 3: "breakpoint", 4: "load address misaligned",
            5: "load access fault", 6: "store address misaligned",
            7: "store access fault", 11: "ecall from M-mode"}
IRQ_NAME = {3: "MSIP", 7: "MTIP (Timer0 ch0 compare)", 11: "MEIP", 16: "GPIO",
            17: "I2C", 18: "SPI event 0", 19: "UART", 20: "Timer0 ch0 overflow",
            21: "Timer0 ch1 overflow", 22: "Timer0 ch1 compare",
            23: "Timer1 ch0 overflow", 24: "Timer1 ch0 compare",
            25: "Timer1 ch1 overflow", 26: "Timer1 ch1 compare",
            27: "SPI end of transfer"}
RESP = {0: "OKAY", 1: "EXOKAY", 2: "SLVERR", 3: "DECERR"}
HMI_WR = {0: "IDLE", 1: "WAIT_ADDR", 2: "WAIT_DATA", 3: "WAIT_RESP"}
HMI_RD = {0: "IDLE", 1: "WAIT_READ"}

# Hop code -> block of the SoC it blames
BLOCK = {
    "SW":         "software / compiler (C source)",
    "IF":         "core IF stage (fetch_cycle, imem_controller, instr_fetch_demux)",
    "ID":         "core ID stage (decode_cycle / Main_Decoder -> lsunit)",
    "EX":         "core EX stage (execute_cycle: ALU / forwarding)",
    "LSU":        "core MEM stage (ls_unit / memory_cycle)",
    "HMI-REQ":    "hybrid_mem_interface (request side)",
    "TMON-REQ":   "axi_lite_timeout_monitor (request side)",
    "XBAR-REQ":   "axi_lite_xbar (request side)",
    "BRIDGE":     "axi_lite_to_apb (APB master)",
    "SPI-PT":     "bootloader APB passthrough",
    "PERIPH":     "peripheral",
    "BRIDGE-RSP": "axi_lite_to_apb (response side)",
    "XBAR-RSP":   "axi_lite_xbar (response side)",
    "TMON-RSP":   "axi_lite_timeout_monitor (response side)",
    "HMI-RSP":    "hybrid_mem_interface (response side)",
    "LSU-FMT":    "core MEM stage (ls_unit load formatting)",
    "WB":         "core WB stage (memory_cycle MEM/WB, wb_trap_mret_commit_controller)",
}


# =============================================================================
#  Toolchain
# =============================================================================
def find_tool(name, bin_dir):
    if bin_dir:
        for prefix in PREFIXES:
            for ext in ("", ".exe"):
                cand = Path(bin_dir) / (prefix + name + ext)
                if cand.is_file():
                    return str(cand)
        sys.exit(f"Error: no {name} with prefixes {PREFIXES} in {bin_dir}")
    for prefix in PREFIXES:
        found = shutil.which(prefix + name)
        if found:
            return found
    if DEFAULT_BIN.is_dir():
        return find_tool(name, DEFAULT_BIN)
    sys.exit(f"Error: {name} not found on PATH; pass --toolchain <bin dir>")


# =============================================================================
#  ELF: loadable bytes (for instruction words and .rodata strings)
# =============================================================================
class Elf:
    def __init__(self, path):
        data = Path(path).read_bytes()
        if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
            sys.exit(f"Error: {path} is not a 32-bit little-endian ELF")
        (shoff,) = struct.unpack_from("<I", data, 0x20)
        shentsize, shnum, _ = struct.unpack_from("<HHH", data, 0x2E)
        self.segs = []
        for i in range(shnum):
            _, typ, flags, addr, off, size = struct.unpack_from("<IIIIII", data, shoff + i * shentsize)
            if typ == 1 and (flags & 0x2) and size:          # PROGBITS + ALLOC
                self.segs.append((addr, data[off:off + size]))

    def byte(self, a):
        for base, blob in self.segs:
            if base <= a < base + len(blob):
                return blob[a - base]
        return None

    def word(self, a):
        b = [self.byte(a + k) for k in range(4)]
        if None in b:
            return None
        return b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24

    def cstr(self, a, maxlen=160):
        if not a:
            return ""
        out = []
        for k in range(maxlen):
            c = self.byte(a + k)
            if c is None:
                return f"<0x{a:08x} not in ELF>" if k == 0 else "".join(out)
            if c == 0:
                break
            out.append(chr(c))
        return "".join(out)


# =============================================================================
#  Disassembly: PC -> symbol, function, file:line, asm
# =============================================================================
SYM_RE = re.compile(r"^([0-9a-f]+) <(.+)>:$")
INS_RE = re.compile(r"^\s+([0-9a-f]+):\s+([0-9a-f]{8}|[0-9a-f]{4})\s+(.*)$")
FUNC_RE = re.compile(r"^([A-Za-z_.$][\w.$]*)\(\):$")
LOC_RE = re.compile(r"^(\S.*):(\d+)(?: \(discriminator \d+\))?$")
INL_RE = re.compile(r"^inlined by (.+):(\d+)(?: \(discriminator \d+\))? \(([^)]+)\)$")


class Disasm:
    def __init__(self, objdump, elf_path, src_dirs):
        # --inlines: for code inlined from a helper (wr32, rd32, ...) objdump
        # also prints the caller's line, which is usually the one that matters.
        res = subprocess.run([objdump, "-d", "-l", "--inlines", "-M", "no-aliases", str(elf_path)],
                             capture_output=True, text=True, errors="replace")
        if res.returncode != 0:
            sys.exit(f"Error: objdump failed:\n{res.stderr}")
        self.ins = {}
        self.src_dirs = [Path(elf_path).resolve().parent] + [Path(d) for d in src_dirs]
        self._src = {}
        sym = func = None
        loc = None
        inl = []
        for line in res.stdout.splitlines():
            m = SYM_RE.match(line)
            if m:
                sym = func = m.group(2)
                loc, inl = None, []
                continue
            m = INS_RE.match(line)
            if m:
                asm = " ".join(m.group(3).split())
                self.ins[int(m.group(1), 16)] = (sym, func, loc, asm, tuple(inl))
                continue
            m = FUNC_RE.match(line)
            if m:
                func = m.group(1)
                continue
            m = INL_RE.match(line)
            if m:
                site = (m.group(1), int(m.group(2)), m.group(3))
                if site not in inl:
                    inl.append(site)
                continue
            m = LOC_RE.match(line)
            if m:
                loc, inl = (m.group(1), int(m.group(2))), []

    def source(self, loc):
        if loc is None:
            return None
        path, ln = loc
        key = path
        if key not in self._src:
            text = None
            for cand in [Path(path)] + [d / Path(path.replace("\\", "/")).name for d in self.src_dirs]:
                try:
                    if cand.is_file():
                        text = cand.read_text(errors="replace").splitlines()
                        break
                except OSError:
                    pass
            self._src[key] = text
        text = self._src[key]
        if text and 1 <= ln <= len(text):
            return text[ln - 1].strip()
        return None

    def where(self, pc):
        """(asm line, C line) for a PC, both as display strings."""
        if pc is None:
            return ("pc unknown", "")
        e = self.ins.get(pc)
        if e is None:
            return (f"0x{pc:08x}  <not in ELF .text>", "")
        sym, func, loc, asm, inl = e
        asm_s = f"0x{pc:08x}  {asm:<34} <{sym}>"
        if loc:
            src = self.source(loc)
            fname = Path(loc[0].replace("\\", "/")).name
            c_s = f"{fname}:{loc[1]}  in {func}()" + (f"   | {src}" if src else "")
            for path, ln, caller in inl:
                src = self.source((path, ln))
                fname = Path(path.replace("\\", "/")).name
                c_s += f"\n          inlined into {fname}:{ln} {caller}()" + (f"   | {src}" if src else "")
        else:
            c_s = f"in {func}()  (no line info: build with -g)"
        return (asm_s, c_s)


# =============================================================================
#  RV32 load/store decode and ls_unit reference model
# =============================================================================
def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def decode(w):
    if w is None:
        return None
    op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
    rs1, rs2 = (w >> 15) & 31, (w >> 20) & 31
    if op == 0x03:
        mn = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}.get(f3)
        return dict(kind="load", mn=mn, f3=f3, rd=rd, rs1=rs1, rs2=None, imm=sext(w >> 20, 12))
    if op == 0x23:
        mn = {0: "sb", 1: "sh", 2: "sw"}.get(f3)
        imm = sext(((w >> 25) << 5) | ((w >> 7) & 31), 12)
        return dict(kind="store", mn=mn, f3=f3, rd=None, rs1=rs1, rs2=rs2, imm=imm)
    return dict(kind=None, mn=None)


def ls_store(f3, addr, rs2):
    """(be, wdata) as ls_unit.v produces them."""
    off = addr & 3
    if f3 == 0:
        return 1 << off, (rs2 << (8 * off)) & MASK
    if f3 == 1:
        return (0x3, rs2) if off < 2 else (0xC, (rs2 << 16) & MASK)
    if f3 == 2:
        return 0xF, rs2
    return 0, 0


def ls_load(f3, addr, raw):
    """Formatted load result as ls_unit.v produces it."""
    off = addr & 3
    if f3 in (0, 4):
        b = (raw >> (8 * off)) & 0xFF
        return (b | 0xFFFFFF00) if (f3 == 0 and b & 0x80) else b
    if f3 in (1, 5):
        h = (raw >> 16) & 0xFFFF if off & 2 else raw & 0xFFFF
        return (h | 0xFFFF0000) if (f3 == 1 and h & 0x8000) else h
    if f3 == 2:
        return raw
    return 0


def misaligned(f3, addr):
    return (f3 == 2 and addr & 3) or (f3 in (1, 5) and addr & 1)


# =============================================================================
#  Trace log
# =============================================================================
EV_RE = re.compile(r"^@(\d+)\s+(\S+)\s*(.*)$")


class Ev:
    __slots__ = ("cyc", "kind", "kv", "line")

    def __init__(self, cyc, kind, kv, line):
        self.cyc, self.kind, self.kv, self.line = cyc, kind, kv, line

    def s(self, k, d=None):
        return self.kv.get(k, d)

    def h(self, k):
        """Hex field; None if missing or X/Z."""
        v = self.kv.get(k)
        if v is None:
            return None
        try:
            return int(v.rstrip("~"), 16)
        except ValueError:
            return None

    def n(self, k, d=None):
        v = self.kv.get(k)
        try:
            return int(v)
        except (TypeError, ValueError):
            return d


def parse_trace(path):
    evs = []
    with open(path, errors="replace") as f:
        for line in f:
            m = EV_RE.match(line)
            if not m:
                continue
            kv = {}
            for tok in m.group(3).split():
                if "=" in tok:
                    k, v = tok.split("=", 1)
                    kv[k] = v
            evs.append(Ev(int(m.group(1)), m.group(2), kv, line.rstrip("\n")))
    return evs


class Txn:
    def __init__(self, tid, req):
        self.tid = tid
        self.req = req
        self.hops = []            # HS / APB_SETUP / APB_DONE / PROTO / TMO tagged t=tid
        self.done = None          # LSU_DONE or LSU_ABORT
        self.commit = None        # RET or TRAP for this pc
        self.exp_addr = None      # from the register shadow
        self.exp_rs2 = None
        self.rst = {}             # reset levels when the access started
        self.section = ""
        self.fw = []              # firmware mailbox records that point at it
        self.dup_of = None
        self.result = None        # list of (code, status, text)


# =============================================================================
#  Analysis
# =============================================================================
class Analysis:
    def __init__(self, evs, elf, dis):
        self.evs, self.elf, self.dis = evs, elf, dis
        self.txns = {}
        self.order = []
        self.xbar_map, self.apb_map = [], []
        self.cfg = {}
        self.clk = None
        self.traps, self.protos, self.tmos, self.hangs = [], [], [], []
        self.fw_records = []
        self.unlinked_hops = []
        self.retired = 0
        self.end = None
        self.ingest()

    # ---------------------------------------------------------------- ingest
    def ingest(self):
        shadow = [None] * 32
        shadow[0] = 0
        rst = {}
        issued = {}               # pc -> tid, cleared at RET / TRAP of that pc
        awaiting = {}             # pc -> txn, waiting for its RET / TRAP
        mbox = {}
        section = ""
        evs = self.evs
        i = 0
        while i < len(evs):
            e = evs[i]
            k = e.kind
            if k == "CLK":
                self.clk = (float(e.s("t0", 0)), float(e.s("period", 0)))
            elif k == "CFG":
                self.cfg = dict(e.kv)
            elif k == "MAP":
                rule = (e.n("idx"), e.h("start"), e.h("end"))
                (self.xbar_map if e.s("bus") == "XBAR" else self.apb_map).append(rule)
            elif k == "RST":
                rst[e.s("name")] = e.s("val")
            elif k == "RET":
                self.retired += 1
                pc = e.h("pc")
                rd = e.n("rd", 0)
                if rd:
                    shadow[rd] = e.h("val")
                issued.pop(pc, None)
                t = awaiting.pop(pc, None)
                if t is not None:
                    t.commit = e
            elif k == "TRAP":
                self.traps.append(e)
                pc = e.h("pc")
                issued.clear()
                t = awaiting.pop(pc, None)
                if t is not None:
                    t.commit = e
            elif k == "LSU_REQ":
                tid = e.n("t")
                t = Txn(tid, e)
                t.rst = dict(rst)
                t.section = section
                d = decode(self.elf.word(e.h("pc")) if e.h("pc") is not None else None)
                if d and d.get("kind"):
                    a = shadow[d["rs1"]]
                    if a is not None:
                        t.exp_addr = (a + d["imm"]) & MASK
                    if d["kind"] == "store":
                        t.exp_rs2 = shadow[d["rs2"]]
                pc = e.h("pc")
                if pc in issued:
                    t.dup_of = issued[pc]
                issued[pc] = tid
                self.txns[tid] = t
                self.order.append(tid)
            elif k in ("HS", "APB_SETUP", "APB_DONE", "PROTO", "TMO"):
                if k == "PROTO":
                    self.protos.append(e)
                if k == "TMO":
                    self.tmos.append(e)
                t = self.txns.get(e.n("t", 0))
                if t is not None:
                    t.hops.append(e)
                else:
                    self.unlinked_hops.append(e)
            elif k in ("LSU_DONE", "LSU_ABORT"):
                t = self.txns.get(e.n("t", 0))
                if t is not None:
                    t.done = e
                    if k == "LSU_DONE":
                        awaiting[t.req.h("pc")] = t
            elif k == "MBOX":
                section = self.mailbox(e, mbox, section)
            elif k in ("STUCK", "NO_RETIRE"):
                block = [e]
                j = i + 1
                while j < len(evs) and evs[j].kind in ("STATE", "PIPE", "RING"):
                    block.append(evs[j])
                    j += 1
                self.hangs.append(block)
                i = j
                continue
            elif k == "END":
                block = [e]
                j = i + 1
                while j < len(evs) and evs[j].kind in ("STATE", "PIPE", "RING"):
                    block.append(evs[j])
                    j += 1
                self.end = block
                i = j
                continue
            i += 1

    # --------------------------------------------------- regtest mailbox decode
    def mailbox(self, e, mbox, section):
        """ips/mem_files/regtest protocol: 7 words at the mailbox base, CMD last."""
        base = int(self.cfg.get("mbox", "00020000-0").split("-")[0], 16)
        addr = e.h("addr")
        val = e.h("wdata")
        if addr is None or val is None:
            return section
        mbox[addr] = val
        if addr != base:
            return section
        rec = dict(cyc=e.cyc, cmd=val,
                   ip=self.elf.cstr(mbox.get(base + 4, 0)),
                   name=self.elf.cstr(mbox.get(base + 8, 0)),
                   sub=self.elf.cstr(mbox.get(base + 12, 0)),
                   addr=mbox.get(base + 16), exp=mbox.get(base + 20), got=mbox.get(base + 24),
                   pc=e.h("pc"), section=section, txn=None)
        if val == 3:
            section = rec["name"]
        elif val in (2, 4) and rec["addr"] is not None:
            # The access the firmware is reporting on: the latest one to that
            # word. A FAIL is a value check, so prefer the latest READ of it.
            hits = [tid for tid in reversed(self.order)
                    if self.txns[tid].req.h("addr") is not None
                    and (self.txns[tid].req.h("addr") & ~3) == (rec["addr"] & ~3)
                    and self.txns[tid].req.cyc <= e.cyc]
            if val == 2:
                reads = [tid for tid in hits if self.txns[tid].req.s("we") == "0"]
                hits = reads or hits
            if hits:
                rec["txn"] = hits[0]
                self.txns[hits[0]].fw.append(rec)
        self.fw_records.append(rec)
        return section

    # ---------------------------------------------------------------- helpers
    def slot_of(self, addr):
        for idx, s, e in self.apb_map:
            if s is not None and s <= addr < e:
                return idx
        return None

    def xbar_of(self, addr):
        for idx, s, e in self.xbar_map:
            if s is not None and s <= addr < e:
                return idx
        return None

    def mmio_range(self):
        r = self.cfg.get("mmio", "40000000-4fffffff").split("-")
        return int(r[0], 16), int(r[1], 16)

    def ns(self, cyc):
        if not self.clk or not self.clk[1]:
            return ""
        return f"{self.clk[0] + cyc * self.clk[1]:.0f} ns"

    # ------------------------------------------------------------ hop checker
    def check(self, t):
        R = []

        def add(code, status, text):
            R.append((code, status, text))

        q = t.req
        pc, addr, we = q.h("pc"), q.h("addr"), q.s("we") == "1"
        be, wdata, rs2v, lsunit = q.h("be"), q.h("wdata"), q.h("rs2"), q.h("lsunit")
        elf_w = self.elf.word(pc) if pc is not None else None
        d = decode(elf_w)
        hs = lambda port, ch: [h for h in t.hops if h.kind == "HS" and h.s("port") == port and h.s("ch") == ch]
        setups = [h for h in t.hops if h.kind == "APB_SETUP"]
        dones = [h for h in t.hops if h.kind == "APB_DONE"]
        protos = [h for h in t.hops if h.kind == "PROTO"]
        tmos = [h for h in t.hops if h.kind == "TMO"]
        late = [h for h in t.hops if h.s("o") == "0"]
        fw_busresp = [r for r in t.fw if r["cmd"] == 4]
        expect_err = None
        if fw_busresp and fw_busresp[0]["exp"] is not None:
            expect_err = fw_busresp[0]["exp"] & 3

        # ---- SW
        if d is None:
            add("SW", "FAIL", f"PC 0x{pc:08x} is not in the ELF: core executed outside the program" if pc is not None
                else "PC unknown")
        elif not d["kind"] or not d["mn"]:
            add("SW", "FAIL", f"ELF word 0x{elf_w:08x} at this PC is not a load/store, but MEM issued a data access")
        else:
            regs = f"{ABI[d['rd']]}, " if d["kind"] == "load" else f"{ABI[d['rs2']]}, "
            add("SW", "OK", f"{d['mn']} {regs}{d['imm']}({ABI[d['rs1']]})")

        # ---- IF
        if q.s("known") != "1":
            add("IF", "--", "ID-stage word for this PC not captured")
        elif elf_w is None:
            add("IF", "--", "no ELF word to compare")
        elif q.h("instr") != elf_w:
            add("IF", "FAIL", f"core decoded 0x{q.h('instr'):08x}, ELF has 0x{elf_w:08x} at 0x{pc:08x}")
        else:
            add("IF", "OK", f"fetched 0x{elf_w:08x} == ELF")

        if not d or not d.get("kind") or not d.get("mn"):
            t.result = R
            return R
        if addr is None or be is None or wdata is None:
            add("LSU", "FAIL", f"X/Z on the LSU bus: addr={q.s('addr')} be={q.s('be')} wdata={q.s('wdata')}")
            t.result = R
            return R
        is_store = d["kind"] == "store"
        f3 = d["f3"]

        # ---- ID
        if lsunit is None:
            add("ID", "--", "lsunit unknown")
        else:
            exp_l = 0x10 | (0x08 if is_store else 0) | f3
            if lsunit != exp_l or we != is_store:
                add("ID", "FAIL", f"lsunitM=0x{lsunit:02x} we={int(we)}, expected 0x{exp_l:02x} we={int(is_store)} for {d['mn']}")
            else:
                add("ID", "OK", f"lsunitM=0x{lsunit:02x} ({d['mn']})")

        # ---- EX
        ex_bad = []
        if t.exp_addr is not None and addr is not None and t.exp_addr != addr:
            ex_bad.append(f"address 0x{addr:08x}, but {ABI[d['rs1']]}{d['imm']:+d} = 0x{t.exp_addr:08x}")
        if is_store and t.exp_rs2 is not None and rs2v is not None and t.exp_rs2 != rs2v:
            ex_bad.append(f"store data {ABI[d['rs2']]}=0x{rs2v:08x}, architectural value 0x{t.exp_rs2:08x}")
        if ex_bad:
            add("EX", "FAIL", "; ".join(ex_bad) + "  (stale operand -> forwarding / hazard)")
        elif t.exp_addr is None:
            add("EX", "--", f"{ABI[d['rs1']]} not known yet (no RET wrote it); address 0x{addr:08x}")
        else:
            add("EX", "OK", f"address 0x{addr:08x} = {ABI[d['rs1']]}{d['imm']:+d}"
                + (f", data {ABI[d['rs2']]}=0x{rs2v:08x}" if is_store else ""))

        # ---- LSU
        lsu_bad = []
        if misaligned(f3, addr):
            lsu_bad.append(f"misaligned {d['mn']} reached the bus (should trap with cause {6 if is_store else 4})")
        if is_store:
            eb, ew = ls_store(f3, addr, rs2v if rs2v is not None else 0)
            if be != eb:
                lsu_bad.append(f"be=0x{be:x}, expected 0x{eb:x}")
            if rs2v is not None and wdata != ew:
                lsu_bad.append(f"wdata=0x{wdata:08x}, expected 0x{ew:08x}")
        if t.dup_of is not None:
            lsu_bad.append(f"same instruction already issued as t={t.dup_of} without retiring: "
                           "MEM presented the access twice (duplicate MMIO side effect)")
        if t.done is not None and t.done.kind == "LSU_ABORT":
            lsu_bad.append("access left MEM before the bus answered (flush/trap while in flight); "
                           f"HMI wr={HMI_WR.get(t.done.n('hmi_wr'), '?')} rd={HMI_RD.get(t.done.n('hmi_rd'), '?')}")
        if lsu_bad:
            add("LSU", "FAIL", "; ".join(lsu_bad))
        else:
            add("LSU", "OK", f"be=0x{be:x}" + (f" wdata=0x{wdata:08x}" if is_store else ""))

        # ---- region decode in hybrid_mem_interface
        lo, hi = self.mmio_range()
        in_mmio = lo <= addr <= hi
        req_ch = ["AW", "W"] if is_store else ["AR"]
        rsp_ch = "B" if is_store else "R"
        hmi_req = {c: hs("HMI", c) for c in req_ch}
        if not in_mmio:
            if any(hmi_req.values()):
                add("HMI-REQ", "FAIL", f"0x{addr:08x} is outside DSRAM and MMIO but an AXI request was issued")
            elif t.done is not None and t.done.s("err") == "1":
                add("HMI-REQ", "OK", f"0x{addr:08x} unmapped -> mem_err without bus traffic (addr_fault)")
                add("SW", "WARN", f"address 0x{addr:08x} is neither DSRAM nor MMIO (software address bug?)")
            else:
                add("HMI-REQ", "FAIL", f"0x{addr:08x} unmapped but mem_err was not raised")
            self._commit(t, d, add, expect_trap=True)
            t.result = R
            return R

        # ---- HMI request
        bad = []
        for c in req_ch:
            if not hmi_req[c]:
                bad.append(f"no {c} handshake")
            elif len(hmi_req[c]) > 1:
                bad.append(f"{len(hmi_req[c])} {c} handshakes for one access")
        if not bad:
            if is_store:
                aw, w = hmi_req["AW"][0], hmi_req["W"][0]
                if aw.h("addr") != addr:
                    bad.append(f"AW addr 0x{aw.h('addr'):08x} != 0x{addr:08x}")
                if w.h("data") != wdata or w.h("strb") != be:
                    bad.append(f"W data/strb 0x{w.h('data'):08x}/{w.h('strb'):x} != 0x{wdata:08x}/{be:x}")
            elif hmi_req["AR"][0].h("addr") != addr:
                bad.append(f"AR addr 0x{hmi_req['AR'][0].h('addr'):08x} != 0x{addr:08x}")
        if bad:
            add("HMI-REQ", "FAIL", "; ".join(bad))
        else:
            add("HMI-REQ", "OK", " ".join(f"{c}(wait {hmi_req[c][0].n('wait')})" for c in req_ch))

        # ---- timeout monitor + crossbar request
        def same_req(port):
            out = []
            for c in req_ch:
                a, b = hs("HMI", c), hs(port, c)
                if not b:
                    out.append(f"no {c}")
                elif a and {k: v for k, v in a[0].kv.items() if k in ("addr", "data", "strb")} != \
                        {k: v for k, v in b[0].kv.items() if k in ("addr", "data", "strb")}:
                    out.append(f"{c} changed: {a[0].line.split(c, 1)[-1].strip()} -> {b[0].line.split(c, 1)[-1].strip()}")
            return out

        xs_bad = same_req("XS")
        add("TMON-REQ", "FAIL" if xs_bad else "OK", "; ".join(xs_bad) or "passed through unchanged")

        xidx = self.xbar_of(addr)
        xm_bad = same_req("XM")
        xs_rsp = hs("XS", rsp_ch)
        if xidx is None:
            if xm_bad:      # nothing reached the bridge: expected
                r = xs_rsp[0].n("resp") if xs_rsp else None
                add("XBAR-REQ", "OK" if r == 3 else "FAIL",
                    f"0x{addr:08x} not in the crossbar map -> {'DECERR as expected' if r == 3 else 'expected DECERR, got ' + RESP.get(r, 'nothing')}")
                add("SW", "WARN", f"address 0x{addr:08x} is not mapped in the crossbar (software address bug?)")
                self._resp_chain(t, d, add, rsp_ch, None, is_store, expect_err)
                t.result = R
                return R
            add("XBAR-REQ", "FAIL", f"0x{addr:08x} is not mapped but reached the APB master port")
        elif xidx != 2:
            add("XBAR-REQ", "--", f"routed to crossbar master {xidx} (not traced)")
        else:
            add("XBAR-REQ", "FAIL" if xm_bad else "OK", "; ".join(xm_bad) or "routed to MST[2] (APB bridge) unchanged")

        # ---- APB bridge
        slot = self.slot_of(addr)
        nslot = int(self.cfg.get("napb", 6))
        apb_set = [s for s in setups if s.n("slot") != nslot]
        pt_set = [s for s in setups if s.n("slot") == nslot]
        apb_done = [s for s in dones if s.n("slot") != nslot]
        pt_done = [s for s in dones if s.n("slot") == nslot]
        b_bad = []
        if slot is None:
            if apb_set:
                b_bad.append(f"0x{addr:08x} is in no APB rule but slot {apb_set[0].n('slot')} was selected")
            if b_bad:
                add("BRIDGE", "FAIL", "; ".join(b_bad))
            else:
                add("BRIDGE", "OK", f"0x{addr:08x} in no APB rule -> no PSEL, bridge answers DECERR")
                add("SW", "WARN", f"address 0x{addr:08x} is in the APB window but no peripheral decodes it")
            self._resp_chain(t, d, add, rsp_ch, None, is_store, expect_err)
            t.result = R
            return R
        name = SLOT_NAME.get(slot, f"slot{slot}")
        if is_store and be == 0:
            b_bad.append("write with PSTRB=0 is dropped by axi_lite_to_apb (OKAY, no APB transfer)")
        if not apb_set:
            b_bad.append(f"no APB SETUP on slot {slot} ({name})")
        else:
            if len(apb_set) > 1:
                b_bad.append(f"{len(apb_set)} APB transfers for one access")
            s = apb_set[0]
            if s.n("slot") != slot:
                b_bad.append(f"PSEL on slot {s.n('slot')} ({SLOT_NAME.get(s.n('slot'))}), expected {slot} ({name})")
            if s.h("paddr") != addr & ~3:
                b_bad.append(f"PADDR 0x{s.h('paddr'):08x}, expected 0x{addr & ~3:08x}")
            if (s.s("write") == "1") != is_store:
                b_bad.append(f"PWRITE={s.s('write')}")
            if is_store and (s.h("pwdata") != wdata or s.h("pstrb") != be):
                b_bad.append(f"PWDATA/PSTRB 0x{s.h('pwdata'):08x}/{s.h('pstrb'):x} != 0x{wdata:08x}/{be:x}")
        ap = [p for p in protos if p.s("bus") == "APB"]
        for p in ap:
            b_bad.append(f"APB protocol (slot {p.s('slot')}): {p.s('msg')}")
        add("BRIDGE", "FAIL" if b_bad else "OK", "; ".join(b_bad) or
            f"SETUP slot {slot} ({name}) PADDR=0x{apb_set[0].h('paddr'):08x}"
            + (f" PWDATA=0x{apb_set[0].h('pwdata'):08x} PSTRB={apb_set[0].h('pstrb'):x}" if is_store else ""))

        # ---- SPI passthrough
        if slot == 4:
            if not pt_set:
                add("SPI-PT", "FAIL", "bootloader did not forward the transfer to apb_spi_master")
            else:
                s = pt_set[0]
                ok = s.h("paddr") == (addr & ~3) and (s.s("write") == "1") == is_store and \
                    (not is_store or s.h("pwdata") == wdata)
                add("SPI-PT", "OK" if ok else "FAIL",
                    "forwarded unchanged" if ok else f"forwarded as {s.line.split('APB_SETUP', 1)[-1].strip()}")

        # ---- peripheral
        p_bad, p_warn, p_txt = [], [], ""
        rn = SLOT_RESET.get(slot)
        if rn and t.rst.get(rn) != "1":
            p_bad.append(f"{rn}_rst_n={t.rst.get(rn, '?')} when the access started (peripheral held in reset)")
        done = (pt_done if slot == 4 and pt_done else apb_done)
        bdone = apb_done[0] if apb_done else None
        tmo_apb = [x for x in tmos if x.s("kind") == "APB"]
        if bdone is None:
            p_bad.append(f"{name} never completed the ACCESS phase (no PREADY)")
        else:
            if bdone.s("slv_pready") != "1":
                p_bad.append(f"apb_timeout_monitor answered after {bdone.n('waits')} wait states: {name} never raised PREADY")
            elif bdone.s("slv_pslverr") == "1":
                if expect_err == 2:
                    p_txt = "PSLVERR, expected by the firmware (BUSRESP SLVERR)"
                else:
                    p_bad.append(f"{name} answered PSLVERR")
            if not p_txt:
                p_txt = (f"PREADY after {bdone.n('waits')} wait states"
                         + ("" if is_store else f", PRDATA=0x{bdone.h('slv_prdata'):08x}"))
        if tmo_apb:
            p_bad.append(f"APB timeout pulse on slot {tmo_apb[0].s('slot')}")
        if is_store and be not in (0xF, 0):
            p_warn.append(f"sub-word store: {SLOT_STRB.get(slot, 'slave ignores PSTRB')}; register at "
                          f"0x{addr & ~3:08x} receives PWDATA=0x{wdata:08x}, not just the byte(s) in PSTRB={be:x}")
        if not is_store and f3 != 2 and addr & 3:
            p_warn.append(f"sub-word read at byte offset {addr & 3}: slave returns its whole register, "
                          f"ls_unit picks lane {addr & 3}")
        if p_bad:
            add("PERIPH", "FAIL", f"{name}: " + "; ".join(p_bad))
        else:
            add("PERIPH", "OK", f"{name}: {p_txt}")
        for w in p_warn:
            add("PERIPH", "WARN", w)
        if late:
            add("PERIPH", "WARN", f"{len(late)} bus event(s) for this access arrived after the core had moved on")

        self._resp_chain(t, d, add, rsp_ch, bdone, is_store, expect_err)
        t.result = R
        return R

    def _resp_chain(self, t, d, add, rsp_ch, bdone, is_store, expect_err):
        hs = lambda port: [h for h in t.hops if h.kind == "HS" and h.s("port") == port and h.s("ch") == rsp_ch]
        xm, xs, hmi = hs("XM"), hs("XS"), hs("HMI")
        tmo_axi = [x for x in t.hops if x.kind == "TMO" and x.s("kind", "").startswith("AXI")]

        def val(h):
            if not h:
                return None
            return (h[0].n("resp"), None if is_store else h[0].h("data"))

        def fmt(v):
            if v is None:
                return "nothing"
            return RESP.get(v[0], "?") + ("" if v[1] is None else f" 0x{v[1]:08x}")

        # bridge: APB -> AXI translation
        if bdone is not None:
            exp = (2 if bdone.s("pslverr") == "1" else 0, None if is_store else bdone.h("prdata"))
            got = val(xm)
            add("BRIDGE-RSP", "OK" if got == exp else "FAIL",
                f"{rsp_ch} {fmt(got)}" if got == exp else f"APB gave {fmt(exp)}, bridge returned {fmt(got)}")
        # crossbar
        if xm or bdone is not None:
            add("XBAR-RSP", "OK" if val(xs) == val(xm) else "FAIL",
                f"{fmt(val(xs))}" if val(xs) == val(xm) else f"MST[2] {fmt(val(xm))} -> SLV[0] {fmt(val(xs))}")
        # timeout monitor
        if tmo_axi:
            add("TMON-RSP", "FAIL", f"axi_lite_timeout_monitor fired ({tmo_axi[0].s('kind')}): answered the core itself with {fmt(val(hmi))}")
        else:
            add("TMON-RSP", "OK" if val(hmi) == val(xs) else "FAIL",
                f"{fmt(val(hmi))}" if val(hmi) == val(xs) else f"SLV[0] {fmt(val(xs))} -> core {fmt(val(hmi))}")
        # HMI -> LSU
        dn = t.done
        if dn is None:
            add("HMI-RSP", "FAIL", "access never completed in MEM (no LSU_DONE): see STUCK / END state")
            return
        if dn.kind == "LSU_ABORT":
            add("HMI-RSP", "--", "access aborted before the response")
            return
        resp = hmi[0].n("resp") if hmi else None
        err = dn.s("err") == "1"
        bad = []
        if resp is None:
            bad.append("core released the access without a response handshake")
        elif err != (resp != 0):
            bad.append(f"mem_err={int(err)} for response {RESP.get(resp)}")
        if not is_store and hmi and dn.h("rdata") != hmi[0].h("data"):
            bad.append(f"lsu_mem_rdata 0x{dn.h('rdata'):08x} != R data 0x{hmi[0].h('data'):08x}")
        add("HMI-RSP", "FAIL" if bad else "OK", "; ".join(bad) or
            (f"mem_err={int(err)}" + ("" if is_store else f" rdata=0x{dn.h('rdata'):08x}")))
        if expect_err is not None and resp is not None and resp != expect_err:
            add("HMI-RSP", "FAIL", f"firmware expected {RESP.get(expect_err)}, bus returned {RESP.get(resp)}")
        if not is_store and not err:
            ef = ls_load(d["f3"], t.req.h("addr"), dn.h("rdata"))
            add("LSU-FMT", "OK" if dn.h("fmt") == ef else "FAIL",
                f"{d['mn']} -> 0x{ef:08x}" if dn.h("fmt") == ef
                else f"ls_unit gave 0x{dn.h('fmt'):08x}, {d['mn']} of 0x{dn.h('rdata'):08x} @+{t.req.h('addr') & 3} is 0x{ef:08x}")
        self._commit(t, d, add, expect_trap=err)

    def _commit(self, t, d, add, expect_trap):
        c = t.commit
        is_store = d["kind"] == "store"
        if c is None:
            add("WB", "--", "no RET/TRAP for this PC in the log")
            return
        if expect_trap:
            want = 7 if is_store else 5
            if c.kind != "TRAP":
                add("WB", "FAIL", f"bus error but the instruction retired (expected trap cause {want})")
            elif c.n("cause") != want or c.h("tval") != t.req.h("addr"):
                add("WB", "FAIL", f"trap cause {c.n('cause')} tval 0x{c.h('tval'):08x}, expected {want} / 0x{t.req.h('addr'):08x}")
            else:
                add("WB", "OK", f"trap cause {want} ({EXC_NAME[want]}), mtval=0x{c.h('tval'):08x}")
            return
        if c.kind == "TRAP":
            add("WB", "FAIL", f"trapped with cause {c.n('cause')} ({EXC_NAME.get(c.n('cause'), '?')}) though the bus said OKAY")
            return
        if is_store or d["rd"] == 0:
            add("WB", "OK", "retired")
            return
        exp = t.done.h("fmt") if t.done is not None else None
        if c.n("rd") != d["rd"] or (exp is not None and c.h("val") != exp):
            add("WB", "FAIL", f"wrote {ABI[c.n('rd', 0)]}=0x{c.h('val'):08x}, expected {ABI[d['rd']]}=0x{exp:08x}")
        else:
            add("WB", "OK", f"{ABI[d['rd']]} <= 0x{c.h('val'):08x}")


# =============================================================================
#  Report
# =============================================================================
MARK = {"OK": "[ OK ]", "FAIL": "[FAIL]", "WARN": "[WARN]", "--": "[ -- ]"}


def verdict(res):
    fails = [r for r in res if r[1] == "FAIL"]
    warns = [r for r in res if r[1] == "WARN"]
    return (fails[0] if fails else None), warns


def access_name(an, t):
    d = decode(an.elf.word(t.req.h("pc")) if t.req.h("pc") is not None else None)
    return (d or {}).get("mn") or ("st?" if t.req.s("we") == "1" else "ld?")


def target_name(an, t):
    a = t.req.h("addr")
    if a is None:
        return "?"
    lo, hi = an.mmio_range()
    if not lo <= a <= hi:
        return "UNMAPPED"
    s = an.slot_of(a)
    return SLOT_NAME.get(s, "APB-HOLE") if s is not None else "APB-HOLE"


def print_txn(an, t, out):
    res = t.result
    first, warns = verdict(res)
    q = t.req
    asm, csrc = an.dis.where(q.h("pc"))
    head = f"t={t.tid}  @cyc {q.cyc} {an.ns(q.cyc)}  {access_name(an, t).upper()} 0x{q.h('addr'):08x} -> {target_name(an, t)}"
    if t.section:
        head += f"   [section: {t.section}]"
    out(head)
    out(f"   C    : {csrc}")
    out(f"   ASM  : {asm}")
    if first:
        out(f"   FIRST DIVERGENCE: {first[0]} = {BLOCK.get(first[0], first[0])}")
        if first[0] == "PERIPH":
            out(f"                     ({first[2]})")
    elif warns:
        out(f"   path clean, {len(warns)} warning(s)")
    for rec in t.fw:
        if rec["cmd"] == 2:
            label = ".".join(x for x in (rec["ip"], rec["name"]) if x) or "(no name)"
            out(f"   FW FAIL: {label}" + (f" : {rec['sub']}" if rec["sub"] else "")
                + f"  exp 0x{rec['exp'] or 0:08x}  got 0x{rec['got'] or 0:08x}")
            if not first:
                out("   -> every hop carried the value faithfully: the peripheral itself produced it.")
                out("      Suspect the peripheral logic, its reset/config state, or the test's expectation.")
    for code, st, txt in res:
        out(f"     {MARK[st]} {code:<10} {txt}")
    if t.done is not None:
        out(f"     latency: {t.done.n('cycles')} cycles in MEM")
    out("")


def print_pipe(an, ev, out, indent="     "):
    stages = [("IF", "F"), ("ID", "D"), ("EX", "E"), ("MEM", "M"), ("WB", "W")]
    out(f"{indent}@cyc {ev.cyc}  stall={ev.s('st')} flush={ev.s('fl')} mem_stall={ev.s('ms')} "
        f"mul={ev.s('mul')} branch={ev.s('br')} trap_redirect={ev.s('trp')}")
    for nm, k in stages:
        raw = ev.s(k, "")
        bubble = raw.endswith("~")
        pc = ev.h(k)
        asm, csrc = an.dis.where(pc)
        out(f"{indent}  {nm:<3} {'(bubble) ' if bubble else ''}{asm}")
        if csrc and not bubble:
            out(f"{indent}       {csrc}")


def explain_state(ev):
    """Localise a hang from one STATE line: furthest hop holding the request."""
    def flags(port):
        # "aw10,w10,b00,ar00,r00" -> {"aw": ("1", "0"), ...}  (valid, ready)
        return {c: (v, r) for c, v, r in re.findall(r"(aw|w|b|ar|r)([01xz])([01xz])", ev.s(port, ""))}
    hmi, xs, xm = flags("HMI"), flags("XS"), flags("XM")
    idle = ("0", "0")
    lines = [f"hybrid_mem_interface FSM: write={HMI_WR.get(ev.n('hmi_wr'), ev.s('hmi_wr'))} "
             f"read={HMI_RD.get(ev.n('hmi_rd'), ev.s('hmi_rd'))}; "
             f"axi_lite_to_apb FSM: {'Access' if ev.s('bridge') == '1' else 'Setup/Idle'}"]
    apb = {}
    for item in ev.s("APB", "").split(","):
        if ":" in item:
            i, f = item.split(":")
            apb[int(i)] = f
    for port, fl in (("HMI", hmi), ("XS", xs), ("XM", xm)):
        busy = [f"{c.upper()} valid={v} ready={r}" for c, (v, r) in fl.items() if v == "1" or (c in ("b", "r") and r == "1")]
        if busy:
            lines.append(f"{port:<3}: " + ", ".join(busy))
    for i, f in apb.items():
        if f[0] == "1":
            lines.append(f"APB slot {i} ({SLOT_NAME.get(i)}): PSEL={f[0]} PENABLE={f[1]} slave PREADY={f[2]} bridge PREADY={f[3]}")
    # Heuristic localisation, most downstream first
    guess = None
    for i, f in apb.items():
        if f[0] == "1" and f[1] == "1" and f[2] != "1":
            guess = f"peripheral {SLOT_NAME.get(i)} is in ACCESS and not raising PREADY"
    if guess is None:
        for port, fl, nxt in (("XM", xm, "axi_lite_to_apb"), ("XS", xs, "axi_lite_xbar"),
                              ("HMI", hmi, "axi_lite_timeout_monitor")):
            if any(fl.get(c, idle)[0] == "1" and fl.get(c, idle)[1] != "1" for c in ("aw", "w", "ar")):
                guess = f"{nxt} is not accepting the request presented on {port}"
                break
    if guess is None:
        # core is ready for B/R but nothing upstream of it is presenting one
        if any(hmi.get(c, idle)[1] == "1" and hmi.get(c, idle)[0] != "1" for c in ("b", "r")):
            guess = "core waits for a B/R response that no hop is presenting (response lost or never generated)"
    if guess is None and ev.s("lsu", "0000")[2:3] == "1":
        guess = "LSU stalled but no AXI channel is active: hybrid_mem_interface FSM out of step with the request"
    if guess:
        lines.append(f"=> likely stuck at: {guess}")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace", nargs="?", help="soc_tracer log (+TRACE_FILE)")
    ap.add_argument("--elf", required=True, help="firmware ELF (built with -g)")
    ap.add_argument("--toolchain", help="RISC-V toolchain bin directory")
    ap.add_argument("--src", action="append", default=[], help="extra directory to find C sources")
    ap.add_argument("--all", action="store_true", help="print every transaction, not only failing ones")
    ap.add_argument("--warn", action="store_true", help="also print transactions with warnings only")
    ap.add_argument("--txn", type=int, nargs="+", help="print these transaction ids")
    ap.add_argument("--max", type=int, default=25, help="max failing transactions printed (default 25)")
    ap.add_argument("--matrix-csv", help="write the peripheral x access-width matrix to this CSV")
    ap.add_argument("--where", nargs="+", help="just resolve these PCs (hex) to asm + C line")
    ap.add_argument("--out", help="also write the report to this file")
    args = ap.parse_args()

    bin_dir = args.toolchain or os.environ.get("RISCV_TOOLCHAIN_BIN")
    objdump = find_tool("objdump", bin_dir)
    elf = Elf(args.elf)
    dis = Disasm(objdump, args.elf, args.src)

    lines = []

    def out(s=""):
        lines.append(s)
        print(s)

    if args.where:
        for p in args.where:
            asm, csrc = dis.where(int(p, 16))
            out(asm)
            out(f"    {csrc}")
        return
    if not args.trace:
        ap.error("trace file required (or use --where)")

    an = Analysis(parse_trace(args.trace), elf, dis)
    for tid in an.order:
        try:
            an.check(an.txns[tid])
        except Exception as ex:     # keep the report going; say which line broke it
            an.txns[tid].result = [("SW", "--", f"analyser error on this transaction: {ex!r}  ({an.txns[tid].req.line})")]

    failing = [an.txns[t] for t in an.order if verdict(an.txns[t].result)[0]]
    warned = [an.txns[t] for t in an.order if not verdict(an.txns[t].result)[0] and verdict(an.txns[t].result)[1]]
    fw_fails = [r for r in an.fw_records if r["cmd"] == 2]
    exc_traps = [e for e in an.traps if e.s("irq") != "1"]

    out("=" * 78)
    out(" RISCFORGE SoC trace report")
    out("=" * 78)
    out(f" trace  : {args.trace}")
    out(f" elf    : {args.elf}")
    out(f" retired instructions : {an.retired}")
    out(f" MMIO / unmapped accesses (transactions) : {len(an.order)}")
    out(f"   with a FAIL hop : {len(failing)}      warnings only : {len(warned)}")
    out(f" traps : {len(an.traps)} ({len(exc_traps)} exceptions)   protocol violations : {len(an.protos)}"
        f"   timeout pulses : {len(an.tmos)}   hangs : {len(an.hangs)}")
    if an.fw_records:
        out(f" firmware mailbox : {sum(1 for r in an.fw_records if r['cmd'] == 1)} PASS, {len(fw_fails)} FAIL")
    if an.end and an.end[0].s("o") == "1":
        out(f" !! simulation ended with transaction t={an.end[0].s('t')} still open")
    out("")

    # ---- first divergence of the whole run
    if failing:
        t = failing[0]
        f, _ = verdict(t.result)
        out("-" * 78)
        out(" FIRST FAILING ACCESS OF THE RUN")
        out("-" * 78)
        out(f" t={t.tid}: first divergence at {f[0]} -> {BLOCK.get(f[0], f[0])}")
        out(f"   {f[2]}")
        out("")

    # ---- transactions
    if args.txn:
        show = [an.txns[t] for t in args.txn if t in an.txns]
    elif args.all:
        show = [an.txns[t] for t in an.order]
    else:
        show = failing[:args.max] + (warned[:args.max] if args.warn else [])
        show.sort(key=lambda t: t.tid)
    if show:
        out("-" * 78)
        out(" TRANSACTIONS (hop by hop, request path then response path)")
        out("-" * 78)
        for t in show:
            print_txn(an, t, out)
        if not (args.txn or args.all) and len(failing) > args.max:
            out(f" ... {len(failing) - args.max} more failing transactions (--max N or --all)")
            out("")

    # ---- firmware failures that are not tied to a bus access
    loose = [r for r in fw_fails if r["txn"] is None]
    if loose:
        out("-" * 78)
        out(" FIRMWARE FAILS WITHOUT A MATCHING BUS ACCESS (DSRAM data, or check done in C only)")
        out("-" * 78)
        for r in loose[:args.max]:
            asm, csrc = dis.where(r["pc"])
            out(f" @cyc {r['cyc']}  {r['ip']}.{r['name']} : {r['sub']}  exp 0x{r['exp'] or 0:08x} got 0x{r['got'] or 0:08x}")
            out(f"     reported from {csrc}")
        out("")

    # ---- traps not explained by a transaction
    tx_pcs = {an.txns[t].commit for t in an.order}
    other = [e for e in an.traps if e not in tx_pcs]
    if other:
        out("-" * 78)
        out(" TRAPS NOT CAUSED BY A TRACED BUS ACCESS")
        out("-" * 78)
        for e in other[:args.max]:
            c = e.n("cause")
            nm = IRQ_NAME.get(c, "?") if e.s("irq") == "1" else EXC_NAME.get(c, "?")
            asm, csrc = dis.where(e.h("pc"))
            out(f" @cyc {e.cyc}  {'IRQ' if e.s('irq') == '1' else 'EXC'} {c} ({nm})  mtval=0x{e.h('tval') or 0:08x}")
            out(f"     {asm}")
            out(f"     {csrc}")
        if len(other) > args.max:
            out(f" ... {len(other) - args.max} more")
        out("")

    # ---- protocol violations not tied to a transaction
    loose_p = [e for e in an.unlinked_hops if e.kind in ("PROTO", "TMO")]
    if loose_p:
        out("-" * 78)
        out(" PROTOCOL VIOLATIONS / TIMEOUTS OUTSIDE ANY CORE ACCESS")
        out("-" * 78)
        for e in loose_p[:args.max]:
            out(f" {e.line}")
        out("")

    # ---- hangs
    for block in an.hangs + ([an.end] if an.end else []):
        head = block[0]
        if head.kind == "END" and head.s("o") != "1" and block is an.end:
            title = "END OF SIMULATION (no access open) - final pipeline"
        else:
            title = f"{head.kind} at cyc {head.cyc} ({head.s('cycles', '')} cycles) t={head.s('t')}"
        out("-" * 78)
        out(f" {title}")
        out("-" * 78)
        for ev in block[1:]:
            if ev.kind == "STATE":
                for ln in explain_state(ev):
                    out(f"   {ln}")
            elif ev.kind == "PIPE" and ev.s("src") == "now":
                out("   pipeline now:")
                print_pipe(an, ev, out)
        ring = [ev for ev in block if ev.kind == "PIPE" and ev.s("src") == "ring"]
        if ring:
            out(f"   last {len(ring)} cycles (oldest first, PC per stage):")
            for ev in ring[-8:]:
                out(f"     @{ev.cyc}  IF {ev.s('F')}  ID {ev.s('D')}  EX {ev.s('E')}  MEM {ev.s('M')}  WB {ev.s('W')}"
                    f"  stall={ev.s('st')} lsu={ev.s('lsu')}")
        out("")

    # ---- matrix
    cols = ["sb", "sh", "sw", "lb", "lbu", "lh", "lhu", "lw"]
    rows = {}
    for tid in an.order:
        t = an.txns[tid]
        key = (target_name(an, t), access_name(an, t))
        cell = rows.setdefault(key[0], {}).setdefault(key[1], {"n": 0, "pass": 0, "warn": 0, "first": {}})
        cell["n"] += 1
        f, w = verdict(t.result)
        if f:
            cell["first"][f[0]] = cell["first"].get(f[0], 0) + 1
        else:
            cell["pass"] += 1
            if w:
                cell["warn"] += 1
    if rows:
        out("-" * 78)
        out(" PERIPHERAL x ACCESS MATRIX   pass/total  (* = warnings, !HOP = first failing hop)")
        out("-" * 78)
        out(" " + f"{'':<10}" + "".join(f"{c:>14}" for c in cols))
        for r in sorted(rows):
            cells = []
            for c in cols:
                x = rows[r].get(c)
                if not x:
                    cells.append(f"{'.':>14}")
                    continue
                s = f"{x['pass']}/{x['n']}" + ("*" if x["warn"] else "")
                if x["first"]:
                    s += " !" + max(x["first"], key=x["first"].get)
                cells.append(f"{s:>14}")
            out(" " + f"{r:<10}" + "".join(cells))
        out("")
        if args.matrix_csv:
            with open(args.matrix_csv, "w", newline="") as f:
                wr = csv.writer(f)
                wr.writerow(["target", "access", "total", "pass", "pass_with_warning", "fail", "first_failing_hops"])
                for r in sorted(rows):
                    for c, x in sorted(rows[r].items()):
                        wr.writerow([r, c, x["n"], x["pass"], x["warn"], x["n"] - x["pass"],
                                     " ".join(f"{k}:{v}" for k, v in x["first"].items())])
            out(f" matrix written to {args.matrix_csv}")

    if args.out:
        Path(args.out).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
