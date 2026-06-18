// alu_coverage.sv
class alu_coverage;
  mailbox #(alu_transaction) mon_mbx;
  alu_transaction txn;

  covergroup alu_cg;
    option.per_instance = 1;
    option.name = "alu_coverage_group";

    // Opcodes coverage
    cp_op: coverpoint txn.ALUControl {
      bins add = {4'b0000};
      bins sub = {4'b0001};
      bins and_op = {4'b0100};
      bins or_op = {4'b0101};
      bins jalr = {4'b0110};
      bins xor_op = {4'b0111};
      bins sll = {4'b1000};
      bins srl = {4'b1001};
      bins sra = {4'b1010};
      bins sltu = {4'b1100};
      bins slt = {4'b1111};
    }

    // Input A operands coverage
    cp_a: coverpoint txn.A {
      bins zero = {32'd0};
      bins one  = {32'd1};
      bins minus_one = {32'hFFFF_FFFF};
      bins max_positive = {32'h7FFF_FFFF};
      bins min_negative = {32'h8000_0000};
      bins misc = default;
    }

    // Input B operands coverage
    cp_b: coverpoint txn.B {
      bins zero = {32'd0};
      bins one  = {32'd1};
      bins minus_one = {32'hFFFF_FFFF};
      bins max_positive = {32'h7FFF_FFFF};
      bins min_negative = {32'h8000_0000};
      bins misc = default;
    }

    // Shift amount (low 5 bits of B) for shift instructions
    cp_shamt: coverpoint txn.B[4:0] iff (txn.ALUControl inside {4'b1000, 4'b1001, 4'b1010}) {
      bins shamt_zero = {5'd0};
      bins shamt_max  = {5'd31};
      bins shamt_mid  = {[5'd1:5'd30]};
    }

    // Cross coverages
    cross_op_a: cross cp_op, cp_a;
    cross_op_b: cross cp_op, cp_b;
  endgroup

  function new(mailbox #(alu_transaction) mon_mbx);
    this.mon_mbx = mon_mbx;
    alu_cg = new();
  endfunction

  task run();
    forever begin
      mon_mbx.get(txn);
      alu_cg.sample();
    end
  endtask
endclass: alu_coverage
