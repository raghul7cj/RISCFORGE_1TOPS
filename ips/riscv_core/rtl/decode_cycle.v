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
    valid_D,
    exc_valid_D,
    exc_cause_D,
    exc_tval_D,
    exc_pc_D,
    RegWriteW, RDW, ResultW,
    RegWriteE, ALUSrcE, MemWriteE, ResultSrcE,
    BranchE, ALUControlE,
    RD1_E, RD2_E, Imm_Ext_E, RD_E,
    PCE, PCPlus4E, RS1_E, RS2_E,
    JumpE, lsunitE,
    RS1_D, RS2_D,
    FlushE, StallE, LUISrcE, isLUIE,
    illegal_instr,
    csr_valid_E,
    csr_imm_mode_E,
    csr_op_E,
    csr_raddr_E,
    rd_index_E,
    is_mret_E,
    valid_E,
    exc_valid_E,
    exc_cause_E,
    exc_tval_E,
    exc_pc_E,
    is_M_instruction_E,
    op_E
);

    // ==================================================
    // Inputs
    // ==================================================
    input clk;
    input rst;           // Active-low reset
    input FlushE;        // Pipeline flush
    input StallE;        // Pipeline stall

    input RegWriteW;
    input [4:0]  RDW;
    input [31:0] ResultW;

    input [31:0] InstrD;
    input [31:0] PCD;
    input [31:0] PCPlus4D;
    input valid_D;
    input exc_valid_D;
    input [5:0] exc_cause_D;
    input [31:0] exc_tval_D;
    input [31:0] exc_pc_D;

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
    output [11:0] csr_raddr_E;
    output [4:0] rd_index_E;
    output csr_valid_E;
    output csr_imm_mode_E;
    output [1:0] csr_op_E;
    output wire is_mret_E;
    output valid_E;
    output [31:0] exc_tval_E; // Exception-specific value (e.g., bad address for load/store exceptions)
    output [5:0] exc_cause_E;       // Exception cause code
    output [31:0] exc_pc_E;     // PC at which exception occurred
    output exc_valid_E;       // Exception valid signal
    output is_M_instruction_E;
    output [2:0] op_E;

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
    wire csr_valid;
    wire csr_imm_mode;
    wire [1:0] csr_op;
    wire is_mret;

    // ==================================================
    // Instruction field extraction
    // ==================================================
    assign RS1_D = InstrD[19:15];
    wire uses_rs2_D = (InstrD[6:0] == 7'b0110011) | (InstrD[6:0] == 7'b0100011) | (InstrD[6:0] == 7'b1100011);
    assign RS2_D = uses_rs2_D ? InstrD[24:20] : 5'd0;

    //ecall and ebreak detection
    wire is_ecall = (InstrD == 32'h00000073); // ECALL instruction encoding
    wire is_ebreak = (InstrD == 32'h00100073); // EBREAK instruction encoding

    wire new_exc_valid_D;
    wire [5:0] new_exc_cause_D;
    wire [31:0] new_exc_tval_D;
    wire [31:0] new_exc_pc_D;
    wire next_exc_valid_D;
    wire [5:0] next_exc_cause_D;
    wire [31:0] next_exc_tval_D;
    wire [31:0] next_exc_pc_D;

    // ==================================================
    // Control Unit
    // ==================================================
    Control_Unit_Top control (
        .Op(InstrD[6:0]),
        .funct7(InstrD[31:25]),
        .rs2(InstrD[24:20]),
        .rs1(InstrD[19:15]),
        .rd(InstrD[11:7]),
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
        .illegal_instr(illegal_instr),
        .csr_valid(csr_valid),
        .csr_imm_mode(csr_imm_mode),
        .csr_op(csr_op),
        .is_mret(is_mret)
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
    reg csr_imm_mode_r;
    reg [1:0] csr_op_r;
    reg csr_valid_r;
    reg [11:0] csr_addr_r;
    reg [4:0] rd_index_r;
    reg is_mret_r;
    reg valid_E_r;
    reg exc_valid_r;
    reg [5:0] exc_cause_r;
    reg [31:0] exc_tval_r;
    reg [31:0] exc_pc_r;
    reg is_M_instruction_r;
    reg [2:0] op_r;

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
            csr_imm_mode_r <= 1'b0;
            csr_op_r <= 2'b00;
            csr_valid_r <= 1'b0;
            is_mret_r <= 1'b0;
            valid_E_r <= 1'b0;
            exc_valid_r <= 1'b0;
            exc_cause_r <= 6'd0;
            exc_tval_r <= 32'h00000000;
            exc_pc_r <= 32'h00000000;
            is_M_instruction_r <= 1'b0;
            op_r <= 3'd0;
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
            csr_imm_mode_r <= 1'b0;
            csr_op_r <= 2'b00;
            csr_valid_r <= 1'b0;
            is_mret_r <= 1'b0;
            valid_E_r <= 1'b0;
            exc_valid_r <= 1'b0;
            exc_cause_r <= 6'd0;
            exc_tval_r <= 32'h00000000;
            exc_pc_r <= 32'h00000000;
            is_M_instruction_r <= 1'b0;
            op_r <= 3'd0;
        end
        else if(StallE)
        begin
            RegWriteD_r   <= RegWriteD_r;
            ALUSrcD_r     <= ALUSrcD_r;
            MemWriteD_r   <= MemWriteD_r;
            ResultSrcD_r  <= ResultSrcD_r;
            JumpD_r       <= JumpD_r;
            BranchD_r     <= BranchD_r;
            ALUControlD_r <= ALUControlD_r;
            RD1_D_r       <= RD1_D_r;
            RD2_D_r       <= RD2_D_r;
            Imm_Ext_D_r   <= Imm_Ext_D_r;
            RD_D_r        <= RD_D_r;
            RS1_D_r       <= RS1_D_r;
            RS2_D_r       <= RS2_D_r;
            lsunitD_r     <= lsunitD_r;
            PCD_r         <= PCD_r;
            PCPlus4D_r    <= PCPlus4D_r;
            LUISrc_r      <= LUISrc_r;
            isLUI_r       <= isLUI_r;
            csr_imm_mode_r <= csr_imm_mode_r;
            csr_op_r <= csr_op_r;
            csr_valid_r <= csr_valid_r;
            csr_addr_r <= csr_addr_r;
            rd_index_r <= rd_index_r;
            is_mret_r <= is_mret_r;
            valid_E_r <= valid_E_r;
            exc_valid_r <= exc_valid_r;
            exc_cause_r <= exc_cause_r;
            exc_tval_r <= exc_tval_r;
            exc_pc_r <= exc_pc_r;
            is_M_instruction_r <= is_M_instruction_r;
            op_r <= op_r;
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
            csr_imm_mode_r <= csr_imm_mode;
            csr_op_r <= csr_op;
            csr_valid_r <= csr_valid;
            csr_addr_r <= InstrD[31:20];
            rd_index_r <= InstrD[11:7];
            is_mret_r <= is_mret;
            valid_E_r <= valid_D;
            exc_valid_r <= next_exc_valid_D;
            exc_cause_r <= next_exc_cause_D;
            exc_tval_r <= next_exc_tval_D;
            exc_pc_r <= next_exc_pc_D;
            is_M_instruction_r <= (InstrD[6:0] == 7'b0110011) && (InstrD[31:25] == 7'b0000001);
            op_r <= InstrD[14:12];
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

    assign csr_imm_mode_E = csr_imm_mode_r;
    assign csr_op_E = csr_op_r;
    assign csr_valid_E = csr_valid_r;
    assign csr_raddr_E = csr_addr_r;
    assign rd_index_E = rd_index_r;
    assign is_mret_E = is_mret_r;

    assign valid_E = valid_E_r;
    assign exc_valid_E = exc_valid_r;
    assign exc_cause_E = exc_cause_r;
    assign exc_tval_E = exc_tval_r;
    assign exc_pc_E = exc_pc_r;
    assign is_M_instruction_E = is_M_instruction_r;
    assign op_E = op_r;

    assign new_exc_valid_D = valid_D && (illegal_instr || is_ecall || is_ebreak);
    assign new_exc_cause_D = (valid_D && illegal_instr) ? 6'd2 : 
                             (valid_D && is_ecall) ? 6'd11 : 
                             (valid_D && is_ebreak) ? 6'd3 : 6'd0;
    assign new_exc_tval_D  = (valid_D && illegal_instr) ? InstrD :
                             (valid_D && is_ebreak)      ? PCD : 32'h00000000;
    assign new_exc_pc_D    = valid_D ? PCD : 32'h00000000;

    assign next_exc_valid_D = exc_valid_D | new_exc_valid_D;
    assign next_exc_cause_D = exc_valid_D ? exc_cause_D : new_exc_cause_D;
    assign next_exc_tval_D = exc_valid_D ? exc_tval_D : new_exc_tval_D;
    assign next_exc_pc_D = exc_valid_D ? exc_pc_D : new_exc_pc_D;

endmodule
