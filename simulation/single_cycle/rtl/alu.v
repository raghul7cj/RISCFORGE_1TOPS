`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.01.2026 13:50:46
// Design Name: 
// Module Name: alu
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


module alu #(parameter N = 32)(
    input  [N-1:0] A,          // ALU operand A
    input  [N-1:0] B,          // ALU operand B
    input  [3:0]   ctrl,       // ALU control signal
    output reg [N-1:0] result, // ALU result
    output [3:0]   flags       // ALU flags
);

    // =========================================================
    // FLAGS DEFINITION
    // =========================================================
    // flags[3] : Carry
    // flags[2] : Unused
    // flags[1] : Sign (MSB of result)
    // flags[0] : Zero (result == 0)

    // =========================================================
    // INTERNAL WIRES FOR ALU OPERATIONS
    // =========================================================

    wire [N-1:0] r0;   // ADD
    wire [N-1:0] r1;   // SUB
    wire [N-1:0] r2;   // EQ
    wire [N-1:0] r3;   // NEQ
    wire [N-1:0] r4;   // AND
    wire [N-1:0] r5;   // OR
    wire [N-1:0] r6;   // JALR helper (aligned address)
    wire [N-1:0] r7;   // XOR
    wire [N-1:0] r8;   // SLL
    wire [N-1:0] r9;   // SRL
    wire [N-1:0] r10;  // SRA
    wire [N-1:0] r12;  // SLTU
    wire [N-1:0] r15;  // SLT

    // Signed versions for signed comparison and shifts
    wire signed [N-1:0] A_signed;
    wire signed [N-1:0] B_signed;

    assign A_signed = A;
    assign B_signed = B;

    // Carry out from addition
    wire cout;

    // =========================================================
    // ALU OPERATION IMPLEMENTATIONS
    // =========================================================

    assign {cout, r0} = A + B;                    // ADD
    assign r1  = A - B;                           // SUB
    assign r2  = (A == B);                        // EQ
    assign r3  = (A != B);                        // NEQ
    assign r4  = A & B;                           // AND
    assign r5  = A | B;                           // OR
    assign r6  = (A + B) & (~32'd1);               // JALR (LSB cleared)
    assign r7  = A ^ B;                           // XOR
    assign r8  = A << B[4:0];                     // SLL
    assign r9  = A >> B[4:0];                     // SRL
    assign r10 = A_signed >>> B[4:0];             // SRA
    assign r12 = (A < B);                         // SLTU (unsigned)
    assign r15 = (A_signed < B_signed);           // SLT (signed)

    // =========================================================
    // FLAG GENERATION
    // =========================================================

    assign flags[0] = (result == 0) ? 1'b1 : 1'b0; // Zero flag
    assign flags[1] = result[N-1];                 // Sign flag
    assign flags[2] = 1'b0;                        // Unused
    assign flags[3] = cout;                        // Carry flag

    // =========================================================
    // ALU RESULT SELECTION
    // =========================================================
    // ALU control encoding (ctrl):
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

    always @(*) begin
        case (ctrl)
            4'b0000: result = r0;    // ADD
            4'b0001: result = r1;    // SUB
            4'b0010: result = r2;    // EQ (unused in datapath)
            4'b0011: result = r3;    // NEQ (unused in datapath)
            4'b0100: result = r4;    // AND
            4'b0101: result = r5;    // OR
            4'b0110: result = r6;    // JALR
            4'b0111: result = r7;    // XOR
            4'b1000: result = r8;    // SLL
            4'b1001: result = r9;    // SRL
            4'b1010: result = r10;   // SRA
            4'b1100: result = r12;   // SLTU
            4'b1111: result = r15;   // SLT
            default: result = r0;    // Default ADD
        endcase
    end

endmodule
