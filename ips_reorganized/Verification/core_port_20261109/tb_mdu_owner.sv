`timescale 1ns/1ps
module tb_mdu_owner;
  reg clk=0;
  reg rst_n=0;
  reg FlushM=0;
  reg wb_redirect_i=0;
  reg FlushE=0;
  reg StallM=0;
  reg RegWriteE=0;
  reg ALUSrcE=0;
  reg MemWriteE=0;
  reg LUISrcE=0;
  reg isLUIE=0;
  reg [1:0] ResultSrcE=0;
  reg [3:0] BranchE=0;
  reg [3:0] ALUControlE=0;
  reg [4:0] lsunitE=0;
  reg [1:0] JumpE=0;
  reg [31:0] RD1_E=0;
  reg [31:0] RD2_E=0;
  reg [31:0] Imm_Ext_E=0;
  reg [4:0] RD_E=0;
  reg [31:0] PCE=0;
  reg [31:0] PCPlus4E=0;
  reg valid_E=0;
  reg exc_valid_E=0;
  reg [5:0] exc_cause_E=0;
  reg [31:0] exc_tval_E=0;
  reg [31:0] exc_pc_E=0;
  reg is_mret_E=0;
  reg irq_pending_i=0;
  reg [30:0] irq_id_i=0;
  reg [1:0] irq_class_i=0;
  reg [31:0] ResultW=0;
  reg [1:0] ForwardA_E=0;
  reg [1:0] ForwardB_E=0;
  reg csr_valid_E=0;
  reg csr_imm_mode_E=0;
  reg [1:0] csr_op_E=0;
  reg [4:0] csr_rs1_uimm_E=0;
  reg [11:0] csr_addr_E=0;
  reg is_M_instruction_E=0;
  reg [2:0] op_E=0;
  reg [31:0] csr_rdata_i=0;
  always #5 clk=~clk;
  wire valid_M,RegWriteM;
  wire [31:0] ALU_ResultM,PC_M;
  wire [4:0] RD_M;
  execute_cycle dut(.clk(clk),
.rst_n(rst_n),
.FlushM(FlushM),
.wb_redirect_i(wb_redirect_i),
.FlushE(FlushE),
.StallM(StallM),
.RegWriteE(RegWriteE),
.ALUSrcE(ALUSrcE),
.MemWriteE(MemWriteE),
.LUISrcE(LUISrcE),
.isLUIE(isLUIE),
.ResultSrcE(ResultSrcE),
.BranchE(BranchE),
.ALUControlE(ALUControlE),
.lsunitE(lsunitE),
.JumpE(JumpE),
.RD1_E(RD1_E),
.RD2_E(RD2_E),
.Imm_Ext_E(Imm_Ext_E),
.RD_E(RD_E),
.PCE(PCE),
.PCPlus4E(PCPlus4E),
.valid_E(valid_E),
.exc_valid_E(exc_valid_E),
.exc_cause_E(exc_cause_E),
.exc_tval_E(exc_tval_E),
.exc_pc_E(exc_pc_E),
.is_mret_E(is_mret_E),
.irq_pending_i(irq_pending_i),
.irq_id_i(irq_id_i),
.irq_class_i(irq_class_i),
.ResultW(ResultW),
.ForwardA_E(ForwardA_E),
.ForwardB_E(ForwardB_E),
.csr_valid_E(csr_valid_E),
.csr_imm_mode_E(csr_imm_mode_E),
.csr_op_E(csr_op_E),
.csr_rs1_uimm_E(csr_rs1_uimm_E),
.csr_addr_E(csr_addr_E),
.is_M_instruction_E(is_M_instruction_E),
.op_E(op_E),
.csr_rdata_i(csr_rdata_i),.valid_M(valid_M),.RegWriteM(RegWriteM),
    .ALU_ResultM(ALU_ResultM),.PC_M(PC_M),.RD_M(RD_M));
  integer writes=0;
  reg [31:0] last_result;
  always @(posedge clk) if(rst_n && valid_M && RegWriteM) begin
    writes=writes+1; last_result=ALU_ResultM;
  end
  task reset_dut;
    begin rst_n=0; valid_E=0;is_M_instruction_E=0;wb_redirect_i=0;StallM=0;
      repeat(3) @(negedge clk); rst_n=1; writes=0; end
  endtask
  task issue(input [2:0] op);
    begin
      @(negedge clk);valid_E=1;is_M_instruction_E=1;op_E=op;
      RD1_E=63;RD2_E=7;RD_E=9;PCE=32'h80000020;PCPlus4E=32'h80000024;
      @(negedge clk);valid_E=0;is_M_instruction_E=0;
    end
  endtask
  initial begin
    reset_dut(); issue(0);
    StallM=1;
    repeat(8) @(negedge clk);
    if(!dut.m_hold) $fatal(1,"MUL completion not buffered");
    StallM=0;
    @(negedge clk);
    if(!valid_M || !RegWriteM || ALU_ResultM!=441 || RD_M!=9 || PC_M!=32'h80000020)
      $fatal(1,"buffered completion packet corrupted");
    repeat(4) @(negedge clk);
    if(writes!=1) $fatal(1,"completion duplicated count=%0d",writes);
    $display("PASS MDU result survives backpressure exactly once with owner PC");
    reset_dut(); issue(0);
    wb_redirect_i=1; @(negedge clk); wb_redirect_i=0;
    repeat(10) @(negedge clk);
    if(writes!=0) $fatal(1,"killed MUL completion escaped");
    $display("PASS killed multiplier completion suppressed");
    reset_dut(); issue(4);
    repeat(4) @(negedge clk);
    wb_redirect_i=1; @(negedge clk); wb_redirect_i=0;
    repeat(50) @(negedge clk);
    if(writes!=0) $fatal(1,"killed DIV completion escaped");
    $display("PASS killed divider completion suppressed");
    reset_dut(); issue(0);
    wb_redirect_i=1; @(negedge clk); wb_redirect_i=0;
    issue(4);
    repeat(60) @(negedge clk);
    if(writes!=1 || last_result!=9)
      $fatal(1,"new MDU owner lost/aliased after abort count=%0d result=%h",writes,last_result);
    $display("PASS new divider owner completes after multiplier abort");
    $finish;
  end
endmodule
