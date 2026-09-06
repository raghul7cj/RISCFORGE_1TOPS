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
//
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps
module ALU(
    input  [31:0] A, B,
    input  [3:0]  ALUControl,
    output reg [31:0] Result,
    output [2:0]  flags
);
    wire signed [31:0] A_signed = A;
    wire signed [31:0] B_signed = B;

    // A case statement prevents Verilog from converting signed operations into unsigned ones!
    always @(*) begin
        case(ALUControl)
            4'b0000: Result = A + B;
            4'b0001: Result = A - B;
            4'b0100: Result = A & B;
            4'b0101: Result = A | B;
            4'b0110: Result = (A + B) & (~32'd1); // JALR
            4'b0111: Result = A ^ B;
            4'b1000: Result = A << B[4:0];
            4'b1001: Result = A >> B[4:0];
            4'b1010: Result = A_signed >>> B[4:0]; // Now safely executes as Arithmetic Shift
            4'b1100: Result = {31'b0, (A < B)}; // SLTU
            4'b1111: Result = {31'b0, (A_signed < B_signed)}; // SLT
            default: Result = 32'd0;
        endcase
    end

    // 3-bit flags so the branch unit can detect Less Than / Greater Than
    assign flags[2] = (A == B);
    assign flags[1] = (A_signed < B_signed);
    assign flags[0] = (A < B);
endmodule
//ORGINAL
// module ALU(A, B, Result, ALUControl, flags);

//     input  [31:0] A, B;
//     input  [3:0]  ALUControl;

//     output [31:0] Result;
//     output [2:0] flags;
//     //output        Zero;

//     //wire Cout;
//     wire signed [31:0] A_signed, B_signed;

//     assign A_signed = A;
//     assign B_signed = B;

//     // --------------------------------------------------
//     // ALU operation selection
//     // --------------------------------------------------

//     assign {Result} =
//         (ALUControl == 4'b0000) ? A + B :                  // ADD
//         (ALUControl == 4'b0001) ? A - B :                  // SUB
// //        (ALUControl == 4'b0010) ?mul
// //        (ALUControl == 4'b0011) ?mulh

//         (ALUControl == 4'b0100) ? A & B :                  // AND
//         (ALUControl == 4'b0101) ? A | B :                  // OR
//         (ALUControl == 4'b0110) ? (A + B) & (~32'd1) :     // JALR (clear LSB)
//         (ALUControl == 4'b0111) ? A ^ B :                  // XOR
//         (ALUControl == 4'b1000) ? A << B[4:0] :            // SLL
//         (ALUControl == 4'b1001) ? A >> B[4:0] :            // SRL
//         (ALUControl == 4'b1010) ? A_signed >>> B[4:0] :    // SRA
//         (ALUControl == 4'b1100) ? A < B :                  // SLTU
//         (ALUControl == 4'b1111) ? A_signed < B_signed :    // SLT
//         {32{1'b0}};                                        // Default

//     // --------------------------------------------------
//     // Zero flag
//     // --------------------------------------------------

//    // assign Zero = &(~Result);  // True when Result == 0

//     //deadbeef fix
//     assign flags[2] = (A == B);
//     assign flags[1] = ($signed(A) < $signed(B));
//     assign flags[0] = (A < B);

// endmodule
