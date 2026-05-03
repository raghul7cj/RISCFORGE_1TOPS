# System Smoke Tests & Regression

**Scope**: Full `top.v` pipeline with loaded programs  
**Priority**: P2  
**Level**: L3 — System-level program execution

---

## 1. Test Program Infrastructure

### 1.1 Common TB Wrapper

```systemverilog
module tb_top_system;
  reg clk = 0, rst = 0;
  wire PCSrcE1;
  always #5 clk = ~clk;

  top dut (.clk(clk), .rst(rst), .PCSrcE1(PCSrcE1));

  // Watchdog
  integer cycle = 0;
  parameter MAX_CYCLES = 2000;
  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (cycle > MAX_CYCLES) begin
      $error("TIMEOUT at cycle %0d", cycle);
      $finish;
    end
  end

  // Halt detection: self-loop (PC == PC_prev for N cycles)
  reg [31:0] pc_prev;
  integer halt_count = 0;
  always @(posedge clk) begin
    if (rst) begin
      pc_prev <= dut.Fetch.PCF;
      if (dut.Fetch.PCF == pc_prev) halt_count <= halt_count + 1;
      else halt_count <= 0;
      if (halt_count > 5) begin
        $display("HALT detected at PC=0x%08h, cycle=%0d", pc_prev, cycle);
        check_results();
        $finish;
      end
    end
  end

  // Reset sequence
  initial begin
    rst = 0;
    repeat(4) @(posedge clk);
    rst = 1;
  end

  // Override in each test
  task check_results(); endtask

  // Monitor (optional, for debug)
  always @(posedge clk) if (rst) begin
    if (dut.valid_W && !dut.exc_valid_W && !dut.mret_commit)
      $display("[%4d] RETIRE PC=%08h", cycle, dut.PC_W);
    if (dut.wb_trap_redirect)
      $display("[%4d] TRAP   PC=%08h → %08h cause=%0d",
               cycle, dut.exc_pc_W, dut.trap_target, dut.exc_cause_W);
    if (dut.mret_commit)
      $display("[%4d] MRET   → %08h", cycle, dut.trap_target);
  end
endmodule
```

### 1.2 Program Loading

Programs are loaded via `$readmemh` in `Instruction_Memory.v`. Each test overrides the hex file path:

```systemverilog
// In Instruction_Memory.v (modify for testability):
parameter PROGRAM_FILE = "program.hex";
initial $readmemh(PROGRAM_FILE, mem);
```

Or use `defparam` / `+define+` from command line:
```bash
# Vivado
xvlog -d PROGRAM_FILE=\"ecall_mret.hex\" ...

# Verilator
verilator --cc -DPROGRAM_FILE=\"ecall_mret.hex\" ...
```

---

## 2. Smoke Test Programs

### P-CSR: CSR Read/Write Suite

```asm
# Tests: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
_start:
    li   x1, 0xDEADBEEF
    csrrw x2, mscratch, x1    # mscratch ← 0xDEADBEEF, x2 ← old(0)
    csrrw x3, mscratch, x0    # mscratch ← 0, x3 ← 0xDEADBEEF
    sw   x2, 0x100(x0)        # sig[0] = 0 (old mscratch)
    sw   x3, 0x104(x0)        # sig[1] = 0xDEADBEEF
    
    li   x1, 0x00000888
    csrrw x0, mstatus, x1     # mstatus ← 0x888 (set MIE,MPIE,MPP)
    csrr  x4, mstatus         # x4 = mstatus (masked: 0x00001888)
    sw   x4, 0x108(x0)        # sig[2] = mstatus readback
    
    j    .                     # halt

# Expected signature:
#   DMEM[0x100] = 0x00000000
#   DMEM[0x104] = 0xDEADBEEF
#   DMEM[0x108] = 0x00001888
```

### P-TRAP: ECALL → Handler → MRET

```asm
_start:
    la   x1, _handler
    csrrw x0, mtvec, x1       # mtvec ← handler address
    li   x10, 0               # test register
    ecall                      # trap!
    # Resumes here after MRET (handler skips ECALL)
    sw   x10, 0x100(x0)       # sig[0] = x10 (should be 42)
    j    .

_handler:
    csrr x11, mcause
    sw   x11, 0x104(x0)       # sig[1] = mcause (should be 11)
    csrr x12, mepc
    addi x12, x12, 4          # skip ECALL
    csrrw x0, mepc, x12
    li   x10, 42              # mark "handler ran"
    mret

# Expected signature:
#   DMEM[0x100] = 42
#   DMEM[0x104] = 11
```

### P-ILL: Illegal Instruction Trap

```asm
_start:
    la   x1, _handler
    csrrw x0, mtvec, x1
    .word 0xFFFFFFFF           # illegal instruction
    sw   x10, 0x100(x0)       # should execute after MRET
    j    .

_handler:
    csrr x11, mcause
    csrr x12, mtval
    sw   x11, 0x104(x0)       # sig[1] = mcause (2)
    sw   x12, 0x108(x0)       # sig[2] = mtval (0xFFFFFFFF)
    csrr x13, mepc
    addi x13, x13, 4
    csrrw x0, mepc, x13
    li   x10, 99
    mret

# Expected:
#   DMEM[0x100] = 99
#   DMEM[0x104] = 2
#   DMEM[0x108] = 0xFFFFFFFF
```

### P-MISALIGN: Load/Store Misalignment Trap

```asm
_start:
    la   x1, _handler
    csrrw x0, mtvec, x1
    li   x2, 3
    lw   x3, 0(x2)            # misaligned load (addr=3)
    sw   x10, 0x100(x0)       # after MRET
    j    .

_handler:
    csrr x11, mcause
    csrr x12, mtval
    sw   x11, 0x104(x0)       # sig[1] = mcause (4 = load misalign)
    sw   x12, 0x108(x0)       # sig[2] = mtval  (3 = fault addr)
    csrr x13, mepc
    addi x13, x13, 4
    csrrw x0, mepc, x13
    li   x10, 77
    mret

# Expected:
#   DMEM[0x100] = 77
#   DMEM[0x104] = 4
#   DMEM[0x108] = 3
```

### P-PERF: Performance Counter Accuracy

```asm
_start:
    csrr x1, mcycle            # read mcycle before
    nop
    nop
    nop
    nop
    nop                        # 5 NOPs
    csrr x2, mcycle            # read mcycle after
    sub  x3, x2, x1           # delta
    sw   x3, 0x100(x0)        # sig[0] = cycle delta

    csrr x4, minstret          # read minstret before
    add  x0, x0, x0            # 3 instructions
    add  x0, x0, x0
    add  x0, x0, x0
    csrr x5, minstret          # read minstret after
    sub  x6, x5, x4
    sw   x6, 0x104(x0)        # sig[1] = instret delta

    j    .

# Expected:
#   DMEM[0x100] > 5 (mcycle delta includes pipeline latency)
#   DMEM[0x104] = 4 (3 adds + the csrr itself, approximately)
```

### P-EBREAK: Breakpoint Trap

```asm
_start:
    la   x1, _handler
    csrrw x0, mtvec, x1
    ebreak
    sw   x10, 0x100(x0)
    j    .

_handler:
    csrr x11, mcause
    sw   x11, 0x104(x0)       # sig[1] = mcause (3 = breakpoint)
    csrr x13, mepc
    addi x13, x13, 4
    csrrw x0, mepc, x13
    li   x10, 55
    mret

# Expected:
#   DMEM[0x100] = 55
#   DMEM[0x104] = 3
```

---

## 3. Signature Checking

Each test writes results to a known DMEM "signature area" (0x100+). The TB checks after halt:

```systemverilog
task check_results();
  // Access DMEM directly via hierarchy
  $display("Signature Check:");
  // P-TRAP example:
  if (dut.Memory.dmem.mem[64] == 32'd42)  // 0x100/4 = 64
    $display("  PASS: x10 = 42 (handler ran)");
  else
    $error("  FAIL: x10 = %0d, expected 42", dut.Memory.dmem.mem[64]);

  if (dut.Memory.dmem.mem[65] == 32'd11)  // 0x104/4 = 65
    $display("  PASS: mcause = 11");
  else
    $error("  FAIL: mcause = %0d, expected 11", dut.Memory.dmem.mem[65]);
endtask
```

---

## 4. Regression Script

### Vivado TCL (`scripts/run_vivado.tcl`)

```tcl
# Usage: vivado -mode batch -source run_vivado.tcl -tclargs <test_name>
set test [lindex $argv 0]

create_project -in_memory -part xc7a35t
add_files [glob ../rtl/5_stage/**/*.v]
add_files ../rtl/5_stage/tb/system/tb_top_${test}.sv
add_files ../rtl/5_stage/tb/common/*.sv

set_property top tb_top_${test} [current_fileset -simset]
launch_simulation -mode behavioral
run all
close_sim
```

### Verilator Script (`scripts/run_verilator.sh`)

```bash
#!/bin/bash
TEST=$1
verilator --cc --exe --assert --trace \
  -Wall -Wno-fatal \
  --top-module top \
  -I../rtl/5_stage/core \
  -I../rtl/5_stage/pipeline \
  -I../rtl/5_stage/utils \
  -I../rtl/5_stage/memory \
  -I../rtl/5_stage/ALU \
  -I../rtl/5_stage/control \
  -I../rtl/5_stage/trap_mret_csr \
  ../rtl/5_stage/tb/system/tb_top_${TEST}.sv \
  && make -C obj_dir -f Vtop.mk \
  && ./obj_dir/Vtop
```

### Regression Runner (`scripts/regression.py`)

```python
#!/usr/bin/env python3
import subprocess, sys

TESTS = [
    "smoke",          # Basic instruction execution
    "trap_roundtrip", # ECALL → handler → MRET
    "perf_counters",  # mcycle/minstret accuracy
    "illegal_instr",  # Illegal instruction trap
    "misaligned_load",# Load misalignment trap
    "ebreak",         # Breakpoint trap
]

results = {}
for test in TESTS:
    print(f"\n{'='*60}\nRunning: {test}\n{'='*60}")
    rc = subprocess.call(["bash", "run_verilator.sh", test])
    results[test] = "PASS" if rc == 0 else "FAIL"

print(f"\n{'='*60}\nREGRESSION SUMMARY\n{'='*60}")
for t, r in results.items():
    print(f"  {t:30s} {r}")
total = len(results)
passed = sum(1 for r in results.values() if r == "PASS")
print(f"\n{passed}/{total} passed")
sys.exit(0 if passed == total else 1)
```

---

## 5. Test Matrix Summary

| ID | Program | Verifies | Expected Result |
|----|---------|----------|-----------------|
| P-CSR | CSR R/W suite | CSRRW, masks, read-back | Signature match |
| P-TRAP | ECALL→MRET | Full trap round-trip | x10=42, mcause=11 |
| P-ILL | Illegal instruction | ID exception detection | mcause=2, mtval=encoding |
| P-MISALIGN | LW @ addr 3 | MEM exception detection | mcause=4, mtval=3 |
| P-PERF | Cycle/instret counters | Counter accuracy | Deltas match |
| P-EBREAK | Breakpoint | EBREAK detection | mcause=3 |
| P-NESTED | Trap in handler | Nested exception | MIE chain correct |
| P-BRANCH | All branch types | Control flow | No exception |
| P-HAZARD | LW+use, forwarding | Pipeline hazards | Correct values |
