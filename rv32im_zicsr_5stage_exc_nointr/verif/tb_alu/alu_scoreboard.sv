// alu_scoreboard.sv
`include "sv_assert_macros.svh"

class alu_scoreboard;
  mailbox #(alu_transaction) mon_mbx;
  int comparison_count = 0;
  int error_count = 0;

  function new(mailbox #(alu_transaction) mon_mbx);
    this.mon_mbx = mon_mbx;
  endfunction

  // Gold reference model of ALU
  function void predict_outputs(alu_transaction txn, output logic [31:0] exp_res, output logic exp_zero, output logic [2:0] exp_flags);
    logic signed [31:0] A_signed = txn.A;
    logic signed [31:0] B_signed = txn.B;
    
    case (txn.ALUControl)
      4'b0000: exp_res = txn.A + txn.B;                  // ADD
      4'b0001: exp_res = txn.A - txn.B;                  // SUB
      4'b0100: exp_res = txn.A & txn.B;                  // AND
      4'b0101: exp_res = txn.A | txn.B;                  // OR
      4'b0110: exp_res = (txn.A + txn.B) & (~32'd1);     // JALR
      4'b0111: exp_res = txn.A ^ txn.B;                  // XOR
      4'b1000: exp_res = txn.A << txn.B[4:0];            // SLL
      4'b1001: exp_res = txn.A >> txn.B[4:0];            // SRL
      4'b1010: exp_res = A_signed >>> txn.B[4:0];        // SRA
      4'b1100: exp_res = {31'b0, txn.A < txn.B};         // SLTU
      4'b1111: exp_res = {31'b0, A_signed < B_signed};   // SLT
      default: exp_res = 32'b0;
    endcase

    exp_zero = (exp_res == 32'h0);
    exp_flags[2] = (txn.A == txn.B);
    exp_flags[1] = (A_signed < B_signed);
    exp_flags[0] = (txn.A < txn.B);
  endfunction

  task run();
    forever begin
      alu_transaction txn;
      logic [31:0] exp_res;
      logic exp_zero;
      logic [2:0] exp_flags;

      mon_mbx.get(txn);
      predict_outputs(txn, exp_res, exp_zero, exp_flags);

      comparison_count++;

      // Check results
      if (txn.Result !== exp_res) begin
        $error("[Scoreboard] RESULT MISMATCH | A: 0x%08h B: 0x%08h Control: 0x%1h | Actual: 0x%08h Expected: 0x%08h", 
               txn.A, txn.B, txn.ALUControl, txn.Result, exp_res);
        error_count++;
      end

      if (txn.Zero !== exp_zero) begin
        $error("[Scoreboard] ZERO FLAG MISMATCH | Actual: %b Expected: %b | A: 0x%08h B: 0x%08h Control: 0x%1h", txn.Zero, exp_zero, txn.A, txn.B, txn.ALUControl);
        error_count++;
      end

      if (txn.flags !== exp_flags) begin
        $error("[Scoreboard] FLAGS MISMATCH | Actual: 3'b%3b Expected: 3'b%3b", txn.flags, exp_flags);
        error_count++;
      end
    end
  endtask
endclass: alu_scoreboard
