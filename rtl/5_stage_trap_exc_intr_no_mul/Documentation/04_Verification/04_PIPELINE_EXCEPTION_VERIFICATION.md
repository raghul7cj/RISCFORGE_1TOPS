# Pipeline Exception Flow Verification

**Scope**: Hazard unit continuous flush · Exception propagation · Full trap round-trip  
**Priority**: P1  
**Level**: Integration (multi-stage) + System (full pipeline with programs)

---

## 1. Hazard Unit Exception Assertions

### Bind File: `sva_hazard_unit.sv`

```systemverilog
module sva_hazard_unit (
  input rst, clk,
  input valid_E, exc_valid_E, valid_M, exc_valid_M,
  input wb_redirect, PCSrcE,
  input [3:0] flush_pipeline_onehot,
  input FlushD, FlushE, FlushM, FlushW,
  input StallF, StallD
);

  // --- Continuous Flush: exc in EX → FlushD ---
  property p_exc_E_flushes_D;
    @(posedge clk) disable iff (!rst)
    (valid_E && exc_valid_E) |-> FlushD;
  endproperty
  assert property (p_exc_E_flushes_D)
    else $error("exc_inflight_E did not FlushD");

  // --- Continuous Flush: exc in MEM → FlushD + FlushE ---
  property p_exc_M_flushes_DE;
    @(posedge clk) disable iff (!rst)
    (valid_M && exc_valid_M) |-> (FlushD && FlushE);
  endproperty
  assert property (p_exc_M_flushes_DE)
    else $error("exc_inflight_M did not FlushD+FlushE");

  // --- WB redirect overrides stall ---
  property p_redirect_overrides_stall;
    @(posedge clk) disable iff (!rst)
    wb_redirect |-> (!StallF && !StallD);
  endproperty
  assert property (p_redirect_overrides_stall)
    else $error("WB redirect did not override stall");

  // --- WB redirect → full flush ---
  property p_redirect_full_flush;
    @(posedge clk) disable iff (!rst)
    wb_redirect |-> (FlushD && FlushE && FlushM && FlushW);
  endproperty
  assert property (p_redirect_full_flush)
    else $error("WB redirect did not cause full flush");

  // --- WB redirect beats PCSrcE ---
  // (verified at top level: PC mux priority)
  property p_redirect_beats_branch;
    @(posedge clk) disable iff (!rst)
    (wb_redirect && PCSrcE) |-> FlushD;  // Both flush, but redirect target wins
  endproperty
  assert property (p_redirect_beats_branch);

endmodule
```

---

## 2. Pipeline-Level Exception Propagation Tests

These tests verify exceptions travel correctly through the pipeline stages.

### 2.1 ECALL Propagation (PEX-1)

```
Program:
  0x000: NOP          (x1=x1+0)
  0x004: ECALL
  0x008: ADD x1,x2,x3 (should be flushed)
  0x00C: SW  x1,0(x0) (should be flushed)

Expected cycle-by-cycle:
  t=N+0: ECALL in ID → new_exc_valid_D=1, cause=11
  t=N+1: ECALL in EX → exc_valid_E=1, FlushD=1 (continuous)
         ADD in ID → flushed (valid_E will be 0)
  t=N+2: ECALL in MEM → exc_valid_M=1, FlushD=1, FlushE=1
         SW in ID → flushed
  t=N+3: ECALL in WB → trap_commit, full flush
         mepc = 0x004, mcause = 11
         PC → mtvec

Checks:
  - ADD never has valid_M=1 or valid_W=1
  - SW never writes DMEM
  - x1 unchanged (ADD suppressed)
  - mepc = 0x004
  - mcause = 0x0000000B
```

### 2.2 Misaligned Load (PEX-2)

```
Program:
  0x000: LI x1, 3          (x1 = 3)
  0x004: LW x2, 0(x1)      (misaligned: addr=3)
  0x008: ADD x3, x2, x1    (should be flushed)

Expected:
  LW reaches MEM: ALU_ResultM=3, lsunitM=load/word
  exc_valid_mem_local=1, cause=4, tval=3
  At WB: trap commit, mepc=0x004, mcause=4, mtval=3
  ADD never completes
  x2 unchanged (load suppressed by exception)
```

### 2.3 Illegal Instruction (PEX-3)

```
Program:
  0x000: .word 0xFFFFFFFF   (illegal encoding)
  0x004: ADD x1, x2, x3    (should be flushed)

Expected:
  t=N: Illegal detected in ID → exc_valid=1, cause=2, tval=0xFFFFFFFF
  Propagates through pipeline, commits at WB
  mepc = 0x000, mcause = 2, mtval = 0xFFFFFFFF
```

### 2.4 Two Exceptions — Oldest Wins (PEX-4)

```
Program:
  0x000: LW x1, 3(x0)      (misaligned → detected at MEM)
  0x004: .word 0xFFFFFFFF   (illegal → detected at ID)

Expected:
  LW exception is older → LW exception commits at WB
  Illegal instruction is younger → flushed by continuous flush
  mepc = 0x000 (LW's PC), mcause = 4, mtval = 3
  NOT: mepc = 0x004, mcause = 2
```

### 2.5 ECALL + SW Behind (PEX-5)

```
Program:
  0x000: ECALL
  0x004: SW x1, 0(x0)       (must NOT write memory)

Expected:
  ECALL in EX/MEM → continuous flush kills SW
  SW never has valid_M=1
  DMEM[0] unchanged

This is the critical side-effect gating test.
```

### 2.6 Exception on Branch (PEX-6)

```
Program:
  0x000: BEQ x0, x0, +8     (branch taken)
  ... but what if the branch instruction itself has exc_valid?

Stimulus: Force exc_valid_E=1 on the branch cycle
Expected:
  PCSrcE = yesE & valid_E & ~exc_valid_E = 0
  Branch redirect suppressed
  Exception propagates to WB and commits
```

### 2.7 Full MRET Round-Trip (PEX-7)

```
Program:
  0x000: CSRRW x0, mtvec, x1  (set mtvec = handler_addr)
  0x004: ECALL                  (trap entry)
  ...
  handler_addr:
  0x100: CSRRW x0, mepc, x2    (modify mepc to skip ECALL)
  0x104: MRET                   (return)
  ...
  0x008: NOP                    (execution resumes here if mepc=0x008)

Expected:
  After ECALL: PC → 0x100, mepc=0x004, MIE=0
  Handler writes mepc=0x008
  After MRET: PC → 0x008, MIE restored
  Pipeline fully flushed on MRET commit
```

---

## 3. Side-Effect Gating Assertions (Top Level)

```systemverilog
// Bind to top.v or inline

// RegWrite gated: faulting instruction cannot write register file
property p_regwrite_gated;
  @(posedge clk) disable iff (!rst)
  (exc_valid_W || mret_commit) |-> !RegWriteW_gated;
endproperty

// CSR write gated: faulting instruction cannot write CSR
property p_csrwrite_gated;
  @(posedge clk) disable iff (!rst)
  (exc_valid_W || mret_commit) |-> !csr_write_en_W_gated;
endproperty

// Store write gated in MEM: exception-tagged instruction cannot write DMEM
property p_store_gated_mem;
  @(posedge clk) disable iff (!rst)
  (exc_valid_M) |-> (Memory.dmem.WE == 1'b0);
endproperty

// PCSrcE gated: faulting branch cannot redirect
property p_branch_gated;
  @(posedge clk) disable iff (!rst)
  exc_valid_E |-> !PCSrcE;
endproperty

// Valid bit cleared on flush
property p_flush_clears_valid;
  @(posedge clk) disable iff (!rst)
  FlushE |=> !valid_E;
endproperty
```

---

## 4. Pipeline Exception Coverage

```systemverilog
// Verilator-compatible manual counters
int cov_ecall_trap = 0;
int cov_illegal_trap = 0;
int cov_load_misalign = 0;
int cov_store_misalign = 0;
int cov_mret_commit = 0;
int cov_exc_beats_branch = 0;
int cov_continuous_flush_E = 0;
int cov_continuous_flush_M = 0;
int cov_sw_behind_exc = 0;
int cov_two_exc_oldest_wins = 0;

always @(posedge clk) begin
  if (trap_commit_valid && trap_commit_cause[4:0] == 5'd11)  cov_ecall_trap++;
  if (trap_commit_valid && trap_commit_cause[4:0] == 5'd2)   cov_illegal_trap++;
  if (trap_commit_valid && trap_commit_cause[4:0] == 5'd4)   cov_load_misalign++;
  if (trap_commit_valid && trap_commit_cause[4:0] == 5'd6)   cov_store_misalign++;
  if (mret_commit)                                            cov_mret_commit++;
  if (exc_valid_E && yesE)                                    cov_exc_beats_branch++;
  if (valid_E && exc_valid_E && FlushD)                       cov_continuous_flush_E++;
  if (valid_M && exc_valid_M && FlushE)                       cov_continuous_flush_M++;
end

final begin
  $display("=== Pipeline Exception Coverage ===");
  $display("  ecall=%0d illegal=%0d load_misalign=%0d store_misalign=%0d",
           cov_ecall_trap, cov_illegal_trap, cov_load_misalign, cov_store_misalign);
  $display("  mret=%0d exc_beats_branch=%0d flush_E=%0d flush_M=%0d",
           cov_mret_commit, cov_exc_beats_branch,
           cov_continuous_flush_E, cov_continuous_flush_M);
end
```

---

## 5. Corner Case Checklist

| # | Scenario | Signal Check | Test |
|---|----------|-------------|------|
| 1 | ECALL + SW behind | DMEM.WE=0 for SW | PEX-5 |
| 2 | Two exceptions, oldest wins | mepc = oldest PC | PEX-4 |
| 3 | Exception suppresses branch | PCSrcE=0 | PEX-6 |
| 4 | MRET flushes all 4 stages | FlushD/E/M/W = 1 | PEX-7 |
| 5 | WB redirect vs lwstall | StallF overridden | Hazard assertion |
| 6 | WB redirect vs PCSrcE | PC = trap_target, not PCTargetE | Top assertion |
| 7 | CSR stall + exception | Stall overridden by redirect | Hazard test |
| 8 | Back-to-back ECALL→MRET | Pipeline correctly drains | PEX-7 variant |
| 9 | Exception in MEM, store in MEM | Store suppressed | PEX-5 variant |
| 10 | mcycle during exception flush | mcycle still increments | Counter assertion |
