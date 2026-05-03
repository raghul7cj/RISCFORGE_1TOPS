# Future Verification Roadmap

**Scope**: ISS integration · Bare-metal C · Interrupts/PLIC · Xcelium migration  
**Timeline**: Month 2+ (after V1–V3 complete)  
**Status**: Planning only — not blocked on current work

---

## 1. ISS Co-Simulation (Spike)

### 1.1 Architecture

```
┌─────────────┐    golden trace     ┌────────────────┐
│  spike ISS   │ ─────────────────► │                │
│  --isa=rv32i │    (PC, rd, val)   │  Python diff   │ → PASS/FAIL
│              │                     │  comparator    │
└─────────────┘                     └────────────────┘
                                           ▲
┌─────────────┐    DUT trace         │
│  Verilator   │ ─────────────────► │
│  RTL sim     │    (PC, rd, val)   
└─────────────┘
```

### 1.2 Trace Format

```
# Each line: PC RegWrite RD Value
00000000 1 02 DEADBEEF
00000004 0 00 00000000
00000008 1 03 00000042
```

### 1.3 DUT Trace Logger (Add to TB)

```systemverilog
// In system TB — log every retirement
integer trace_fd;
initial trace_fd = $fopen("dut_trace.log", "w");

always @(posedge clk) begin
  if (rst && dut.valid_W && !dut.exc_valid_W && !dut.mret_commit) begin
    $fwrite(trace_fd, "%08h %01b %02d %08h\n",
            dut.PC_W,
            dut.RegWriteW_gated,
            dut.RDW,
            dut.ResultW);
  end
end

final $fclose(trace_fd);
```

### 1.4 Spike Golden Trace

```bash
# Generate trace from spike
spike --isa=rv32i --log-commits program.elf 2> spike_trace.log

# Parse spike log → normalized format
python3 parse_spike_trace.py spike_trace.log > golden_trace.log
```

### 1.5 Comparator Script

```python
#!/usr/bin/env python3
"""Compare DUT trace against spike golden trace."""
import sys

def parse_line(line):
    parts = line.strip().split()
    return {"pc": parts[0], "wr": parts[1], "rd": parts[2], "val": parts[3]}

golden = open("golden_trace.log").readlines()
dut    = open("dut_trace.log").readlines()

mismatches = 0
for i, (g, d) in enumerate(zip(golden, dut)):
    gp, dp = parse_line(g), parse_line(d)
    if gp != dp:
        print(f"MISMATCH line {i}: golden={gp} dut={dp}")
        mismatches += 1

if mismatches == 0:
    print(f"PASS: {len(golden)} instructions matched")
else:
    print(f"FAIL: {mismatches} mismatches out of {len(golden)}")
    sys.exit(1)
```

### 1.6 Prerequisites
- Install `spike` (RISC-V ISA simulator)
- Install RISC-V GCC cross-compiler (`riscv32-unknown-elf-gcc`)
- Python 3.x for comparison scripts
- **No Xcelium required** — works with Verilator

---

## 2. Bare-Metal C Integration

### 2.1 Toolchain Flow

```
main.c + start.S + link.ld
        │
        ▼
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T link.ld
        │
        ▼
    program.elf
        │
        ▼
riscv32-unknown-elf-objcopy -O verilog → program.hex
        │
        ▼
$readmemh("program.hex", imem) → Simulation
```

### 2.2 Minimal C Test

```c
// main.c — bare-metal, no stdlib
volatile unsigned int* const SIG = (unsigned int*)0x100;

void main() {
    int a = 10, b = 20;
    SIG[0] = a + b;        // Should be 30
    SIG[1] = a * b;        // Not available (no M extension) — use shift/add
    
    // Simple loop
    int sum = 0;
    for (int i = 0; i < 5; i++) {
        sum += i;
    }
    SIG[2] = sum;           // Should be 10
    
    while(1);               // Halt
}
```

### 2.3 Boot Code (start.S)

```asm
.section .text.init
.global _start
_start:
    la   sp, _stack_top
    la   t0, _trap_handler
    csrw mtvec, t0
    call main
    j    .

_trap_handler:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    csrr t0, mcause
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t0, 4(sp)
    lw   ra, 0(sp)
    addi sp, sp, 16
    mret
```

### 2.4 Linker Script

```ld
ENTRY(_start)
MEMORY {
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    SRAM  (rwx) : ORIGIN = 0x00002000, LENGTH = 4K
}
SECTIONS {
    .text  : { *(.text.init) *(.text) } > FLASH
    .data  : { *(.data) }               > SRAM
    .bss   : { *(.bss) }                > SRAM
    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
}
```

### 2.5 Prerequisites
- Address decoder in `top.v` (DMEM at 0x2000, not 0x0000)
- `$readmemh` in Instruction_Memory
- Stack pointer initialization in boot code
- **Blocking**: Needs Phase 7 memory map changes

---

## 3. Interrupt/PLIC Verification (Xcelium Phase)

### 3.1 When to Start
- After all synchronous exception tests pass (V1–V3)
- After CLIC instantiation (Phase 6 of implementation roadmap)
- When comfortable with Xcelium basics

### 3.2 What Xcelium Enables
| Feature | Verilator | Xcelium |
|---------|-----------|---------|
| `covergroup` | ✗ | ✓ |
| Constrained random | ✗ | ✓ |
| UVM phases/sequences | ✗ | ✓ |
| Temporal coverage | Limited | Full |
| Multi-clock domains | ✓ | ✓ |

### 3.3 Interrupt Test Scenarios (Future)

| ID | Test | Expected |
|----|------|----------|
| IRQ-1 | Timer interrupt fires | Core jumps to mtvec, mcause[31]=1 |
| IRQ-2 | IRQ during normal execution | mepc = next_PC (PC_W+4) |
| IRQ-3 | IRQ with MIE=0 | IRQ suppressed |
| IRQ-4 | IRQ during exception | Exception wins |
| IRQ-5 | IRQ during MRET | MRET wins |
| IRQ-6 | MRET re-enables interrupts, pending IRQ | IRQ fires immediately |
| IRQ-7 | Nested interrupt (if supported) | Context save/restore |

### 3.4 Learning Path for Xcelium
1. Run existing Verilator TBs on Xcelium (`xrun` replaces `verilator`)
2. Add `covergroup` to existing TBs (incremental)
3. Write first UVM agent for interrupt stimulus
4. Constrained-random interrupt timing
5. Full UVM testbench for SoC integration

---

## 4. Verification Maturity Model

```
Level 0: Compile clean        ← You are here
Level 1: Directed unit tests  ← Phase V1 target
Level 2: Integration asserts  ← Phase V2 target
Level 3: Program regression   ← Phase V3 target
Level 4: ISS co-simulation    ← Future
Level 5: Bare-metal C         ← End goal
Level 6: Constrained random   ← Xcelium (optional)
```

---

## 5. Deferred Verification Items

These are explicitly **not verified now** but tracked for future:

| Item | Why Deferred | When to Verify |
|------|-------------|---------------|
| External interrupts (CLIC) | Hardware not instantiated | Phase 6 |
| Access fault (cause 1,5,7) | Detection logic not implemented | After address decoder |
| Vectored mtvec mode | MODE bits frozen to 00 | After unfreezing |
| WFI instruction | Not decoded | After implementation |
| User/Supervisor mode | M-mode only design | N/A for this core |
| PMP (physical memory protection) | Not implemented | N/A for this core |
| Atomics (A extension) | RV32I only | N/A |
| Multiply (M extension) | RV32I only | N/A |
| Multi-hart | Single-hart design | N/A |
| Cache coherency | No cache | N/A |

---

## 6. Summary: What To Do Now vs Later

### Do Now (High ROI, V1–V3)
1. ✅ Write `tb_csr_regfile.sv` with assertions from Doc 01
2. ✅ Write `tb_wb_commit_ctrl.sv` with assertions from Doc 02
3. ✅ Write `tb_csr_trap_integration.sv` from Doc 03
4. ✅ Add bind-file assertions to hazard_unit from Doc 04
5. ✅ Create assembly test programs from Doc 05
6. ✅ Set up regression script

### Do Later (After foundation solid)
7. 📋 ISS trace comparison (this doc §1)
8. 📋 Bare-metal C compilation (this doc §2, needs Phase 7)
9. 📋 Interrupt verification (this doc §3, needs Phase 6)
10. 📋 Xcelium migration (when ready)

### Never Do (Low ROI)
- ALU exhaustive test (covered by programs)
- Sign extender standalone test
- PC adder standalone test
- Mux standalone test
