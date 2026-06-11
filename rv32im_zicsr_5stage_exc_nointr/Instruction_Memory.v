`timescale 1ns / 1ps

module Instruction_Memory(rst,A,RD);

  input rst;
  input [29:0]A;
  output [31:0]RD;

  reg [31:0] mem [1048575:0];
  
  assign RD = (!rst) ? {32{1'b0}} : mem[A - 30'h20000000];

  initial begin : init_block
    integer i;
    for (i = 0; i <1048576; i = i + 1) begin
      mem[i] = 32'h0;
    end
    $readmemh("imem.hex", mem);
  end

endmodule
