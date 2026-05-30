`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : hazard_unit
//
// Description:
//  Handles pipeline hazards in a 5-stage RISC-V processor.
//
//  Responsibilities:
//      1. Data forwarding (EX stage)
//      2. Load-use hazard detection (stall generation)
//      3. Control hazard handling (flush on branch/jump)
//
//  Inputs:
//      RegWriteM  : MEM stage register write enable
//      RegWriteW  : WB stage register write enable
//      RD_M       : Destination register in MEM stage
//      RD_W       : Destination register in WB stage
//
//      Rs1_E      : Source register 1 in EX stage
//      Rs2_E      : Source register 2 in EX stage
//
//      Rs1_D      : Source register 1 in Decode stage
//      Rs2_D      : Source register 2 in Decode stage
//      RdE        : Destination register in EX stage
//
//      ResultSrcE : Determines if EX instruction is load
//                   (2'b01 → load instruction)
//
//      PCSrcE     : Branch/jump taken signal
//
//  Outputs:
//      ForwardAE  : Forward select for ALU source A
//      ForwardBE  : Forward select for ALU source B
//
//      StallF     : Stall Fetch stage
//      StallD     : Stall Decode stage
//
//      FlushE     : Flush Execute stage
//      FlushD     : Flush Decode stage
//
//////////////////////////////////////////////////////////////////////////////////

module hazard_unit(
    rst,
    RegWriteM,
    RegWriteW,
    RD_M,
    RD_W,
    Rs1_E,
    Rs2_E,
    Rs1_D,
    Rs2_D,
    RdE,
    ForwardAE,
    ForwardBE,
    ResultSrcE,
    PCSrcE,
    StallF,
    StallD,
    FlushE,
    FlushD,
    illegal_instr,
    
    stallM
);

    // ==================================================
    // Inputs
    // ==================================================

    input rst;
    input RegWriteM, RegWriteW;
    input PCSrcE;

    input [1:0] ResultSrcE;

    input [4:0] RD_M, RD_W;
    input [4:0] Rs1_E, Rs2_E;
    input [4:0] Rs1_D, Rs2_D;
    input [4:0] RdE;
    input illegal_instr;
    
    input stallM;

    // ==================================================
    // Outputs
    // ==================================================

    output [1:0] ForwardAE, ForwardBE;
    output StallF, StallD;
    output FlushE, FlushD;

    // ==================================================
    // Forwarding Logic
    // ==================================================
    // Priority:
    //      1. Forward from MEM stage
    //      2. Forward from WB stage
    //      3. No forwarding

    assign ForwardAE =
        (rst == 1'b0) ? 2'b00 :
        (RegWriteM && (Rs1_E != 5'd0) && (RD_M == Rs1_E)) ? 2'b10 :
        (RegWriteW && (Rs1_E != 5'd0) && (RD_W == Rs1_E)) ? 2'b01 :
        2'b00;

    assign ForwardBE =
        (rst == 1'b0) ? 2'b00 :
        (RegWriteM && (Rs2_E != 5'd0) && (RD_M == Rs2_E)) ? 2'b10 :
        (RegWriteW && (Rs2_E != 5'd0) && (RD_W == Rs2_E)) ? 2'b01 :
        2'b00;

    // ==================================================
    // Load-Use Hazard Detection
    // ==================================================
    // If EX stage instruction is a load (ResultSrcE == 01)
    // AND Decode stage uses the same register,
    // then stall Fetch and Decode, and flush Execute.

    wire lwstall;

    assign lwstall =
        (ResultSrcE == 2'b01) &&
        ((Rs1_D == RdE) || (Rs2_D == RdE)) &&
        (RdE != 5'd0);

    assign StallF = lwstall | stallM;
    assign StallD = lwstall | stallM;

    // ==================================================
    // Control Hazard Handling
    // ==================================================
    // On branch/jump taken (PCSrcE):
    //      - Flush Decode stage
    //      - Flush Execute stage

    assign FlushE = lwstall | PCSrcE | illegal_instr | stallM;
    assign FlushD = PCSrcE;

endmodule
