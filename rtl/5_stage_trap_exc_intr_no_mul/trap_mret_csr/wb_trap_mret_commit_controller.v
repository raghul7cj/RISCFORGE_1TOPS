`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : wb_trap_mret_commit_controller
//
// Description:
//  Retirement-boundary (WB) commit controller for traps and MRET.
//
//  Responsibilities:
//    - Decide when a precise exception trap is committed at WB
//    - Decide when an MRET is committed at WB
//    - Drive IF-stage redirect (wb_trap_redirect + trap_target)
//    - Request pipeline flush (flush_pipeline_onehot) to empty younger stages
//    - Drive CSR regfile trap inputs for trap entry CSR updates
//    - Provide commit-qualified mret pulse for CSR regfile mstatus restore
//
// Notes:
//  - This module is purely combinational.
//  - Interrupts are not handled here yet; trap_is_interrupt is hardwired to 0.
//
//////////////////////////////////////////////////////////////////////////////////

module wb_trap_mret_commit_controller (
    input  wire        valid_W,
    input  wire        exc_valid_W,
    input  wire [4:0]  exc_cause_W,
    input  wire [31:0] exc_tval_W,
    input  wire [31:0] exc_pc_W,

    input  wire        is_mret_W,

    // CLIC Interrupt inputs - currently primitive, but will be integrated in the future
    input  wire        irq_valid_i,
    input  wire [30:0] irq_id_i,

    input  wire [31:0] mtvec_i,
    input  wire [31:0] mepc_i,
    input  wire [31:0] mstatus_i,

    output wire        wb_trap_redirect_o,
    output wire [31:0] trap_target_o,
    output wire [3:0]  flush_pipeline_onehot_o,

    // CSR regfile trap-entry interface (PORT A)
    output wire        trap_valid_o,
    output wire [30:0] trap_cause_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_addr_o,
    output wire        trap_addr_valid_o,
    output wire        trap_is_interrupt_o,

    // CSR regfile PORT C: MRET write interface
    output wire        csr_write_en_mret_o,
    output wire [11:0] csr_waddr_mret_o,
    output wire [31:0] csr_wdata_mret_o,

    // Commit-qualified MRET pulse
    output wire        mret_commit_o
);

    // CSR Address constant for MSTATUS
    localparam [11:0] MSTATUS_ADDR = 12'h300;

    wire trap_commit;
    wire mret_commit;
    wire irq_commit;

    assign trap_commit = valid_W & exc_valid_W;
    assign mret_commit = valid_W & is_mret_W & ~exc_valid_W;
    
    // Interrupt is committed at the retirement boundary of a non-faulting instruction
    assign irq_commit  = valid_W & irq_valid_i & ~exc_valid_W & ~is_mret_W;

    assign wb_trap_redirect_o = trap_commit | mret_commit | irq_commit;
    
    // Redirect to mtvec for both exceptions and interrupts
    assign trap_target_o      = (trap_commit | irq_commit) ? {mtvec_i[31:2], 2'b00} : {mepc_i[31:2], 2'b00};

    // Empty the pipeline when trap/mret/irq commits
    assign flush_pipeline_onehot_o = wb_trap_redirect_o ? 4'b1111 : 4'b0000;

    // Drive CSR trap-entry write bundle
    assign trap_valid_o        = trap_commit | irq_commit;
    assign trap_is_interrupt_o = irq_commit;
    assign trap_cause_o        = trap_commit ? {26'b0, exc_cause_W} : irq_id_i;
    assign trap_pc_o           = exc_pc_W;
    assign trap_addr_o         = exc_tval_W;
    assign trap_addr_valid_o   = trap_commit; // mtval only valid for exceptions

    // ====================================
    // PORT C: MRET CSR Write Interface
    // ====================================
    // On MRET commit: update mstatus fields
    // - mstatus[3] (MIE)        ← mstatus[7] (MPIE)
    // - mstatus[7] (MPIE)       ← 1
    // - mstatus[12:11] (MPP)    ← 2'b11 (Machine mode for M-mode only core)
    // Preserve reserved bits [10:8] and other non-MSTATUS fields.
    wire [31:0] new_mstatus;
    assign new_mstatus = {
        mstatus_i[31:13],
        2'b11,              // MPP = Machine mode
        mstatus_i[10],      // preserve reserved bit 10
        mstatus_i[9:8],     // preserve reserved bits 9:8
        1'b1,               // MPIE = 1
        mstatus_i[6:4],     // preserve reserved bits 6:4
        mstatus_i[7],       // MIE <- previous MPIE
        mstatus_i[2:0]      // preserve other low bits
    };

    assign csr_write_en_mret_o = mret_commit;
    assign csr_waddr_mret_o    = MSTATUS_ADDR;
    assign csr_wdata_mret_o    = new_mstatus;

    assign mret_commit_o = mret_commit;

endmodule
