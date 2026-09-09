`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ALU
//
// Description:
//  Arithmetic Logic Unit for RV32I subset.
//
//  Performs arithmetic, logical, shift, comparison,
//  and JALR address computation operations.
//
//  Outputs:
//      Result : 32-bit result
//      Zero   : Asserted when Result == 0
//      flags  : Comparison flags for branch decisions:
//                 flags[2]: A == B
//                 flags[1]: A_signed < B_signed
//                 flags[0]: A < B
//
//////////////////////////////////////////////////////////////////////////////////

module ALU(
    input  [31:0] A, B,
    input  [3:0]  ALUControl,
    output reg [31:0] Result,
    output        Zero,
    output [2:0]  flags
);

    wire signed [31:0] A_signed, B_signed;
    wire signed [31:0] sra_result;

    assign A_signed = A;
    assign B_signed = B;
    assign sra_result = A_signed >>> B[4:0];

    // --------------------------------------------------
    // ALU operation selection
    // --------------------------------------------------

    always @(*) begin
        case (ALUControl)
            4'b0000: Result = A + B;                  // ADD
            4'b0001: Result = A - B;                  // SUB
            4'b0100: Result = A & B;                  // AND
            4'b0101: Result = A | B;                  // OR
            4'b0110: Result = (A + B) & (~32'd1);     // JALR (clear LSB)
            4'b0111: Result = A ^ B;                  // XOR
            4'b1000: Result = A << B[4:0];            // SLL
            4'b1001: Result = A >> B[4:0];            // SRL
            4'b1010: Result = sra_result;             // SRA
            4'b1100: Result = {31'b0, A < B};         // SLTU
            4'b1111: Result = {31'b0, A_signed < B_signed}; // SLT
            default: Result = 32'b0;                  // Default
        endcase
    end

    // --------------------------------------------------
    // Zero flag
    // --------------------------------------------------
    assign Zero = &(~Result);  // True when Result == 0

    // --------------------------------------------------
    // Comparison flags (for compatibility with 5_stage JB_unit)
    // --------------------------------------------------
    assign flags[2] = (A == B);
    assign flags[1] = (A_signed < B_signed);
    assign flags[0] = (A < B);

endmodule
