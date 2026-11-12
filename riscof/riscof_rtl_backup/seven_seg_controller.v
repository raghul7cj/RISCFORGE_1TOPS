`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: seven_seg_controller
// Description: 8-Digit Hexadecimal 7-Segment Display Controller for Nexys 4 DDR
//////////////////////////////////////////////////////////////////////////////////

module seven_seg_controller(
    input             clk,       // 100 MHz board clock
    input             rst,       // Active-high reset
    input      [31:0] data_in,   // 32-bit hex value to display
    output reg [7:0]  anode,     // AN[7:0] (active low digit enable)
    output reg [6:0]  cathode    // CA-CG (active low segments)
);

    // Refresh counter for ~1 kHz multiplexing rate
    reg [19:0] refresh_counter = 0;
    always @(posedge clk or posedge rst) begin
        if (rst)
            refresh_counter <= 20'd0;
        else
            refresh_counter <= refresh_counter + 1'b1;
    end

    wire [2:0] digit_sel = refresh_counter[19:17]; // 8 states for 8 digits
    reg  [3:0] hex_digit;

    // Anode & Nibble multiplexer
    always @(*) begin
        case (digit_sel)
            3'd0: begin anode = 8'b11111110; hex_digit = data_in[3:0];   end
            3'd1: begin anode = 8'b11111101; hex_digit = data_in[7:4];   end
            3'd2: begin anode = 8'b11111011; hex_digit = data_in[11:8];  end
            3'd3: begin anode = 8'b11110111; hex_digit = data_in[15:12]; end
            3'd4: begin anode = 8'b11101111; hex_digit = data_in[19:16]; end
            3'd5: begin anode = 8'b11011111; hex_digit = data_in[23:20]; end
            3'd6: begin anode = 8'b10111111; hex_digit = data_in[27:24]; end
            3'd7: begin anode = 8'b01111111; hex_digit = data_in[31:28]; end
            default: begin anode = 8'b11111111; hex_digit = 4'h0; end
        endcase
    end

    // Hex-to-Segment Cathode Decoder (Active LOW: CA, CB, CC, CD, CE, CF, CG)
    always @(*) begin
        case (hex_digit)
            4'h0: cathode = 7'b0000001; // 0
            4'h1: cathode = 7'b1001111; // 1
            4'h2: cathode = 7'b0010010; // 2
            4'h3: cathode = 7'b0000110; // 3
            4'h4: cathode = 7'b1001100; // 4
            4'h5: cathode = 7'b0100100; // 5
            4'h6: cathode = 7'b0100000; // 6
            4'h7: cathode = 7'b0001111; // 7
            4'h8: cathode = 7'b0000000; // 8
            4'h9: cathode = 7'b0000100; // 9
            4'hA: cathode = 7'b0001000; // A
            4'hB: cathode = 7'b1100000; // b
            4'hC: cathode = 7'b0110001; // C
            4'hD: cathode = 7'b1000010; // d
            4'hE: cathode = 7'b0110000; // E
            4'hF: cathode = 7'b0111000; // F
            default: cathode = 7'b1111111;
        endcase
    end

endmodule
