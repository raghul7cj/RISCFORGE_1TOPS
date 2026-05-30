`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : fetch_cycle
//
// Description:
//  Implements the Instruction Fetch (IF) stage and the IF → ID pipeline register.
//
//  Responsibilities:
//      - Maintain Program Counter (PC)
//      - Select next PC (sequential or branch/jump target)
//      - Fetch instruction from instruction memory
//      - Provide PC and PC+4 to Decode stage
//      - Handle stalls and flushes
//
//  Control Signals:
//      PCSrcE  : Select branch/jump target
//      StallF  : Freeze PC update
//      StallD  : Freeze IF/ID register update
//      FlushD  : Clear IF/ID register (on taken branch)
//
//  Reset:
//      Active-low reset clears IF/ID pipeline registers.
//
//////////////////////////////////////////////////////////////////////////////////

module fetch_cycle(

    input clk,                  // System clock
    input rst,                  // Active-low reset

    input PCSrcE,               // 0 → sequential, 1 → branch/jump target
    input StallF,               // Stall Fetch stage (freeze PC)
    input StallD,               // Stall Decode stage (freeze IF/ID reg)
    input FlushD,               // Flush Decode stage (branch taken)

    input [31:0] PCTargetE,     // Branch/jump target address

    output [31:0] InstrD,       // Instruction to Decode stage
    output [31:0] PCD,          // PC forwarded to Decode stage
    output [31:0] PCPlus4D      // PC+4 forwarded to Decode stage
);

    // ==================================================
    // Internal Fetch Signals
    // ==================================================

    wire [31:0] PCF;            // Current PC
    wire [31:0] PCPlus4F;       // PC + 4
    wire [31:0] PC_F;           // Selected next PC
    wire [31:0] InstrF;         // Instruction fetched from memory

    // ==================================================
    // IF → ID Pipeline Registers
    // ==================================================

    reg [31:0] InstrF_reg;
    reg [31:0] PCF_reg;
    reg [31:0] PCPlus4F_reg;

    // ==================================================
    // PC Selection Mux
    // ==================================================
    // Selects next PC:
    //   - PCPlus4F (normal execution)
    //   - PCTargetE (branch/jump taken)

    Mux2 PC_Mux(
        .a(PCPlus4F),
        .b(PCTargetE),
        .s(PCSrcE),
        .c(PC_F)
    );

    // ==================================================
    // Program Counter Register
    // ==================================================
    // Updates PC when not stalled.

    PC program_counter(
        .clk(clk),
        .rst(rst),
        .PC(PCF),
        .PC_Next(PC_F),
        .StallF(StallF)
    );

    // ==================================================
    // Instruction Memory
    // ==================================================

    Instruction_Memory IMEM(
        .rst(rst),
        .A(PCF[31:2]),
        .RD(InstrF)
    );

    // ==================================================
    // PC + 4 Adder
    // ==================================================

    PC_Adder PC_adder (
        .a(PCF),
        .b(32'h00000004),
        .c(PCPlus4F)
    );

    // ==================================================
    // IF → ID Pipeline Register Logic
    // ==================================================
    // Behavior:
    //   - Reset or FlushD → insert bubble (clear IF/ID)
    //   - StallD → hold previous values
    //   - Otherwise → advance normally

    always @(posedge clk or negedge rst) begin
        if (!rst /*|| FlushD*/) begin
            InstrF_reg    <= 32'h00000000;
            PCF_reg       <= 32'h00000000;
            PCPlus4F_reg  <= 32'h00000000;
        end
        else if(FlushD) begin
            InstrF_reg    <= 32'h00000000;
            PCF_reg       <= 32'h00000000;
            PCPlus4F_reg  <= 32'h00000000;
        end
        else if (StallD == 1'b0) begin
            InstrF_reg    <= InstrF;
            PCF_reg       <= PCF;
            PCPlus4F_reg  <= PCPlus4F;
        end
        else begin
            InstrF_reg    <= InstrF_reg;
            PCF_reg       <= PCF_reg;
            PCPlus4F_reg  <= PCPlus4F_reg;
        end
    end

    // ==================================================
    // Outputs to Decode Stage
    // ==================================================

    assign InstrD   = InstrF_reg;
    assign PCD      = PCF_reg;
    assign PCPlus4D = PCPlus4F_reg;

endmodule
