`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 18:20:43
// Design Name: 
// Module Name: rv32m_div
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

`timescale 1ns / 1ps
module rv32m_div (
    input         clk,
    input         rst_n,

    input         valid_in,
    output reg    stall,
    output reg    valid_out,

    input  [31:0] rs1,
    input  [31:0] rs2,
    input  [2:0]  funct3,
    input  [4:0]  rd_in,

    output reg [31:0] result,
    output reg [4:0]  rd_out
);
    // -------------------------------------------------------------------------
    //  Live decode - safe ONLY in IDLE while valid_in is high
    // -------------------------------------------------------------------------
    wire is_div    = (funct3 == 3'b100);
    wire is_divu   = (funct3 == 3'b101);
    wire is_rem    = (funct3 == 3'b110);
    wire is_remu   = (funct3 == 3'b111);
    wire signed_op = is_div | is_rem;

    wire div_by_zero = (rs2 == 32'b0);
    wire signed_ovf  = signed_op
                       & (rs1 == 32'h8000_0000)
                       & (rs2 == 32'hFFFF_FFFF);

    // -------------------------------------------------------------------------
    //  Working registers
    // -------------------------------------------------------------------------
    reg [33:0] P;
    reg [31:0] divisor_r;
    reg [31:0] quotient;      // holds |rs1| initially; accumulates SD q-bits
    reg [5:0]  cnt;
    reg        neg_dividend, neg_divisor;
    reg [4:0]  rd_r;
    reg [31:0] edge_result;

    // BUG 4 FIX: snapshot op flags in IDLE - funct3 changes during execution
    reg s_is_div, s_is_divu, s_is_rem, s_is_remu;

    // Module-level temporaries for CORRECT state (Verilog-2001)
    wire [31:0] q_final_sd       = quotient - (~quotient);   // KEY: SD to binary
    wire [31:0] q_final_restored = P[33] ? (q_final_sd - 1'b1) : q_final_sd;
    wire [31:0] r_final_restored = P[33] ? (P[31:0] + divisor_r) : P[31:0];

    wire [31:0] q_final = (s_is_div && (neg_dividend ^ neg_divisor)) ? (~q_final_restored + 1'b1) : q_final_restored;
    wire [31:0] r_final = (s_is_rem && neg_dividend) ? (~r_final_restored + 1'b1) : r_final_restored;

    reg [32:0] temp;
    reg temp1;


    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam CORRECT = 2'd2;
    localparam DONE    = 2'd3;

    reg [1:0] state;

    // -------------------------------------------------------------------------
    //  Non-restoring step wires
    //
    //  BUG 2 FIX: p_shl brings in quotient[31] (next dividend bit), not 1'b0
    //  BUG 3 FIX: p_sign = p_shl[32] checks sign AFTER shift (= old P[31]),
    //             not P[32] which is sign BEFORE shift
    // -------------------------------------------------------------------------
    wire [33:0] p_shl   = {P[32:0], quotient[31]}; // shift {P,Q} left 1
    wire        p_sign  = p_shl[33];               // sign of shifted value
    wire [33:0] div_ext = {2'b0, divisor_r};
    wire [33:0] p_add   = p_shl + div_ext;          // 2P + D  (P was negative)
    wire [33:0] p_sub   = p_shl - div_ext;          // 2P - D  (P non-negative)
    wire        q_bit   = ~p_sign;                  // 1 = subtracted, 0 = added

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            stall     <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            case (state)

                // -------------------------------------------------------------
                //  IDLE
                // -------------------------------------------------------------
                IDLE: begin
                    valid_out <= 1'b0;
                    if (valid_in) begin
                        rd_r <= rd_in;
                        cnt  <= 6'd0;

                        s_is_div  <= is_div;
                        s_is_divu <= is_divu;
                        s_is_rem  <= is_rem;
                        s_is_remu <= is_remu;

                        if (div_by_zero) begin
                            edge_result <= (is_rem | is_remu) ? rs1 : 32'hFFFF_FFFF;
                            stall       <= 1'b1;
                            state       <= DONE;

                        end else if (signed_ovf) begin
                            edge_result <= is_rem ? 32'h0000_0000 : 32'h8000_0000;
                            stall       <= 1'b1;
                            state       <= DONE;

                        end else begin
                            neg_dividend <= signed_op & rs1[31];
                            neg_divisor  <= signed_op & rs2[31];
                            divisor_r    <= (signed_op & rs2[31]) ? (~rs2 + 1'b1) : rs2;

                            // BUG 1 FIX: P starts at 0, NOT {1'b0, rs1}.
                            // Dividend bits live in 'quotient' and shift into P
                            // one per cycle via p_shl above.
                            P        <= 34'h0_0000_0000;
                            quotient <= (signed_op & rs1[31]) ? (~rs1 + 1'b1) : rs1;

                            stall <= 1'b1;
                            state <= COMPUTE;
                        end
                    end
                end

                // -------------------------------------------------------------
                //  COMPUTE: 32 non-restoring iterations
                //
                //  Each cycle:
                //    p_shl = {P[31:0], quotient[31]}  - shift left, bring in
                //                                        next dividend bit
                //    if p_shl >= 0: P = p_shl - D, q_bit = 1  (+1 digit)
                //    if p_shl <  0: P = p_shl + D, q_bit = 0  (-1 digit)
                //    quotient shifts left, q_bit enters at LSB
                //
                //  After 32 cycles, quotient holds signed-digit (SD) result.
                //  P holds a partial remainder that may still be negative.
                // -------------------------------------------------------------
                COMPUTE: begin
                    P        <= p_sign ? p_add : p_sub;
                    quotient <= {quotient[30:0], q_bit};
                    cnt      <= cnt + 1'b1;
                    if (cnt == 6'd31)
                        state <= CORRECT;
                end

                // -------------------------------------------------------------
                //  CORRECT: SD→binary conversion + remainder fix + sign apply
                //
                //  BUG 5 FIX (THE KEY MISSING STEP): Convert signed-digit
                //  quotient to ordinary binary.
                //
                //  In NR division each quotient bit encodes +1 (if 1) or -1
                //  (if 0), NOT the usual 0/1.  The decimal value is therefore:
                //
                //    Q_decimal = Q_register - ~Q_register
                //
                //  Example - 7÷2: after 32 steps quotient = ...1001 = 9 (binary)
                //    but represents 8-4-2+1 = 3.
                //    Conversion: 1001 - 0110 = 0011 = 3  ✓
                //
                //  Without this step the output is completely wrong for most
                //  inputs (9 instead of 3 in the example above).
                //
                //  Remainder correction:
                //    If P < 0 after COMPUTE, the true remainder is P + D,
                //    and the true quotient decimal value is Q_decimal - 1.
                //    Apply both before the sign step.
                //
                //  BUG 4 FIX: uses s_is_* (saved in IDLE), not live is_* wires
                // -------------------------------------------------------------
                CORRECT: begin
                    edge_result <= (s_is_div | s_is_divu) ? q_final : r_final;
                    state       <= DONE;
                end

                // -------------------------------------------------------------
                //  DONE
                // -------------------------------------------------------------
                DONE: begin
                    result    <= edge_result;
                    rd_out    <= rd_r;
                    valid_out <= 1'b1;
                    stall     <= 1'b0;
                    state     <= IDLE;
                end

            endcase
        end
    end
endmodule
