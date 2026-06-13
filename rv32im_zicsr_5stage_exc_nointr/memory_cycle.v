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
    FlushW,
    RegWriteM, MemWriteM,
    ResultSrcM,
    RD_M, lsunitM,
    PC_M,
    PCPlus4M,
    valid_M,
    exc_valid_M,
    exc_cause_M,
    exc_tval_M,
    exc_pc_M,
    is_mret_M,
    WriteDataM,
    ALU_ResultM,
    csr_write_en_M,
    csr_addr_M,
    new_csr_M,
    old_csr_M,
    RegWriteW,
    ResultSrcW,
    RD_W,
    PC_W,
    PCPlus4W,
    ALU_ResultW,
    ReadDataW,
    valid_W,
    exc_valid_W,
    exc_cause_W,
    exc_tval_W,
    exc_pc_W,
    is_mret_W,
    csr_write_en_W,
    csr_addr_W,
    new_csr_W,
    old_csr_W
);

    // ==================================================
    // Inputs from Execute stage
    // ==================================================

    input clk;
    input rst;
    input FlushW;

    input RegWriteM;          // Register write enable
    input MemWriteM;          // Memory write enable

    input [1:0] ResultSrcM;   // Writeback source select
    input [4:0] RD_M;         // Destination register
    input [4:0] lsunitM;      // Load/store control bus

    input [31:0] PC_M;        // PC propagated from EX/MEM
    input [31:0] PCPlus4M;    // PC + 4
    input valid_M;
    input exc_valid_M;
    input [4:0] exc_cause_M;
    input [31:0] exc_tval_M;
    input [31:0] exc_pc_M;
    input is_mret_M;
    input [31:0] WriteDataM;  // Store data (aligned in EX)
    input [31:0] ALU_ResultM; // Effective address / ALU result

    // CSR write request (from EX/MEM pipeline register)
    input        csr_write_en_M;
    input [11:0] csr_addr_M;
    input [31:0] new_csr_M;
    input [31:0] old_csr_M;

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    output RegWriteW;
    output [1:0] ResultSrcW;
    output [4:0] RD_W;
    output [31:0] PC_W;
    output [31:0] PCPlus4W;
    output [31:0] ALU_ResultW;
    output [31:0] ReadDataW;
    output valid_W;
    output exc_valid_W;
    output [4:0] exc_cause_W;
    output [31:0] exc_tval_W;
    output [31:0] exc_pc_W;
    output is_mret_W;

    // CSR write request (to WB stage / retirement)
    output        csr_write_en_W;
    output [11:0] csr_addr_W;
    output [31:0] new_csr_W;
    output [31:0] old_csr_W;
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

    wire exc_valid_mem_local = (misaligned_load | misaligned_store) & valid_M;

    wire [4:0] exc_cause_mem_local =
        misaligned_load  ? 5'd4 :
        misaligned_store ? 5'd6 :
                           5'd0; // 4: Load misalign, 6: Store misalign

    wire [31:0] exc_tval_mem_local = ALU_ResultM; // Faulting address

    // Merge with propagated exception (first wins)
    wire exc_valid_mem_final = exc_valid_M | exc_valid_mem_local;
    wire [4:0] exc_cause_mem_final = exc_valid_M ? exc_cause_M : exc_cause_mem_local;
    wire [31:0] exc_tval_mem_final = exc_valid_M ? exc_tval_M : exc_tval_mem_local;

    // ==================================================
    // Data Memory
    // ==================================================
    // WE      : Controlled by MemWriteM
    // WD      : Aligned store data for stores
    // WSTRB   : Byte enables from ls_unit

    Data_Memory dmem (
        .clk(clk),
        .rst(rst),
        .WE(MemWriteM & valid_M & ~exc_valid_mem_final),
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

    // Dummy pins for future extensions (Access Faults, etc.)
    wire dummy_mem_access_fault = 1'b0;
    wire dummy_mem_page_fault   = 1'b0;

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
    reg [4:0] exc_cause_r;
    reg [31:0] exc_tval_r;
    reg [31:0] exc_pc_r;
    reg is_mret_r;

    reg        csr_write_en_M_r;
    reg [11:0] csr_addr_M_r;
    reg [31:0] new_csr_M_r;
    reg [31:0] old_csr_M_r;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            RegWriteM_r   <= 1'b0;
            ResultSrcM_r  <= 2'b00;
            RD_M_r        <= 5'd0;
            PC_M_r        <= 32'd0;
            PCPlus4M_r    <= 32'd0;
            ALU_ResultM_r <= 32'd0;
            ReadDataM_r   <= 32'd0;
            valid_W_r     <= 1'b0;
            exc_valid_r   <= 1'b0;
            exc_cause_r   <= 5'd0;
            exc_tval_r    <= 32'd0;
            exc_pc_r      <= 32'd0;
            is_mret_r     <= 1'b0;

            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else if (FlushW) begin
            RegWriteM_r   <= 1'b0;
            ResultSrcM_r  <= 2'b00;
            RD_M_r        <= 5'd0;
            PC_M_r        <= 32'd0;
            PCPlus4M_r    <= 32'd0;
            ALU_ResultM_r <= 32'd0;
            ReadDataM_r   <= 32'd0;
            valid_W_r     <= 1'b0;
            exc_valid_r   <= 1'b0;
            exc_cause_r   <= 5'd0;
            exc_tval_r    <= 32'd0;
            exc_pc_r      <= 32'd0;
            is_mret_r     <= 1'b0;

            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else begin
            RegWriteM_r   <= RegWriteM;
            ResultSrcM_r  <= ResultSrcM;
            RD_M_r        <= RD_M;
            PC_M_r        <= PC_M;
            PCPlus4M_r    <= PCPlus4M;
            ALU_ResultM_r <= ALU_ResultM;
            ReadDataM_r   <= result;
            valid_W_r     <= valid_M;
            exc_valid_r   <= exc_valid_mem_final; // CHANGED
            exc_cause_r   <= exc_cause_mem_final; // CHANGED
            exc_tval_r    <= exc_tval_mem_final;  // CHANGED
            exc_pc_r      <= exc_pc_M;
            is_mret_r     <= is_mret_M;

            csr_write_en_M_r <= csr_write_en_M;
            csr_addr_M_r     <= csr_addr_M;
            new_csr_M_r      <= new_csr_M;
            old_csr_M_r      <= old_csr_M;
        end
    end

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    assign RegWriteW   = RegWriteM_r;
    assign ResultSrcW  = ResultSrcM_r;
    assign RD_W        = RD_M_r;
    assign PC_W        = PC_M_r;
    assign PCPlus4W    = PCPlus4M_r;
    assign ALU_ResultW = ALU_ResultM_r;
    assign ReadDataW   = ReadDataM_r;
    assign valid_W     = valid_W_r;
    assign exc_valid_W = exc_valid_r;
    assign exc_cause_W = exc_cause_r;
    assign exc_tval_W  = exc_tval_r;
    assign exc_pc_W    = exc_pc_r;
    assign is_mret_W   = is_mret_r;

    assign csr_write_en_W = csr_write_en_M_r;
    assign csr_addr_W     = csr_addr_M_r;
    assign new_csr_W      = new_csr_M_r;
    assign old_csr_W      = old_csr_M_r;
    
endmodule
