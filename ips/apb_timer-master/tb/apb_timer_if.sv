interface apb_timer_if #(
    parameter APB_ADDR_WIDTH = 12,
    parameter TIMER_CNT = 2
)(
    input logic HCLK
);

    logic HRESETn = 1'b0;

    logic [APB_ADDR_WIDTH-1:0] PADDR;
    logic [31:0] PWDATA;
    logic PWRITE;
    logic PSEL;
    logic PENABLE;

    logic [31:0] PRDATA;
    logic PREADY;
    logic PSLVERR;

    logic [(TIMER_CNT*2)-1:0] irq_o;

endinterface
