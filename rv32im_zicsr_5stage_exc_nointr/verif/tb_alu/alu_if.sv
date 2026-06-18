// alu_if.sv
interface alu_if;
  logic [31:0] A;
  logic [31:0] B;
  logic [3:0]  ALUControl;
  logic [31:0] Result;
  logic        Zero;
  logic [2:0]  flags;
endinterface: alu_if
