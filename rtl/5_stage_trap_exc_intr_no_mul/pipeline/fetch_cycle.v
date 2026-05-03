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
    input wb_trap_redirect,     // trap/return redirect from WB
    input StallF,               // Stall Fetch stage (freeze PC)
    input StallD,               // Stall Decode stage (freeze IF/ID reg)
    input FlushD,               // Flush Decode stage (branch taken)

    input [31:0] PCTargetE,     // Branch/jump target address
    input [31:0] trap_target,   // trap/return target address

    output [31:0] InstrD,       // Instruction to Decode stage
    output [31:0] PCD,          // PC forwarded to Decode stage
    output [31:0] PCPlus4D,      // PC+4 forwarded to Decode stage

    output valid_D,
    output exc_valid_D,       // Exception valid signal
    output [4:0] exc_cause_D,  // Exception cause code
    output [31:0] exc_pc_D,    // PC at which exception occurred
    output [31:0] exc_tval_D   // Bad address / instruction for exceptions

);

    // ==================================================
    // Internal Fetch Signals
    // ==================================================

    wire [31:0] PCF;            // Current PC
    wire [31:0] PCPlus4F;       // PC + 4
    wire [31:0] PC_F;           // Selected next PC
    wire [31:0] InstrF;         // Instruction fetched from memory
    wire exc_valid_F;
    wire [4:0] exc_cause_F;
    wire [31:0] exc_pc_F;
    wire [31:0] exc_tval_F;

    // ==================================================
    // IF → ID Pipeline Registers
    // ==================================================

    reg [31:0] InstrF_reg;
    reg [31:0] PCF_reg;
    reg [31:0] PCPlus4F_reg;
    reg valid_D_reg;
    reg exc_valid_reg;
    reg [4:0] exc_cause_reg;
    reg [31:0] exc_pc_reg;
    reg [31:0] exc_tval_reg;

    // ==================================================
    // PC Selection Mux
    // ==================================================
    // Selects next PC:
    //   - PCPlus4F (normal execution)
    //   - PCTargetE (branch/jump taken)

    assign PC_F = wb_trap_redirect ? trap_target :
                  PCSrcE ? PCTargetE :
                  PCPlus4F;

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
            valid_D_reg   <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 5'd0;
            exc_pc_reg    <= 32'h00000000;
            exc_tval_reg  <= 32'h00000000;
        end
        else if(FlushD) begin
            InstrF_reg    <= 32'h00000000;
            PCF_reg       <= 32'h00000000;
            PCPlus4F_reg  <= 32'h00000000;
            valid_D_reg   <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 5'd0;
            exc_pc_reg    <= 32'h00000000;
            exc_tval_reg  <= 32'h00000000;
        end
        else if (StallD == 1'b0) begin
            InstrF_reg    <= InstrF;
            PCF_reg       <= PCF;
            PCPlus4F_reg  <= PCPlus4F;
            valid_D_reg   <= 1'b1;
            exc_valid_reg <= exc_valid_F;
            exc_cause_reg <= exc_cause_F;
            exc_pc_reg    <= exc_pc_F;
            exc_tval_reg  <= exc_tval_F;
        end
        else begin
            InstrF_reg    <= InstrF_reg;
            PCF_reg       <= PCF_reg;
            PCPlus4F_reg  <= PCPlus4F_reg;
            valid_D_reg   <= valid_D_reg;
            exc_valid_reg <= exc_valid_reg;
            exc_cause_reg <= exc_cause_reg;
            exc_pc_reg    <= exc_pc_reg;
            exc_tval_reg  <= exc_tval_reg;
        end
    end

    // ==================================================
    // Outputs to Decode Stage
    // ==================================================

    assign InstrD   = InstrF_reg;
    assign PCD      = PCF_reg;
    assign PCPlus4D = PCPlus4F_reg;

    assign valid_D = valid_D_reg;
    assign exc_valid_D = exc_valid_reg;
    assign exc_cause_D = exc_cause_reg;
    assign exc_pc_D = exc_pc_reg;
    assign exc_tval_D = exc_tval_reg;

    assign exc_valid_F = (PCF[1:0] != 2'b00);
    assign exc_cause_F = 5'b00000;
    assign exc_pc_F = PCF;
    assign exc_tval_F = PCF;

endmodule
