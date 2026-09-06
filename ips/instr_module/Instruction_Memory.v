`timescale 1ns / 1ps
// Module : Instruction_Memory_new
// Synchronous instruction memory.

module Instruction_Memory_new #(
    parameter integer MEM_DEPTH      = 524288,
    parameter [31:0]  IMEM_BASE_BYTE = 32'h8000_0000
) (
    input             clk,
    input             rst_n,
    input             sram_en,
    input             sram_we,
    input      [3:0]  sram_wmask,
    input      [29:0] sram_addr,
    input      [31:0] sram_wdata,
    output     [31:0] sram_rdata
);

    localparam [29:0] IMEM_BASE_WORD = IMEM_BASE_BYTE[31:2];
    localparam ADDR_W = $clog2(MEM_DEPTH);

    reg [31:0] mem_array [0:MEM_DEPTH-1];

    wire [29:0] local_addr_full = sram_addr - IMEM_BASE_WORD;
    wire [ADDR_W-1:0] local_addr = local_addr_full[ADDR_W-1:0];

    reg [ADDR_W-1:0] raddr_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            raddr_q <= 'b0;
        end else if (sram_en) begin
            raddr_q <= local_addr;
        end
    end

    always @(posedge clk) begin
        if (rst_n && sram_en && sram_we) begin
            if (sram_wmask[0]) mem_array[local_addr][ 7: 0] <= sram_wdata[ 7: 0];
            if (sram_wmask[1]) mem_array[local_addr][15: 8] <= sram_wdata[15: 8];
            if (sram_wmask[2]) mem_array[local_addr][23:16] <= sram_wdata[23:16];
            if (sram_wmask[3]) mem_array[local_addr][31:24] <= sram_wdata[31:24];
        end
    end

    assign sram_rdata = (!rst_n) ? 32'd0 : mem_array[raddr_q];

`ifndef SYNTHESIS
    initial begin : init_mem
        integer i;
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem_array[i] = 32'h0000_0013;
        $readmemh("imem.hex", mem_array);
    end
`endif

endmodule