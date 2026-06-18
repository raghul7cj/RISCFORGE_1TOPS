// tb_alu_top.sv
`timescale 1ns / 1ps

// Include all TB files in correct compilation order
`include "alu_transaction.sv"
`include "alu_driver.sv"
`include "alu_monitor.sv"
`include "alu_scoreboard.sv"
`include "alu_coverage.sv"
`include "alu_env.sv"
`include "alu_seq_directed.sv"
`include "alu_seq_crv.sv"
`include "alu_seq_corner.sv"

module tb_alu_top;

  // Interface instance
  alu_if inf();

  // DUT instance
  ALU dut (
    .A(inf.A),
    .B(inf.B),
    .ALUControl(inf.ALUControl),
    .Result(inf.Result),
    .Zero(inf.Zero),
    .flags(inf.flags)
  );

  // Environment instance
  alu_env env;

  // Sequence handles
  alu_seq_directed seq_dir;
  alu_seq_crv      seq_crv;
  alu_seq_corner   seq_corn;

  initial begin
    $display("[TB_ALU_TOP] Starting ALU SystemVerilog Class-Based Verification...");
    
    // Initialize environment
    env = new(inf);
    
    // Run environment
    env.run();

    // Instantiate sequences
    seq_dir  = new(env.drv_mbx);
    seq_crv  = new(env.drv_mbx, 150); // Run 150 random iterations
    seq_corn = new(env.drv_mbx);

    // ----------------------------------------------------
    // Execute sequences sequentially
    // ----------------------------------------------------
    #1ns;
    seq_dir.body();   // 1. Directed tests
    #10ns;
    seq_corn.body();  // 2. Corner values
    #10ns;
    seq_crv.body();   // 3. Constrained random tests
    #20ns;

    $display("[TB_ALU_TOP] Verification completed.");
    $display("[TB_ALU_TOP] Total Comparisons: %0d", env.scoreboard.comparison_count);
    $display("[TB_ALU_TOP] Total Errors: %0d", env.scoreboard.error_count);
    
    if (env.scoreboard.error_count == 0) begin
      $display("[TB_ALU_TOP] STATUS: PASSED");
    end else begin
      $display("[TB_ALU_TOP] STATUS: FAILED");
    end
    
    $finish;
  end

endmodule
