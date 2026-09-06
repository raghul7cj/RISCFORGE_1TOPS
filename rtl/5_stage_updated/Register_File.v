`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Register_File
//
// Description:
//  32 × 32-bit register file for RV32I
//  - Two asynchronous read ports
//  - One synchronous write port
//
//  x0 is hard-wired to zero.
//  Writes to x0 are ignored.
//
//  Includes simple same-cycle write forwarding.
//
//////////////////////////////////////////////////////////////////////////////////

// module Register_File(clk, rst, WE3, WD3, A1, A2, A3, RD1, RD2);

//     input clk;
//     input rst;
//     input WE3;              // Write enable
//     input [4:0] A1, A2;     // Read addresses
//     input [4:0] A3;         // Write address
//     input [31:0] WD3;       // Write data

//     output [31:0] RD1, RD2; // Read data outputs

//     // 32 registers, each 32-bit wide
//     reg [31:0] Register [31:0];

//     // ==================================================
//     // Synchronous write logic
//     // ==================================================
//     always @(posedge clk) begin
//         if (WE3 && A3 != 5'd0)
//             Register[A3] <= WD3;   // Write to selected register
//         else
//             Register[0] <= 32'd0;  // Enforce x0 = 0
//     end

//     // ==================================================
//     // Asynchronous read logic with write forwarding
//     // ==================================================
//     assign RD1 = (rst == 1'b0) ? 32'd0 :
//                  (WE3 && A1 == A3 && (A3 != 5'd0)) ? WD3 :
//                  Register[A1];

//     assign RD2 = (rst == 1'b0) ? 32'd0 :
//                  (WE3 && A2 == A3 && (A3 != 5'd0)) ? WD3 :
//                  Register[A2];

//     // // Initialize x0
//     // initial begin
//     //     Register[0] = 32'h00000000;
//     // end
//     integer i;
//     initial begin
//         for (i = 0; i < 32; i = i + 1) begin
//             Register[i] = 32'd0;
//         end
//     end

// endmodule
    
`timescale 1ns / 1ps

module Register_File(clk, rst, WE3, WD3, A1, A2, A3, RD1, RD2);

    input clk;
    input rst;
    input WE3;
    input [4:0] A1, A2;
    input [4:0] A3;
    input [31:0] WD3;

    output [31:0] RD1, RD2;

    reg [31:0] Register [31:0];
    
    // MISSING DECLARATION FIX:
    integer i; 

    always @(posedge clk) begin
        // rst must be HIGH (1) to write in active-low reset
        if (WE3 && rst && A3 != 5'd0)
            Register[A3] <= WD3;
    end

    assign RD1 = (rst == 1'b0) ? 32'd0 : 
                 (WE3 && A1 == A3 && (A3 != 5'd0)) ? WD3 : 
                 Register[A1];

    assign RD2 = (rst == 1'b0) ? 32'd0 : 
                 (WE3 && A2 == A3 && (A3 != 5'd0)) ? WD3 : 
                 Register[A2];

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            Register[i] = 32'h00000000;
        end
    end

endmodule    