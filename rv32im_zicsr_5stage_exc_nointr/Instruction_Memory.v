`timescale 1ns / 1ps

module Instruction_Memory(rst,A,RD);

  input rst;
  input [29:0]A;
  output [31:0]RD;

  wire [29:0] local_addr_full = A - 30'h20000000;
`ifdef SYNTHESIS
  wire [11:0] local_addr = local_addr_full[11:0];
  reg [31:0] mem [4095:0];
`else
  wire [19:0] local_addr = local_addr_full[19:0];
  reg [31:0] mem [1048575:0];
`endif
  
  assign RD = (!rst) ? {32{1'b0}} : mem[local_addr];

`ifndef SYNTHESIS
  initial begin : init_block
    integer i;
    for (i = 0; i <1048576; i = i + 1) begin
      mem[i] = 32'h0;
    end
    $readmemh("imem.hex", mem);
  end
`endif

endmodule
