//------------------------------------------------------------------------------
// spi_tb_top : instantiates apb_spi_master, the two VIP interfaces, drives
// clock/reset, publishes the virtual interfaces to config_db, and hands off
// to run_test().
//------------------------------------------------------------------------------
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import spi_uvm_pkg::*;

module spi_tb_top;

    localparam int BUFFER_DEPTH   = 10;
    localparam int APB_ADDR_WIDTH = 12;
    localparam int CLK_PERIOD_NS  = 10;

    logic HCLK;
    logic HRESETn;
    logic [1:0] events_o;

    initial HCLK = 1'b0;
    always #(CLK_PERIOD_NS/2) HCLK = ~HCLK;

    initial begin
        HRESETn = 1'b0;
        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
    end

    apb_if #(.APB_ADDR_WIDTH(APB_ADDR_WIDTH)) apb_vif (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),
        .events_o(events_o)
    );

    spi_if spi_vif ();

    apb_spi_master #(
        .BUFFER_DEPTH  (BUFFER_DEPTH),
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
    ) dut (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),
        .PADDR   (apb_vif.PADDR),
        .PWDATA  (apb_vif.PWDATA),
        .PWRITE  (apb_vif.PWRITE),
        .PSEL    (apb_vif.PSEL),
        .PENABLE (apb_vif.PENABLE),
        .PRDATA  (apb_vif.PRDATA),
        .PREADY  (apb_vif.PREADY),
        .PSLVERR (apb_vif.PSLVERR),

        .events_o(events_o),

        .spi_clk (spi_vif.spi_clk),
        .spi_csn0(spi_vif.spi_csn[0]),
        .spi_csn1(spi_vif.spi_csn[1]),
        .spi_csn2(spi_vif.spi_csn[2]),
        .spi_csn3(spi_vif.spi_csn[3]),
        .spi_mode(spi_vif.spi_mode),
        .spi_sdo0(spi_vif.spi_sdo[0]),
        .spi_sdo1(spi_vif.spi_sdo[1]),
        .spi_sdo2(spi_vif.spi_sdo[2]),
        .spi_sdo3(spi_vif.spi_sdo[3]),
        .spi_sdi0(spi_vif.spi_sdi[0]),
        .spi_sdi1(spi_vif.spi_sdi[1]),
        .spi_sdi2(spi_vif.spi_sdi[2]),
        .spi_sdi3(spi_vif.spi_sdi[3])
    );

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_vif);
        uvm_config_db#(virtual spi_if)::set(null, "*", "spi_vif", spi_vif);
        run_test();
    end

    // Waveform dump, enabled with +DUMP on the sim command line.
    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("spi_tb_top.vcd");
            $dumpvars(0, spi_tb_top);
        end
    end

endmodule : spi_tb_top
