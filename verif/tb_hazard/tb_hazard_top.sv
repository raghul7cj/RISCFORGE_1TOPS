// tb_hazard_top.sv
`timescale 1ns / 1ps

module tb_hazard_top;

  hazard_if inf();

  // DUT Instance
  hazard_unit dut (
    .rst(inf.rst),
    .RegWriteM(inf.RegWriteM),
    .RegWriteW(inf.RegWriteW),
    .RD_M(inf.RD_M),
    .RD_W(inf.RD_W),
    .Rs1_E(inf.Rs1_E),
    .Rs2_E(inf.Rs2_E),
    .Rs1_D(inf.Rs1_D),
    .Rs2_D(inf.Rs2_D),
    .RdE(inf.RdE),
    .ForwardAE(inf.ForwardAE),
    .ForwardBE(inf.ForwardBE),
    .ResultSrcE(inf.ResultSrcE),
    .PCSrcE(inf.PCSrcE),
    .StallF(inf.StallF),
    .StallD(inf.StallD),
    .FlushD(inf.FlushD),
    .FlushE(inf.FlushE),
    .FlushM(inf.FlushM),
    .FlushW(inf.FlushW),
    .illegal_instr(inf.illegal_instr),
    .csr_valid_D(inf.csr_valid_D),
    .csr_raddr_D(inf.csr_raddr_D),
    .csr_raddr_E(inf.csr_raddr_E),
    .csr_raddr_W(inf.csr_raddr_W),
    .csr_addr_E(inf.csr_addr_E),
    .csr_addr_M(inf.csr_addr_M),
    .csr_addr_W(inf.csr_addr_W),
    .csr_write_en_W(inf.csr_write_en_W),
    .csr_write_en_M(inf.csr_write_en_M),
    .csr_write_en_E(inf.csr_write_en_E),
    .flush_pipeline_onehot(inf.flush_pipeline_onehot),
    .valid_E(inf.valid_E),
    .exc_valid_E(inf.exc_valid_E),
    .valid_M(inf.valid_M),
    .exc_valid_M(inf.exc_valid_M),
    .wb_redirect(inf.wb_redirect),
    .stallM(inf.stallM)
  );

  hazard_env env;

  initial begin
    $display("[TB_HAZARD_TOP] Starting Hazard Unit Verification...");
    
    env = new(inf);
    env.run();

    // ----------------------------------------------------
    // Scenario 1: Reset Behavior
    // ----------------------------------------------------
    $display("[TB_HAZARD_TOP] Running Reset test...");
    drive_reset_test();

    // ----------------------------------------------------
    // Scenario 2: Data Forwarding Tests
    // ----------------------------------------------------
    $display("[TB_HAZARD_TOP] Running Forwarding tests...");
    
    // RAW distance-1 Forwarding to Rs1 (MEM -> EX)
    drive_forward_test(.rs1_e(5'd12), .rs2_e(5'd0), .rd_m(5'd12), .rd_w(5'd0), .regwrite_m(1'b1), .regwrite_w(1'b0));
    
    // RAW distance-2 Forwarding to Rs2 (WB -> EX)
    drive_forward_test(.rs1_e(5'd0), .rs2_e(5'd15), .rd_m(5'd0), .rd_w(5'd15), .regwrite_m(1'b0), .regwrite_w(1'b1));

    // Priority test: Rs1 matches both MEM and WB stage. MEM must take priority (2'b10).
    drive_forward_test(.rs1_e(5'd8), .rs2_e(5'd0), .rd_m(5'd8), .rd_w(5'd8), .regwrite_m(1'b1), .regwrite_w(1'b1));

    // x0 bypass exception check: x0 must not trigger forwarding
    drive_forward_test(.rs1_e(5'd0), .rs2_e(5'd0), .rd_m(5'd0), .rd_w(5'd0), .regwrite_m(1'b1), .regwrite_w(1'b1));

    // ----------------------------------------------------
    // Scenario 3: Load-Use Hazard Stall
    // ----------------------------------------------------
    $display("[TB_HAZARD_TOP] Running Load-Use Stall tests...");
    drive_load_use_test(.rs1_d(5'd4), .rs2_d(5'd0), .rd_e(5'd4), .result_src_e(2'b01)); // Load instruction in EX writes Rd=4

    // ----------------------------------------------------
    // Scenario 4: CSR Hazard Stall
    // ----------------------------------------------------
    $display("[TB_HAZARD_TOP] Running CSR Stall tests...");
    drive_csr_stall_test();

    // ----------------------------------------------------
    // Scenario 5: Random Verification
    // ----------------------------------------------------
    $display("[TB_HAZARD_TOP] Running Constrained Random Tests...");
    for (int i = 0; i < 100; i++) begin
      hazard_transaction txn = new();
      if (!txn.randomize()) begin
        $error("[TB_HAZARD_TOP] Randomization failed!");
      end else begin
        env.drv_mbx.put(txn);
        #2ns;
      end
    end

    #10ns;

    $display("[TB_HAZARD_TOP] Verification completed.");
    $display("[TB_HAZARD_TOP] Total Comparisons: %0d", env.scoreboard.comparison_count);
    $display("[TB_HAZARD_TOP] Total Errors: %0d", env.scoreboard.error_count);
    
    if (env.scoreboard.error_count == 0) begin
      $display("[TB_HAZARD_TOP] STATUS: PASSED");
    end else begin
      $display("[TB_HAZARD_TOP] STATUS: FAILED");
    end
    
    $finish;
  end

  // Helper Tasks
  task drive_reset_test();
    hazard_transaction txn = new();
    txn.rst = 1'b0;
    env.drv_mbx.put(txn);
    #2ns;
  endtask

  task drive_forward_test(
    input [4:0] rs1_e, rs2_e, rd_m, rd_w,
    input regwrite_m, regwrite_w
  );
    hazard_transaction txn = new();
    txn.rst = 1'b1;
    txn.Rs1_E = rs1_e;
    txn.Rs2_E = rs2_e;
    txn.RD_M = rd_m;
    txn.RD_W = rd_w;
    txn.RegWriteM = regwrite_m;
    txn.RegWriteW = regwrite_w;
    env.drv_mbx.put(txn);
    #2ns;
  endtask

  task drive_load_use_test(
    input [4:0] rs1_d, rs2_d, rd_e,
    input [1:0] result_src_e
  );
    hazard_transaction txn = new();
    txn.rst = 1'b1;
    txn.Rs1_D = rs1_d;
    txn.Rs2_D = rs2_d;
    txn.RdE = rd_e;
    txn.ResultSrcE = result_src_e;
    env.drv_mbx.put(txn);
    #2ns;
  endtask

  task drive_csr_stall_test();
    hazard_transaction txn = new();
    txn.rst = 1'b1;
    txn.csr_valid_D = 1'b1;
    txn.csr_raddr_D = 12'h300; // mstatus
    txn.csr_addr_E  = 12'h300; // match in EX
    txn.csr_write_en_E = 1'b1;
    env.drv_mbx.put(txn);
    #2ns;
  endtask

endmodule
