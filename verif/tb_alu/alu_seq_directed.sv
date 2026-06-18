// alu_seq_directed.sv
class alu_seq_directed;
  mailbox #(alu_transaction) drv_mbx;

  function new(mailbox #(alu_transaction) drv_mbx);
    this.drv_mbx = drv_mbx;
  endfunction

  task body();
    $display("[Sequence] Starting Directed ALU Sequence...");
    
    // Test ADD
    drive_item(32'd10, 32'd20, 4'b0000);
    // Test SUB
    drive_item(32'd50, 32'd30, 4'b0001);
    // Test AND
    drive_item(32'h00FF_00FF, 32'h0F0F_0F0F, 4'b0100);
    // Test OR
    drive_item(32'h00FF_00FF, 32'h0F0F_0F0F, 4'b0101);
    // Test JALR (should mask LSB to 0)
    drive_item(32'h1000_0001, 32'h0000_0003, 4'b0110);
    // Test XOR
    drive_item(32'h5555_5555, 32'hAAAA_AAAA, 4'b0111);
    // Test SLL
    drive_item(32'h0000_0001, 32'd5, 4'b1000);
    // Test SRL
    drive_item(32'h8000_0000, 32'd4, 4'b1001);
    // Test SRA
    drive_item(32'h8000_0000, 32'd4, 4'b1010);
    // Test SLTU
    drive_item(32'd5, 32'd10, 4'b1100);
    // Test SLT
    drive_item(32'hFFFF_FFFF, 32'd5, 4'b1111); // -1 < 5 (True)

    $display("[Sequence] Directed ALU Sequence Done.");
  endtask

  task drive_item(logic [31:0] a, logic [31:0] b, logic [3:0] op);
    alu_transaction txn = new();
    txn.A = a;
    txn.B = b;
    txn.ALUControl = op;
    drv_mbx.put(txn);
    #2ns;
  endtask
endclass: alu_seq_directed
