`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Main_Decoder
//
// Description:
//  Main opcode decoder for RV32I subset + CSR support.
//  Decodes the 7-bit instruction opcode and generates
//  high-level control signals used in the pipeline.
//
//  Purely combinational logic using always @(*) blocks.
//  No sequential elements. Synthesizable.
//
//  Supported Instruction Types:
//    - U-type:   LUI (0x37), AUIPC (0x17)
//    - I-type:   ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI (0x13)
//    - R-type:   ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU (0x33)
//    - Load:     LB, LH, LW, LBU, LHU (0x03)
//    - Store:    SB, SH, SW (0x23)
//    - Branch:   BEQ, BNE, BLT, BGE, BLTU, BGEU (0x63)
//    - Jump:     JAL (0x6F), JALR (0x67)
//    - System:   CSR, ECALL, EBREAK, MRET (0x73)
//
//////////////////////////////////////////////////////////////////////////////////

module Main_Decoder(
    Op,
    RegWrite,
    ImmSrc,
    ALUSrc,
    MemWrite,
    ResultSrc,
    Branche,
    ALUOp,
    lse,
    Jumpe,
    LUISrcE,
    isLUIE,
    illegal_instr,
    csr_valid
);

    // ==================================================
    // Port Declarations
    // ==================================================
    input  [6:0] Op;   // Instruction opcode field [6:0]

    output reg lse;                // Load/Store enable
    output reg RegWrite;           // Register write enable
    output reg ALUSrc;             // Select immediate as ALU operand B
    output reg MemWrite;           // Data memory write enable
    output reg Branche;            // Branch enable
    output reg Jumpe;              // Jump enable
    output reg [1:0] ImmSrc;       // Immediate format selector
    output reg [1:0] ALUOp;        // ALU operation category
    output reg [1:0] ResultSrc;    // Write-back source selector
    output reg LUISrcE;            // Op[5] (LUI/AUIPC distinction)
    output reg isLUIE;             // U-type indicator
    output illegal_instr;          // Illegal instruction flag
    output reg csr_valid;          // SYSTEM opcode detected

    // ==================================================
    // Combinational Logic (always @(*) blocks)
    // ==================================================

    // ==================================================
    // Block 1: U-type Detection (LUI / AUIPC)
    // ==================================================
    always @(*) begin
        if (Op == 7'b0110111 || Op == 7'b0010111) begin
            isLUIE = 1'b1;
        end else begin
            isLUIE = 1'b0;
        end
        
        // Direct exposure of opcode bit 5 (Op[5])
        LUISrcE = Op[5];
    end

    // ==================================================
    // Block 2: Load / Store Detection
    // Load  = 0000011 (0x03)
    // Store = 0100011 (0x23)
    // ==================================================
    always @(*) begin
        if (Op == 7'b0000011 || Op == 7'b0100011) begin
            lse = 1'b1;
        end else begin
            lse = 1'b0;
        end
    end

    // ==================================================
    // Block 3: Register Write Enable
    // Includes: LUI, AUIPC, LOAD, JAL, JALR, I-ALU, R-ALU, CSR
    // ==================================================
    always @(*) begin
        case (Op)
            7'b0110111,  // LUI    (0x37)
            7'b0010111,  // AUIPC  (0x17)
            7'b0000011,  // LOAD   (0x03)
            7'b1101111,  // JAL    (0x6F)
            7'b1100111,  // JALR   (0x67)
            7'b0010011,  // I-ALU  (0x13)
            7'b0110011,  // R-ALU  (0x33)
            7'b1110011:  // SYSTEM (0x73) - CSR
                RegWrite = 1'b1;
            default:
                RegWrite = 1'b0;
        endcase
    end

    // ==================================================
    // Block 4: Immediate Format Selection
    // 00: I-type (12-bit sign-extended)
    // 01: S-type (12-bit sign-extended, 7:5 + 4:0)
    // 10: B-type (13-bit offset)
    // 11: J-type (20-bit offset)
    // ==================================================
    always @(*) begin
        case (Op)
            7'b0100011:  // Store   → S-type
                ImmSrc = 2'b01;
            7'b1100011:  // Branch  → B-type
                ImmSrc = 2'b10;
            7'b1101111:  // JAL     → J-type
                ImmSrc = 2'b11;
            default:     // Load, I-ALU, etc. → I-type
                ImmSrc = 2'b00;
        endcase
    end

    // ==================================================
    // Block 5: ALU Operand B Source Selection
    // 0: Use register (RD2_E)
    // 1: Use immediate
    // ==================================================
    always @(*) begin
        case (Op)
            7'b0110111,  // LUI
            7'b0010111,  // AUIPC
            7'b1101111,  // JAL
            7'b1100111,  // JALR
            7'b0100011,  // STORE
            7'b0000011,  // LOAD
            7'b0010011:  // I-type ALU
                ALUSrc = 1'b1;
            default:
                ALUSrc = 1'b0;
        endcase
    end

    // ==================================================
    // Block 6: Data Memory Write Enable
    // Only Store instructions write to memory
    // ==================================================
    always @(*) begin
        if (Op == 7'b0100011) begin  // Store
            MemWrite = 1'b1;
        end else begin
            MemWrite = 1'b0;
        end
    end

    // ==================================================
    // Block 7: Write-back Result Source Selection
    // 00: ALU result
    // 01: Data memory read (Load)
    // 10: PC + 4 (JAL/JALR)
    // 11: CSR old value (CSR instructions)
    // ==================================================
    always @(*) begin
        case (Op)
            7'b0000011:               // LOAD
                ResultSrc = 2'b01;
            7'b1101111, 7'b1100111:   // JAL, JALR
                ResultSrc = 2'b10;
            7'b1110011:               // SYSTEM (CSR)
                ResultSrc = 2'b11;
            default:                  // ALU operations (R-type, I-type, LUI, AUIPC)
                ResultSrc = 2'b00;
        endcase
    end

    // ==================================================
    // Block 8: Branch Detection
    // Branch = 1100011 (0x63)
    // ==================================================
    always @(*) begin
        if (Op == 7'b1100011) begin
            Branche = 1'b1;
        end else begin
            Branche = 1'b0;
        end
    end

    // ==================================================
    // Block 9: Jump Detection
    // JAL  = 1101111 (0x6F)
    // JALR = 1100111 (0x67)
    // ==================================================
    always @(*) begin
        if (Op == 7'b1101111 || Op == 7'b1100111) begin
            Jumpe = 1'b1;
        end else begin
            Jumpe = 1'b0;
        end
    end

    // ==================================================
    // Block 10: ALU Operation Category
    // 00: Load/Store/JAL (addition)
    // 01: Branch (comparison)
    // 10: Arithmetic (R-type, I-type)
    // 11: JALR (use ALU result for target)
    // ==================================================
    always @(*) begin
        case (Op)
            7'b1101111,      // JAL
            7'b0000011,      // LOAD
            7'b0100011:      // STORE
                ALUOp = 2'b00;
            7'b1100011:      // BRANCH
                ALUOp = 2'b01;
            7'b0010011,      // I-type ALU
            7'b0110011:      // R-type ALU
                ALUOp = 2'b10;
            7'b1100111:      // JALR
                ALUOp = 2'b11;
            default:
                ALUOp = 2'b00;
        endcase
    end

    // ==================================================
    // Block 11: CSR Instruction Detection (CORRECTED)
    // SYSTEM opcode = 1110011 (0x73)
    // ==================================================
    always @(*) begin
        csr_valid = (Op == 7'b1110011) ? 1'b1 : 1'b0;
        // NOTE: funct3[2] and funct3[1:0] are decoded in Control_Unit_Top
        // DO NOT output csr_imm_mode or csr_op here (not available)
    end

    // ==================================================
    // Opcode Validity Check (instantiate opcode_check)
    // ==================================================
    opcode_check op_check(
        .opcode(Op),
        .illegal_instr(illegal_instr)
    );

endmodule


