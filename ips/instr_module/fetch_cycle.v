`timescale 1ns / 1ps
// Module : fetch_cycle
// IF stage and IF/ID pipeline register.

module fetch_cycle (
    input  clk,
    input  rst,
    input  PCSrcE,
    input  wb_trap_redirect,
    input  StallF,
    input  StallD,
    input  FlushD,
    input  [31:0] PCTargetE,
    input  [31:0] trap_target,
    output [31:0] InstrD,
    output [31:0] PCD,
    output [31:0] PCPlus4D,
    output        valid_D,
    output        exc_valid_D,
    output [4:0]  exc_cause_D,
    output [31:0] exc_pc_D,
    output [31:0] exc_tval_D,
    output        imem_stall
);

    wire [31:0] PCF;
    wire [31:0] PCPlus4F;
    wire [31:0] PC_next;
    wire [31:0] InstrF;
    wire        exc_valid_F;
    wire [4:0]  exc_cause_F;
    wire [31:0] exc_pc_F;
    wire [31:0] exc_tval_F;

    wire        sram_en;
    wire        sram_we;
    wire [3:0]  sram_wmask;
    wire [29:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [31:0] sram_rdata;
    wire        imem_stall_raw;

    assign PC_next = wb_trap_redirect ? trap_target  :
                     PCSrcE           ? PCTargetE    :
                                        PCPlus4F;

    PC program_counter (
        .clk    (clk),
        .rst    (rst),
        .PC     (PCF),
        .PC_Next(PC_next),
        .StallF ((StallF | imem_stall_raw) && !PCSrcE && !wb_trap_redirect)
    );

    PC_Adder PC_adder (
        .a(PCF),
        .b(32'h00000004),
        .c(PCPlus4F)
    );

    imem_controller u_imem_ctrl (
        .clk                  (clk),
        .rst_n                (rst),
        .PC                   (PCF),
        .PC_next              (PC_next),
        .instruction_is_branch(PCSrcE | wb_trap_redirect),
        .stall_in             (StallF | imem_stall_raw),
        .sram_en              (sram_en),
        .sram_we              (sram_we),
        .sram_wmask           (sram_wmask),
        .sram_addr            (sram_addr),
        .sram_wdata           (sram_wdata),
        .sram_rdata           (sram_rdata),
        .instruction          (InstrF),
        .stall                (imem_stall_raw)
    );

    Instruction_Memory_new u_imem (
        .clk       (clk),
        .rst_n     (rst),
        .sram_en   (sram_en),
        .sram_we   (sram_we),
        .sram_wmask(sram_wmask),
        .sram_addr (sram_addr),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata)
    );

    assign exc_valid_F = (PC_next[1:0] != 2'b00);
    assign exc_cause_F = 5'd0;
    assign exc_pc_F    = PC_next;
    assign exc_tval_F  = PC_next;

    assign imem_stall = imem_stall_raw;

    reg [31:0] InstrF_reg;
    reg [31:0] PCF_reg;
    reg [31:0] PCPlus4F_reg;
    reg        valid_reg;
    reg        exc_valid_reg;
    reg [4:0]  exc_cause_reg;
    reg [31:0] exc_pc_reg;
    reg [31:0] exc_tval_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            InstrF_reg    <= 32'h0000_0013;
            PCF_reg       <= 32'h0000_0000;
            PCPlus4F_reg  <= 32'h0000_0000;
            valid_reg <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 5'd0;
            exc_pc_reg    <= 32'h0000_0000;
            exc_tval_reg  <= 32'h0000_0000;
        end
        else if (FlushD) begin
            InstrF_reg    <= 32'h0000_0013;
            PCF_reg       <= 32'h0000_0000;
            PCPlus4F_reg  <= 32'h0000_0000;
            valid_reg <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 5'd0;
            exc_pc_reg    <= 32'h0000_0000;
            exc_tval_reg  <= 32'h0000_0000;
        end
        else if (StallD | imem_stall_raw) begin
            InstrF_reg    <= InstrF_reg;
            PCF_reg       <= PCF_reg;
            PCPlus4F_reg  <= PCPlus4F_reg;
            valid_reg <= valid_reg;
            exc_valid_reg <= exc_valid_reg;
            exc_cause_reg <= exc_cause_reg;
            exc_pc_reg    <= exc_pc_reg;
            exc_tval_reg  <= exc_tval_reg;
        end
        else begin
            InstrF_reg    <= InstrF;
            PCF_reg       <= PCF;
            PCPlus4F_reg  <= PCPlus4F;
            valid_reg <= 1'b1;
            exc_valid_reg <= exc_valid_F;
            exc_cause_reg <= exc_cause_F;
            exc_pc_reg    <= exc_pc_F;
            exc_tval_reg  <= exc_tval_F;
        end
    end

    assign InstrD      = InstrF_reg;
    assign PCD         = PCF_reg;
    assign PCPlus4D    = PCPlus4F_reg;
    assign valid_D     = valid_reg;
    assign exc_valid_D = exc_valid_reg;
    assign exc_cause_D = exc_cause_reg;
    assign exc_pc_D    = exc_pc_reg;
    assign exc_tval_D  = exc_tval_reg;

endmodule