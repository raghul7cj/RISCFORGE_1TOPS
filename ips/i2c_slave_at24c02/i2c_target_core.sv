//====================================================================
// i2c_target_core.sv -- I2C target core (address match, data and ACK)
//
// 与主机不同：从机不使用 clkgen，全靠 scl_pos/scl_neg 边沿驱动。
//   - 接收（RX）：scl_pos 采样 SDA → 通过 i2c_rx 模块拼字节
//   - 发送（TX）：scl_neg 驱动 SDA → 内建移位寄存器，MSB 先
//   - ACK：     scl_neg 拉低 SDA，保持到下一个 scl_neg
//
// 接口：使用 drv 同步后的 scl_in/sda_in 和 start_det/stop_det 事件。
//====================================================================
`timescale 1ns/1ps
module i2c_target_core #(
    parameter [6:0] DEF_ADDR = 7'h50
)(
    input  wire i_clk,
    input  wire i_rst_n,

    // I2C 总线（来自 drv，已两级同步）
    input  wire i_scl_in,       // 同步后的 SCL
    input  wire i_sda_in,       // 同步后的 SDA
    input  wire i_start_det,    // START 条件脉冲
    input  wire i_stop_det,     // STOP 条件脉冲

    // Target-application byte stream. The transport knows nothing about the
    // meaning of these bytes (FIFO peripheral, EEPROM, sensor, and so on).
    input  wire       i_en,           // 从机使能
    input  wire [6:0] i_addr,         // 本机地址
    input  wire [7:0] i_tx_data,      // 读模式当前待发数据
    output reg        o_tx_data_pop,  // 已取用 i_tx_data（脉冲，可直接推进 TX FIFO）
    input  wire       i_rx_ready,     // 1=应用层可接收下一个主机写字节

    // 状态输出
    output wire [7:0] o_rx_data,      // 写模式收到的字节
    output wire       o_rx_valid,     // 收到字节脉冲
    output wire       o_busy,         // 从机忙（非 IDLE）
    output wire       o_addr_match,   // 地址匹配（含 RSTART 后重新匹配）
    output wire       o_rw,           // 0=主机写（从机收） 1=主机读（从机发）

    // SDA 驱动（与主机 AND 后送 drv）
    output reg        o_sda_out       // 0=拉低 1=释放
);

    //==================================================================
    // 边沿检测（~prev & curr），drv 已做两级同步
    // scl_in_d / sda_in_d 寄存器在 always 块中更新
    //==================================================================
    reg  scl_in_d;
    wire scl_pos =  i_scl_in && !scl_in_d;
    wire scl_neg = !i_scl_in &&  scl_in_d;

    //==================================================================
    // 状态机
    //   S_IDLE        — 等 START
    //   S_START_WAIT  — START 后等 SCL 下降沿再进入地址接收
    //   S_ADDR        — 收地址字节（scl_pos 采样）
    //   S_ACK_PULL    — 拉低 ACK（scl_neg）
    //   S_ACK_HOLD    — 保持 ACK，决定读写方向
    //   S_RX_DATA     — 收数据（写模式）
    //   S_TX_DATA     — 发数据（读模式）
    //   S_RX_ACK      — 等主机 ACK/NACK（读模式）
    //==================================================================
    localparam [2:0] S_IDLE       = 3'd0,
                     S_START_WAIT = 3'd1,
                     S_ADDR       = 3'd2,
                     S_ACK_PULL   = 3'd3,
                     S_ACK_HOLD   = 3'd4,
                     S_RX_DATA    = 3'd5,
                     S_TX_DATA    = 3'd6,
                     S_RX_ACK     = 3'd7;

    reg [2:0] s_state;
    reg       s_rw;            // 0=写(收) 1=读(发)
    reg       s_ack_drive;     // 本次 ACK 位是否拉低 SDA
    reg [7:0] s_shift;         // 发数据移位寄存器
    reg [3:0] s_bit_cnt;       // 发数据位计数（0..7），scl_pos 递增

    //==================================================================
    // rx 模块 — 寄存器 scl_pos 采样（延迟 1 拍，给 sda_in 稳定时间）
    //==================================================================
    wire       rx_done;
    wire [7:0] rx_data;
    reg        rx_sample;

    i2c_rx u_rx (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_clr    (i_start_det || i_stop_det),
        .i_sda_in (i_sda_in),
        .i_sample (rx_sample),
        .o_data   (rx_data),
        .o_done   (rx_done)
    );

    // rx_done 时锁存数据，避免后续 STOP 周期冲掉 rx shift_reg
    reg  [7:0] s_rx_latched;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) s_rx_latched <= 8'd0;
        else if (rx_done && (s_state == S_RX_DATA || s_state == S_ADDR))
            s_rx_latched <= rx_data;
    end
    // rx_done 有效的这一拍，s_rx_latched 尚未完成 NBA 更新。
    // 因此有效窗口直接输出 rx_data，其余时间输出锁存值。
    assign o_rx_data  = rx_done ? rx_data : s_rx_latched;
    assign o_rw       = s_rw;
    assign o_addr_match = (s_state == S_ACK_PULL || s_state == S_ACK_HOLD ||
                           s_state == S_RX_DATA || s_state == S_TX_DATA ||
                           s_state == S_RX_ACK);
    assign o_busy     = (s_state != S_IDLE);

    //==================================================================
    // 时序逻辑
    //==================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            s_state      <= S_IDLE;
            scl_in_d     <= 1'b1;
            s_rw         <= 1'b0;
            s_ack_drive  <= 1'b0;
            s_shift      <= 8'h55;        // 上电默认返回数据
            o_sda_out    <= 1'b1;
            rx_sample    <= 1'b0;
            o_tx_data_pop <= 1'b0;
        end else begin
            scl_in_d <= i_scl_in;
            o_tx_data_pop <= 1'b0;

            //----------------------------------------------------------
            // START / repeated START — 从任意状态重新开始地址帧。
            // drv 只在同步后的 SCL 高电平检测 SDA 1→0，正常数据位
            // 在 SCL 低电平变更，不会与 repeated START 混淆。
            //----------------------------------------------------------
            if (i_start_det) begin
                s_state   <= i_en ? S_START_WAIT : S_IDLE;
                s_rw      <= 1'b0;
                s_ack_drive <= 1'b0;
                o_sda_out <= 1'b1;
            end
            //----------------------------------------------------------
            // STOP — 回 IDLE
            //----------------------------------------------------------
            else if (i_stop_det) begin
                s_state   <= S_IDLE;
                o_sda_out <= 1'b1;
            end
            //----------------------------------------------------------
            // 正常状态机 — 不包含 START/STOP（上面处理了）
            //----------------------------------------------------------
            else begin
                case (s_state)

                //------------------------------------------------------
                // S_START_WAIT: 等 SCL 下降沿 → S_ADDR
                //   目的：跳过 START 周期内残留的 SCL 高段，
                //   确保 scl_pos 只来自真正的数据位
                //------------------------------------------------------
                S_START_WAIT: begin
                    rx_sample <= 1'b0;
                    if (scl_neg) begin
                        s_state <= S_ADDR;
                    end
                end

                //------------------------------------------------------
                // S_ADDR: scl_pos 采样收地址 → rx_done 时切换
                //------------------------------------------------------
                S_ADDR: begin
                    rx_sample <= scl_pos;
                    if (rx_done) begin
                        if (rx_data[7:1] == i_addr) begin
                            s_rw        <= rx_data[0];
                            // Reads do not consume RX capacity.  For a write,
                            // reject the address immediately when the
                            // application cannot accept even the first byte.
                            s_ack_drive <= rx_data[0] || i_rx_ready;
                            s_state     <= S_ACK_PULL;
                        end else begin
                            // 地址不匹配：回 IDLE，等 STOP 或下一个 START
                            s_state <= S_IDLE;
                        end
                    end
                end

                //------------------------------------------------------
                // S_ACK_PULL: scl_neg 拉低 SDA → S_ACK_HOLD
                //------------------------------------------------------
                S_ACK_PULL: begin
                    rx_sample <= 1'b0;
                    if (scl_neg) begin
                        // Open-drain ACK=0, NACK=release.  The decision was
                        // captured with the address/data byte so a later FIFO
                        // status change cannot alter an ACK already in flight.
                        o_sda_out <= !s_ack_drive;
                        s_state   <= S_ACK_HOLD;
                    end
                end

                //------------------------------------------------------
                // S_ACK_HOLD: 保持 ACK 到下一个 scl_neg，然后进入收发
                //------------------------------------------------------
                S_ACK_HOLD: begin
                    rx_sample <= 1'b0;
                    if (scl_neg) begin
                        if (!s_ack_drive) begin
                            // The write address or payload was rejected because
                            // i_rx_ready was low.  Wait for STOP or a repeated
                            // START without accepting more bytes from this
                            // transfer.
                            o_sda_out <= 1'b1;
                            s_state   <= S_IDLE;
                        end else if (s_rw) begin
                            // 读模式：预载 MSB 到 SDA，移位寄存器装填 bit6..0
                            s_shift   <= {i_tx_data[6:0], 1'b0};
                            o_sda_out <= i_tx_data[7];
                            s_bit_cnt <= 4'd0;
                            s_state   <= S_TX_DATA;
                            o_tx_data_pop <= 1'b1;
                        end else begin
                            // 写模式：释放 SDA，准备收数据
                            o_sda_out <= 1'b1;
                            s_state   <= S_RX_DATA;
                        end
                    end
                end

                //------------------------------------------------------
                // S_RX_DATA: scl_pos 采样 → rx_done → 锁存 → 回 ACK
                //   主机可能发多个字节，每个字节后回 ACK
                //------------------------------------------------------
                S_RX_DATA: begin
                    rx_sample <= scl_pos;
                    if (rx_done) begin
                        // Sample ready at the byte boundary.  Full FIFOs are
                        // reported to the master as NACK instead of ACKing and
                        // then silently discarding the byte.
                        s_ack_drive <= i_rx_ready;
                        s_state     <= S_ACK_PULL;
                    end
                end

                //------------------------------------------------------
                // S_TX_DATA: scl_neg 驱动数据 + 移位，scl_pos 计数
                //   第 1 个 scl_neg 驱动 bit6（MSB 已在 S_ACK_HOLD 预载）
                //   发完 8 位（bit0 驱动完）→ S_RX_ACK
                //------------------------------------------------------
                S_TX_DATA: begin
                    rx_sample <= 1'b0;
                    if (scl_neg) begin
                        o_sda_out <= s_shift[7];
                        s_shift   <= {s_shift[6:0], 1'b0};
                    end
                    if (scl_pos) begin
                        if (s_bit_cnt == 4'd7)
                            s_state <= S_RX_ACK;
                        else
                            s_bit_cnt <= s_bit_cnt + 4'd1;
                    end
                end

                //------------------------------------------------------
                // S_RX_ACK: scl_neg 释放 SDA → scl_pos 采样主机 ACK
                //   主机 ACK(0) → 继续发下一字节
                //   主机 NACK(1) → 回 IDLE
                //------------------------------------------------------
                S_RX_ACK: begin
                    rx_sample <= 1'b0;
                    if (scl_neg)
                        o_sda_out <= 1'b1;
                    if (scl_pos) begin
                        if (!i_sda_in) begin
                            // 主机 ACK：装填下一字节（不预移位，由首 scl_neg 驱动 MSB）
                            s_shift   <= i_tx_data;
                            s_bit_cnt <= 4'd0;
                            s_state   <= S_TX_DATA;
                            o_tx_data_pop <= 1'b1;
                        end else begin
                            // 主机 NACK：结束
                            s_state <= S_IDLE;
                        end
                    end
                end

                default: ;
                endcase
            end
        end
    end

    //==================================================================
    // o_rx_valid — 写模式收到字节的脉冲
    //   S_RX_DATA 中 rx_done 那一拍
    //==================================================================
    reg rx_done_d;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) rx_done_d <= 1'b0;
        else          rx_done_d <= rx_done;
    end
    assign o_rx_valid = rx_done && !rx_done_d && (s_state == S_RX_DATA);

endmodule
