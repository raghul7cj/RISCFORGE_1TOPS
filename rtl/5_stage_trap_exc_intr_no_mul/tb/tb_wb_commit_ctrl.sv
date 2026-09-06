`timescale 1ns/1ps

module tb_wb_commit_ctrl;
  // Simple clock for sampling (DUT itself is combinational)
  logic clk;
  logic rst_n;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Inputs
  logic        valid_W;
  logic        exc_valid_W;
  logic [4:0]  exc_cause_W;
  logic [31:0] exc_tval_W;
  logic [31:0] exc_pc_W;

  logic        is_mret_W;

  logic        irq_valid_i;
  logic [30:0] irq_id_i;

  logic [31:0] mtvec_i;
  logic [31:0] mepc_i;
  logic [31:0] mstatus_i;

  // Outputs
  wire        wb_trap_redirect_o;
  wire [31:0] trap_target_o;
  wire [3:0]  flush_pipeline_onehot_o;

  wire        trap_valid_o;
  wire [30:0] trap_cause_o;
  wire [31:0] trap_pc_o;
  wire [31:0] trap_addr_o;
  wire        trap_addr_valid_o;
  wire        trap_is_interrupt_o;

  wire        csr_write_en_mret_o;
  wire [11:0] csr_waddr_mret_o;
  wire [31:0] csr_wdata_mret_o;

  wire        mret_commit_o;

  wb_trap_mret_commit_controller dut (
    .valid_W(valid_W),
    .exc_valid_W(exc_valid_W),
    .exc_cause_W(exc_cause_W),
    .exc_tval_W(exc_tval_W),
    .exc_pc_W(exc_pc_W),
    .is_mret_W(is_mret_W),
    .irq_valid_i(irq_valid_i),
    .irq_id_i(irq_id_i),
    .mtvec_i(mtvec_i),
    .mepc_i(mepc_i),
    .mstatus_i(mstatus_i),
    .wb_trap_redirect_o(wb_trap_redirect_o),
    .trap_target_o(trap_target_o),
    .flush_pipeline_onehot_o(flush_pipeline_onehot_o),
    .trap_valid_o(trap_valid_o),
    .trap_cause_o(trap_cause_o),
    .trap_pc_o(trap_pc_o),
    .trap_addr_o(trap_addr_o),
    .trap_addr_valid_o(trap_addr_valid_o),
    .trap_is_interrupt_o(trap_is_interrupt_o),
    .csr_write_en_mret_o(csr_write_en_mret_o),
    .csr_waddr_mret_o(csr_waddr_mret_o),
    .csr_wdata_mret_o(csr_wdata_mret_o),
    .mret_commit_o(mret_commit_o)
  );

  int pass, fail;
  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      $error("FAIL: %s", msg);
      fail++;
    end else begin
      pass++;
    end
  endtask

  task automatic clear_inputs();
    valid_W = 0;
    exc_valid_W = 0;
    exc_cause_W = 0;
    exc_tval_W = 0;
    exc_pc_W = 0;
    is_mret_W = 0;
    irq_valid_i = 0;
    irq_id_i = 0;
    mtvec_i = 0;
    mepc_i = 0;
    mstatus_i = 0;
    #1;
  endtask

  initial begin
    pass = 0;
    fail = 0;
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    $display("=== tb_wb_commit_ctrl ===");

    // WB-S1: Trap commit targets mtvec
    clear_inputs();
    valid_W = 1;
    exc_valid_W = 1;
    exc_cause_W = 5'd11;
    mtvec_i = 32'h0000_0103; // unaligned input
    exc_pc_W = 32'h0000_0040;
    exc_tval_W = 32'h0;
    #1;
    check(wb_trap_redirect_o == 1'b1, "Trap: redirect asserted");
    check(trap_target_o == 32'h0000_0100, "Trap: target aligned mtvec");
    check(flush_pipeline_onehot_o == 4'b1111, "Trap: full flush");
    check(trap_valid_o == 1'b1, "Trap: trap_valid asserted");
    check(trap_is_interrupt_o == 1'b0, "Trap: not interrupt");
    check(trap_addr_valid_o == 1'b1, "Trap: addr_valid true for exception");

    // WB-S2: MRET commit targets mepc and drives Port C
    clear_inputs();
    valid_W = 1;
    is_mret_W = 1;
    mepc_i = 32'h0000_0205;
    mstatus_i = 32'h0000_0080; // MPIE=1 (bit7)
    #1;
    check(wb_trap_redirect_o == 1'b1, "MRET: redirect asserted");
    check(trap_target_o == 32'h0000_0204, "MRET: target aligned mepc");
    check(mret_commit_o == 1'b1, "MRET: mret_commit asserted");
    check(csr_write_en_mret_o == 1'b1, "MRET: csr write enable");
    check(csr_waddr_mret_o == 12'h300, "MRET: writes mstatus");
    check(csr_wdata_mret_o[3] == mstatus_i[7], "MRET: MIE <- MPIE");
    check(csr_wdata_mret_o[7] == 1'b1, "MRET: MPIE <- 1");
    check(csr_wdata_mret_o[12:11] == 2'b11, "MRET: MPP <- 11");
    check(trap_valid_o == 1'b0, "MRET: trap_valid not asserted");

    // WB-S5: Exception beats MRET
    clear_inputs();
    valid_W = 1;
    exc_valid_W = 1;
    is_mret_W = 1;
    mtvec_i = 32'h100;
    #1;
    check(trap_valid_o == 1'b1, "Exc beats MRET: trap_valid");
    check(csr_write_en_mret_o == 1'b0, "Exc beats MRET: no Port C write");

    $display("=== Results: %0d pass, %0d fail ===", pass, fail);
    if (fail != 0) $fatal(1);
    $finish;
  end

endmodule
