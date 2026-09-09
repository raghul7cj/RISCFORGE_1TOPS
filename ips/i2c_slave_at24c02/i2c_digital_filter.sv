//====================================================================
// i2c_digital_filter.sv -- sampled binary sequence filter
//
// This block is deliberately clock-enable based: CLK_DIV controls how often
// the synchronized pins are sampled, but no derived clock domain is created.
// For an even WINDOW_LEN=2*M, a filtered bit changes only after its window is
// exactly M old samples followed by M new samples:
//
//     rise:  00..00 11..11       fall:  11..11 00..00
//
// This is a nonlinear transition validator, not a linear FIR filter.
//====================================================================
`timescale 1ns/1ps

module i2c_digital_filter #(
    parameter int unsigned WIDTH      = 2,
    parameter int unsigned WINDOW_LEN = 8,
    parameter int unsigned CLK_DIV    = 1,
    parameter logic [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b1}}
)(
    input  logic                 i_clk,
    input  logic                 i_rst_n,
    input  logic [WIDTH-1:0]     i_sample,
    output logic [WIDTH-1:0]     o_filtered,
    output logic [WIDTH-1:0]     o_rise,
    output logic [WIDTH-1:0]     o_fall
);

    localparam int unsigned HALF_WINDOW = WINDOW_LEN / 2;
    localparam int unsigned DIV_COUNT_WIDTH =
        (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    localparam logic [WINDOW_LEN-1:0] RISE_PATTERN = {
        {HALF_WINDOW{1'b0}}, {HALF_WINDOW{1'b1}}
    };
    localparam logic [WINDOW_LEN-1:0] FALL_PATTERN = {
        {HALF_WINDOW{1'b1}}, {HALF_WINDOW{1'b0}}
    };

    logic [WINDOW_LEN-1:0] sample_window [0:WIDTH-1];
    wire sample_tick;

    generate
        if (CLK_DIV == 1) begin : g_sample_every_clock
            assign sample_tick = 1'b1;
        end else begin : g_sample_divider
            logic [DIV_COUNT_WIDTH-1:0] div_count;
            localparam logic [DIV_COUNT_WIDTH-1:0] DIV_LAST = CLK_DIV - 1;

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n)
                    div_count <= '0;
                else if (div_count == DIV_LAST)
                    div_count <= '0;
                else
                    div_count <= div_count + 1'b1;
            end

            assign sample_tick = (div_count == DIV_LAST);
        end
    endgenerate

    integer channel;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_filtered <= RESET_VALUE;
            o_rise     <= '0;
            o_fall     <= '0;
            for (channel = 0; channel < WIDTH; channel = channel + 1) begin
                if (RESET_VALUE[channel])
                    sample_window[channel] <= {WINDOW_LEN{1'b1}};
                else
                    sample_window[channel] <= {WINDOW_LEN{1'b0}};
            end
        end else begin
            o_rise <= '0;
            o_fall <= '0;

            if (sample_tick) begin
                for (channel = 0; channel < WIDTH; channel = channel + 1) begin
                    if (i_sample[channel] == o_filtered[channel]) begin
                        // Returning to the accepted level re-arms the exact
                        // old/new pattern. A rejected glitch therefore cannot
                        // contaminate and permanently hide the next real edge.
                        if (o_filtered[channel])
                            sample_window[channel] <= {WINDOW_LEN{1'b1}};
                        else
                            sample_window[channel] <= {WINDOW_LEN{1'b0}};
                    end else begin
                        sample_window[channel] <= {
                            sample_window[channel][WINDOW_LEN-2:0],
                            i_sample[channel]
                        };

                        if (!o_filtered[channel] &&
                            ({sample_window[channel][WINDOW_LEN-2:0],
                              i_sample[channel]} == RISE_PATTERN)) begin
                            o_filtered[channel] <= 1'b1;
                            o_rise[channel]     <= 1'b1;
                        end else if (o_filtered[channel] &&
                                     ({sample_window[channel][WINDOW_LEN-2:0],
                                       i_sample[channel]} == FALL_PATTERN)) begin
                            o_filtered[channel] <= 1'b0;
                            o_fall[channel]     <= 1'b1;
                        end
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (WIDTH < 1)
            $fatal(1, "i2c_digital_filter: WIDTH must be positive");
        if ((WINDOW_LEN < 2) || ((WINDOW_LEN & 1) != 0))
            $fatal(1,
                "i2c_digital_filter: WINDOW_LEN must be even and >= 2");
        if (CLK_DIV < 1)
            $fatal(1, "i2c_digital_filter: CLK_DIV must be >= 1");
    end
`endif

endmodule
