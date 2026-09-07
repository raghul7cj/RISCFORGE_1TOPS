`timescale 1ns/1ps

module apb_timer_tb;

    import uvm_pkg::*;
    import apb_timer_pkg::*;


    parameter APB_ADDR_WIDTH = 12;
    parameter TIMER_CNT      = 2;


    logic HCLK;


    initial begin

        HCLK = 0;

        forever #5 HCLK = ~HCLK;

    end


    apb_timer_if #(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
        .TIMER_CNT(TIMER_CNT)
    ) apb_if (
        .HCLK(HCLK)
    );


    apb_timer #(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
        .TIMER_CNT(TIMER_CNT)
    ) dut (

        .HCLK    (HCLK),
        .HRESETn (apb_if.HRESETn),

        .PADDR   (apb_if.PADDR),
        .PWDATA  (apb_if.PWDATA),
        .PWRITE  (apb_if.PWRITE),
        .PSEL    (apb_if.PSEL),
        .PENABLE (apb_if.PENABLE),

        .PRDATA  (apb_if.PRDATA),
        .PREADY  (apb_if.PREADY),
        .PSLVERR (apb_if.PSLVERR),

        .irq_o   (apb_if.irq_o)

    );


    apb_timer_assertions #(
        .ADDR_WIDTH(APB_ADDR_WIDTH)
    ) sva (

        .HCLK    (HCLK),
        .HRESETn (apb_if.HRESETn),

        .PADDR   (apb_if.PADDR),
        .PWDATA  (apb_if.PWDATA),
        .PWRITE  (apb_if.PWRITE),
        .PSEL    (apb_if.PSEL),
        .PENABLE (apb_if.PENABLE),

        .PREADY  (apb_if.PREADY),
        .PSLVERR (apb_if.PSLVERR),

        .irq_o   (apb_if.irq_o)

    );


    initial begin
        uvm_config_db#(virtual apb_timer_if)::set(null, "*", "vif", apb_if);
        run_test();
    end
endmodule
