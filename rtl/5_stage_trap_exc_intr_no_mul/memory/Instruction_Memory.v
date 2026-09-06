`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.01.2026 14:19:07
// Design Name: 
// Module Name: Instruction_Memory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////




module Instruction_Memory(rst,A,RD);

  input rst;
  input [29:0]A;//[31:0]A;
  output [31:0]RD;

  reg [31:0] mem [1023:0];
  
  assign RD = (!rst) ? {32{1'b0}} : mem[A];//[31:2]];

`ifndef SYNTHESIS
  // Simulation-only program loading hook.
  // Usage (xsim): add plusarg `+IMEM_HEX=path/to/program.mem`
  integer i;
  reg [8*260:1] imem_hex_file;
  reg imem_loaded;
  initial begin
    // Deterministic default contents
    for (i = 0; i < 1024; i = i + 1)
      mem[i] = 32'h00000013; // NOP (addi x0,x0,0)

    imem_loaded = 1'b0;
    if ($value$plusargs("IMEM_HEX=%s", imem_hex_file)) begin
      $display("[IMEM] Loading program from %0s", imem_hex_file);
      $readmemh(imem_hex_file, mem);
      imem_loaded = 1'b1;
    end else begin
      $display("[IMEM] No +IMEM_HEX specified; using NOP-filled memory");
    end
    if (!imem_loaded) begin
  end
  end
`endif

endmodule
