//====================================================================
// i2c_target_endpoint.sv -- reusable standalone I2C target transport
//
// Standalone device models normally need exactly this repeated shell:
// open-drain pin handling + address/ACK/byte transport.  Device/application
// logic plugs into the byte stream and never touches SCL or SDA.  i_rx_ready
// provides byte-boundary backpressure: a low value makes the transport NACK a
// master write instead of claiming data that the application cannot retain.
//====================================================================
`timescale 1ns/1ps

module i2c_target_endpoint #(
    parameter bit          FILTER_EN      = 1'b0,
    parameter int unsigned FILTER_WINDOW  = 8,
    parameter int unsigned FILTER_CLK_DIV = 1
)(
    input  logic       i_clk,
    input  logic       i_rst_n,
    input  logic       i_en,
    input  logic [6:0] i_addr,

    input  logic [7:0] i_tx_data,
    input  logic       i_rx_ready,
    output logic       o_tx_take,
    output logic [7:0] o_rx_data,
    output logic       o_rx_valid,
    output logic       o_selected,
    output logic       o_read,
    output logic       o_transport_busy,
    output logic       o_start,
    output logic       o_stop,

    inout  wire        io_scl,
    inout  wire        io_sda
);

    wire scl_in;
    wire sda_in;
    wire target_sda_out;

    i2c_drv #(
        .FILTER_EN(FILTER_EN), .FILTER_WINDOW(FILTER_WINDOW),
        .FILTER_CLK_DIV(FILTER_CLK_DIV)
    ) u_drv (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_scl_out(1'b1),
        .i_sda_out(target_sda_out), .o_scl_in(scl_in),
        .o_sda_in(sda_in), .o_start_det(o_start), .o_stop_det(o_stop),
        .io_scl(io_scl), .io_sda(io_sda)
    );

    i2c_target_core u_target (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_scl_in(scl_in),
        .i_sda_in(sda_in), .i_start_det(o_start), .i_stop_det(o_stop),
        .i_en(i_en), .i_addr(i_addr), .i_tx_data(i_tx_data),
        .o_tx_data_pop(o_tx_take), .i_rx_ready(i_rx_ready),
        .o_rx_data(o_rx_data),
        .o_rx_valid(o_rx_valid), .o_busy(o_transport_busy),
        .o_addr_match(o_selected), .o_rw(o_read),
        .o_sda_out(target_sda_out)
    );

endmodule
