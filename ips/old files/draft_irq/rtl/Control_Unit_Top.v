`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Control_Unit_Top
//
// Description:
//  Top-level control unit for the processor.
//  Integrates:
//      - Main_Decoder  (opcode-level decoding)
//      - ALU_Decoder   (precise ALU operation decoding)
//
//  Generates grouped control buses for:
//      - Load/Store unit
//      - Branch unit
//      - Jump unit
//
//  Purely combinational logic.
//
//////////////////////////////////////////////////////////////////////////////////

module Control_Unit_Top(
    Op,
    funct7,
    rs2,
    rs1,
    rd,
    RegWrite,
    ImmSrc,
    ALUSrc,
    MemWrite,
    ResultSrc,
    lsunit,
    Branch,
    Jump,
    funct3,
    funct7_30,
    ALUControl,
    LUISrcE,
    isLUIE,
    illegal_instr,
    csr_valid,
    csr_imm_mode,
    csr_op,
    is_mret
);

    // ==================================================
    // Instruction fields
    // ==================================================
    input  [6:0] Op;        // Opcode field
    input  [6:0] funct7;    // funct7 field
    input  [4:0] rs2;       // rs2 field
    input  [4:0] rs1;       // rs1 field
    input  [4:0] rd;        // rd field
    input funct7_30;
    input  [2:0] funct3;    // funct3 field

    // ==================================================
    // Primary control outputs
    // ==================================================
    output RegWrite;        // Register file write enable
    output ALUSrc;          // ALU operand B source select
    output MemWrite;        // Data memory write enable

    output [1:0] ImmSrc;    // Immediate format selector
    output [1:0] ResultSrc; // Write-back source selector

    output [3:0] ALUControl;// Exact ALU operation
    output [3:0] Branch;    // Branch control bus
    output [1:0] Jump;      // Jump control bus

    output [4:0] lsunit;    // Load/Store control bus

    output LUISrcE;         // Exposed opcode bit 5
    output isLUIE;          // U-type indicator
    output illegal_instr;

    output csr_valid;            // SYSTEM opcode detected
    output reg csr_imm_mode;      // CSR immediate mode (from funct3)
    output reg [1:0] csr_op;      // CSR operation (from funct3)
    output wire is_mret;          // mret instruction indicator

    // ==================================================
    // Internal wires
    // ==================================================
    wire Jumpe;             // Jump enable (JAL/JALR)
    wire Branche;           // Branch enable
    wire lse;               // Load/Store enable
    wire [1:0] ALUOp;       // High-level ALU category

    // ==================================================
    // Main Decoder
    // ==================================================
    Main_Decoder Main_Decoder(
        .Op(Op),
        .RegWrite(RegWrite),
        .ImmSrc(ImmSrc),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .Branche(Branche),
        .ALUSrc(ALUSrc),
        .ALUOp(ALUOp),
        .lse(lse),
        .Jumpe(Jumpe),
        .LUISrcE(LUISrcE),
        .isLUIE(isLUIE),
        .illegal_instr(illegal_instr),
        .csr_valid(csr_valid)
    );

    // ==================================================
    // Load / Store Control Bus
    //
    // lsunit[4]   : load/store enable
    // lsunit[3]   : opcode bit [5]
    // lsunit[2:0] : funct3
    // ==================================================
    assign lsunit[4]   = lse;
    assign lsunit[3]   = Op[5];
    assign lsunit[2:0] = funct3;

    // ==================================================
    // Branch Control Bus
    //
    // Branch[3]   : branch enable
    // Branch[2:0] : branch type (funct3)
    // ==================================================
    assign Branch[3]   = Branche;
    assign Branch[2:0] = funct3;

    // ==================================================
    // Jump Control Bus
    //
    // Jump[1] : jump enable
    // Jump[0] : opcode bit [3] (JAL vs JALR)
    // ==================================================
    assign Jump[1] = Jumpe;
    assign Jump[0] = Op[3];

    // ==================================================
    // ALU Decoder
    // ==================================================
    ALU_Decoder ALU_Decoder(
        .ALUOp(ALUOp),
        .funct3(funct3),
        .funct7_30(funct7_30),//funct7[5]
        .op_5(Op[5]),
        .ALUControl(ALUControl)
    );

    // ==================================================
    // CSR Decoder
    // ==================================================
    // Extract CSR immediate mode and operation from funct3
    always @(*) begin
        // Decode CSR-specific fields ONLY if csr_valid
        if (csr_valid) begin
            csr_imm_mode = funct3[2];      // Bit 2: immediate variant flag
            csr_op[1:0] = funct3[1:0];     // Bits 1:0: RW/RS/RC operation
        end else begin
            csr_imm_mode = 1'b0;
            csr_op = 2'b00;
        end
    end

    assign is_mret = ({funct7, rs2, rs1, funct3, rd, Op} ==
                      32'b0011000_00010_00000_000_00000_1110011);
    
endmodule
