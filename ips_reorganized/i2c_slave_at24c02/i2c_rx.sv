// Byte receiver used by i2c_ctrl.
// Samples SDA at the controller-selected high-phase sample point and shifts
// MSB-first data into an eight-bit result.
//====================================================================
// i2c_rx.sv -- I2C byte receiver
//
// 职责：
//   - 在采样窗口逐位采样 SDA，移位拼字节（MSB 先，bit7 先采样）
//   - 收满 8 位输出 o_done 脉冲与字节数据
//   - o_data 随移位实时更新，o_done 脉冲时采样
//
// 时序：
//   i_sample: SCL 高段中点（sample_point），每个数据位一个脉冲
//   o_done:   第 8 位采样后置 1（持续一拍），同时 o_data 完整
//
// 纯接收逻辑，不含协议状态机，由控制器调度。
//====================================================================
module i2c_rx (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_clr,       // 同步清除当前未完成字节

    input  wire       i_sda_in,  // 总线 SDA（同步采样值）
    input  wire       i_sample,  // 采样窗口使能（SCL 高电平中点）

    output      [7:0] o_data,
    output reg        o_done     // 8 位收完（脉冲）
);

    reg [7:0] shift_reg;
    reg [3:0] bit_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            shift_reg <= 8'd0;
            bit_cnt   <= 4'd0;
            o_done    <= 1'b0;
        end else if (i_clr) begin
            shift_reg <= 8'd0;
            bit_cnt   <= 4'd0;
            o_done    <= 1'b0;
        end else begin
            o_done <= 1'b0;
            if (i_sample) begin
                shift_reg <= {shift_reg[6:0], i_sda_in};
                if (bit_cnt == 4'd7) begin
                    bit_cnt <= 4'd0;
                    o_done  <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 4'd1;
                end
            end
        end
    end

    assign o_data = shift_reg;

endmodule
