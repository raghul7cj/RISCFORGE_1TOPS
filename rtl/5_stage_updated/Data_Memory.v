`timescale 1ns / 1ps


module Data_Memory(clk, rst, WE, WD, A, RD, WSTRB);
    input [3:0]  WSTRB;     
    input clk, rst, WE;
    input [29:0] A;
    input [31:0] WD;
    output [31:0] RD;

    // 1MB Memory Array
    reg [31:0] mem [262143:0]; 

    always @ (posedge clk) begin
        if (WE && A !== 30'bx) begin
            // FIXED: Sliced A down to 18 bits to prevent out-of-bounds dropping
            if (WSTRB[0]) mem[A[17:0]][7:0]   <= WD[7:0];
            if (WSTRB[1]) mem[A[17:0]][15:8]  <= WD[15:8];
            if (WSTRB[2]) mem[A[17:0]][23:16] <= WD[23:16];
            if (WSTRB[3]) mem[A[17:0]][31:24] <= WD[31:24];
        end
    end

    // FIXED: Sliced A down to 18 bits here as well
    assign RD = (~rst || A === 30'bx) ? 32'd0 : mem[A[17:0]]; 
endmodule



///ORGINAL// module Data_Memory(clk,rst,WE,WD,A,RD,WSTRB);
 
//     input [3:0]  WSTRB;     // Byte write strobes
//     input clk,rst,WE;
//     input [29:0]A;
//     input [31:0]WD; //initially A was [31:0] but issues in linting as only 31:2 was used
//     output [31:0]RD;

//     reg [31:0] mem [262143:0];

//     always @ (posedge clk)
//     begin
//         if (WE) begin
//             if (WSTRB[0]) mem[A/*[31:2]*/][7:0]   <= WD[7:0];
//             if (WSTRB[1]) mem[A/*[31:2]*/][15:8]  <= WD[15:8];
//             if (WSTRB[2]) mem[A/*[31:2]*/][23:16] <= WD[23:16];
//             if (WSTRB[3]) mem[A/*[31:2]*/][31:24] <= WD[31:24];
//         end
//     end

//     assign RD = (~rst) ? 32'd0 : mem[{A/*[31:2]*/}];


// endmodule


//module Data_Memory(clk,rst,WE,WD,A,RD,WSTRB);

//    input [3:0]  WSTRB;
//    input clk, rst,WE;
//    input [31:0] A, WD;
//    output reg [31:0] RD;

//    reg [31:0] mem [1023:0];

//    always @(posedge clk) begin

//        if (WE) begin
//            if (WSTRB[0]) mem[A[31:2]][7:0]   <= WD[7:0];
//            if (WSTRB[1]) mem[A[31:2]][15:8]  <= WD[15:8];
//            if (WSTRB[2]) mem[A[31:2]][23:16] <= WD[23:16];
//            if (WSTRB[3]) mem[A[31:2]][31:24] <= WD[31:24];
//        end

//        RD <= mem[A[31:2]];

//    end

//endmodule
