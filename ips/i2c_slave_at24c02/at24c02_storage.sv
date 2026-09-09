//====================================================================
// at24c02_storage.sv -- replaceable inferred 256 x 8 EEPROM backing store
//
// This is a volatile synthesizable memory implementation. ASIC users can
// replace this module with an NVM/SRAM macro wrapper without touching either
// the AT24C02 transaction behavior or the I2C target transport.
//====================================================================
`timescale 1ns/1ps

module at24c02_storage #(
    parameter logic [7:0] SIM_INIT_VALUE = 8'hff
)(
    input  logic       i_clk,
    input  logic [7:0] i_addr,
    input  logic       i_we,
    input  logic [7:0] i_wdata,
    output logic [7:0] o_rdata
);

    logic [7:0] mem [0:255];

    // Plain always is intentional: the optional simulation initializer is a
    // second procedural source that old VCS correctly rejects with always_ff.
    always @(posedge i_clk) begin
        if (i_we)
            mem[i_addr] <= i_wdata;
    end

    assign o_rdata = mem[i_addr];

`ifndef SYNTHESIS
    integer idx;
    initial begin
        for (idx = 0; idx < 256; idx = idx + 1)
            mem[idx] = SIM_INIT_VALUE;
    end
`endif

endmodule
