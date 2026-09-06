//------------------------------------------------------------------------------
// apb_if : APB3 interface toward apb_spi_master's PADDR/PWDATA/... port group.
//------------------------------------------------------------------------------
interface apb_if #(
    parameter int APB_ADDR_WIDTH = 12
) (
    input logic       HCLK,
    input logic       HRESETn,
    input logic [1:0] events_o  // sideband: events_o[0]=int_tx|int_rx, events_o[1]=eot pulse
);

    logic [APB_ADDR_WIDTH-1:0] PADDR;
    logic [31:0]                PWDATA;
    logic                       PWRITE;
    logic                       PSEL;
    logic                       PENABLE;
    logic [31:0]                PRDATA;
    logic                       PREADY;
    logic                       PSLVERR;

    clocking drv_cb @(posedge HCLK);
        default input #1step output #1;
        output PADDR, PWDATA, PWRITE, PSEL, PENABLE;
        input  PRDATA, PREADY, PSLVERR;
    endclocking

    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input PADDR, PWDATA, PWRITE, PSEL, PENABLE, PRDATA, PREADY, PSLVERR, events_o;
    endclocking

    modport driver   (clocking drv_cb, input HCLK, HRESETn, events_o);
    modport monitor  (clocking mon_cb, input HCLK, HRESETn, events_o);

    // Passive DUT-facing modport used at the top level to hook the interface
    // directly to the apb_spi_master port list.
    modport dut (
        input  HCLK, HRESETn, PADDR, PWDATA, PWRITE, PSEL, PENABLE,
        output PRDATA, PREADY, PSLVERR,
        input  events_o
    );

`ifndef SYNTHESIS
    // Basic protocol assertion: PADDR/PWDATA/PWRITE must be stable across
    // the SETUP->ACCESS phase (PSEL high, PENABLE low -> PENABLE high).
    property p_addr_stable_during_access;
        @(posedge HCLK) disable iff (!HRESETn)
        (PSEL && PENABLE && $past(PSEL) && $past(!PENABLE)) |->
            ($stable(PADDR) && $stable(PWRITE));
    endproperty
    a_addr_stable_during_access: assert property (p_addr_stable_during_access)
        else $error("[apb_if] PADDR/PWRITE changed between SETUP and ACCESS phase");
`endif

endinterface : apb_if
