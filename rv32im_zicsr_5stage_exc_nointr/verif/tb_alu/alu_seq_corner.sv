// alu_seq_corner.sv
class alu_seq_corner;
  mailbox #(alu_transaction) drv_mbx;

  function new(mailbox #(alu_transaction) drv_mbx);
    this.drv_mbx = drv_mbx;
  endfunction

  task body();
    logic [31:0] corner_vals[] = '{
      32'h0000_0000, // Zero
      32'h0000_0001, // One
      32'hFFFF_FFFF, // Minus One
      32'h7FFF_FFFF, // Max Positive Signed
      32'h8000_0000  // Min Negative Signed
    };

    logic [3:0] opcodes[] = '{
      4'b0000, // ADD
      4'b0001, // SUB
      4'b0100, // AND
      4'b0101, // OR
      4'b0110, // JALR
      4'b0111, // XOR
      4'b1000, // SLL
      4'b1001, // SRL
      4'b1010, // SRA
      4'b1100, // SLTU
      4'b1111  // SLT
    };

    $display("[Sequence] Starting Corner Value ALU Sequence...");

    // Test cross combinations of corner values across all opcodes
    foreach (opcodes[op_idx]) begin
      foreach (corner_vals[a_idx]) begin
        foreach (corner_vals[b_idx]) begin
          drive_item(corner_vals[a_idx], corner_vals[b_idx], opcodes[op_idx]);
        end
      end
    end

    // Specific shift-amount corner testing
    foreach (opcodes[op_idx]) begin
      if (opcodes[op_idx] inside {4'b1000, 4'b1001, 4'b1010}) begin
        // Shift by 0
        drive_item(32'hFFFF_FFFF, 32'd0, opcodes[op_idx]);
        drive_item(32'h5555_5555, 32'd0, opcodes[op_idx]);
        // Shift by 31
        drive_item(32'hFFFF_FFFF, 32'd31, opcodes[op_idx]);
        drive_item(32'h5555_5555, 32'd31, opcodes[op_idx]);
      end
    end

    $display("[Sequence] Corner Value ALU Sequence Done.");
  endtask

  task drive_item(logic [31:0] a, logic [31:0] b, logic [3:0] op);
    alu_transaction txn = new();
    txn.A = a;
    txn.B = b;
    txn.ALUControl = op;
    drv_mbx.put(txn);
    #2ns;
  endtask
endclass: alu_seq_corner
