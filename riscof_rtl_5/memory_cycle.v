`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : memory_cycle
//
// Description:
//  Implements the Memory (MEM) stage and the MEM → WB pipeline register.
//
//  Responsibilities:
//      - Interface with data memory
//      - Perform load data formatting (via ls_unit)
//      - Perform store data alignment and strobe generation
//      - Register MEM outputs into WB stage
//
//  Pipeline Flow:
//      EX stage → memory_cycle → WB stage
//
//  Control Flow:
//      - RegWriteM propagated to WB
//      - ResultSrc determines WB mux selection
//
//////////////////////////////////////////////////////////////////////////////////

module memory_cycle(
    clk, rst,
    RegWriteM, MemWriteM,
    ResultSrcM,
    RD_M, lsunitM,
    PCPlus4M,
    WriteDataM,
    ALU_ResultM,
    RegWriteW,
    ResultSrcW,
    RD_W,
    PCPlus4W,
    ALU_ResultW,
    ReadDataW
);

    // ==================================================
    // Inputs from Execute stage
    // ==================================================

    input clk;
    input rst;

    input RegWriteM;          // Register write enable
    input MemWriteM;          // Memory write enable

    input [1:0] ResultSrcM;   // Writeback source select
    input [4:0] RD_M;         // Destination register
    input [4:0] lsunitM;      // Load/store control bus

    input [31:0] PCPlus4M;    // PC + 4
    input [31:0] WriteDataM;  // Store data (aligned in EX)
    input [31:0] ALU_ResultM; // Effective address / ALU result

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    output RegWriteW;
    output [1:0] ResultSrcW;
    output [4:0] RD_W;
    output [31:0] PCPlus4W;
    output [31:0] ALU_ResultW;
    output [31:0] ReadDataW;

    // ==================================================
    // Internal wires
    // ==================================================

    wire [31:0] ReadDataM;   // Raw memory read data

    // ==================================================
    // Load/Store Unit
    // Handles:
    //   - Load data formatting
    //   - Store data alignment
    //   - Byte-enable generation
    // ==================================================

    wire [31:0] lsout;   // Formatted load data
    wire [3:0]  strobe;  // Byte enable signals
    wire [31:0] out_s;   // Aligned store data

    ls_unit lsunit(
        .in(ReadDataM),
        .lsunit(lsunitM),
        .out(lsout),
        .strobe(strobe),
        .address(ALU_ResultM[1:0]),
        .in_s(WriteDataM),
        .out_s(out_s)
    );

    // ==================================================
    // Data Memory
    // ==================================================
    // WE      : Controlled by MemWriteM
    // WD      : Aligned store data for stores
    // WSTRB   : Byte enables from ls_unit

    Data_Memory dmem (
        .clk(clk),
        .rst(rst),
        .WE(MemWriteM),
        .WD((lsunitM[4:3] == 2'b11) ? out_s : WriteDataM),
       // .A(ALU_ResultM),
        .A(ALU_ResultM[31:2]),
        .RD(ReadDataM),
        .WSTRB(strobe)
    );

    // ==================================================
    // Load Result Selection
    // If load → use formatted lsout
    // Otherwise pass raw memory data
    // ==================================================

    wire [31:0] result;

    assign result = (lsunitM[4:3] == 2'b10) ?
                    lsout :
                    ReadDataM;

    // ==================================================
    // MEM → WB Pipeline Registers
    // ==================================================

    reg RegWriteM_r;
    reg [1:0] ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PCPlus4M_r;
    reg [31:0] ALU_ResultM_r;
    reg [31:0] ReadDataM_r;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            RegWriteM_r   <= 1'b0;
            ResultSrcM_r  <= 2'b00;
            RD_M_r        <= 5'd0;
            PCPlus4M_r    <= 32'd0;
            ALU_ResultM_r <= 32'd0;
            ReadDataM_r   <= 32'd0;
        end
        else begin
            RegWriteM_r   <= RegWriteM;
            ResultSrcM_r  <= ResultSrcM;
            RD_M_r        <= RD_M;
            PCPlus4M_r    <= PCPlus4M;
            ALU_ResultM_r <= ALU_ResultM;
            ReadDataM_r   <= result;
        end
    end

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    assign RegWriteW   = RegWriteM_r;
    assign ResultSrcW  = ResultSrcM_r;
    assign RD_W        = RD_M_r;
    assign PCPlus4W    = PCPlus4M_r;
    assign ALU_ResultW = ALU_ResultM_r;
    assign ReadDataW   = ReadDataM_r;

endmodule
