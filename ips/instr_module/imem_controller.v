`timescale 1ns / 1ps
// Module : imem_controller
// Fetch controller for instruction memory.

module imem_controller (
    input             clk,
    input             rst_n,
    input      [31:0] PC,
    input      [31:0] PC_next,
    input             instruction_is_branch,
    input             stall_in,
    output            sram_en,
    output            sram_we,
    output     [3:0]  sram_wmask,
    output     [29:0] sram_addr,
    output     [31:0] sram_wdata,
    input      [31:0] sram_rdata,
    output     [31:0] instruction,
    output            stall
);

    localparam NOP = 32'h0000_0013;

    assign sram_en    = rst_n;
    assign sram_we    = 1'b0;
    assign sram_wmask = 4'b0000;
    assign sram_wdata = 32'd0;

    assign sram_addr = (stall_in && !instruction_is_branch) ? PC[31:2] : PC_next[31:2];

    reg spec_tag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            spec_tag <= 1'b0;
        else
            spec_tag <= instruction_is_branch;
    end

    assign stall = spec_tag;

    assign instruction = (!rst_n || spec_tag) ? NOP : sram_rdata;

endmodule