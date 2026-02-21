`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : decode_cycle
//
// Description:
//  Implements the Instruction Decode (ID) stage and the
//  Decode → Execute (ID/EX) pipeline register.
//
//  Responsibilities:
//      - Instruction field extraction
//      - Control signal generation
//      - Register file read
//      - Immediate generation
//      - Pipeline register storage
//
//  Synchronous pipeline register with:
//      - Active-low reset
//      - Flush support (FlushE)
//
//  Outputs are forwarded to Execute stage.
//
//////////////////////////////////////////////////////////////////////////////////

module decode_cycle(
    clk, rst,
    InstrD, PCD, PCPlus4D,
    RegWriteW, RDW, ResultW,
    RegWriteE, ALUSrcE, MemWriteE, ResultSrcE,
    BranchE, ALUControlE,
    RD1_E, RD2_E, Imm_Ext_E, RD_E,
    PCE, PCPlus4E, RS1_E, RS2_E,
    JumpE, lsunitE,
    RS1_D, RS2_D,
    FlushE, LUISrcE, isLUIE,
    illegal_instr
);

    // ==================================================
    // Inputs
    // ==================================================
    input clk;
    input rst;           // Active-low reset
    input FlushE;        // Pipeline flush

    input RegWriteW;
    input [4:0]  RDW;
    input [31:0] ResultW;

    input [31:0] InstrD;
    input [31:0] PCD;
    input [31:0] PCPlus4D;

    // ==================================================
    // Outputs to Execute stage
    // ==================================================
    output RegWriteE;
    output ALUSrcE;
    output MemWriteE;
    output [1:0] ResultSrcE;
    output [1:0] JumpE;
    output [4:0] lsunitE;
    output [3:0] ALUControlE;
    output [3:0] BranchE;

    output [31:0] RD1_E;
    output [31:0] RD2_E;
    output [31:0] Imm_Ext_E;

    output [4:0] RD_E;
    output [4:0] RS1_E;
    output [4:0] RS2_E;

    output [4:0] RS1_D;
    output [4:0] RS2_D;

    output [31:0] PCE;
    output [31:0] PCPlus4E;

    output LUISrcE;
    output isLUIE;
    output illegal_instr;

    // ==================================================
    // Decode-stage combinational signals
    // ==================================================
    wire RegWriteD;
    wire ALUSrcD;
    wire MemWriteD;

    wire [1:0] ImmSrcD;
    wire [1:0] ResultSrcD;
    wire [1:0] JumpD;
    wire [4:0] lsunitD;
    wire [3:0] ALUControlD;
    wire [3:0] BranchD;

    wire [31:0] RD1_D;
    wire [31:0] RD2_D;
    wire [31:0] Imm_Ext_D;

    wire LUISrcD, isLUID;

    // ==================================================
    // Instruction field extraction
    // ==================================================
    assign RS1_D = InstrD[19:15];
    assign RS2_D = InstrD[24:20];

    // ==================================================
    // Control Unit
    // ==================================================
    Control_Unit_Top control (
        .Op(InstrD[6:0]),
        .RegWrite(RegWriteD),
        .ImmSrc(ImmSrcD),
        .ALUSrc(ALUSrcD),
        .MemWrite(MemWriteD),
        .ResultSrc(ResultSrcD),
        .Branch(BranchD),
        .funct3(InstrD[14:12]),
        .funct7_30(InstrD[30]),
        .ALUControl(ALUControlD),
        .Jump(JumpD),
        .lsunit(lsunitD),
        .LUISrcE(LUISrcD),
        .isLUIE(isLUID),
        .illegal_instr(illegal_instr)
    );

    // ==================================================
    // Register File
    // ==================================================
    Register_File rf (
        .clk(clk),
        .rst(rst),
        .WE3(RegWriteW),
        .WD3(ResultW),
        .A1(InstrD[19:15]),
        .A2(InstrD[24:20]),
        .A3(RDW),
        .RD1(RD1_D),
        .RD2(RD2_D)
    );

    // ==================================================
    // Immediate Generator
    // ==================================================
    Sign_Extend extension (
        .In(InstrD),
        .Imm_Ext(Imm_Ext_D),
        .ImmSrc(ImmSrcD),
        .LUI(isLUID)
    );

    // ==================================================
    // ID/EX Pipeline Registers
    // ==================================================
    reg RegWriteD_r, ALUSrcD_r, MemWriteD_r;
    reg [1:0] ResultSrcD_r, JumpD_r;
    reg [3:0] ALUControlD_r, BranchD_r;
    reg [31:0] RD1_D_r, RD2_D_r, Imm_Ext_D_r;
    reg [4:0] RD_D_r, RS1_D_r, RS2_D_r, lsunitD_r;
    reg [31:0] PCD_r, PCPlus4D_r;
    reg LUISrc_r, isLUI_r;

    always @(posedge clk or negedge rst) begin
        if (!rst /*|| FlushE*/) begin
            RegWriteD_r   <= 1'b0;
            ALUSrcD_r     <= 1'b0;
            MemWriteD_r   <= 1'b0;
            ResultSrcD_r  <= 2'b00;
            JumpD_r       <= 2'b00;
            BranchD_r     <= 4'b0000;
            ALUControlD_r <= 4'b0000;
            RD1_D_r       <= 32'h00000000;
            RD2_D_r       <= 32'h00000000;
            Imm_Ext_D_r   <= 32'h00000000;
            RD_D_r        <= 5'd0;
            RS1_D_r       <= 5'd0;
            RS2_D_r       <= 5'd0;
            lsunitD_r     <= 5'd0;
            PCD_r         <= 32'h00000000;
            PCPlus4D_r    <= 32'h00000000;
            LUISrc_r      <= 1'b0;
            isLUI_r       <= 1'b0;
        end
        else if(FlushE)
        begin
            RegWriteD_r   <= 1'b0;
            ALUSrcD_r     <= 1'b0;
            MemWriteD_r   <= 1'b0;
            ResultSrcD_r  <= 2'b00;
            JumpD_r       <= 2'b00;
            BranchD_r     <= 4'b0000;
            ALUControlD_r <= 4'b0000;
            RD1_D_r       <= 32'h00000000;
            RD2_D_r       <= 32'h00000000;
            Imm_Ext_D_r   <= 32'h00000000;
            RD_D_r        <= 5'd0;
            RS1_D_r       <= 5'd0;
            RS2_D_r       <= 5'd0;
            lsunitD_r     <= 5'd0;
            PCD_r         <= 32'h00000000;
            PCPlus4D_r    <= 32'h00000000;
            LUISrc_r      <= 1'b0;
            isLUI_r       <= 1'b0;
        end
        else begin
            RegWriteD_r   <= RegWriteD;
            ALUSrcD_r     <= ALUSrcD;
            MemWriteD_r   <= MemWriteD;
            ResultSrcD_r  <= ResultSrcD;
            JumpD_r       <= JumpD;
            BranchD_r     <= BranchD;
            ALUControlD_r <= ALUControlD;
            RD1_D_r       <= RD1_D;
            RD2_D_r       <= RD2_D;
            Imm_Ext_D_r   <= Imm_Ext_D;
            RD_D_r        <= InstrD[11:7];
            RS1_D_r       <= InstrD[19:15];
            RS2_D_r       <= InstrD[24:20];
            lsunitD_r     <= lsunitD;
            PCD_r         <= PCD;
            PCPlus4D_r    <= PCPlus4D;
            LUISrc_r      <= LUISrcD;
            isLUI_r       <= isLUID;
        end
    end

    // ==================================================
    // Outputs to Execute stage
    // ==================================================
    assign RegWriteE   = RegWriteD_r;
    assign ALUSrcE     = ALUSrcD_r;
    assign MemWriteE   = MemWriteD_r;
    assign ResultSrcE  = ResultSrcD_r;
    assign JumpE       = JumpD_r;
    assign BranchE     = BranchD_r;
    assign ALUControlE = ALUControlD_r;

    assign RD1_E       = RD1_D_r;
    assign RD2_E       = RD2_D_r;
    assign Imm_Ext_E   = Imm_Ext_D_r;

    assign RD_E        = RD_D_r;
    assign RS1_E       = RS1_D_r;
    assign RS2_E       = RS2_D_r;

    assign PCE         = PCD_r;
    assign PCPlus4E    = PCPlus4D_r;

    assign lsunitE     = lsunitD_r;
    assign LUISrcE     = LUISrc_r;
    assign isLUIE      = isLUI_r;

endmodule
