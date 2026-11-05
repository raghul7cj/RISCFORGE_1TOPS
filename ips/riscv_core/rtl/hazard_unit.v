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
//  Stall signals (freeze registers):
//      StallF  : freeze PC register (IF stage)
//      StallD  : freeze IF/ID register
//      StallE  : freeze ID/EX register (during M-ext or mem stall)
//      StallM  : freeze EX/MEM register (during mem stall only)
//
//  Flush signals (insert NOP bubbles):
//      FlushD  : flush IF/ID  (branch taken, exception in-flight)
//      FlushE  : flush ID/EX  (load-use, CSR hazard, branch taken)
//      FlushM  : flush EX/MEM (M-ext done, wb redirect)
//      FlushW  : flush MEM/WB (mem stall, wb redirect)
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
    StallE,
    StallM,
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

    // M-extension stall (multiplier/divider busy)
    stallMUL,

    // LSU / memory-bridge stall (AXI multi-cycle, SRAM wait-states)
    mem_stall_i
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
    input stallMUL;     // M-extension (multiply/divide) multi-cycle stall
    input mem_stall_i;  // LSU stall: freeze EX/MEM and downstream

    // ==================================================
    // Outputs
    // ==================================================

    output [1:0] ForwardAE, ForwardBE;
    output StallF, StallD, StallE, StallM;
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
    assign StallF = wb_redirect ? 1'b0 : (lwstall | csr_stall | csr_gpr_stall | stallMUL | mem_stall_i);
    assign StallD = wb_redirect ? 1'b0 : (lwstall | csr_stall | csr_gpr_stall | stallMUL | mem_stall_i);
    // StallE: hold ID/EX while M-ext or LSU is busy (keeps the stalled instruction in EX)
    assign StallE = wb_redirect ? 1'b0 : ( mem_stall_i);
    // StallM: hold EX/MEM while LSU is waiting for memory (keeps valid_M=1 active)
    assign StallM = wb_redirect ? 1'b0 : mem_stall_i;

    // ==================================================
    // Control Hazard Handling
    // ==================================================

    // Continuous flush "wake" behind an exception-tagged instruction.
    wire exc_inflight_E;
    wire exc_inflight_M;
    assign exc_inflight_E = valid_E & exc_valid_E;
    assign exc_inflight_M = valid_M & exc_valid_M;

    // FlushE: kill ID/EX when we have a data hazard bubble, branch taken, or
    //         CSR hazard, or M-extension stall (multiplier busy).
    assign FlushE = (lwstall & ~mem_stall_i) | (csr_gpr_stall & ~mem_stall_i) | PCSrcE | (csr_stall & ~mem_stall_i) | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1] | stallMUL;
    // FlushD: kill IF/ID when branch taken, exception in-flight, or wb redirect.
    //         exc_inflight_E included so that the wrongly-fetched instruction after
    //         a misaligned-branch exception (where PCSrcE was suppressed) is removed.
    assign FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | wb_redirect | flush_pipeline_onehot[0];
    // FlushM: insert NOP into EX/MEM when M-ext stall completes or wb redirect.
    //         mem_stall_i excluded — EX/MEM is HELD via StallM, not flushed.
    assign FlushM = wb_redirect | flush_pipeline_onehot[2] | (stallMUL & ~mem_stall_i);
    // FlushW: insert NOP into MEM/WB on wb redirect or pipeline flush.
    //         mem_stall_i excluded — memory_cycle self-holds via lsu_core_stall instead.
    assign FlushW = wb_redirect | flush_pipeline_onehot[3];

endmodule
