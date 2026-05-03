# CSR + Trap Integration Verification

**Scope**: `csr_regfile` ↔ `wb_trap_mret_commit_controller` ↔ `memory_cycle` (misalignment)  
**Priority**: P0–P1  
**Tests**: Multi-block integration — verifies wiring, port priority, and state transitions

---

## 1. Integration Scope

This level connects CSR regfile + WB controller together and verifies:
1. Trap entry: controller asserts trap → CSR atomically updates 4 registers
2. MRET: controller computes new mstatus → CSR Port C applies it
3. Round-trip: ECALL → trap entry → (handler runs) → MRET → correct mstatus
4. MEM exception merge: misalignment detected locally → merged with propagated exc

---

## 2. Integration TB Architecture

```systemverilog
module tb_csr_trap_integration;
  logic clk = 0, rst_n;
  always #5 clk = ~clk;

  // Stimulus wires (driven by test)
  logic valid_W, exc_valid_W, is_mret_W;
  logic [4:0] exc_cause_W;
  logic [31:0] exc_tval_W, exc_pc_W;
  logic irq_valid_i;
  logic [30:0] irq_id_i;
  logic instr_retired;
  // Normal CSR write (simulates CSR instruction at WB)
  logic [11:0] csr_waddr_normal; logic [31:0] csr_wdata_normal; logic csr_wen_normal;

  // Controller → CSR wires (internal)
  wire trap_valid, trap_is_interrupt, trap_addr_valid;
  wire [30:0] trap_cause; wire [31:0] trap_pc, trap_addr;
  wire csr_write_en_mret; wire [11:0] csr_waddr_mret; wire [31:0] csr_wdata_mret;
  wire mret_commit, wb_trap_redirect;
  wire [31:0] trap_target;
  wire [3:0] flush_pipeline_onehot;

  // CSR sideband → Controller
  wire [31:0] mtvec_sb, mepc_sb, mstatus_sb;

  // CSR read port
  logic [11:0] csr_raddr; wire [31:0] csr_rdata;
  wire [31:0] mie_sb, mip_sb, mcause_sb;
  wire mstatus_mie_sb;

  // --- DUT Instances ---
  wb_trap_mret_commit_controller u_ctrl (
    .valid_W(valid_W), .exc_valid_W(exc_valid_W),
    .exc_cause_W(exc_cause_W), .exc_tval_W(exc_tval_W), .exc_pc_W(exc_pc_W),
    .is_mret_W(is_mret_W),
    .irq_valid_i(irq_valid_i), .irq_id_i(irq_id_i),
    .mtvec_i(mtvec_sb), .mepc_i(mepc_sb), .mstatus_i(mstatus_sb),
    .wb_trap_redirect_o(wb_trap_redirect), .trap_target_o(trap_target),
    .flush_pipeline_onehot_o(flush_pipeline_onehot),
    .trap_valid_o(trap_valid), .trap_cause_o(trap_cause),
    .trap_pc_o(trap_pc), .trap_addr_o(trap_addr),
    .trap_addr_valid_o(trap_addr_valid), .trap_is_interrupt_o(trap_is_interrupt),
    .csr_write_en_mret_o(csr_write_en_mret),
    .csr_waddr_mret_o(csr_waddr_mret), .csr_wdata_mret_o(csr_wdata_mret),
    .mret_commit_o(mret_commit)
  );

  csr_regfile u_csr (
    .clk_i(clk), .rst_n_i(rst_n),
    .csr_raddr_i(csr_raddr), .csr_rdata_o(csr_rdata),
    .csr_waddr_normal_i(csr_waddr_normal), .csr_wdata_normal_i(csr_wdata_normal),
    .csr_write_en_normal_i(csr_wen_normal),
    .csr_waddr_mret_i(csr_waddr_mret), .csr_wdata_mret_i(csr_wdata_mret),
    .csr_write_en_mret_i(csr_write_en_mret),
    .trap_valid_i(trap_valid), .trap_cause_i(trap_cause),
    .trap_pc_i(trap_pc), .trap_addr_i(trap_addr),
    .trap_addr_valid_i(trap_addr_valid), .trap_is_interrupt_i(trap_is_interrupt),
    .instr_retired_i(instr_retired),
    .timer_intr_i(1'b0), .ext_intr_i(1'b0), .msft_intr_i(1'b0),
    .mtvec_out_o(mtvec_sb), .mie_out_o(mie_sb), .mip_out_o(mip_sb),
    .mstatus_mie_out_o(mstatus_mie_sb),
    .mepc_out_o(mepc_sb), .mcause_out_o(mcause_sb), .mstatus_out_o(mstatus_sb)
  );
  // ... tests follow
endmodule
```

---

## 3. Integration Test Scenarios

### 3.1 ECALL Trap Entry (INT-S1)

```
Sequence:
  1. Set mtvec = 0x200 (via normal CSR write)
  2. Set mstatus.MIE = 1
  3. Fire: valid_W=1, exc_valid_W=1, cause=11, pc=0x50, tval=0

Check (next clock edge):
  - mepc = 0x50
  - mcause = 32'h0000000B (exception, cause 11)
  - mtval = 0 (ECALL has no addr)
  - mstatus.MIE = 0 (cleared)
  - mstatus.MPIE = 1 (saved from MIE)
  - mstatus.MPP = 2'b11
  - trap_target = 0x200 (same cycle, combinational)
  - wb_trap_redirect = 1
```

### 3.2 MRET After Trap (INT-S2)

```
Sequence (continues from INT-S1):
  1. De-assert trap inputs (valid_W=0)
  2. Wait 1 cycle
  3. Fire: valid_W=1, is_mret_W=1, exc_valid_W=0

Check (same cycle, combinational):
  - mret_commit = 1
  - trap_target = mepc = 0x50 (set by INT-S1)
  - csr_write_en_mret = 1
  - csr_wdata_mret[3] = mstatus.MPIE (which is 1 from INT-S1)
  - csr_wdata_mret[7] = 1
  - csr_wdata_mret[12:11] = 2'b11

Check (next clock edge):
  - mstatus.MIE = 1 (restored from MPIE)
  - mstatus.MPIE = 1
  - mstatus.MPP = 2'b11
```

### 3.3 Full Round-Trip Sequence (INT-S3)

```
Cycle 0: Setup mtvec=0x200, mstatus.MIE=1
Cycle 1: ECALL trap → mepc=PC, MIE→0, MPIE←1
Cycle 2: (handler executes — no WB commit)
Cycle 3: MRET → MIE←MPIE=1, PC→mepc
Cycle 4: Verify: mstatus.MIE=1, PC redirect to mepc

This is the minimum viable exception round-trip.
```

### 3.4 Exception Beats MRET (INT-S4)

```
Stimulus: valid_W=1, exc_valid_W=1, is_mret_W=1, cause=2

Check:
  - trap_commit fires (not mret_commit)
  - mepc updated to exc_pc_W
  - mcause = 2 (illegal instruction)
  - mret CSR write suppressed
```

### 3.5 Misaligned Load Trap (INT-S5)

```
Stimulus: valid_W=1, exc_valid_W=1, cause=4, tval=0x00000003, addr_valid=1

Check:
  - mtval = 0x00000003 (faulting address)
  - mcause = 4 (load misalign)
```

### 3.6 Nested Trap (INT-S6)

```
Sequence:
  1. ECALL trap entry (MIE→0, MPIE←1)
  2. Illegal instruction in handler
  3. Second trap entry: MPIE←MIE=0, MIE←0
  4. MRET: MIE←MPIE=0 (interrupts still disabled!)
  5. Verify: mstatus.MIE = 0 (no spurious re-enable)
```

---

## 4. MEM-Stage Misalignment Integration

### 4.1 Misalignment Detection Assertions (in `memory_cycle.v`)

```systemverilog
// Bind file: sva_mem_exception.sv

// LW at misaligned address → exception
property p_lw_misalign;
  @(posedge clk) disable iff (!rst)
  (valid_M && lsunitM[4:3]==2'b10 && lsunitM[2:0]==3'b010 && 
   ALU_ResultM[1:0]!=2'b00) |->
    exc_valid_mem_local;
endproperty

// LH at odd address → exception
property p_lh_misalign;
  @(posedge clk) disable iff (!rst)
  (valid_M && lsunitM[4:3]==2'b10 && lsunitM[2:0]==3'b001 && 
   ALU_ResultM[0]!=1'b0) |->
    exc_valid_mem_local;
endproperty

// LB at any address → NO exception (always aligned)
property p_lb_no_misalign;
  @(posedge clk) disable iff (!rst)
  (valid_M && lsunitM[4:3]==2'b10 && lsunitM[2:0]==3'b000) |->
    !misaligned_load;
endproperty

// SW at misaligned address → exception
property p_sw_misalign;
  @(posedge clk) disable iff (!rst)
  (valid_M && lsunitM[4:3]==2'b11 && lsunitM[2:0]==3'b010 && 
   ALU_ResultM[1:0]!=2'b00) |->
    misaligned_store;
endproperty

// First-wins merge: propagated exception beats local
property p_first_wins;
  @(posedge clk) disable iff (!rst)
  (exc_valid_M && exc_valid_mem_local) |->
    (exc_cause_mem_final == exc_cause_M);  // Propagated wins
endproperty

// Store write gated when exception
property p_store_gated;
  @(posedge clk) disable iff (!rst)
  (exc_valid_M || exc_valid_mem_local) |->
    (dmem.WE == 1'b0);
endproperty
```

### 4.2 MEM Exception Test Matrix

| ID | Operation | Address | Expected |
|----|-----------|---------|----------|
| MEM-S1 | LW | 0x0004 (aligned) | No exception |
| MEM-S2 | LW | 0x0001 | exc_valid=1, cause=4, tval=0x1 |
| MEM-S3 | LW | 0x0002 | exc_valid=1, cause=4, tval=0x2 |
| MEM-S4 | LW | 0x0003 | exc_valid=1, cause=4, tval=0x3 |
| MEM-S5 | LH | 0x0001 | exc_valid=1, cause=4, tval=0x1 |
| MEM-S6 | LH | 0x0002 | No exception (2-byte aligned) |
| MEM-S7 | LB | 0x0001 | No exception (always aligned) |
| MEM-S8 | SW | 0x0002 | exc_valid=1, cause=6, tval=0x2 |
| MEM-S9 | SH | 0x0003 | exc_valid=1, cause=6, tval=0x3 |
| MEM-S10 | SB | 0x0003 | No exception |
| MEM-S11 | LW misalign + propagated exc | Any | Propagated cause wins |
| MEM-S12 | SW with exc_valid_M=1 | Any | DMEM.WE = 0 |

---

## 5. Integration Assertions Summary

| ID | Property | Location |
|----|----------|----------|
| INT-A1 | Trap entry is atomic (mepc+mcause+mtval+mstatus in 1 cycle) | CSR bind |
| INT-A2 | MRET restores MIE from MPIE | Controller + CSR bind |
| INT-A3 | Exception priority > MRET > IRQ | Controller bind |
| INT-A4 | Continuous flush while exc_inflight | Hazard unit (see doc 04) |
| INT-A5 | MEM misalignment merge: first-wins | MEM bind |
| INT-A6 | Store gated on any exception (propagated or local) | MEM bind |
| INT-A7 | minstret does NOT count on trap commit cycle | CSR bind |
| INT-A8 | mcycle always counts (even during trap) | CSR bind |

---

## 6. Coverage Targets

| Bin | Description | Min Hits |
|-----|-------------|----------|
| Trap entry with each cause code (0,2,3,4,6,11) | Cause diversity | 1 each |
| MRET with MIE=0 before → MIE=0 after | Edge case | 1 |
| MRET with MIE=1 before → MIE=1 after | Normal case | 1 |
| Exception beats MRET | Priority | 1 |
| Nested trap (trap inside handler) | State depth | 1 |
| MEM local exception (load misalign) | Detection | 2+ |
| MEM local exception (store misalign) | Detection | 2+ |
| Propagated exc beats MEM local | Merge | 1 |
