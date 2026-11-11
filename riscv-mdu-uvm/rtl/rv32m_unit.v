`timescale 1ns / 1ps
module rv32m_unit (
    input         clk,
    input         rst_n,
 
    // From EX stage decoder
    input  [31:0] rs1,
    input  [31:0] rs2,
    input  [2:0]  funct3,       // 3-bit M-ext op code
    input  [4:0]  rd_in,
    input         valid_in,     // 1 = this is an M-ext instruction
 
    // To hazard/stall unit
    output        stall,        // 1 = freeze upstream pipeline stages
 
    // To WB stage
    output [31:0] result,
    output [4:0]  rd_out,
    output        valid_out
);
    wire is_mul_op = ~funct3[2];   // funct3[2]=0 → MUL family
    wire is_div_op =  funct3[2];   // funct3[2]=1 → DIV family
 
    // Multiplier outputs
    wire [31:0] mul_result;
    wire [4:0]  mul_rd;
    wire        mul_valid;
 
    // Divider outputs
    wire [31:0] div_result;
    wire [4:0]  div_rd;
    wire        div_valid;
    wire        div_stall;
 
    rv32m_mul u_mul (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1       (rs1),
        .rs2       (rs2),
        .funct3    (funct3),
        .rd_in     (rd_in),
        .valid_in  (valid_in & is_mul_op),
        .result    (mul_result),
        .rd_out    (mul_rd),
        .valid_out (mul_valid)
    );
 
    rv32m_div u_div (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1       (rs1),
        .rs2       (rs2),
        .funct3    (funct3),
        .rd_in     (rd_in),
        .valid_in  (valid_in & is_div_op),
        .stall     (div_stall),
        .result    (div_result),
        .rd_out    (div_rd),
        .valid_out (div_valid)
    );
 
    // MUL generates a 3-cycle stall (no result in flight after cycle 0)
    // Simple approach: stall for 2 extra cycles after MUL issue
    reg [1:0] mul_stall_cnt;
    reg       mul_stall;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_stall_cnt <= 0;
            mul_stall     <= 0;
        end else if (valid_in & is_mul_op) begin
            mul_stall_cnt <= 2'd2;
            mul_stall     <= 1;
        end else if (mul_stall_cnt > 0) begin
            mul_stall_cnt <= mul_stall_cnt - 1;
            mul_stall     <= (mul_stall_cnt > 1);
        end
    end
 
    assign stall     = mul_stall | div_stall | valid_in ;
    assign valid_out = mul_valid | div_valid;
    assign rd_out    = mul_valid ? mul_rd : div_rd;
    assign result    = mul_valid ? mul_result : div_result;
 
endmodule
