//====================================================================
// at24c02_device.sv -- AT24C02 transaction/application behavior
//
// This block contains no SCL/SDA logic.  It consumes a selected target byte
// stream and drives a single-port byte memory.  The separation is deliberate:
// another I2C target, SPI front-end or test port can reuse the storage-facing
// device behavior without containing open-drain or bit-timing logic.
//====================================================================
`timescale 1ns/1ps

module at24c02_device #(
    parameter int unsigned WRITE_CYCLE_CLKS = 64
)(
    input  logic       i_clk,
    input  logic       i_rst_n,
    input  logic       i_wp,

    // Transaction/byte-stream side (normally from i2c_target_core).
    input  logic       i_start,
    input  logic       i_stop,
    input  logic       i_selected,
    input  logic       i_rw,
    input  logic       i_rx_valid,
    input  logic [7:0] i_rx_data,
    input  logic       i_tx_take,
    output logic [7:0] o_tx_data,
    output logic       o_busy,

    // Replaceable 256 x 8 backing-store port.
    output logic [7:0] o_mem_addr,
    output logic       o_mem_we,
    output logic [7:0] o_mem_wdata,
    input  logic [7:0] i_mem_rdata
);

    localparam int unsigned BUSY_W = $clog2(WRITE_CYCLE_CLKS + 1);

    logic [7:0] current_addr;
    logic       expect_word_addr;
    logic       selected_d;

    // The real part buffers one physical eight-byte page and commits it after
    // STOP. Repeated writes to a wrapped offset overwrite the buffered byte.
    logic [7:0] page_buf [0:7];
    logic [7:0] page_valid;
    logic [4:0] page_row;
    logic [2:0] page_index;

    logic              commit_active;
    logic [2:0]        commit_index;
    logic [BUSY_W-1:0] busy_count;

    wire selected_rise = i_selected && !selected_d;

    assign o_busy = (busy_count != '0);
    assign o_tx_data = i_mem_rdata;

    // The backing memory is not needed by the bus while the device NACKs
    // during its write cycle, so one port can serve commit and read access.
    always_comb begin
        o_mem_addr  = current_addr;
        o_mem_we    = 1'b0;
        o_mem_wdata = 8'd0;
        if (commit_active) begin
            o_mem_addr  = {page_row, commit_index};
            o_mem_we    = page_valid[commit_index];
            o_mem_wdata = page_buf[commit_index];
        end
    end

    integer idx;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            current_addr     <= 8'd0;
            expect_word_addr <= 1'b0;
            selected_d       <= 1'b0;
            page_valid       <= 8'd0;
            page_row         <= 5'd0;
            page_index       <= 3'd0;
            commit_active    <= 1'b0;
            commit_index     <= 3'd0;
            busy_count       <= '0;
            for (idx = 0; idx < 8; idx = idx + 1)
                page_buf[idx] <= 8'hff;
        end else begin
            selected_d <= i_selected;

            if (busy_count != '0)
                busy_count <= busy_count - 1'b1;

            // Commit at most one buffered byte per controller clock.  Busy
            // remains asserted longer than the eight commit slots.
            if (commit_active) begin
                if (commit_index == 3'd7) begin
                    commit_active <= 1'b0;
                    page_valid    <= 8'd0;
                end else begin
                    commit_index <= commit_index + 3'd1;
                end
            end

            // START also covers repeated START. An uncommitted page write is
            // abandoned; the normal random-read dummy write has no data bytes
            // and therefore loses nothing here.
            if (i_start && !o_busy) begin
                page_valid       <= 8'd0;
                expect_word_addr <= 1'b0;
            end

            // A matched write-address byte makes the first following byte the
            // eight-bit EEPROM word address.
            if (selected_rise && !i_rw && !o_busy) begin
                expect_word_addr <= 1'b1;
                page_valid       <= 8'd0;
            end

            if (i_rx_valid && i_selected && !i_rw && !o_busy) begin
                if (expect_word_addr) begin
                    current_addr     <= i_rx_data;
                    page_row         <= i_rx_data[7:3];
                    page_index       <= i_rx_data[2:0];
                    expect_word_addr <= 1'b0;
                end else if (!i_wp) begin
                    page_buf[page_index]   <= i_rx_data;
                    page_valid[page_index] <= 1'b1;
                    page_index             <= page_index + 3'd1;
                    current_addr           <= {page_row, page_index + 3'd1};
                end
            end

            // i_tx_take means the current combinational byte has been loaded
            // by the target transport. Sequential reads wrap across 0xff.
            if (i_tx_take && i_selected && i_rw && !o_busy)
                current_addr <= current_addr + 8'd1;

            // A STOP commits buffered data and starts the NACK/busy interval.
            if (i_stop && (|page_valid) && !o_busy) begin
                commit_active    <= 1'b1;
                commit_index     <= 3'd0;
                busy_count       <= WRITE_CYCLE_CLKS[BUSY_W-1:0];
                expect_word_addr <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (WRITE_CYCLE_CLKS < 9)
            $fatal(1, "at24c02_device: WRITE_CYCLE_CLKS must be >= 9");
    end
`endif

endmodule
