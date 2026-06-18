// hazard_transaction.sv
class hazard_transaction;
  // Inputs
  rand logic        rst;
  rand logic        RegWriteM;
  rand logic        RegWriteW;
  rand logic [4:0]  RD_M;
  rand logic [4:0]  RD_W;
  rand logic [4:0]  Rs1_E;
  rand logic [4:0]  Rs2_E;
  rand logic [4:0]  Rs1_D;
  rand logic [4:0]  Rs2_D;
  rand logic [4:0]  RdE;
  rand logic [1:0]  ResultSrcE;
  rand logic        PCSrcE;
  rand logic        illegal_instr;
  rand logic        csr_valid_D;
  rand logic [11:0] csr_raddr_D;
  rand logic [11:0] csr_raddr_E;
  rand logic [11:0] csr_raddr_W;
  rand logic [11:0] csr_addr_E;
  rand logic [11:0] csr_addr_M;
  rand logic [11:0] csr_addr_W;
  rand logic        csr_write_en_W;
  rand logic        csr_write_en_M;
  rand logic        csr_write_en_E;
  rand logic [3:0]  flush_pipeline_onehot;
  rand logic        valid_E;
  rand logic        exc_valid_E;
  rand logic        valid_M;
  rand logic        exc_valid_M;
  rand logic        wb_redirect;
  rand logic        stallM;

  // Outputs
  logic [1:0]  ForwardAE;
  logic [1:0]  ForwardBE;
  logic        StallF;
  logic        StallD;
  logic        FlushD;
  logic        FlushE;
  logic        FlushM;
  logic        FlushW;

  // Default Constraints
  constraint c_default {
    rst == 1'b1;
    flush_pipeline_onehot == 4'b0000;
  }

  function void display(string prefix = "");
    $display("[%s] rst=%b | StallF=%b StallD=%b FlushE=%b FlushD=%b | ForwardAE=%b ForwardBE=%b",
             prefix, rst, StallF, StallD, FlushE, FlushD, ForwardAE, ForwardBE);
  endfunction
endclass: hazard_transaction
