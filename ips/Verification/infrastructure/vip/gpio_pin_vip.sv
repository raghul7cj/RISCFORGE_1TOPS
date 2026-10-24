/* =============================================================================
 * RISCFORGE 1TOPS — Lightweight GPIO Pin BFM (gpio_pin_vip.sv)
 * Emulates external pin loopback, pullups, and external stimulus drive
 * ============================================================================= */

`timescale 1ns / 1ps

module gpio_pin_vip #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] gpio_out_o,  /* Output driven by SoC */
    input  logic [WIDTH-1:0] gpio_oe_o,   /* Output enable driven by SoC */
    output logic [WIDTH-1:0] gpio_in_i    /* Input sampled by SoC */
);

    /* Testbench stimulus injection control */
    logic [WIDTH-1:0] ext_drive_en;
    logic [WIDTH-1:0] ext_drive_data;
    logic             loopback_en;

    initial begin
        ext_drive_en   = '0;
        ext_drive_data = '0;
        loopback_en    = 1'b1; // Default: Loopback SoC outputs to inputs
    end

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : gen_pin
            assign gpio_in_i[i] = (ext_drive_en[i])              ? ext_drive_data[i] :
                                  (loopback_en && gpio_oe_o[i])  ? gpio_out_o[i] :
                                  1'b0; // Default pull-down
        end
    endgenerate

    /* Tasks for stimulus control */
    task automatic set_loopback(input logic enable);
        loopback_en = enable;
    endtask

    task automatic inject_pin_value(input int pin_idx, input logic val);
        ext_drive_en[pin_idx]   = 1'b1;
        ext_drive_data[pin_idx] = val;
    endtask

    task automatic release_pin(input int pin_idx);
        ext_drive_en[pin_idx]   = 1'b0;
    endtask

endmodule
