# WB Commit Controller Verification — Detailed Plan

**DUT**: `trap_mret_csr/wb_trap_mret_commit_controller.v` (106 lines)  
**Priority**: P0 — Controls all trap/MRET/IRQ commit decisions  
**Nature**: Purely combinational — no clock-edge behavior

---

## 1. Block Summary

The WB commit controller makes three combinational decisions every cycle:
- `trap_commit = valid_W & exc_valid_W` → exception trap
- `mret_commit = valid_W & is_mret_W & ~exc_valid_W` → MRET return
- `irq_commit = valid_W & irq_valid_i & ~exc_valid_W & ~is_mret_W` → interrupt

It then drives: redirect PC, flush pipeline, CSR trap-entry bundle, MRET mstatus restore.

**Critical Property**: Exception always beats MRET always beats IRQ.

---

## 2. SVA Assertions (Bind File: `sva_wb_commit_ctrl.sv`)

### 2.1 Mutual Exclusion

```systemverilog
// At most one commit type per cycle
property p_mutual_exclusion;
  @(posedge clk) disable iff (!rst_n)
  $onehot0({trap_commit, mret_commit, irq_commit});
endproperty
assert property (p_mutual_exclusion) else $error("Multiple commits in same cycle");

// Exception beats MRET
property p_exc_beats_mret;
  @(posedge clk) disable iff (!rst_n)
  (valid_W && exc_valid_W && is_mret_W) |-> (trap_commit && !mret_commit);
endproperty
assert property (p_exc_beats_mret) else $error("MRET fired despite exception");

// Exception beats IRQ
property p_exc_beats_irq;
  @(posedge clk) disable iff (!rst_n)
  (valid_W && exc_valid_W && irq_valid_i) |-> (trap_commit && !irq_commit);
endproperty
assert property (p_exc_beats_irq) else $error("IRQ fired despite exception");

// MRET beats IRQ (MRET is a valid instruction, so it takes priority)
property p_mret_beats_irq;
  @(posedge clk) disable iff (!rst_n)
  (valid_W && is_mret_W && irq_valid_i && !exc_valid_W) |-> 
    (mret_commit && !irq_commit);
endproperty
assert property (p_mret_beats_irq) else $error("IRQ fired despite MRET");
```

### 2.2 Redirect & Flush

```systemverilog
// Any commit → redirect asserted
property p_commit_redirects;
  @(posedge clk) disable iff (!rst_n)
  (trap_commit || mret_commit || irq_commit) |-> wb_trap_redirect_o;
endproperty
assert property (p_commit_redirects) else $error("Commit without redirect");

// No commit → no redirect
property p_no_commit_no_redirect;
  @(posedge clk) disable iff (!rst_n)
  (!trap_commit && !mret_commit && !irq_commit) |-> !wb_trap_redirect_o;
endproperty
assert property (p_no_commit_no_redirect) else $error("Redirect without commit");

// Redirect → full pipeline flush
property p_redirect_flushes;
  @(posedge clk) disable iff (!rst_n)
  wb_trap_redirect_o |-> (flush_pipeline_onehot_o == 4'b1111);
endproperty
assert property (p_redirect_flushes) else $error("Redirect without full flush");

// No redirect → no flush
property p_no_redirect_no_flush;
  @(posedge clk) disable iff (!rst_n)
  !wb_trap_redirect_o |-> (flush_pipeline_onehot_o == 4'b0000);
endproperty
assert property (p_no_redirect_no_flush) else $error("Flush without redirect");
```

### 2.3 Target Address

```systemverilog
// Trap target → mtvec (aligned)
property p_trap_target_mtvec;
  @(posedge clk) disable iff (!rst_n)
  trap_commit |-> (trap_target_o == {mtvec_i[31:2], 2'b00});
endproperty
assert property (p_trap_target_mtvec) else $error("Trap target != mtvec");

// MRET target → mepc (aligned)
property p_mret_target_mepc;
  @(posedge clk) disable iff (!rst_n)
  mret_commit |-> (trap_target_o == {mepc_i[31:2], 2'b00});
endproperty
assert property (p_mret_target_mepc) else $error("MRET target != mepc");

// IRQ target → mtvec (aligned)
property p_irq_target_mtvec;
  @(posedge clk) disable iff (!rst_n)
  irq_commit |-> (trap_target_o == {mtvec_i[31:2], 2'b00});
endproperty
assert property (p_irq_target_mtvec) else $error("IRQ target != mtvec");

// Target always 4-byte aligned
property p_target_aligned;
  @(posedge clk) disable iff (!rst_n)
  wb_trap_redirect_o |-> (trap_target_o[1:0] == 2'b00);
endproperty
assert property (p_target_aligned) else $error("Redirect target not aligned");
```

### 2.4 CSR Trap Bundle

```systemverilog
// trap_valid_o asserted only for trap or IRQ (not MRET)
property p_trap_valid_scope;
  @(posedge clk) disable iff (!rst_n)
  trap_valid_o |-> (trap_commit || irq_commit);
endproperty
assert property (p_trap_valid_scope);

// trap_is_interrupt set only for IRQ
property p_interrupt_flag;
  @(posedge clk) disable iff (!rst_n)
  trap_valid_o |-> (trap_is_interrupt_o == irq_commit);
endproperty
assert property (p_interrupt_flag);

// trap_addr_valid only for exceptions (not IRQ)
property p_addr_valid_scope;
  @(posedge clk) disable iff (!rst_n)
  trap_valid_o |-> (trap_addr_valid_o == trap_commit);
endproperty
assert property (p_addr_valid_scope);
```

### 2.5 MRET CSR Write Interface

```systemverilog
// MRET commit → Port C write to mstatus
property p_mret_csr_write;
  @(posedge clk) disable iff (!rst_n)
  mret_commit |-> (csr_write_en_mret_o && csr_waddr_mret_o == 12'h300);
endproperty
assert property (p_mret_csr_write);

// MRET mstatus construction: MIE ← MPIE, MPIE ← 1, MPP ← 11
property p_mret_mstatus_bits;
  @(posedge clk) disable iff (!rst_n)
  mret_commit |-> (
    csr_wdata_mret_o[3]     == mstatus_i[7] &&   // MIE ← MPIE
    csr_wdata_mret_o[7]     == 1'b1 &&            // MPIE ← 1
    csr_wdata_mret_o[12:11] == 2'b11              // MPP ← M-mode
  );
endproperty
assert property (p_mret_mstatus_bits);

// No MRET → no Port C write
property p_no_mret_no_csr;
  @(posedge clk) disable iff (!rst_n)
  !mret_commit |-> !csr_write_en_mret_o;
endproperty
assert property (p_no_mret_no_csr);
```

---

## 3. Directed Smoke Tests (Combinational)

Since this module is purely combinational, tests are just stimulus→check pairs.

| ID | Inputs | Expected Outputs |
|----|--------|------------------|
| WB-S1 | `valid=1, exc_valid=1, cause=11, mtvec=0x100` | trap_commit=1, target=0x100, flush=1111, trap_valid=1 |
| WB-S2 | `valid=1, is_mret=1, exc_valid=0, mepc=0x200` | mret_commit=1, target=0x200, flush=1111, csr_write_en_mret=1 |
| WB-S3 | `valid=1, irq_valid=1, exc_valid=0, is_mret=0` | irq_commit=1, trap_is_interrupt=1 |
| WB-S4 | `valid=0` (bubble) | All commits=0, no redirect, no flush |
| WB-S5 | `valid=1, exc_valid=1, is_mret=1` (exc beats mret) | trap_commit=1, mret_commit=0 |
| WB-S6 | `valid=1, exc_valid=1, irq_valid=1` (exc beats irq) | trap_commit=1, irq_commit=0 |
| WB-S7 | `valid=1, is_mret=1, irq_valid=1` (mret beats irq) | mret_commit=1, irq_commit=0 |
| WB-S8 | mtvec=0xABCDEFFF (unaligned) | target[1:0]=00 (masked) |
| WB-S9 | MRET: mstatus_i = {MPIE=0, MIE=1} | csr_wdata_mret: MIE=0 (from MPIE) |
| WB-S10 | trap: cause=4 (load misalign) | trap_addr_valid=1, trap_cause=4 |
| WB-S11 | irq: irq_id=31'd7 | trap_cause=irq_id, trap_is_interrupt=1 |

### TB Skeleton

```systemverilog
module tb_wb_commit_ctrl;
  // All inputs are regs (combinational DUT)
  logic valid_W, exc_valid_W, is_mret_W, irq_valid_i;
  logic [4:0] exc_cause_W;
  logic [31:0] exc_tval_W, exc_pc_W, mtvec_i, mepc_i, mstatus_i;
  logic [30:0] irq_id_i;
  // Outputs
  logic wb_trap_redirect_o, trap_valid_o, trap_addr_valid_o, trap_is_interrupt_o;
  logic [31:0] trap_target_o, trap_pc_o, trap_addr_o;
  logic [30:0] trap_cause_o;
  logic [3:0] flush_pipeline_onehot_o;
  logic csr_write_en_mret_o, mret_commit_o;
  logic [11:0] csr_waddr_mret_o;
  logic [31:0] csr_wdata_mret_o;

  wb_trap_mret_commit_controller dut (.*);

  integer pass = 0, fail = 0;
  `define CHECK(c, m) if(!(c)) begin $error("FAIL: %s",m); fail++; end else begin pass++; end

  task automatic clear_inputs();
    valid_W=0; exc_valid_W=0; is_mret_W=0; irq_valid_i=0;
    exc_cause_W=0; exc_tval_W=0; exc_pc_W=0;
    mtvec_i=0; mepc_i=0; mstatus_i=0; irq_id_i=0;
    #1;
  endtask

  initial begin
    $display("=== WB Commit Controller Tests ===");

    // WB-S1: Basic trap commit
    clear_inputs();
    valid_W=1; exc_valid_W=1; exc_cause_W=5'd11; mtvec_i=32'h100;
    #1;
    `CHECK(wb_trap_redirect_o==1, "WB-S1: redirect")
    `CHECK(trap_target_o==32'h100, "WB-S1: target=mtvec")
    `CHECK(flush_pipeline_onehot_o==4'b1111, "WB-S1: full flush")
    `CHECK(trap_valid_o==1, "WB-S1: trap_valid")

    // WB-S5: Exception beats MRET
    clear_inputs();
    valid_W=1; exc_valid_W=1; is_mret_W=1; mtvec_i=32'h100;
    #1;
    `CHECK(wb_trap_redirect_o==1, "WB-S5: redirect")
    `CHECK(mret_commit_o==0, "WB-S5: mret suppressed")
    `CHECK(trap_valid_o==1, "WB-S5: trap valid")

    // ... remaining tests ...

    $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
    $finish;
  end
endmodule
```

---

## 4. Coverage Points

```systemverilog
// Commit type distribution
covergroup cg_commit @(posedge clk);
  cp_type: coverpoint {trap_commit, mret_commit, irq_commit} {
    bins trap_only    = {3'b100};
    bins mret_only    = {3'b010};
    bins irq_only     = {3'b001};
    bins no_commit    = {3'b000};
    illegal_bins multi = default;
  }
  cp_priority: coverpoint {valid_W, exc_valid_W, is_mret_W, irq_valid_i} {
    bins exc_vs_mret = {4'b1110};  // exc beats mret
    bins exc_vs_irq  = {4'b1101};  // exc beats irq
    bins mret_vs_irq = {4'b1011};  // mret beats irq
    bins all_three   = {4'b1111};  // exc beats both
  }
endgroup
```
