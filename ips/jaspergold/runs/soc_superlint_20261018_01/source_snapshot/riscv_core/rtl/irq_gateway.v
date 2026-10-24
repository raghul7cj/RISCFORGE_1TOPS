`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: irq_gateway
// Description:
//   Hardened interrupt capture gateway for RISCFORGE SoC.
//   Captures single-cycle peripheral pulses on edge-triggered lines with
//   a registered edge detector and pulse-wins latch precedence.
//   Level-triggered lines are passed through combinationally.
//
// Inputs:
//   irq_raw_i[5:0]   : {Watchdog, Timer0, UART, SPI, I2C, GPIO}
//   edge_mode_i[5:0] : Static mode configuration (1=Edge, 0=Level)
//                      Default: 6'b110101 (WD, Timer0, SPI, GPIO are Edge; UART, I2C are Level)
//   clear_i[5:0]     : 1-cycle commit strobe from Writeback stage
// Outputs:
//   pend_o[5:0]      : Qualified pending vector to irq_arbiter & CSR mip
//////////////////////////////////////////////////////////////////////////////////

module irq_gateway (
    input  wire       clk_i,
    input  wire       rst_ni,

    input  wire [5:0] irq_raw_i,
    input  wire [5:0] edge_mode_i,
    input  wire [5:0] clear_i,

    output wire [5:0] pend_o
);

    // Registered edge detection flops
    reg [5:0] irq_raw_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            irq_raw_q <= 6'b000000;
        end else begin
            irq_raw_q <= irq_raw_i;
        end
    end

    // Positive rising edge detector
    wire [5:0] edge_detect = irq_raw_i & ~irq_raw_q;

    // Sticky latch with strict pulse-wins precedence
    reg [5:0] pend_q;
    integer k;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pend_q <= 6'b000000;
        end else begin
            for (k = 0; k < 6; k = k + 1) begin
                if (edge_detect[k]) begin
                    pend_q[k] <= 1'b1; // New rising edge strictly wins over clear
                end else if (clear_i[k]) begin
                    pend_q[k] <= 1'b0;
                end
            end
        end
    end

    // Output assignment: Edge lines use sticky latch, Level lines bypass latch
    genvar i;
    generate
        for (i = 0; i < 6; i = i + 1) begin : gen_pend_out
            assign pend_o[i] = edge_mode_i[i] ? pend_q[i] : irq_raw_i[i];
        end
    endgenerate

endmodule
