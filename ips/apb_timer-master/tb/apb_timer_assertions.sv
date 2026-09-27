module apb_timer_assertions #(
    parameter ADDR_WIDTH = 12
)(
    input logic HCLK,
    input logic HRESETn,

    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic [31:0] PWDATA,
    input logic PWRITE,
    input logic PSEL,
    input logic PENABLE,

    input logic PREADY,
    input logic PSLVERR,

    input logic [3:0] irq_o
);


    property p_pready;
        @(posedge HCLK)
        disable iff (!HRESETn)

        PREADY == 1'b1;
    endproperty


    property p_no_slverr;
        @(posedge HCLK)
        disable iff (!HRESETn)

        PSLVERR == 1'b0;
    endproperty


    property p_setup_to_access;
        @(posedge HCLK)
        disable iff (!HRESETn)

        (PSEL && !PENABLE) |=> (PSEL && PENABLE);
    endproperty


    property p_addr_stable;
        @(posedge HCLK)
        disable iff (!HRESETn)

        (PSEL && !PENABLE) |=> $stable(PADDR);
    endproperty


    property p_write_stable;
        @(posedge HCLK)
        disable iff (!HRESETn)

        (PSEL && !PENABLE) |=> $stable(PWRITE);
    endproperty


    property p_wdata_stable;
        @(posedge HCLK)
        disable iff (!HRESETn)

        (PSEL && !PENABLE && PWRITE) |=>  $stable(PWDATA);
    endproperty


    property p_access_has_setup;
        @(posedge HCLK)
        disable iff (!HRESETn)

        $rose(PENABLE) |->  $past(PSEL && !PENABLE);
    endproperty


    property p_reset_irq;
        @(posedge HCLK)

        !HRESETn |-> irq_o == 4'b0;
    endproperty


    assert property (p_pready)
        else $error("PREADY assertion failed");

    assert property (p_no_slverr)
        else $error("PSLVERR assertion failed");

    assert property (p_setup_to_access)
        else $error("APB setup/access assertion failed");

    assert property (p_addr_stable)
        else $error("PADDR changed during APB transfer");

    assert property (p_write_stable)
        else $error("PWRITE changed during APB transfer");

    assert property (p_wdata_stable)
        else $error("PWDATA changed during APB write");

    assert property (p_access_has_setup)
        else $error("APB access without setup");

    assert property (p_reset_irq)
        else $error("IRQ active during reset");

endmodule
