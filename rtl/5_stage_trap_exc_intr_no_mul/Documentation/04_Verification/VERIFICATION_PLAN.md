# Verification Plan — RISCFORGE 1TOPS

**Core**: 5-Stage RV32I, M-Mode Only, Propagate-and-Commit Exceptions  
**Last Updated**: May 2026  

---

## 1. Verification Goals

### Must-Pass (Blocking)
1. **RV32I functional correctness** — all instructions produce correct results
2. **Pipeline hazard correctness** — forwarding, stalls, flushes behave exactly as specified
3. **Precise exceptions** — faulting instruction commits at WB; younger instructions produce zero side effects
4. **CSR correctness** — all implemented CSRs read/write with correct masks; `mcycle`/`minstret` count correctly
5. **MRET correctness** — WB-boundary redirect to `mepc`, `mstatus` restored correctly
6. **Performance counter accuracy** — `mcycle` counts every cycle; `minstret` counts only retired instructions

### Current Non-Goals (Tracked)
- External interrupt commit path (Phase 6 — not yet implemented)
- Access fault exceptions (future)
- Vectored interrupt mode (future)

---

## 2. Tooling

### Simulator Options
| Tool | Platform | Notes |
|------|----------|-------|
| **Icarus Verilog + GTKWave** | WSL / Linux | Recommended for waveform debug |
| **Verilator + C++ harness** | Any | Faster for regression sweeps |
| **Vivado Simulator** | Windows | Available if Vivado is installed |

### Environment Setup (WSL)
```bash
# Install
sudo apt install iverilog gtkwave

# Compile a testbench
iverilog -g2005-sv -Wall -o sim.out top_tb.v core/top.v pipeline/*.v utils/*.v memory/*.v ALU/*.v control/*.v csr_regfile.v wb_trap_mret_commit_controller.v

# Run simulation
vvp sim.out

# Open waveform
gtkwave dump.vcd
```

> **Windows Note**: `iverilog` is not on the Windows PATH. Use WSL or install the Windows binary separately.

---

## 3. Verification Layers

| Layer | Scope | Blocks When to Run |
|-------|-------|----------|
| **L0** | Static: compile & elaborate | All files | Every RTL change |
| **L1** | Unit: leaf modules | ALU, ls_unit, Sign_Extend, JB_unit, Register_File, Data_Memory, Instruction_Memory | Each module change |
| **L2** | Stage: pipeline stage modules | fetch_cycle, decode_cycle, execute_cycle, memory_cycle, writeback_cycle | Each stage change |
| **L3** | Control-plane: hazard + flush | hazard_unit, continuous flush wake | Control-path changes |
| **L4** | Privileged: trap + MRET + CSR | wb_trap_mret_commit_controller, csr_regfile | Trap/CSR changes |
| **L5** | Program-level: directed assembly | top (full integration) | Before any milestone |

---

## 4. Testbench Architecture

### Required TB Structure
```verilog
module top_tb;
    // Clock and reset
    reg clk = 0;
    reg rst = 0;  // Active-low
    always #5 clk = ~clk;  // 100 MHz
    
    // DUT
    top dut (.clk(clk), .rst(rst), .PCSrcE1());
    
    // Timeout watchdog
    integer cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count > MAX_CYCLES) begin
            $display("TIMEOUT"); $finish;
        end
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top_tb);
    end
    
    // Reset sequence
    initial begin
        rst = 0;
        repeat(4) @(posedge clk);  // Hold reset for 4 cycles
        rst = 1;
        // ... test body ...
    end
endmodule
```

### Required Monitor Signals (Always Capture)
```
valid_D, valid_E, valid_M, valid_W
exc_valid_D, exc_valid_E, exc_valid_M, exc_valid_W
exc_cause_W, exc_pc_W, exc_tval_W
FlushD, FlushE, FlushM, FlushW
StallF, StallD
PCSrcE, wb_trap_redirect, trap_target
flush_pipeline_onehot, mret_commit
dut.csr_file.mcycle_r, dut.csr_file.minstret_r
dut.csr_file.mstatus_r, dut.csr_file.mepc_r, dut.csr_file.mcause_r
```

### Commit Event Definitions
```verilog
wire normal_commit  =  valid_W & ~exc_valid_W & ~mret_commit;
wire trap_commit    =  valid_W &  exc_valid_W;
wire mret_commit_ev =  mret_commit;  // Already commit-qualified in top.v
```

---

## 5. L1: Unit Tests

### 5.1 ALU (`ALU/ALU.v`)
| Test ID | Stimulus | Expected | Pass Criteria |
|---------|----------|----------|---------------|
| ALU-1 | ADD: A=0x7FFFFFFF, B=1 | Result=0x80000000 | Wrap-around correct |
| ALU-2 | SUB: A=5, B=10 | Result=0xFFFFFFFB | Negative subtraction |
| ALU-3 | SRA: A=0x80000000, shamt=4 | Result=0xF8000000 | Sign-extension correct |
| ALU-4 | SLT: A=-1, B=0 (signed) | Result=1 | Signed comparison |
| ALU-5 | SLTU: A=0xFFFFFFFF, B=0 | Result=0 | Unsigned: max > 0 |
| ALU-6 | JALR: A=0x1001, B=4 | Result=0x1004, bit0=0 | LSB forced to 0 |

### 5.2 Load/Store Unit (`utils/ls_unit.v`)
| Test ID | Stimulus | Expected |
|---------|----------|----------|
| LSU-1 | LBU, addr[1:0]=0, mem=0xDEADBEEF | out=0xEF |
| LSU-2 | LB, addr[1:0]=0, mem=0x000000FF | out=0xFFFFFFFF (sign extend) |
| LSU-3 | LHU, addr[1]=0, mem=0xDEADBEEF | out=0x0000BEEF |
| LSU-4 | LH, addr[1]=0, mem=0x0000BEEE | out=0xFFFFBEEE (sign extend) |
| LSU-5 | SB, addr[1:0]=2, WD=0xAA | strobe=4'b0100, out_s[23:16]=0xAA |
| LSU-6 | SH, addr[1]=1, WD=0x1234 | strobe=4'b1100 |
| LSU-7 | SW | strobe=4'b1111 |

### 5.3 Register File (`memory/Register_File.v`)
| Test ID | Description |
|---------|-------------|
| RF-1 | Write and read back all registers x1–x31 |
| RF-2 | Write to x0 — reads back 0 |
| RF-3 | Same-cycle forwarding: write xN and read xN in same cycle |

---

## 6. L2: Stage Tests

### 6.1 Fetch Stage (`fetch_cycle.v`)
| Test ID | Scenario | Expected |
|---------|----------|----------|
| IF-1 | Normal execution | PC increments by 4 each cycle |
| IF-2 | StallF=1 | PC frozen |
| IF-3 | StallD=1 | IF/ID register held |
| IF-4 | FlushD=1 | IF/ID cleared, valid_D=0 |
| IF-5 | PCSrcE=1 & wb_trap_redirect=0 | PC ← PCTargetE |
| IF-6 | wb_trap_redirect=1 | PC ← trap_target (highest priority) |
| IF-7 | PCSrcE=1 & wb_trap_redirect=1 simultaneously | PC ← trap_target (trap wins) |
| IF-8 | PC = 0x1002 (JALR target unaligned) | exc_valid_D=1, cause=0 |

### 6.2 Memory Stage (`memory_cycle.v`)
| Test ID | Scenario | Expected |
|---------|----------|----------|
| MEM-1 | SW then LW same address | Stored value returned |
| MEM-2 | LW at address 0x0001 (misaligned) | exc_valid_W=1, cause=4, tval=0x0001 |
| MEM-3 | SW at address 0x0002 (misaligned) | exc_valid_W=1, cause=6, tval=0x0002 |
| MEM-4 | LH at address 0x0001 (misaligned) | exc_valid_W=1, cause=4 |
| MEM-5 | LB at any address | No exception (byte is always aligned) |
| MEM-6 | FlushW=1 | MEM/WB cleared, valid_W=0 |
| MEM-7 | exc_valid_M=1 on store | Store write suppressed (DMEM.WE=0) |
| MEM-8 | Store with exc_valid from earlier stage | Store suppressed regardless of misalignment result |

---

## 7. L3: Control-Plane Tests (Hazard Unit)

| Test ID | Scenario | Expected |
|---------|----------|----------|
| HAZ-1 | LW x1, ADD x2←x1 | StallF=1, StallD=1, FlushE=1 for 1 cycle |
| HAZ-2 | MEM→EX forwarding | ForwardAE=2'b10, correct result |
| HAZ-3 | WB→EX forwarding | ForwardBE=2'b01, correct result |
| HAZ-4 | CSR write then read same address (back-to-back) | CSR stall applied |
| HAZ-5 | Branch taken | FlushD=1, FlushE=1 |
| HAZ-6 | Continuous flush: ECALL followed by SW | SW never reaches MEM with valid=1 |
| HAZ-7 | WB redirect while lwstall active | Stall overridden; PC takes redirect |
| HAZ-8 | Exception in EX while store in MEM | FlushM=0 until WB, but exc_valid_M suppresses store |

---

## 8. L4: Privilege Plane Tests (Trap + CSR)

### 8.1 CSR Register Behavior
| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| CSR-1 | CSRRW mscratch | Read-back matches written value |
| CSR-2 | mstatus write mask | Only MIE[3]/MPIE[7]/MPP[12:11] writable; other bits preserved |
| CSR-3 | mtvec MODE frozen | Write 0x3 to mtvec[1:0]; read back 0x0 |
| CSR-4 | mip is read-only | CSRRW to mip has no effect on software-controlled bits |
| CSR-5 | mcycle increments every cycle | Read mcycle, wait N cycles, read again; delta = N |
| CSR-6 | minstret counts only retired instructions | Execute 5 instructions; minstret increments by 5 |
| CSR-7 | minstret does not count on trap | ECALL increments minstret by 0 (it faults, not retires) |
| CSR-8 | mcycleh/minstret 64-bit overflow | Write low half to max; verify rollover to high half |

### 8.2 Trap Entry (Synchronous Exception)
| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| TRAP-1 | ECALL → trap entry | mepc=ECALL_PC, mcause=11, mstatus.MIE=0, PC→mtvec |
| TRAP-2 | Illegal instruction | mepc=INSTR_PC, mcause=2, mtval=instr_encoding |
| TRAP-3 | EBREAK | mcause=3 |
| TRAP-4 | Misaligned LW | mcause=4, mtval=faulting_address |
| TRAP-5 | Misaligned SW | mcause=6, mtval=faulting_address |
| TRAP-6 | mstatus.MPIE saved | After trap, mstatus[7]=previous MIE |
| TRAP-7 | mstatus.MPP = 2'b11 | Always M-mode on trap entry |
| TRAP-8 | Trap from exception, not MRET | `exc_valid_W` wins over `is_mret_W` |
| TRAP-9 | Trap redirect priority | `wb_trap_redirect` overrides `PCSrcE` on same cycle |

### 8.3 MRET
| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| MRET-1 | Basic MRET | PC → mepc, mstatus.MIE ← MPIE |
| MRET-2 | MRET flushes pipeline | FlushD/E/M all asserted on mret_commit cycle |
| MRET-3 | MRET does not write register file | x0/rd unchanged after MRET |
| MRET-4 | MRET mstatus.MPP stays 2'b11 | M-mode only — MPP must remain machine mode |
| MRET-5 | MRET with pending exception | MRET suppressed, exception wins |
| MRET-6 | Full round-trip | ECALL → handler → MRET → resumes at ECALL+4 |

### 8.4 WB Commit Controller Logic
| Test ID | Signal Under Test | Expected |
|---------|-------------------|----------|
| WBCTRL-1 | `trap_commit = valid_W & exc_valid_W` | 1 cycle pulse |
| WBCTRL-2 | `mret_commit = valid_W & is_mret_W & ~exc_valid_W` | 1 cycle pulse |
| WBCTRL-3 | `wb_trap_redirect` | Asserted for exactly 1 cycle |
| WBCTRL-4 | `trap_target` alignment | Lower 2 bits = 0 |
| WBCTRL-5 | `flush_pipeline_onehot = 4'b1111` | On same cycle as redirect |

---

## 9. L5: Program-Level Directed Tests

### Assembly Test Programs
| ID | Program | Verifies |
|----|---------|---------|
| P-ALU | Arithmetic/shift/compare suite | All ALU ops, correct results in registers |
| P-BR | All branch types taken/not taken + JAL/JALR | Control flow correctness |
| P-LS | SB/SH/SW + LB/LBU/LH/LHU/LW | Load/store all widths and sign extensions |
| P-CSR | CSRRW/CSRRS/CSRRC + immediate variants | CSR instruction decode and data path |
| P-TRAP | ECALL → handler → modify mepc → MRET | Full trap round-trip |
| P-ILL | `.word 0xFFFFFFFF` → trap | Illegal instruction detection |
| P-PERF | Read mcycle before/after a loop, verify delta | Performance counter accuracy |
| P-MISALIGN | Unaligned LW/SW → trap (cause 4/6) | MEM-stage exception detection |

### Test Program Template
```asm
.section .text
.global _start
_start:
    # Test setup
    li x1, TEST_VALUE
    
    # Test body
    add x2, x1, x1
    
    # Write result to DMEM signature area (x0 base + offset)
    sw x2, 0x100(x0)
    
    # Self-loop to halt
    j .

.section .data
signature:
    .word 0xDEAD  # Overwritten by test if passing
```

---

## 10. Critical Corner Case Checklist

Run these manually in waveform inspection before any milestone:

| # | Scenario | Signals to Check |
|---|----------|-----------------|
| 1 | Reset: all stage valids cleared | `valid_D/E/M/W` all 0 after rst deassert+1 cycle |
| 2 | `StallD=1` and `FlushE=1` same cycle | Flush wins — ID/EX becomes bubble |
| 3 | `wb_trap_redirect=1` and `StallF=1` same cycle | Stall overridden; PC redirects |
| 4 | Branch taken and trap redirect same cycle | `wb_trap_redirect` wins over `PCSrcE` |
| 5 | ECALL followed immediately by SW | SW never has `valid_M=1` (continuous flush) |
| 6 | Exception in EX, store in MEM | `exc_valid_M` propagated from older instr suppresses store |
| 7 | CSR back-to-back same address | CSR stall applied; read sees updated value |
| 8 | Load-use hazard with forwarding | Stall inserted; forwarding not bypassing load result |
| 9 | MRET with mret_commit, normal CSR write same cycle | CSR write suppressed; only MRET restore happens |
| 10 | mcycle counting during stall | mcycle still increments; minstret does not (no retirement) |
| 11 | minstret on trap (ECALL) | Trap does NOT increment minstret (faulting instr doesn't retire normally) |
| 12 | Trap redirect target alignment | `trap_target[1:0] == 2'b00` always |

---

## 11. Regression Schedule

| Trigger | Run Layers |
|---------|------------|
| Any RTL edit | L0 (compile), L1 (affected unit) |
| Stage-level change | L0 + L2 (affected stage) |
| Hazard/flush changes | L0 + L3 |
| Trap/CSR changes | L0 + L4 |
| Before CLIC integration | L0–L4 full sweep |
| Before bare-metal C milestone | L0–L5 full sweep + P-PERF |

---

## 12. Exception System Gap Audit (Reference)

*Verified against current RTL — May 2026*

| Gap | Status | Notes |
|-----|--------|-------|
| `trap_is_interrupt_i` hardcoded 1'b0 in top.v | ✅ **Fixed** | Now `trap_commit_is_interrupt` |
| `trap_addr_valid_i` hardcoded 1'b1 in top.v | ✅ **Fixed** | Now `trap_commit_addr_valid` |
| MEM-stage misalignment detection missing | ✅ **Fixed** | Implemented in `memory_cycle.v` |
| Performance counters missing | ✅ **Fixed** | mcycle/minstret in `csr_regfile.v` |
| `instr_retired_i` missing from CSR regfile | ✅ **Fixed** | Replaces old `instr_is_mret` port |
| CLIC physical instantiation | ❌ Pending | Stub only (`irq_valid_i=0`) |
| External interrupt commit path (`wb_irq_commit`) | ❌ Pending | Phase 6 |
| Access fault detection (cause 5/7) | ❌ Pending | Future |
| Vectored mode (`mtvec[1:0]=01`) | ❌ Pending | Future |
