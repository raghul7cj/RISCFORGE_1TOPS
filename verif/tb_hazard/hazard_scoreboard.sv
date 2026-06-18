// hazard_scoreboard.sv
class hazard_scoreboard;
  mailbox #(hazard_transaction) mon_mbx;
  int comparison_count = 0;
  int error_count = 0;

  function new(mailbox #(hazard_transaction) mon_mbx);
    this.mon_mbx = mon_mbx;
  endfunction

  function void predict_outputs(
    hazard_transaction txn,
    output logic [1:0] exp_ForwardAE,
    output logic [1:0] exp_ForwardBE,
    output logic exp_StallF,
    output logic exp_StallD,
    output logic exp_FlushD,
    output logic exp_FlushE,
    output logic exp_FlushM,
    output logic exp_FlushW
  );
    logic lwstall;
    logic csr_stall;
    logic csr_gpr_stall;
    logic exc_inflight_E;
    logic exc_inflight_M;

    // Forwarding
    if (txn.rst == 1'b0) begin
      exp_ForwardAE = 2'b00;
      exp_ForwardBE = 2'b00;
    end else begin
      if (txn.RegWriteM && (txn.Rs1_E != 5'd0) && (txn.RD_M == txn.Rs1_E))
        exp_ForwardAE = 2'b10;
      else if (txn.RegWriteW && (txn.Rs1_E != 5'd0) && (txn.RD_W == txn.Rs1_E))
        exp_ForwardAE = 2'b01;
      else
        exp_ForwardAE = 2'b00;

      if (txn.RegWriteM && (txn.Rs2_E != 5'd0) && (txn.RD_M == txn.Rs2_E))
        exp_ForwardBE = 2'b10;
      else if (txn.RegWriteW && (txn.Rs2_E != 5'd0) && (txn.RD_W == txn.Rs2_E))
        exp_ForwardBE = 2'b01;
      else
        exp_ForwardBE = 2'b00;
    end

    // Load-Use Stall
    lwstall = (txn.ResultSrcE == 2'b01) &&
              ((txn.Rs1_D == txn.RdE) || (txn.Rs2_D == txn.RdE)) &&
              (txn.RdE != 5'd0);

    // CSR Stall
    csr_stall = txn.csr_valid_D &&
                ((txn.csr_raddr_D == txn.csr_addr_E && txn.csr_write_en_E) ||
                 (txn.csr_raddr_D == txn.csr_addr_M && txn.csr_write_en_M) ||
                 (txn.csr_raddr_D == txn.csr_addr_W && txn.csr_write_en_W));

    // CSR-use GPR Stall
    csr_gpr_stall = (txn.ResultSrcE == 2'b11) &&
                    ((txn.Rs1_D == txn.RdE) || (txn.Rs2_D == txn.RdE)) &&
                    (txn.RdE != 5'd0);

    // Stall Outputs
    if (txn.wb_redirect) begin
      exp_StallF = 1'b0;
      exp_StallD = 1'b0;
    end else begin
      exp_StallF = lwstall | csr_stall | csr_gpr_stall | txn.stallM;
      exp_StallD = lwstall | csr_stall | csr_gpr_stall | txn.stallM;
    end

    // Exception inflight
    exc_inflight_E = txn.valid_E & txn.exc_valid_E;
    exc_inflight_M = txn.valid_M & txn.exc_valid_M;

    // Flushes
    exp_FlushE = lwstall | csr_gpr_stall | txn.PCSrcE | csr_stall | exc_inflight_M | txn.wb_redirect | txn.flush_pipeline_onehot[1] | txn.stallM;
    exp_FlushD = txn.PCSrcE | exc_inflight_E | exc_inflight_M | txn.wb_redirect | txn.flush_pipeline_onehot[0];
    exp_FlushM = txn.wb_redirect | txn.flush_pipeline_onehot[2] | txn.stallM;
    exp_FlushW = txn.wb_redirect | txn.flush_pipeline_onehot[3];
  end

  task run();
    forever begin
      hazard_transaction txn;
      logic [1:0] exp_ForwardAE, exp_ForwardBE;
      logic exp_StallF, exp_StallD;
      logic exp_FlushD, exp_FlushE, exp_FlushM, exp_FlushW;

      mon_mbx.get(txn);
      predict_outputs(
        txn,
        exp_ForwardAE, exp_ForwardBE,
        exp_StallF, exp_StallD,
        exp_FlushD, exp_FlushE, exp_FlushM, exp_FlushW
      );

      comparison_count++;

      if (txn.ForwardAE !== exp_ForwardAE) begin
        $error("[Scoreboard] ForwardAE MISMATCH | Actual: %b Expected: %b", txn.ForwardAE, exp_ForwardAE);
        error_count++;
      end

      if (txn.ForwardBE !== exp_ForwardBE) begin
        $error("[Scoreboard] ForwardBE MISMATCH | Actual: %b Expected: %b", txn.ForwardBE, exp_ForwardBE);
        error_count++;
      end

      if (txn.StallF !== exp_StallF) begin
        $error("[Scoreboard] StallF MISMATCH | Actual: %b Expected: %b", txn.StallF, exp_StallF);
        error_count++;
      end

      if (txn.StallD !== exp_StallD) begin
        $error("[Scoreboard] StallD MISMATCH | Actual: %b Expected: %b", txn.StallD, exp_StallD);
        error_count++;
      end

      if (txn.FlushD !== exp_FlushD) begin
        $error("[Scoreboard] FlushD MISMATCH | Actual: %b Expected: %b", txn.FlushD, exp_FlushD);
        error_count++;
      end

      if (txn.FlushE !== exp_FlushE) begin
        $error("[Scoreboard] FlushE MISMATCH | Actual: %b Expected: %b", txn.FlushE, exp_FlushE);
        error_count++;
      end

      if (txn.FlushM !== exp_FlushM) begin
        $error("[Scoreboard] FlushM MISMATCH | Actual: %b Expected: %b", txn.FlushM, exp_FlushM);
        error_count++;
      end

      if (txn.FlushW !== exp_FlushW) begin
        $error("[Scoreboard] FlushW MISMATCH | Actual: %b Expected: %b", txn.FlushW, exp_FlushW);
        error_count++;
      end
    end
  endtask
endclass: hazard_scoreboard
