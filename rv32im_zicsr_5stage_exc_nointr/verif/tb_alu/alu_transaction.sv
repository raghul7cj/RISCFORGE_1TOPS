// alu_transaction.sv
class alu_transaction;
  rand logic [31:0] A;
  rand logic [31:0] B;
  rand logic [3:0]  ALUControl;

  // Outputs captured from DUT or predicted
  logic [31:0] Result;
  logic        Zero;
  logic [2:0]  flags;

  // Constraint to favor valid ALU opcodes
  constraint valid_opcodes {
    ALUControl inside {
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
  }

  // Helper function to clone transaction
  function alu_transaction clone();
    alu_transaction c = new();
    c.A          = this.A;
    c.B          = this.B;
    c.ALUControl = this.ALUControl;
    c.Result     = this.Result;
    c.Zero       = this.Zero;
    c.flags      = this.flags;
    return c;
  endfunction

  function void display(string prefix = "");
    $display("[%s] ALUControl: 4'b%4b | A: 32'h%08h | B: 32'h%08h | Result: 32'h%08h | Zero: %b | flags: 3'b%3b",
             prefix, ALUControl, A, B, Result, Zero, flags);
  endfunction
endclass: alu_transaction
