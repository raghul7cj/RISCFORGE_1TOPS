//====================================================================
// i2c_at24c02.sv -- complete synthesizable AT24C02-compatible I2C target
//====================================================================
`timescale 1ns/1ps

module i2c_at24c02 #(
    parameter logic [2:0] HW_ADDR = 3'b000,
    parameter int unsigned WRITE_CYCLE_CLKS = 64,
    parameter logic [7:0] SIM_INIT_VALUE = 8'hff,
    parameter bit          PHY_FILTER_EN = 1'b0,
    parameter int unsigned PHY_FILTER_WINDOW = 8,
    parameter int unsigned PHY_FILTER_CLK_DIV = 1
)(
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_wp,
    output logic o_busy,
    inout  wire  io_scl,
    inout  wire  io_sda
);

    localparam logic [6:0] I2C_ADDR = 7'b1010000 | HW_ADDR;

    wire start_det;
    wire stop_det;
    wire [7:0] rx_data;
    wire rx_valid;
    wire selected;
    wire rw;
    wire tx_take;
    wire [7:0] tx_data;

    wire [7:0] mem_addr;
    wire mem_we;
    wire [7:0] mem_wdata;
    wire [7:0] mem_rdata;

    i2c_target_endpoint #(
        .FILTER_EN(PHY_FILTER_EN), .FILTER_WINDOW(PHY_FILTER_WINDOW),
        .FILTER_CLK_DIV(PHY_FILTER_CLK_DIV)
    ) u_endpoint (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_en(!o_busy),
        .i_addr(I2C_ADDR), .i_tx_data(tx_data), .i_rx_ready(1'b1),
        .o_tx_take(tx_take),
        .o_rx_data(rx_data), .o_rx_valid(rx_valid),
        .o_selected(selected), .o_read(rw), .o_transport_busy(),
        .o_start(start_det), .o_stop(stop_det),
        .io_scl(io_scl), .io_sda(io_sda)
    );

    at24c02_device #(
        .WRITE_CYCLE_CLKS(WRITE_CYCLE_CLKS)
    ) u_device (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_wp(i_wp),
        .i_start(start_det), .i_stop(stop_det), .i_selected(selected),
        .i_rw(rw), .i_rx_valid(rx_valid), .i_rx_data(rx_data),
        .i_tx_take(tx_take), .o_tx_data(tx_data), .o_busy(o_busy),
        .o_mem_addr(mem_addr), .o_mem_we(mem_we),
        .o_mem_wdata(mem_wdata), .i_mem_rdata(mem_rdata)
    );

    at24c02_storage #(
        .SIM_INIT_VALUE(SIM_INIT_VALUE)
    ) u_storage (
        .i_clk(i_clk), .i_addr(mem_addr), .i_we(mem_we),
        .i_wdata(mem_wdata), .o_rdata(mem_rdata)
    );

endmodule
