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
    FlushD,
    FlushE,
    FlushM,
    FlushW,
    illegal_instr,
    csr_valid_D,
    csr_raddr_D,
    csr_raddr_E,
    csr_raddr_W,
    csr_addr_E,
    csr_addr_M,
    csr_addr_W,
    csr_write_en_W,
    csr_write_en_M,
    csr_write_en_E,

    flush_pipeline_onehot,

    // Precise exception / retire control
    valid_E,
    exc_valid_E,
    valid_M,
    exc_valid_M,
    wb_redirect,

    // M-extension stall
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
    input csr_valid_D;
    input [11:0] csr_raddr_D;
    input [11:0] csr_raddr_E;
    input [11:0] csr_raddr_W;
    input [11:0] csr_addr_E;
    input [11:0] csr_addr_M;
    input [11:0] csr_addr_W;
    input csr_write_en_W;
    input csr_write_en_M;
    input csr_write_en_E;
    input [3:0] flush_pipeline_onehot;
    input valid_E;
    input exc_valid_E;
    input valid_M;
    input exc_valid_M;
    input wb_redirect;
    input stallM;

    // ==================================================
    // Outputs
    // ==================================================

    output [1:0] ForwardAE, ForwardBE;
    output StallF, StallD;
    output FlushE, FlushD, FlushM, FlushW;

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

    // CSR-to-CSR stall: next CSR instruction reads a CSR being written in EX/MEM/WB
    wire csr_stall;
    assign csr_stall = csr_valid_D &&
                          ((csr_raddr_D == csr_addr_E && csr_write_en_E) ||
                            (csr_raddr_D == csr_addr_M && csr_write_en_M) ||
                            (csr_raddr_D == csr_addr_W && csr_write_en_W));

    // CSR-use GPR stall: a CSR instruction in EX or MEM writes a GPR (old_csr result)
    // that cannot be forwarded via ALU_ResultM. Stall until it retires to WB.
    wire csr_gpr_stall;
    assign csr_gpr_stall =
        // CSR in EX writing GPR that Decode-stage reads
        (ResultSrcE == 2'b11) &&
        ((Rs1_D == RdE) || (Rs2_D == RdE)) &&
        (RdE != 5'd0);

    // On WB redirect (trap/mret), override stalls so IF can take redirect immediately.
    assign StallF = wb_redirect ? 1'b0 : (lwstall | csr_stall | csr_gpr_stall | stallM);
    assign StallD = wb_redirect ? 1'b0 : (lwstall | csr_stall | csr_gpr_stall | stallM);

    // ==================================================
    // Control Hazard Handling
    // ==================================================
    // On branch/jump taken (PCSrcE):
    //      - Flush Decode stage
    //      - Flush Execute stage

    // Continuous flush "wake" behind an exception-tagged instruction.
    wire exc_inflight_E;
    wire exc_inflight_M;
    assign exc_inflight_E = valid_E & exc_valid_E;
    assign exc_inflight_M = valid_M & exc_valid_M;

    // Control hazard / younger-kill policy.
    // NOTE: illegal_instr is handled as an exception sideband, not as an immediate flush here.
    assign FlushE = lwstall | csr_gpr_stall | PCSrcE | csr_stall | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1] | stallM;
    assign FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | wb_redirect | flush_pipeline_onehot[0];
    assign FlushM = wb_redirect | flush_pipeline_onehot[2] | stallM;
    assign FlushW = wb_redirect | flush_pipeline_onehot[3];

endmodule
