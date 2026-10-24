`timescale 1ns/1ps

package tb_bus_pkg;

  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } aw_chan_t;

  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  strb;
  } w_chan_t;

  typedef struct packed {
    logic [1:0] resp;
  } b_chan_t;

  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } ar_chan_t;

  typedef struct packed {
    logic [31:0] data;
    logic [1:0]  resp;
  } r_chan_t;

  typedef struct packed {
    aw_chan_t aw;
    logic     aw_valid;
    w_chan_t  w;
    logic     w_valid;
    logic     b_ready;
    ar_chan_t ar;
    logic     ar_valid;
    logic     r_ready;
  } axi_lite_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    b_chan_t b;
    logic    b_valid;
    logic    ar_ready;
    r_chan_t r;
    logic    r_valid;
  } axi_lite_resp_t;

  typedef struct packed {
    logic [31:0] paddr;
    logic [2:0]  pprot;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
  } apb_req_t;

  typedef struct packed {
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;
  } apb_resp_t;

endpackage : tb_bus_pkg


module bootloader_tb;
  import tb_bus_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  logic clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  logic hard_rst_ni;
  logic soft_rst_ni;

  axi_lite_req_t  axi_req;      // DUT output: do not drive in TB
  axi_lite_resp_t axi_resp;     // TB drives
  apb_req_t       apb_slv_req;  // TB drives
  apb_resp_t      apb_slv_resp; // DUT drives
  apb_req_t       apb_mst_req;  // DUT drives
  apb_resp_t      apb_mst_resp; // TB drives

  logic core_rst_ni;
  logic periph_rst_ni;
  logic spi_rst_ni;
  logic boot_done;

  localparam logic [31:0] ISRAM_BASE = 32'h0000_0000;
  localparam logic [31:0] DSRAM_BASE = 32'h0001_0000;

  bootloader #(
    .axi_req_t         ( axi_lite_req_t ),
    .axi_resp_t        ( axi_lite_resp_t ),
    .apb_req_t         ( apb_req_t ),
    .apb_resp_t        ( apb_resp_t ),
    .AXI_ADDR_WIDTH    ( 32 ),
    .AXI_DATA_WIDTH    ( 32 ),
    .ISRAM_BASE_ADDR   ( ISRAM_BASE ),
    .DSRAM_BASE_ADDR   ( DSRAM_BASE ),
    .ISRAM_NUM_WORDS   ( 16 ),
    .DSRAM_NUM_WORDS   ( 16 ),
    .NUM_INSTR_WORDS   ( 4 ),
    .NUM_DATA_WORDS    ( 0 ),
    .FLASH_START_ADDR  ( 24'h000000 ),
    .FLASH_READ_CMD    ( 8'h03 ),
    .CMD_LEN_BITS      ( 6'd8 ),
    .ADDR_LEN_BITS     ( 6'd24 ),
    .DATA_LEN_BITS     ( 16'd32 ),
    .SPI_CLK_DIV       ( 8'd4 ),
    .CS_FLASH          ( 4'b0001 ),
    .RESET_HOLD_CYCLES ( 4 )
  ) dut_bootloader (
    .clk_i           ( clk ),
    .hard_rst_ni     ( hard_rst_ni ),
    .soft_rst_ni     ( soft_rst_ni ),
    .axi_req_o       ( axi_req ),
    .axi_resp_i      ( axi_resp ),
    .apb_slv_req_i   ( apb_slv_req ),
    .apb_slv_resp_o  ( apb_slv_resp ),
    .apb_mst_req_o   ( apb_mst_req ),
    .apb_mst_resp_i  ( apb_mst_resp ),
    .core_rst_ni_o   ( core_rst_ni ),
    .periph_rst_ni_o ( periph_rst_ni ),
    .spi_rst_ni_o    ( spi_rst_ni ),
    .boot_done_o     ( boot_done )
  );

  initial begin
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b0;

    axi_resp = '0;
    axi_resp.aw_ready = 1'b1;
    axi_resp.w_ready  = 1'b1;
    axi_resp.ar_ready = 1'b1;
    axi_resp.b_valid  = 1'b0;
    axi_resp.r_valid  = 1'b0;
    axi_resp.b.resp   = 2'b00;
    axi_resp.r.resp   = 2'b00;
    axi_resp.r.data   = 32'h0000_0000;

    apb_slv_req = '0;

    apb_mst_resp = '0;
    apb_mst_resp.pready  = 1'b1;
    apb_mst_resp.prdata  = 32'h0000_0000;
    apb_mst_resp.pslverr = 1'b0;

    $shm_open("bootloader_tb.shm");
    $shm_probe(bootloader_tb, "AS");
    $shm_probe(bootloader_tb.dut_bootloader, "AS");

    repeat (10) @(posedge clk);
    hard_rst_ni = 1'b1;
    soft_rst_ni = 1'b1;

    repeat (500) @(posedge clk);
    $display("[TB] Finished bootloader smoke test.");
    $finish;
  end

  always @(posedge clk) begin
    if ($isunknown({core_rst_ni, periph_rst_ni, spi_rst_ni, boot_done})) begin
      $error("[TB] X/Z detected on bootloader outputs at time %0t", $time);
    end
  end

  initial begin
    #1ms;
    $error("[TB] GLOBAL TIMEOUT");
    $finish;
  end

endmodule : bootloader_tb
