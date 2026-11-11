`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 18:05:28
// Design Name: 
// Module Name: rv32m_mul
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


module rv32m_mul (
    input         clk,
    input         rst_n,
 
    // Inputs (from EX stage)
    input  [31:0] rs1,
    input  [31:0] rs2,
    input  [2:0]  funct3,     // MUL=000, MULH=001, MULHSU=010, MULHU=011
    input  [4:0]  rd_in,
    input         valid_in,
 
    // Outputs (to WB, available 3 cycles after valid_in)
    output reg [31:0] result,
    output reg [4:0]  rd_out,
    output reg        valid_out
);
    // -------------------------------------------------------------------------
    //  Sign extension of operands (33 bits each)
    //  MUL/MULH    : both signed  → sign-extend
    //  MULHSU      : rs1 signed, rs2 unsigned
    //  MULHU       : both unsigned → zero-extend
    // -------------------------------------------------------------------------
    wire signed_rs1 = (funct3 == 3'b001) | (funct3 == 3'b010) | (funct3 == 3'b000);
    wire signed_rs2 = (funct3 == 3'b001) | (funct3 == 3'b000);
 
    wire [32:0] mcand  = {signed_rs1 & rs1[31], rs1};   // 33-bit multiplicand
    wire [32:0] mplier = {signed_rs2 & rs2[31], rs2};   // 33-bit multiplier
 
    // Select upper vs lower half
    wire upper = (funct3 != 3'b000);    // MULH, MULHSU, MULHU all want upper 32
 
    // =========================================================================
    //  STAGE 1: Booth Encoding + Partial Product Generation
    //  17 partial products (Radix-4: ceil(33/2)+1 = 17 groups)
    //  mplier is 33 bits; pad with 1 implicit 0 below bit 0 → 35 bits total
    // =========================================================================
    wire [34:0] mplier_pad = {mplier[32], mplier, 1'b0};   // pad LSB with 0 and sign-extend MSB
 
    wire [16:0] enc_neg, enc_zero, enc_two;
    wire [65:0] pp   [0:16];
    wire [16:0] ppn;          // correction bits (one per PP)
 
    genvar i;
    generate
        for (i = 0; i < 17; i = i + 1) begin : gen_booth
            booth_enc u_enc (
                .bits  (mplier_pad[2*i+2 : 2*i]),   // 3-bit group
                .neg   (enc_neg  [i]),
                .zero  (enc_zero [i]),
                .two   (enc_two  [i])
            );
            pp_gen u_ppg (
                .neg   (enc_neg  [i]),
                .zero  (enc_zero [i]),
                .two   (enc_two  [i]),
                .mcand (mcand),
//                .shift (7'(2*i)),
                .shift ((2*i)),
                .pp    (pp[i]),
                .pp_neg(ppn[i])
            );
        end
    endgenerate
 
    // Correction word: sum all pp_neg bits aligned to their bit positions
    // Each correction bit at position 2i (since each PP is shifted by 2i)
    wire [65:0] corr;
    /*assign corr = { ppn[16], ppn[15], ppn[14], ppn[13], ppn[12],
                    ppn[11], ppn[10], ppn[9],  ppn[8],  ppn[7],
                    ppn[6],  ppn[5],  ppn[4],  ppn[3],  ppn[2],
                    ppn[1],  ppn[0] };*/
                    
    // WRONG - all 17 bits packed into top of corr
// assign corr = { ppn[16], ppn[15], ..., ppn[0] };
 
// FIXED - each ppn[i] placed at its correct bit position 2*i
// Total: 33 zeros (bits 65:33) + ppn[16] at bit 32 + ... + ppn[0] at bit 0
// Count: 33 + (1+1)×16 + 1 = 66 bits ✓
// FIXED: ppn[i] must sit at bit 2*i, not packed into bits [65:49]
// ppn[16] → bit 32,  ppn[15] → bit 30, ... ppn[0] → bit 0
assign corr = {
    33'b0,          // bits [65:33] - no correction needed above bit 32
    ppn[16], 1'b0,  // bit 32: correction for i=16 (shift=32)
    ppn[15], 1'b0,  // bit 30
    ppn[14], 1'b0,  // bit 28
    ppn[13], 1'b0,  // bit 26
    ppn[12], 1'b0,  // bit 24
    ppn[11], 1'b0,  // bit 22
    ppn[10], 1'b0,  // bit 20
    ppn[ 9], 1'b0,  // bit 18
    ppn[ 8], 1'b0,  // bit 16
    ppn[ 7], 1'b0,  // bit 14
    ppn[ 6], 1'b0,  // bit 12
    ppn[ 5], 1'b0,  // bit 10
    ppn[ 4], 1'b0,  // bit  8
    ppn[ 3], 1'b0,  // bit  6
    ppn[ 2], 1'b0,  // bit  4
    ppn[ 1], 1'b0,  // bit  2
    ppn[ 0]         // bit  0: correction for i=0  (shift=0)
};
 
    // -- Pipeline Register 1 (end of Stage 1) ---------------------------------
    reg [65:0] s1_pp   [0:16];
    reg [65:0] s1_corr;
    reg [2:0]  s1_funct3;
    reg [4:0]  s1_rd;
    reg        s1_valid;
    reg        s1_upper;
    
    integer k;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid  <= 0;
        end else begin
            s1_valid  <= valid_in;
            s1_funct3 <= funct3;
            s1_rd     <= rd_in;
            s1_upper  <= upper;
            s1_corr   <= corr;
            for (k = 0; k < 17; k = k+1)
                s1_pp[k] <= pp[k];
        end
    end
 
    // =========================================================================
    //  STAGE 2: Dadda CSA Reduction Tree  (17 → 2 rows)
    //
    //  Dadda target sequence: 17 → 12 → 8 → 6 → 4 → 3 → 2
    //  Each level uses FAs to reduce rows; remaining rows carry forward.
    //  Including s1_corr as the 18th input, rounded to nearest target.
    //
    //  Note: All PPs are 66 bits wide (full precision).
    //        CSA co outputs are shifted left by 1 before next level.
    // =========================================================================
    wire [65:0] l0 [0:17];    // 18 inputs (17 PPs + correction word)
    assign l0[0]  = s1_pp[0];  assign l0[1]  = s1_pp[1];
    assign l0[2]  = s1_pp[2];  assign l0[3]  = s1_pp[3];
    assign l0[4]  = s1_pp[4];  assign l0[5]  = s1_pp[5];
    assign l0[6]  = s1_pp[6];  assign l0[7]  = s1_pp[7];
    assign l0[8]  = s1_pp[8];  assign l0[9]  = s1_pp[9];
    assign l0[10] = s1_pp[10]; assign l0[11] = s1_pp[11];
    assign l0[12] = s1_pp[12]; assign l0[13] = s1_pp[13];
    assign l0[14] = s1_pp[14]; assign l0[15] = s1_pp[15];
    assign l0[16] = s1_pp[16]; assign l0[17] = s1_corr;
 
    // -- Level 1: 18 → 12 (reduce 6 via 6 FAs) --
    wire [65:0] l1s0,  l1s1,  l1s2, 
                l1s3,  l1s4,  l1s5;
                
    wire [64:0] l1c0,l1c1,l1c2,l1c3,l1c4,l1c5;
    csa u_l1_0(.a(l0[0]), .b(l0[1]),  .c(l0[2]),  .s(l1s0), .co(l1c0));
    csa u_l1_1(.a(l0[3]), .b(l0[4]),  .c(l0[5]),  .s(l1s1), .co(l1c1));
    csa u_l1_2(.a(l0[6]), .b(l0[7]),  .c(l0[8]),  .s(l1s2), .co(l1c2));
    csa u_l1_3(.a(l0[9]), .b(l0[10]), .c(l0[11]), .s(l1s3), .co(l1c3));
    csa u_l1_4(.a(l0[12]),.b(l0[13]), .c(l0[14]), .s(l1s4), .co(l1c4));
    csa u_l1_5(.a(l0[15]),.b(l0[16]), .c(l0[17]), .s(l1s5), .co(l1c5));
    // 12 rows: l1s0-5, {l1c0-5 << 1}
 
    // -- Level 2: 12 → 8 (reduce 4 via 4 FAs) --
    wire [65:0] l2s0, l2s1, l2s2, l2s3;
    wire [64:0] l2c0, l2c1, l2c2, l2c3;
    
    csa u_l2_0(.a(l1s0),        .b(l1s1),        .c({l1c0[64:0],1'b0}), .s(l2s0), .co(l2c0));
    csa u_l2_1(.a(l1s2),        .b(l1s3),        .c({l1c1[64:0],1'b0}), .s(l2s1), .co(l2c1));
    csa u_l2_2(.a(l1s4),        .b(l1s5),        .c({l1c2[64:0],1'b0}), .s(l2s2), .co(l2c2));
    csa u_l2_3(.a({l1c3[64:0],1'b0}),.b({l1c4[64:0],1'b0}),.c({l1c5[64:0],1'b0}), .s(l2s3), .co(l2c3));
    // 8 rows: l2s0-3, {l2c0-3 << 1}
 
    // -- Level 3: 8 → 6 (reduce 2 via 2 FAs) --
    wire [65:0] l3s0, l3s1;
    wire [64:0] l3c0, l3c1;
    csa u_l3_0(.a(l2s0), .b(l2s1), .c({l2c0[64:0],1'b0}), .s(l3s0), .co(l3c0));
    csa u_l3_1(.a(l2s2), .b(l2s3), .c({l2c1[64:0],1'b0}), .s(l3s1), .co(l3c1));
    // 6 rows: l3s0-1, {l3c0-1<<1}, {l2c2<<1}, {l2c3<<1}
 
    // -- Level 4: 6 → 4 (reduce 2 via 2 FAs) --
    wire [65:0] l4s0, l4s1;
    wire [64:0] l4c0, l4c1;
    wire [65:0] l2c2_sh = {l2c2[64:0], 1'b0};
    wire [65:0] l2c3_sh = {l2c3[64:0], 1'b0};
    csa u_l4_0(.a(l3s0), .b(l3s1), .c({l3c0[64:0],1'b0}), .s(l4s0), .co(l4c0));
    csa u_l4_1(.a({l3c1[64:0],1'b0}), .b(l2c2_sh), .c(l2c3_sh), .s(l4s1), .co(l4c1));
    // 4 rows: l4s0, l4s1, {l4c0<<1}, {l4c1<<1}
 
    // -- Level 5: 4 → 3 (reduce 1 via 1 FA) --
    wire [65:0] l5s0;
    wire [64:0] l5c0;
    csa u_l5_0(.a(l4s0), .b(l4s1), .c({l4c0[64:0],1'b0}), .s(l5s0), .co(l5c0));
    // 3 rows: l5s0, {l5c0<<1}, {l4c1<<1}
 
    // -- Level 6: 3 → 2 (1 FA) --
    wire [65:0] final_sum;
    wire [64:0] final_cout;
    wire [65:0] l4c1_sh = {l4c1[64:0], 1'b0};
    csa u_l6(.a(l5s0), .b({l5c0[64:0],1'b0}), .c(l4c1_sh), .s(final_sum), .co(final_cout));
    // Result: final_sum + (final_cout << 1)  → feed to CPA in Stage 3
 
    // -- Pipeline Register 2 (end of Stage 2) ---------------------------------
    reg [65:0] s2_sum, s2_carry;
    reg [2:0]  s2_funct3;
    reg [4:0]  s2_rd;
    reg        s2_valid;
    reg        s2_upper;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
        end else begin
            s2_valid   <= s1_valid;
            s2_funct3  <= s1_funct3;
            s2_rd      <= s1_rd;
            s2_upper   <= s1_upper;
            s2_sum     <= final_sum;
            s2_carry   <= {final_cout[64:0], 1'b0};  // carry shift
        end
    end
 
    // =========================================================================
    //  STAGE 3: 66-bit Carry-Propagate Adder + Result Selection
    //  Using Verilog '+' here - synthesiser maps to a fast carry-lookahead
    //  or parallel-prefix adder at 65nm (Kogge-Stone / Han-Carlson).
    // =========================================================================
    
    wire [63:0] product_full = s2_sum + s2_carry;   // full precision, no ASSIGN-1
    wire [63:0] product      = product_full[63:0];   // explicit slice, not arithmetic
    //wire [65:0] product = s2_sum + s2_carry;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
        end else begin
            valid_out <= s2_valid;
            rd_out    <= s2_rd;
            result    <= s2_upper ? product[63:32] : product[31:0];
        end
    end
 
endmodule
