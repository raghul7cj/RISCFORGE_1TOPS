# CSR Regfile Verification — Detailed Plan

**DUT**: `trap_mret_csr/csr_regfile.v` (284 lines)  
**Priority**: P0 — Silent state corruption risk  
**Tools**: Vivado xsim (primary), Verilator (regression)

---

## 1. Block Summary

The CSR regfile is passive storage with 3 write ports and 1 read port:
- **Port A** (Read): Combinational read mux, 12 CSRs
- **Port B** (Write): Normal CSR instruction commits from WB
- **Port C** (Write): MRET mstatus restore from WB commit controller
- **Trap Port**: Atomic trap entry (mepc/mcause/mtval/mstatus)
- **Counters**: mcycle (every cycle), minstret (on retirement)

**Write Priority**: Trap > Port C (MRET) > Port B (normal)

---

## 2. SVA Assertions (Bind File: `sva_csr_regfile.sv`)

### 2.1 Write Mask Enforcement

```systemverilog
// mstatus: only bits [3], [7], [12:11] are writable
property p_mstatus_mask;
  @(posedge clk_i) disable iff (!rst_n_i)
  (csr_write_en_normal_i && csr_waddr_normal_i == 12'h300) |=>
    (mstatus_r[31:13] == $past(mstatus_r[31:13]) || 
     mstatus_r[12:11] != $past(mstatus_r[12:11])) &&  // MPP writable
    (mstatus_r[10:8] == $past(mstatus_r[10:8])) &&     // reserved
    (mstatus_r[6:4] == $past(mstatus_r[6:4])) &&       // reserved
    (mstatus_r[2:0] == $past(mstatus_r[2:0]));          // reserved
endproperty
assert property (p_mstatus_mask) else $error("mstatus write mask violated");

// mtvec: MODE bits [1:0] frozen to 00
property p_mtvec_mode_frozen;
  @(posedge clk_i) disable iff (!rst_n_i)
  (csr_write_en_normal_i && csr_waddr_normal_i == 12'h305) |=>
    (mtvec_r[1:0] == 2'b00);
endproperty
assert property (p_mtvec_mode_frozen) else $error("mtvec MODE not frozen");

// mie: only bits [3], [7], [11] writable
property p_mie_mask;
  @(posedge clk_i) disable iff (!rst_n_i)
  (csr_write_en_normal_i && csr_waddr_normal_i == 12'h304) |=>
    (mie_r & ~32'h00000888) == ($past(mie_r) & ~32'h00000888);
endproperty
assert property (p_mie_mask) else $error("mie write mask violated");
```

### 2.2 Trap Entry Atomicity

```systemverilog
// When trap_valid_i asserts, all 4 CSRs update on same clock edge
property p_trap_atomic;
  @(posedge clk_i) disable iff (!rst_n_i)
  trap_valid_i |=>
    (mepc_r == $past(trap_pc_i)) &&
    (mcause_r == {$past(trap_is_interrupt_i), $past(trap_cause_i)}) &&
    (mstatus_r[3] == 1'b0) &&                    // MIE cleared
    (mstatus_r[7] == $past(mstatus_r[3])) &&     // MPIE = old MIE
    (mstatus_r[12:11] == 2'b11);                  // MPP = M-mode
endproperty
assert property (p_trap_atomic) else $error("Trap entry not atomic");

// mtval conditional write
property p_mtval_conditional;
  @(posedge clk_i) disable iff (!rst_n_i)
  (trap_valid_i && !trap_addr_valid_i) |=>
    (mtval_r == 32'h0);
endproperty
assert property (p_mtval_conditional) else $error("mtval not zeroed on invalid addr");

property p_mtval_valid;
  @(posedge clk_i) disable iff (!rst_n_i)
  (trap_valid_i && trap_addr_valid_i) |=>
    (mtval_r == $past(trap_addr_i));
endproperty
assert property (p_mtval_valid) else $error("mtval not set on valid addr");
```

### 2.3 Write Priority

```systemverilog
// Trap beats normal write to same CSR
property p_trap_priority;
  @(posedge clk_i) disable iff (!rst_n_i)
  (trap_valid_i && csr_write_en_normal_i && csr_waddr_normal_i == 12'h341) |=>
    (mepc_r == $past(trap_pc_i));  // Trap wins, not normal write
endproperty
assert property (p_trap_priority) else $error("Trap did not win priority");

// Trap beats MRET
property p_trap_beats_mret;
  @(posedge clk_i) disable iff (!rst_n_i)
  (trap_valid_i && csr_write_en_mret_i) |=>
    (mstatus_r[3] == 1'b0);  // Trap clears MIE, MRET would restore it
endproperty
assert property (p_trap_beats_mret) else $error("Trap did not beat MRET");
```

### 2.4 Performance Counters

```systemverilog
// mcycle increments every cycle (when not written)
property p_mcycle_inc;
  @(posedge clk_i) disable iff (!rst_n_i)
  (!trap_valid_i && !csr_write_en_mret_i && !csr_write_en_normal_i) |=>
    (mcycle_r == $past(mcycle_r) + 1);
endproperty
assert property (p_mcycle_inc) else $error("mcycle did not increment");

// minstret increments only on retirement
property p_minstret_retire;
  @(posedge clk_i) disable iff (!rst_n_i)
  (instr_retired_i && !trap_valid_i && 
   !(csr_write_en_normal_i && csr_waddr_normal_i == 12'hB02)) |=>
    (minstret_r == $past(minstret_r) + 1);
endproperty
assert property (p_minstret_retire) else $error("minstret did not increment on retire");

// minstret does NOT increment without retirement
property p_minstret_no_retire;
  @(posedge clk_i) disable iff (!rst_n_i)
  (!instr_retired_i && !trap_valid_i && 
   !(csr_write_en_normal_i && csr_waddr_normal_i == 12'hB02)) |=>
    (minstret_r == $past(minstret_r));
endproperty
assert property (p_minstret_no_retire) else $error("minstret incremented without retire");
```

### 2.5 mip Read-Only

```systemverilog
// mip timer/external bits reflect hardware inputs, not software writes
property p_mip_readonly_timer;
  @(posedge clk_i) disable iff (!rst_n_i)
  1 |-> (mip_out_o[7] == timer_intr_i);
endproperty
assert property (p_mip_readonly_timer) else $error("mip timer bit not tracking hardware");

property p_mip_readonly_ext;
  @(posedge clk_i) disable iff (!rst_n_i)
  1 |-> (mip_out_o[11] == ext_intr_i);
endproperty
assert property (p_mip_readonly_ext) else $error("mip ext bit not tracking hardware");
```

---

## 3. Directed Smoke Tests

### Test Matrix

| ID | Test | Stimulus | Check |
|----|------|----------|-------|
| CSR-S1 | CSRRW mscratch round-trip | Write 0xDEADBEEF via Port B, read back | `csr_rdata_o == 0xDEADBEEF` |
| CSR-S2 | mstatus write mask | Write 0xFFFFFFFF via Port B | Read back `0x00001888` |
| CSR-S3 | mtvec MODE frozen | Write 0xFFFFFFFF via Port B | `mtvec_r[1:0] == 2'b00` |
| CSR-S4 | mie write mask | Write 0xFFFFFFFF via Port B | Read back shows only bits [3,7,11] |
| CSR-S5 | Trap entry: ECALL | `trap_valid=1, cause=11, pc=0x100` | mepc=0x100, mcause=11, MIE=0 |
| CSR-S6 | Trap entry: illegal | `trap_valid=1, cause=2, addr_valid=0` | mtval=0 |
| CSR-S7 | Trap entry: misalign | `trap_valid=1, cause=4, addr=0x3, addr_valid=1` | mtval=0x3 |
| CSR-S8 | MRET restore | Port C: mstatus write with MPIE→MIE | MIE restored, MPIE=1, MPP=11 |
| CSR-S9 | Priority: trap vs normal | Both assert same cycle, mepc target | Trap value wins |
| CSR-S10 | mcycle counts during stall | No writes for 10 cycles | mcycle delta = 10 |
| CSR-S11 | minstret selective | 5 retires, 3 non-retires | minstret delta = 5 |
| CSR-S12 | 64-bit rollover | Set mcycle[31:0] = 0xFFFFFFFF | Next cycle: mcycleh increments |
| CSR-S13 | mip read-only | Write to mip via Port B | timer/ext bits unchanged |
| CSR-S14 | Reset values | Assert reset | All CSRs = 0 |
| CSR-S15 | Read unknown CSR | Read addr 0xFFF | Returns 0 |

### TB Skeleton

```systemverilog
module tb_csr_regfile;
  logic clk, rst_n;
  // Port A
  logic [11:0] raddr; logic [31:0] rdata;
  // Port B
  logic [11:0] waddr_n; logic [31:0] wdata_n; logic wen_n;
  // Port C (MRET)
  logic [11:0] waddr_m; logic [31:0] wdata_m; logic wen_m;
  // Trap
  logic trap_valid; logic [30:0] trap_cause; logic [31:0] trap_pc, trap_addr;
  logic trap_addr_valid, trap_is_interrupt, instr_retired;
  logic timer_intr, ext_intr, msft_intr;
  // Outputs
  logic [31:0] mtvec_out, mie_out, mip_out, mepc_out, mcause_out, mstatus_out;
  logic mstatus_mie_out;

  always #5 clk = ~clk;

  csr_regfile dut (
    .clk_i(clk), .rst_n_i(rst_n),
    .csr_raddr_i(raddr), .csr_rdata_o(rdata),
    .csr_waddr_normal_i(waddr_n), .csr_wdata_normal_i(wdata_n),
    .csr_write_en_normal_i(wen_n),
    .csr_waddr_mret_i(waddr_m), .csr_wdata_mret_i(wdata_m),
    .csr_write_en_mret_i(wen_m),
    .trap_valid_i(trap_valid), .trap_cause_i(trap_cause),
    .trap_pc_i(trap_pc), .trap_addr_i(trap_addr),
    .trap_addr_valid_i(trap_addr_valid),
    .trap_is_interrupt_i(trap_is_interrupt),
    .instr_retired_i(instr_retired),
    .timer_intr_i(timer_intr), .ext_intr_i(ext_intr), .msft_intr_i(msft_intr),
    .mtvec_out_o(mtvec_out), .mie_out_o(mie_out), .mip_out_o(mip_out),
    .mstatus_mie_out_o(mstatus_mie_out),
    .mepc_out_o(mepc_out), .mcause_out_o(mcause_out), .mstatus_out_o(mstatus_out)
  );

  // --- Helper Tasks ---
  task automatic reset_dut();
    rst_n = 0; clk = 0;
    trap_valid = 0; wen_n = 0; wen_m = 0; instr_retired = 0;
    timer_intr = 0; ext_intr = 0; msft_intr = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  task automatic write_csr_normal(input [11:0] addr, input [31:0] data);
    @(posedge clk);
    waddr_n = addr; wdata_n = data; wen_n = 1;
    @(posedge clk);
    wen_n = 0;
  endtask

  task automatic read_csr(input [11:0] addr, output [31:0] data);
    raddr = addr;
    #1; // Combinational settle
    data = rdata;
  endtask

  task automatic fire_trap(input [30:0] cause, input [31:0] pc, addr,
                           input addr_valid, is_intr);
    @(posedge clk);
    trap_valid = 1; trap_cause = cause; trap_pc = pc;
    trap_addr = addr; trap_addr_valid = addr_valid;
    trap_is_interrupt = is_intr;
    @(posedge clk);
    trap_valid = 0;
  endtask

  // --- Test Execution ---
  integer pass_count = 0, fail_count = 0;

  `define CHECK(cond, msg) \
    if (!(cond)) begin $error("FAIL: %s", msg); fail_count++; end \
    else begin $display("PASS: %s", msg); pass_count++; end

  initial begin
    $display("=== CSR Regfile Unit Tests ===");
    reset_dut();

    // CSR-S1: mscratch round-trip
    write_csr_normal(12'h340, 32'hDEADBEEF);
    begin logic [31:0] v; read_csr(12'h340, v);
      `CHECK(v == 32'hDEADBEEF, "CSR-S1: mscratch round-trip")
    end

    // CSR-S2: mstatus mask
    write_csr_normal(12'h300, 32'hFFFFFFFF);
    begin logic [31:0] v; read_csr(12'h300, v);
      `CHECK(v == 32'h00001888, "CSR-S2: mstatus write mask")
    end

    // ... (remaining tests follow same pattern)

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
    if (fail_count > 0) $fatal(1, "TEST SUITE FAILED");
    $finish;
  end
endmodule
```

---

## 4. Functional Coverage (Vivado)

```systemverilog
// In TB wrapper or bind file
covergroup cg_csr_writes @(posedge clk);
  cp_waddr: coverpoint waddr_n iff (wen_n) {
    bins mstatus  = {12'h300};
    bins mie      = {12'h304};
    bins mtvec    = {12'h305};
    bins mscratch = {12'h340};
    bins mepc     = {12'h341};
    bins mcause   = {12'h342};
    bins mtval    = {12'h343};
    bins mcycle   = {12'hB00};
    bins minstret = {12'hB02};
    illegal_bins invalid = default;
  }

  cp_trap_cause: coverpoint trap_cause[4:0] iff (trap_valid) {
    bins misalign_instr = {5'd0};
    bins illegal        = {5'd2};
    bins breakpoint     = {5'd3};
    bins load_misalign  = {5'd4};
    bins store_misalign = {5'd6};
    bins ecall_m        = {5'd11};
  }

  cp_write_priority: coverpoint {trap_valid, wen_m, wen_n} {
    bins trap_only   = {3'b100};
    bins mret_only   = {3'b010};
    bins normal_only = {3'b001};
    bins trap_vs_normal = {3'b101};  // Corner case
    bins trap_vs_mret   = {3'b110};  // Corner case
  }
endgroup
```

### Verilator-Compatible Coverage (Manual Counters)

```systemverilog
// For Verilator: simple hit counters
int cov_trap_ecall = 0, cov_trap_illegal = 0, cov_trap_misalign = 0;
int cov_mret_restore = 0, cov_priority_trap_vs_normal = 0;

always @(posedge clk) begin
  if (trap_valid && trap_cause[4:0] == 5'd11) cov_trap_ecall++;
  if (trap_valid && trap_cause[4:0] == 5'd2)  cov_trap_illegal++;
  if (trap_valid && trap_cause[4:0] == 5'd4)  cov_trap_misalign++;
  if (wen_m)                                   cov_mret_restore++;
  if (trap_valid && wen_n)                     cov_priority_trap_vs_normal++;
end

final begin
  $display("Coverage: ecall=%0d illegal=%0d misalign=%0d mret=%0d priority=%0d",
           cov_trap_ecall, cov_trap_illegal, cov_trap_misalign,
           cov_mret_restore, cov_priority_trap_vs_normal);
end
```

---

## 5. Corner Cases Checklist

| # | Scenario | Expected | Verified By |
|---|----------|----------|-------------|
| 1 | Write to mip (Port B) — timer/ext bits | No effect on [7],[11] | CSR-S13 + assertion |
| 2 | Trap + normal write to mepc same cycle | Trap value wins | CSR-S9 + p_trap_priority |
| 3 | Trap + MRET same cycle | Trap wins (MIE=0) | p_trap_beats_mret |
| 4 | mcycle rollover 32→64 bit | mcycleh increments | CSR-S12 |
| 5 | minstret on trap cycle | Does NOT increment | p_minstret_no_retire |
| 6 | Reset clears all CSRs | All = 0 | CSR-S14 |
| 7 | Read unimplemented CSR | Returns 0 | CSR-S15 |
| 8 | mcycle counter during write | Write value takes effect, then resumes counting | Directed test |
| 9 | Back-to-back writes same CSR | Second write wins | Directed test |
| 10 | MRET mstatus: MPIE=0 before entry | After MRET: MIE=0 (restored from MPIE=0) | Directed test |
