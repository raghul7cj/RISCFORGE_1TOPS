`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.01.2026 11:53:01
// Design Name: 
// Module Name: control_unit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module control_unit(
   // input  [31:0] in,          // 32-bit instruction
    input  [6:0] Op,        // Opcode field
    input  funct7_30,    // funct7 field
    input  [2:0] funct3,
    input    flags,       // ALU flags (used for branch decisions)

    // Control outputs
    output        LUI_Src,      // Select between LUI and AUIPC
    output        isJALR,       // JALR instruction indicator
    output        isLUI,        // LUI instruction indicator
    output        regwrite,     // Register file write enable
    output [1:0]  ImmSrc,       // Immediate type selector
    output        Memwrite,     // Data memory write enable
    output [1:0]  ResultSrc,    // Writeback result selector
    output        ALUSrc,       // ALU operand source select
    output [3:0]  alu_ctrl,     // ALU control signal
    output        PCSrc,        // PC source select
    output [4:0]  lsunit        // Load/store unit control
);

    // =========================================================
    // INTERNAL CONTROL SIGNALS
    // =========================================================

    wire [1:0] ALUop;           // High-level ALU operation type
    wire       Branch;          // Indicates branch instruction
    reg  [3:0] a_ctrl;          // Internal ALU control register

    assign alu_ctrl = a_ctrl;   // Drive ALU control output

    // =========================================================
    // MAIN DECODER
    // =========================================================
    // Decodes opcode and generates high-level control signals

    main_decoder main_decoder (
        //.in        (in),
        .Op(Op),
        .funct3(funct3),
       // .funct7(in[31:25]),
        .LUI_Src   (LUI_Src),
        .isLUI     (isLUI),
        .isJALR    (isJALR),
        .regwrite  (regwrite),
        .ImmSrc    (ImmSrc),
        .Memwrite  (Memwrite),
        .ResultSrc (ResultSrc),
        .ALUSrc    (ALUSrc),
        .ALUop     (ALUop),
        .Branch    (Branch),
        .lsunit    (lsunit),
        .illegal_instr (illegal_instr)
    );

    // =========================================================
    // ALU CONTROL LOGIC
    // =========================================================
    // ALU control encoding (alu_ctrl):
    // --------------------------------
    // ADD   : 4'b0000
    // SUB   : 4'b0001
    // AND   : 4'b0100
    // OR    : 4'b0101
    // XOR   : 4'b0111
    // JALR  : 4'b0110
    // SLL   : 4'b1000
    // SRL   : 4'b1001
    // SRA   : 4'b1010
    // SLTU  : 4'b1100
    // SLT   : 4'b1111
    // --------------------------------
    //
    // ALU control depends on:
    // - ALUop from main decoder
    // - funct3 field (in[14:12])
    // - funct7 bits (in[30], in[5])

    always @(*) begin
        if (ALUop == 2'b00) begin
            // Load / Store / AUIPC
            a_ctrl = 4'b0000;   // ADD
        end
        else if (ALUop == 2'b01) begin
            // Branch instructions
            if (funct3 == 3'b000 || funct3 == 3'b001)
                a_ctrl = 4'b0001;   // SUB (BEQ, BNE)
            else if (funct3 == 3'b100 || funct3 == 3'b101)
                a_ctrl = 4'b1111;   // SLT  (BLT, BGE)
            else if (funct3 == 3'b110 || funct3 == 3'b111)
                a_ctrl = 4'b1100;   // SLTU (BLTU, BGEU)
            else
                a_ctrl = 4'b0000;   // Default ADD
        end
        else if (ALUop == 2'b10) begin
            // R-type / I-type ALU instructions
            if (funct3 == 3'b000) begin
                // ADD / SUB
                if ({Op[5], funct7_30/*funct7[5]*/} == 2'b11)
                    a_ctrl = 4'b0001;   // SUB
                else
                    a_ctrl = 4'b0000;   // ADD
            end
            else if (funct3 == 3'b001)
                a_ctrl = 4'b1000;       // SLL
            else if (funct3 == 3'b010)
                a_ctrl = 4'b1111;       // SLT
            else if (funct3 == 3'b011)
                a_ctrl = 4'b1100;       // SLTU
            else if (funct3 == 3'b100)
                a_ctrl = 4'b0111;       // XOR
            else if (funct3 == 3'b101) begin
                // SRL / SRA
                if (funct7_30/*funct7[5]*/ == 1'b1)
                    a_ctrl = 4'b1010;   // SRA
                else
                    a_ctrl = 4'b1001;   // SRL
            end
            else if (funct3 == 3'b110)
                a_ctrl = 4'b0101;       // OR
            else if (funct3 == 3'b111)
                a_ctrl = 4'b0100;       // AND
           else
           a_ctrl=4'b0000;  //extra line added tp prevent latch 
        end
        else begin
            a_ctrl = 4'b0110;           // JALR / safe default
        end
    end

    // =========================================================
    // BRANCH DECISION LOGIC
    // =========================================================
    // Determines whether a branch is taken using ALU flags

    wire sbranch;   // Successful branch indicator

    assign sbranch = (Branch == 1'b0) ? 1'b0 :
                     ((funct3 == 3'b000 && flags == 1'b1) ||  // BEQ
                      (funct3 == 3'b001 && flags == 1'b0) ||  // BNE
                      (funct3 == 3'b100 && flags == 1'b0) ||  // BLT
                      (funct3 == 3'b101 && flags == 1'b1) ||  // BGE
                      (funct3 == 3'b110 && flags == 1'b0) ||  // BLTU
                      (funct3 == 3'b111 && flags == 1'b1))    // BGEU
                     ? 1'b1 : 1'b0;

    // =========================================================
    // PC SOURCE SELECTION
    // =========================================================
    // PCSrc asserted for:
    // - JAL
    // - JALR
    // - Taken branch

    assign PCSrc = (!illegal_instr)&&((Op == 7'b1101111 ||   // JAL
                    sbranch == 1'b1       ||  // Taken branch
                    Op == 7'b1100111)    // JALR
                    ? 1'b1 : 1'b0);

endmodule
