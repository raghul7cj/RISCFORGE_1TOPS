// I2C physical-layer wrapper: open-drain pin drive, synchronized/optionally
// filtered sampling, and START/STOP edge detection. It is protocol agnostic.
//====================================================================
// i2c_drv.sv -- I2C open-drain physical driver
//
// 职责：
//   - 开漏输出驱动：0=拉低，1=释放（配合外部上拉）
//   - 输入两级同步采样，防亚稳态
//   - START/STOP 总线事件检测
//
// 本模块只负责"线"，不关心协议内容。
// 更换平台（IOBUF / OD 原语）时只需修改本层。
//====================================================================
`timescale 1ns/1ps
module i2c_drv #(
    parameter bit          FILTER_EN         = 1'b0,
    parameter int unsigned FILTER_WINDOW     = 8,
    parameter int unsigned FILTER_CLK_DIV    = 1
)(
    input  wire i_clk,
    input  wire i_rst_n,

    // 输出驱动（0=拉低, 1=释放）
    input  wire i_scl_out,
    input  wire i_sda_out,

    // 同步采样回读
    output wire o_scl_in,
    output wire o_sda_in,

    // 总线事件（同步后检测，脉冲）
    output wire o_start_det,   // SCL=1 期间 SDA 1->0
    output wire o_stop_det,    // SCL=1 期间 SDA 0->1

    // 物理引脚（仿真时需外部 pullup）
    inout  wire io_scl,
    inout  wire io_sda
);

    //------------------------------------------------------------------
    // 输入同步（两级触发器）
    //------------------------------------------------------------------
    reg scl_ff1, scl_ff2;
    reg sda_ff1, sda_ff2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            scl_ff1   <= 1'b1;
            scl_ff2   <= 1'b1;
            sda_ff1   <= 1'b1;
            sda_ff2   <= 1'b1;
        end else begin
            scl_ff1   <= io_scl;
            scl_ff2   <= scl_ff1;
            sda_ff1   <= io_sda;
            sda_ff2   <= sda_ff1;
        end
    end

    wire [1:0] synchronized_lines = {scl_ff2, sda_ff2};
    wire [1:0] observed_lines;

    generate
        if (FILTER_EN) begin : g_digital_filter
            i2c_digital_filter #(
                .WIDTH(2), .WINDOW_LEN(FILTER_WINDOW),
                .CLK_DIV(FILTER_CLK_DIV), .RESET_VALUE(2'b11)
            ) u_filter (
                .i_clk(i_clk), .i_rst_n(i_rst_n),
                .i_sample(synchronized_lines),
                .o_filtered(observed_lines), .o_rise(), .o_fall()
            );
        end else begin : g_filter_bypass
            assign observed_lines = synchronized_lines;
        end
    endgenerate

    assign o_scl_in = observed_lines[1];
    assign o_sda_in = observed_lines[0];

    reg [1:0] observed_lines_d;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            observed_lines_d <= 2'b11;
        else
            observed_lines_d <= observed_lines;
    end

    //------------------------------------------------------------------
    // 事件检测：SCL 高电平期间 SDA 跳变
    //------------------------------------------------------------------
    assign o_start_det = observed_lines[1] &&
                         observed_lines_d[0] && ~observed_lines[0];

    assign o_stop_det  = observed_lines[1] &&
                         ~observed_lines_d[0] && observed_lines[0];

    //------------------------------------------------------------------
    // 开漏输出（线与逻辑）
    //------------------------------------------------------------------
    assign io_scl = i_scl_out ? 1'bz : 1'b0;
    assign io_sda = i_sda_out ? 1'bz : 1'b0;

endmodule
