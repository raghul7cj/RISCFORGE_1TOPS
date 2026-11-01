`timescale 1ns / 1ps
// Gateway vector: [0] MTIP (cause 7), [12:1] fast causes 27:16.
// Event inputs capture each asserted cycle; edge inputs capture rising edges;
// level inputs pass through. Captures coalesce while pending and win over ack.
module irq_gateway (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [12:0] irq_raw_i,
    input  wire [12:0] edge_mode_i,
    input  wire [12:0] event_mode_i,
    input  wire [12:0] clear_i,
    output wire [12:0] pend_o
);
    reg [12:0] irq_raw_q;
    reg [12:0] pend_q;
    wire [12:0] capture = (irq_raw_i & event_mode_i) |
                          (irq_raw_i & ~irq_raw_q & edge_mode_i);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            irq_raw_q <= 13'b0;
            pend_q <= 13'b0;
        end else begin
            irq_raw_q <= irq_raw_i;
            pend_q <= capture | (pend_q & ~clear_i);
        end
    end

    assign pend_o = (pend_q & (edge_mode_i | event_mode_i)) |
                    (irq_raw_i & ~(edge_mode_i | event_mode_i));
endmodule
