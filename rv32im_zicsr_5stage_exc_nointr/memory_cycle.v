`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : memory_cycle
//
// Description:
//  Implements the Memory (MEM) stage and the MEM → WB pipeline register.
//
//  Responsibilities:
//      - Interface with data memory via hybrid_mem_interface bus router
//      - Perform load data formatting (via ls_unit)
//      - Perform store data alignment and strobe generation (via ls_unit)
//      - Register MEM outputs into WB stage
//
//  Sub-module hierarchy:
//      memory_cycle
//          ├── ls_unit            (load/store formatting + mem-request bus)
//          ├── hybrid_mem_interface (address decode → SRAM / AXI4-Lite router)
//          └── Data_Memory        (native synchronous SRAM, 1-cycle read latency)
//
//  Pipeline Flow:
//      EX stage → memory_cycle → WB stage
//
//  Control Flow:
//      - RegWriteM propagated to WB
//      - ResultSrc determines WB mux selection
//
//  Reset convention:
//      - memory_cycle pipeline registers : active-low  (negedge rst)
//      - Data_Memory / hybrid_mem_interface: active-low rst_n
//      All driven from the same `rst` input which is treated as active-low
//      throughout this design (rst = 0 → reset).
//
//////////////////////////////////////////////////////////////////////////////////

module memory_cycle #(
    // ── Memory sizing (optional parameters for compatibility) ──────────────
    parameter integer MEM_DEPTH      = 524288,        // words (2 MB default)
    parameter [31:0]  DMEM_BASE_BYTE = 32'h8000_1000  // DMEM byte base address
) (
    input clk,
    input rst,
    input FlushW,
    input RegWriteM,
    input MemWriteM,
    input [1:0] ResultSrcM,
    input [4:0] RD_M,
    input [4:0] lsunitM,
    input [31:0] PC_M,
    input [31:0] PCPlus4M,
    input valid_M,
    input exc_valid_M,
    input [5:0] exc_cause_M,
    input [31:0] exc_tval_M,
    input [31:0] exc_pc_M,
    input is_mret_M,
    input [31:0] WriteDataM,
    input [31:0] ALU_ResultM,
    input csr_write_en_M,
    input [11:0] csr_addr_M,
    input [31:0] new_csr_M,
    input [31:0] old_csr_M,

    // Stall output to pipeline controller
    output mem_stall_out,

    // ==================================================
    // LSU Memory Bus Interface (to external hybrid_mem_interface / interconnect)
    // ==================================================
    output        lsu_mem_req,
    output        lsu_mem_we,
    output [31:0] lsu_mem_addr,
    output [31:0] lsu_mem_wdata,
    output [3:0]  lsu_mem_be,
    input  [31:0] lsu_mem_rdata,
    input         lsu_mem_stall,
    input         lsu_mem_err,

    // WB outputs
    output RegWriteW,
    output [1:0] ResultSrcW,
    output [4:0] RD_W,
    output [31:0] PC_W,
    output [31:0] PCPlus4W,
    output [31:0] ALU_ResultW,
    output [31:0] ReadDataW,
    output valid_W,
    output exc_valid_W,
    output [5:0] exc_cause_W,
    output [31:0] exc_tval_W,
    output [31:0] exc_pc_W,
    output is_mret_W,
    output csr_write_en_W,
    output [11:0] csr_addr_W,
    output [31:0] new_csr_W,
    output [31:0] old_csr_W
);

    // ==================================================
    // ls_unit internal wires
    // ==================================================
    wire        lsu_raw_req;
    wire        lsu_raw_we;

    // ls_unit formatted load result
    wire [31:0] lsu_core_rdata;
    wire        lsu_core_stall;   // same as mem_stall_out ultimately
    wire        lsu_core_err;     // access fault from bridge

    // ==================================================
    // MEM-Stage Exception Detection (Misalignment)
    // ==================================================

    wire is_load  = (lsunitM[4:3] == 2'b10);
    wire is_store = (lsunitM[4:3] == 2'b11);

    // Basic misalignment check:
    // LW/SW must be 4-byte aligned (addr[1:0] == 00)
    // LH/SH must be 2-byte aligned (addr[0] == 0)
    wire misaligned_load  = is_load  && (
        (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00) || // LW (010)
        (lsunitM[2:0] == 3'b001 && ALU_ResultM[0]   != 1'b0)  || // LH (001)
        (lsunitM[2:0] == 3'b101 && ALU_ResultM[0]   != 1'b0)     // LHU (101)
    );

    wire misaligned_store = is_store && (
        (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00) || // SW (010)
        (lsunitM[2:0] == 3'b001 && ALU_ResultM[0]   != 1'b0)     // SH (001)
    );

    wire exc_valid_mem_local = (misaligned_load | misaligned_store | lsu_core_err) & valid_M;

    wire [5:0] exc_cause_mem_local =
        misaligned_load  ? 6'd4 :
        misaligned_store ? 6'd6 :
        (lsu_core_err & is_load)  ? 6'd5 :
        (lsu_core_err & is_store) ? 6'd7 :
                           6'd0; // 4: Load misalign, 6: Store misalign, 5: Load access fault, 7: Store access fault

    wire [31:0] exc_tval_mem_local = ALU_ResultM; // Faulting address

    // Merge with propagated exception (first wins)
    wire exc_valid_mem_final = exc_valid_M | exc_valid_mem_local;
    wire [5:0] exc_cause_mem_final = exc_valid_M ? exc_cause_M : exc_cause_mem_local;
    wire [31:0] exc_tval_mem_final = exc_valid_M ? exc_tval_M  : exc_tval_mem_local;
    wire [31:0] exc_pc_mem_final   = exc_valid_M ? exc_pc_M    : PC_M;

    // ==================================================
    // 1. ls_unit instantiation
    //    Handles:
    //      - Request generation (mem_req, mem_we)
    //      - Load data formatting per funct3 / byte offset
    //      - Store data alignment + byte-enable generation
    // ==================================================

    ls_unit lsunit (
        // Core pipeline interface
        .core_addr  (ALU_ResultM),   // Full 32-bit effective address
        .core_wdata (WriteDataM),    // Raw RS2 store data (ls_unit aligns internally)
        .lsunit     (lsunitM),       // Control bus [4]=en,[3]=is_store,[2:0]=funct3
        .core_rdata (lsu_core_rdata),// Formatted load result → WB
        .core_stall (lsu_core_stall),// Pipeline freeze (also routed to mem_stall_out)
        .core_err   (lsu_core_err),  // Access fault

        // Memory bridge interface
        .mem_req    (lsu_raw_req),
        .mem_we     (lsu_raw_we),
        .mem_addr   (lsu_mem_addr),
        .mem_wdata  (lsu_mem_wdata),
        .mem_be     (lsu_mem_be),
        .mem_rdata  (lsu_mem_rdata),
        .mem_stall  (lsu_mem_stall),
        .mem_err    (lsu_mem_err)
    );

    // Gate memory request with valid_M and absence of a prior or alignment exception
    // (suppress spurious accesses from flushed/faulted instructions, avoiding circular dependency on local bus error)
    assign lsu_mem_req = lsu_raw_req & valid_M & ~(exc_valid_M | misaligned_load | misaligned_store);
    assign lsu_mem_we  = lsu_raw_we  & valid_M & ~(exc_valid_M | misaligned_load | misaligned_store);

    // Derive a stall that DOESN'T freeze MEM/WB for misaligned exceptions.
    // If misaligned_load/store is detected, gated_mem_req=0 → no new transaction,
    // but previous instruction's stall (lsu_mem_stall) could still be asserted.
    // Gate core_stall so MEM/WB can capture the exception instead of holding.
    wire core_stall_gated = lsu_core_stall & ~(misaligned_load | misaligned_store);

    // Fix: misaligned must NOT stall the pipeline — it must trap immediately.
    // lsu_core_stall is 0 for misaligned (gated request), but hybrid may still
    // hold mem_stall from previous load's 2-cycle SRAM. Gate it so WB can capture
    // the exception instead of stalling IF/ID/EX and flushing the next misaligned
    // instruction before it reaches MEM (which caused NEW to have 1 vs OLD 3 commits).
    assign mem_stall_out = core_stall_gated;

    // ==================================================
    // MEM → WB Pipeline Registers
    // ==================================================

    reg RegWriteM_r;
    reg [1:0] ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PC_M_r;
    reg [31:0] PCPlus4M_r;
    reg [31:0] ALU_ResultM_r;
    reg [31:0] ReadDataM_r;
    reg valid_W_r;
    reg exc_valid_r;
    reg [5:0] exc_cause_r;
    reg [31:0] exc_tval_r;
    reg [31:0] exc_pc_r;
    reg is_mret_r;

    reg        csr_write_en_M_r;
    reg [11:0] csr_addr_M_r;
    reg [31:0] new_csr_M_r;
    reg [31:0] old_csr_M_r;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            RegWriteM_r      <= 1'b0;
            ResultSrcM_r     <= 2'b00;
            RD_M_r           <= 5'd0;
            PC_M_r           <= 32'd0;
            PCPlus4M_r       <= 32'd0;
            ALU_ResultM_r    <= 32'd0;
            ReadDataM_r      <= 32'd0;
            valid_W_r        <= 1'b0;
            exc_valid_r      <= 1'b0;
            exc_cause_r      <= 6'd0;
            exc_tval_r       <= 32'd0;
            exc_pc_r         <= 32'd0;
            is_mret_r        <= 1'b0;
            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else if (FlushW) begin
            RegWriteM_r      <= 1'b0;
            ResultSrcM_r     <= 2'b00;
            RD_M_r           <= 5'd0;
            PC_M_r           <= 32'd0;
            PCPlus4M_r       <= 32'd0;
            ALU_ResultM_r    <= 32'd0;
            ReadDataM_r      <= 32'd0;
            valid_W_r        <= 1'b0;
            exc_valid_r      <= 1'b0;
            exc_cause_r      <= 6'd0;
            exc_tval_r       <= 32'd0;
            exc_pc_r         <= 32'd0;
            is_mret_r        <= 1'b0;
            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else if (core_stall_gated) begin
            // Hold all MEM->WB registers during memory stall.
            // Prevents WB from capturing stale lsu_core_rdata (=0) before the
            // SRAM read completes and ls_unit formatting becomes valid.
            // Misaligned exceptions bypass this hold so they reach WB.
        end
        else begin
            RegWriteM_r      <= RegWriteM;
            ResultSrcM_r     <= ResultSrcM;
            RD_M_r           <= RD_M;
            PC_M_r           <= PC_M;
            PCPlus4M_r       <= PCPlus4M;
            ALU_ResultM_r    <= ALU_ResultM;
            // lsu_core_rdata is already formatted by ls_unit (sign/zero extended, byte selected)
            ReadDataM_r      <= lsu_core_rdata;
            valid_W_r        <= valid_M;
            exc_valid_r      <= exc_valid_mem_final;
            exc_cause_r      <= exc_cause_mem_final;
            exc_tval_r       <= exc_tval_mem_final;
            exc_pc_r         <= exc_pc_mem_final;
            is_mret_r        <= is_mret_M;
            csr_write_en_M_r <= csr_write_en_M;
            csr_addr_M_r     <= csr_addr_M;
            new_csr_M_r      <= new_csr_M;
            old_csr_M_r      <= old_csr_M;
        end
    end

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    assign RegWriteW      = RegWriteM_r;
    assign ResultSrcW     = ResultSrcM_r;
    assign RD_W           = RD_M_r;
    assign PC_W           = PC_M_r;
    assign PCPlus4W       = PCPlus4M_r;
    assign ALU_ResultW    = ALU_ResultM_r;
    assign ReadDataW      = ReadDataM_r;
    assign valid_W        = valid_W_r;
    assign exc_valid_W    = exc_valid_r;
    assign exc_cause_W    = exc_cause_r;
    assign exc_tval_W     = exc_tval_r;
    assign exc_pc_W       = exc_pc_r;
    assign is_mret_W      = is_mret_r;

    assign csr_write_en_W = csr_write_en_M_r;
    assign csr_addr_W     = csr_addr_M_r;
    assign new_csr_W      = new_csr_M_r;
    assign old_csr_W      = old_csr_M_r;

endmodule
