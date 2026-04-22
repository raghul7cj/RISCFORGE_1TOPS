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

`timescale 1ns / 1ps
module decode_cycle(
    clk, rst, InstrD, PCD, PCPlus4D, RegWriteW, RDW, ResultW, RegWriteE, ALUSrcE, MemWriteE, ResultSrcE,
    BranchE, ALUControlE, RD1_E, RD2_E, Imm_Ext_E, RD_E, PCE, PCPlus4E, RS1_E, RS2_E, JumpE, lsunitE,
    RS1_D, RS2_D, FlushE, LUISrcE, isLUIE, illegal_instr, is_M_instruction, op
);

    input clk, rst, FlushE, RegWriteW;
    input [4:0] RDW;
    input [31:0] ResultW, InstrD, PCD, PCPlus4D;

    output RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, illegal_instr, is_M_instruction;
    output [1:0] ResultSrcE, JumpE;
    output [4:0] lsunitE, RD_E, RS1_E, RS2_E, RS1_D, RS2_D;
    output [3:0] ALUControlE, BranchE;
    output [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;
    output [2:0] op;

    wire [2:0] opD = InstrD[14:12];

    wire RegWriteD, ALUSrcD, MemWriteD, LUISrcD, isLUID;
    wire [1:0] ImmSrcD, ResultSrcD;
    wire [3:0] ALUControlD;

    assign RS1_D = InstrD[19:15];
    assign RS2_D = InstrD[24:20];

    Control_Unit_Top control (
        .Op(InstrD[6:0]), .RegWrite(RegWriteD), .ImmSrc(ImmSrcD), .ALUSrc(ALUSrcD),
        .MemWrite(MemWriteD), .ResultSrc(ResultSrcD), .Branch(), .funct3(InstrD[14:12]),
        .funct7_30(InstrD[30]), .ALUControl(ALUControlD), .Jump(), .lsunit(), 
        .LUISrcE(LUISrcD), .isLUIE(isLUID), .illegal_instr(illegal_instr), .is_M_instruction() 
    );

    wire [6:0] opc = InstrD[6:0];
    wire [2:0] f3  = InstrD[14:12];
    wire [6:0] f7  = InstrD[31:25];

    wire is_load   = (opc == 7'b0000011);
    wire is_store  = (opc == 7'b0100011);
    wire is_branch = (opc == 7'b1100011);
    wire is_jal    = (opc == 7'b1101111);
    wire is_jalr   = (opc == 7'b1100111);

    wire is_M_instructionD_fixed = (opc == 7'b0110011) && (f7 == 7'b0000001);
    wire [1:0] JumpD_fixed = { (is_jal || is_jalr), is_jal };
    wire [3:0] BranchD_fixed = { is_branch, f3 };
    wire [4:0] lsunitD_fixed = { (is_load || is_store), is_store, f3 };

    wire [31:0] RD1_D, RD2_D, Imm_Ext_D;

    Register_File rf (
        .clk(clk), .rst(rst), .WE3(RegWriteW), .WD3(ResultW),
        .A1(InstrD[19:15]), .A2(InstrD[24:20]), .A3(RDW), .RD1(RD1_D), .RD2(RD2_D)
    );

    Sign_Extend extension (.In(InstrD), .Imm_Ext(Imm_Ext_D), .ImmSrc(ImmSrcD), .LUI(isLUID));

    reg RegWriteD_r, ALUSrcD_r, MemWriteD_r, LUISrc_r, isLUI_r, is_M_instruction_r;
    reg [1:0] ResultSrcD_r, JumpD_r;
    reg [3:0] ALUControlD_r, BranchD_r;
    reg [4:0] RD_D_r, RS1_D_r, RS2_D_r, lsunitD_r;
    reg [31:0] RD1_D_r, RD2_D_r, Imm_Ext_D_r, PCD_r, PCPlus4D_r;
    reg [2:0] op_r;

    always @(posedge clk or negedge rst) begin
        if (!rst || FlushE) begin
            RegWriteD_r <= 0; ALUSrcD_r <= 0; MemWriteD_r <= 0; ResultSrcD_r <= 0; JumpD_r <= 0; BranchD_r <= 0;
            ALUControlD_r <= 0; RD1_D_r <= 0; RD2_D_r <= 0; Imm_Ext_D_r <= 0; RD_D_r <= 0; RS1_D_r <= 0; RS2_D_r <= 0;
            lsunitD_r <= 0; PCD_r <= 0; PCPlus4D_r <= 0; LUISrc_r <= 0; isLUI_r <= 0; is_M_instruction_r <= 0; op_r <= 0;
        end else begin
            RegWriteD_r <= RegWriteD; ALUSrcD_r <= ALUSrcD; MemWriteD_r <= MemWriteD; ResultSrcD_r <= ResultSrcD;
            ALUControlD_r <= ALUControlD; RD1_D_r <= RD1_D; RD2_D_r <= RD2_D; Imm_Ext_D_r <= Imm_Ext_D;
            RD_D_r <= InstrD[11:7]; RS1_D_r <= InstrD[19:15]; RS2_D_r <= InstrD[24:20];
            PCD_r <= PCD; PCPlus4D_r <= PCPlus4D; LUISrc_r <= LUISrcD; isLUI_r <= isLUID; op_r <= opD;

            JumpD_r <= JumpD_fixed;
            BranchD_r <= BranchD_fixed;
            lsunitD_r <= lsunitD_fixed;
            is_M_instruction_r <= is_M_instructionD_fixed;
        end
    end

    assign RegWriteE = RegWriteD_r; assign ALUSrcE = ALUSrcD_r; assign MemWriteE = MemWriteD_r;
    assign ResultSrcE = ResultSrcD_r; assign JumpE = JumpD_r; assign BranchE = BranchD_r;
    assign ALUControlE = ALUControlD_r; assign RD1_E = RD1_D_r; assign RD2_E = RD2_D_r;
    assign Imm_Ext_E = Imm_Ext_D_r; assign RD_E = RD_D_r; assign RS1_E = RS1_D_r; assign RS2_E = RS2_D_r;
    assign PCE = PCD_r; assign PCPlus4E = PCPlus4D_r; assign lsunitE = lsunitD_r;
    assign LUISrcE = LUISrc_r; assign isLUIE = isLUI_r; assign is_M_instruction = is_M_instruction_r; assign op = op_r;

endmodule


// `timescale 1ns / 1ps

// module decode_cycle(
//     clk, rst,
//     InstrD, PCD, PCPlus4D,
//     RegWriteW, RDW, ResultW,
//     RegWriteE, ALUSrcE, MemWriteE, ResultSrcE,
//     BranchE, ALUControlE,
//     RD1_E, RD2_E, Imm_Ext_E, RD_E,
//     PCE, PCPlus4E, RS1_E, RS2_E,
//     JumpE, lsunitE,
//     RS1_D, RS2_D,
//     FlushE, LUISrcE, isLUIE,
//     illegal_instr,
//     is_M_instruction, op
// );

//     input clk, rst, FlushE, RegWriteW;
//     input [4:0] RDW;
//     input [31:0] ResultW, InstrD, PCD, PCPlus4D;

//     output RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, illegal_instr, is_M_instruction;
//     output [1:0] ResultSrcE, JumpE;
//     output [4:0] lsunitE, RD_E, RS1_E, RS2_E, RS1_D, RS2_D;
//     output [3:0] ALUControlE, BranchE;
//     output [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;
//     output [2:0] op;

//     wire [2:0] opD = InstrD[14:12];

//     // Original Control Signals
//     wire RegWriteD, ALUSrcD, MemWriteD, LUISrcD, isLUID;
//     wire [1:0] ImmSrcD, ResultSrcD;
//     wire [3:0] ALUControlD;

//     assign RS1_D = InstrD[19:15];
//     assign RS2_D = InstrD[24:20];

//     Control_Unit_Top control (
//         .Op(InstrD[6:0]),
//         .RegWrite(RegWriteD),
//         .ImmSrc(ImmSrcD),
//         .ALUSrc(ALUSrcD),
//         .MemWrite(MemWriteD),
//         .ResultSrc(ResultSrcD),
//         .Branch(), // Ignored and overridden
//         .funct3(InstrD[14:12]),
//         .funct7_30(InstrD[30]),
//         .ALUControl(ALUControlD),
//         .Jump(),   // Ignored and overridden
//         .lsunit(), // Ignored and overridden
//         .LUISrcE(LUISrcD),
//         .isLUIE(isLUID),
//         .illegal_instr(illegal_instr),
//         .is_M_instruction() // Ignored and overridden
//     );

//     // ==================================================
//     // MAGIC OVERRIDES: Fixing the 5-Stage Transition Bugs!
//     // ==================================================
//     wire [6:0] opc = InstrD[6:0];
//     wire [2:0] f3  = InstrD[14:12];
//     wire [6:0] f7  = InstrD[31:25];

//     wire is_load   = (opc == 7'b0000011);
//     wire is_store  = (opc == 7'b0100011);
//     wire is_branch = (opc == 7'b1100011);
//     wire is_jal    = (opc == 7'b1101111);
//     wire is_jalr   = (opc == 7'b1100111);

//     // 1. M-Extension Fix: Only trigger for funct7 == 0000001
//     wire is_M_instructionD_fixed = (opc == 7'b0110011) && (f7 == 7'b0000001);

//     // 2. Jump Fix: Match the JB_unit format {Jump Enable, isJAL}
//     wire [1:0] JumpD_fixed = { (is_jal || is_jalr), is_jal };

//     // 3. Branch Fix: Match the JB_unit format {Branch Enable, funct3}
//     wire [3:0] BranchD_fixed = { is_branch, f3 };

//     // 4. LS_Unit Fix: Match the ls_unit format {Mem Enable, isStore, funct3}
//     wire [4:0] lsunitD_fixed = { (is_load || is_store), is_store, f3 };

//     // ==================================================

//     wire [31:0] RD1_D, RD2_D, Imm_Ext_D;

//     Register_File rf (
//         .clk(clk),
//         .rst(rst),
//         .WE3(RegWriteW),
//         .WD3(ResultW),
//         .A1(InstrD[19:15]),
//         .A2(InstrD[24:20]),
//         .A3(RDW),
//         .RD1(RD1_D),
//         .RD2(RD2_D)
//     );

//     Sign_Extend extension (
//         .In(InstrD),
//         .Imm_Ext(Imm_Ext_D),
//         .ImmSrc(ImmSrcD),
//         .LUI(isLUID)
//     );

//     reg RegWriteD_r, ALUSrcD_r, MemWriteD_r, LUISrc_r, isLUI_r, is_M_instruction_r;
//     reg [1:0] ResultSrcD_r, JumpD_r;
//     reg [3:0] ALUControlD_r, BranchD_r;
//     reg [4:0] RD_D_r, RS1_D_r, RS2_D_r, lsunitD_r;
//     reg [31:0] RD1_D_r, RD2_D_r, Imm_Ext_D_r, PCD_r, PCPlus4D_r;
//     reg [2:0] op_r;

//     always @(posedge clk or negedge rst) begin
//         if (!rst || FlushE) begin
//             RegWriteD_r <= 0; ALUSrcD_r <= 0; MemWriteD_r <= 0;
//             ResultSrcD_r <= 0; JumpD_r <= 0; BranchD_r <= 0;
//             ALUControlD_r <= 0; RD1_D_r <= 0; RD2_D_r <= 0;
//             Imm_Ext_D_r <= 0; RD_D_r <= 0; RS1_D_r <= 0; RS2_D_r <= 0;
//             lsunitD_r <= 0; PCD_r <= 0; PCPlus4D_r <= 0;
//             LUISrc_r <= 0; isLUI_r <= 0; is_M_instruction_r <= 0; op_r <= 0;
//         end else begin
//             RegWriteD_r   <= RegWriteD;
//             ALUSrcD_r     <= ALUSrcD;
//             MemWriteD_r   <= MemWriteD;
//             ResultSrcD_r  <= ResultSrcD;
//             ALUControlD_r <= ALUControlD;
//             RD1_D_r       <= RD1_D;
//             RD2_D_r       <= RD2_D;
//             Imm_Ext_D_r   <= Imm_Ext_D;
//             RD_D_r        <= InstrD[11:7];
//             RS1_D_r       <= InstrD[19:15];
//             RS2_D_r       <= InstrD[24:20];
//             PCD_r         <= PCD;
//             PCPlus4D_r    <= PCPlus4D;
//             LUISrc_r      <= LUISrcD;
//             isLUI_r       <= isLUID;
//             op_r          <= opD;

//             // INJECT FIXED SIGNALS HERE
//             JumpD_r            <= JumpD_fixed;
//             BranchD_r          <= BranchD_fixed;
//             lsunitD_r          <= lsunitD_fixed;
//             is_M_instruction_r <= is_M_instructionD_fixed;
//         end
//     end

//     assign RegWriteE = RegWriteD_r;
//     assign ALUSrcE = ALUSrcD_r;
//     assign MemWriteE = MemWriteD_r;
//     assign ResultSrcE = ResultSrcD_r;
//     assign JumpE = JumpD_r;
//     assign BranchE = BranchD_r;
//     assign ALUControlE = ALUControlD_r;
//     assign RD1_E = RD1_D_r;
//     assign RD2_E = RD2_D_r;
//     assign Imm_Ext_E = Imm_Ext_D_r;
//     assign RD_E = RD_D_r;
//     assign RS1_E = RS1_D_r;
//     assign RS2_E = RS2_D_r;
//     assign PCE = PCD_r;
//     assign PCPlus4E = PCPlus4D_r;
//     assign lsunitE = lsunitD_r;
//     assign LUISrcE = LUISrc_r;
//     assign isLUIE = isLUI_r;
//     assign is_M_instruction = is_M_instruction_r;
//     assign op = op_r;

// endmodule

//ORGINAL
// module decode_cycle(
//     clk, rst,
//     InstrD, PCD, PCPlus4D,
//     RegWriteW, RDW, ResultW,
//     RegWriteE, ALUSrcE, MemWriteE, ResultSrcE,
//     BranchE, ALUControlE,
//     RD1_E, RD2_E, Imm_Ext_E, RD_E,
//     PCE, PCPlus4E, RS1_E, RS2_E,
//     JumpE, lsunitE,
//     RS1_D, RS2_D,
//     FlushE, LUISrcE, isLUIE,
//     illegal_instr,
    
//     is_M_instruction,op
// );

//     // ==================================================
//     // Inputs
//     // ==================================================
//     input clk;
//     input rst;           // Active-low reset
//     input FlushE;        // Pipeline flush

//     input RegWriteW;
//     input [4:0]  RDW;
//     input [31:0] ResultW;

//     input [31:0] InstrD;
//     input [31:0] PCD;
//     input [31:0] PCPlus4D;

//     // ==================================================
//     // Outputs to Execute stage
//     // ==================================================
//     output RegWriteE;
//     output ALUSrcE;
//     output MemWriteE;
//     output [1:0] ResultSrcE;
//     output [1:0] JumpE;
//     output [4:0] lsunitE;
//     output [3:0] ALUControlE;
//     output [3:0] BranchE;

//     output [31:0] RD1_E;
//     output [31:0] RD2_E;
//     output [31:0] Imm_Ext_E;

//     output [4:0] RD_E;
//     output [4:0] RS1_E;
//     output [4:0] RS2_E;

//     output [4:0] RS1_D;
//     output [4:0] RS2_D;

//     output [31:0] PCE;
//     output [31:0] PCPlus4E;

//     output LUISrcE;
//     output isLUIE;
//     output illegal_instr;
    
//     output is_M_instruction;
//     output [2:0] op;
    
//     wire [2:0] opD;
//     assign opD=InstrD[14:12];

//     // ==================================================
//     // Decode-stage combinational signals
//     // ==================================================
//     wire RegWriteD;
//     wire ALUSrcD;
//     wire MemWriteD;

//     wire [1:0] ImmSrcD;
//     wire [1:0] ResultSrcD;
//     wire [1:0] JumpD;
//     wire [4:0] lsunitD;
//     wire [3:0] ALUControlD;
//     wire [3:0] BranchD;

//     wire [31:0] RD1_D;
//     wire [31:0] RD2_D;
//     wire [31:0] Imm_Ext_D;

//     wire LUISrcD, isLUID;

//     // ==================================================
//     // Instruction field extraction
//     // ==================================================
//     assign RS1_D = InstrD[19:15];
//     assign RS2_D = InstrD[24:20];

//     // ==================================================
//     // Control Unit
//     // ==================================================
//     Control_Unit_Top control (
//         .Op(InstrD[6:0]),
//         .RegWrite(RegWriteD),
//         .ImmSrc(ImmSrcD),
//         .ALUSrc(ALUSrcD),
//         .MemWrite(MemWriteD),
//         .ResultSrc(ResultSrcD),
//         .Branch(BranchD),
//         .funct3(InstrD[14:12]),
//         .funct7_30(InstrD[30]),
//         .ALUControl(ALUControlD),
//         .Jump(JumpD),
//         .lsunit(lsunitD),
//         .LUISrcE(LUISrcD),
//         .isLUIE(isLUID),
//         .illegal_instr(illegal_instr),
//         .is_M_instruction(is_M_instructionD)
//     );

//     // ==================================================
//     // Register File
//     // ==================================================
//     Register_File rf (
//         .clk(clk),
//         .rst(rst),
//         .WE3(RegWriteW),
//         .WD3(ResultW),
//         .A1(InstrD[19:15]),
//         .A2(InstrD[24:20]),
//         .A3(RDW),
//         .RD1(RD1_D),
//         .RD2(RD2_D)
//     );

//     // ==================================================
//     // Immediate Generator
//     // ==================================================
//     Sign_Extend extension (
//         .In(InstrD),
//         .Imm_Ext(Imm_Ext_D),
//         .ImmSrc(ImmSrcD),
//         .LUI(isLUID)
//     );

//     // ==================================================
//     // ID/EX Pipeline Registers
//     // ==================================================
//     reg RegWriteD_r, ALUSrcD_r, MemWriteD_r;
//     reg [1:0] ResultSrcD_r, JumpD_r;
//     reg [3:0] ALUControlD_r, BranchD_r;
//     reg [31:0] RD1_D_r, RD2_D_r, Imm_Ext_D_r;
//     reg [4:0] RD_D_r, RS1_D_r, RS2_D_r, lsunitD_r;
//     reg [31:0] PCD_r, PCPlus4D_r;
//     reg LUISrc_r, isLUI_r;
//     reg is_M_instruction_r;
//     reg [2:0] op_r;

//     always @(posedge clk or negedge rst) begin
//         if (!rst /*|| FlushE*/) begin
//             RegWriteD_r   <= 1'b0;
//             ALUSrcD_r     <= 1'b0;
//             MemWriteD_r   <= 1'b0;
//             ResultSrcD_r  <= 2'b00;
//             JumpD_r       <= 2'b00;
//             BranchD_r     <= 4'b0000;
//             ALUControlD_r <= 4'b0000;
//             RD1_D_r       <= 32'h00000000;
//             RD2_D_r       <= 32'h00000000;
//             Imm_Ext_D_r   <= 32'h00000000;
//             RD_D_r        <= 5'd0;
//             RS1_D_r       <= 5'd0;
//             RS2_D_r       <= 5'd0;
//             lsunitD_r     <= 5'd0;
//             PCD_r         <= 32'h00000000;
//             PCPlus4D_r    <= 32'h00000000;
//             LUISrc_r      <= 1'b0;
//             isLUI_r       <= 1'b0;
//             is_M_instruction_r<=1'b0;
//             op_r<=1'b0;
//         end
//         else if(FlushE)
//         begin
//             RegWriteD_r   <= 1'b0;
//             ALUSrcD_r     <= 1'b0;
//             MemWriteD_r   <= 1'b0;
//             ResultSrcD_r  <= 2'b00;
//             JumpD_r       <= 2'b00;
//             BranchD_r     <= 4'b0000;
//             ALUControlD_r <= 4'b0000;
//             RD1_D_r       <= 32'h00000000;
//             RD2_D_r       <= 32'h00000000;
//             Imm_Ext_D_r   <= 32'h00000000;
//             RD_D_r        <= 5'd0;
//             RS1_D_r       <= 5'd0;
//             RS2_D_r       <= 5'd0;
//             lsunitD_r     <= 5'd0;
//             PCD_r         <= 32'h00000000;
//             PCPlus4D_r    <= 32'h00000000;
//             LUISrc_r      <= 1'b0;
//             isLUI_r       <= 1'b0;
//             is_M_instruction_r<=1'b0;
//             op_r<=1'b0;
//         end
//         else begin
//             RegWriteD_r   <= RegWriteD;
//             ALUSrcD_r     <= ALUSrcD;
//             MemWriteD_r   <= MemWriteD;
//             ResultSrcD_r  <= ResultSrcD;
//             JumpD_r       <= JumpD;
//             BranchD_r     <= BranchD;
//             ALUControlD_r <= ALUControlD;
//             RD1_D_r       <= RD1_D;
//             RD2_D_r       <= RD2_D;
//             Imm_Ext_D_r   <= Imm_Ext_D;
//             RD_D_r        <= InstrD[11:7];
//             RS1_D_r       <= InstrD[19:15];
//             RS2_D_r       <= InstrD[24:20];
//             lsunitD_r     <= lsunitD;
//             PCD_r         <= PCD;
//             PCPlus4D_r    <= PCPlus4D;
//             LUISrc_r      <= LUISrcD;
//             isLUI_r       <= isLUID;
//             is_M_instruction_r<=is_M_instructionD;
//             op_r<=opD;
//         end
//     end

//     // ==================================================
//     // Outputs to Execute stage
//     // ==================================================
//     assign RegWriteE   = RegWriteD_r;
//     assign ALUSrcE     = ALUSrcD_r;
//     assign MemWriteE   = MemWriteD_r;
//     assign ResultSrcE  = ResultSrcD_r;
//     assign JumpE       = JumpD_r;
//     assign BranchE     = BranchD_r;
//     assign ALUControlE = ALUControlD_r;

//     assign RD1_E       = RD1_D_r;
//     assign RD2_E       = RD2_D_r;
//     assign Imm_Ext_E   = Imm_Ext_D_r;

//     assign RD_E        = RD_D_r;
//     assign RS1_E       = RS1_D_r;
//     assign RS2_E       = RS2_D_r;

//     assign PCE         = PCD_r;
//     assign PCPlus4E    = PCPlus4D_r;

//     assign lsunitE     = lsunitD_r;
//     assign LUISrcE     = LUISrc_r;
//     assign isLUIE      = isLUI_r;
    
//     assign is_M_instruction =is_M_instruction_r;
//     assign op=op_r;
// endmodule
