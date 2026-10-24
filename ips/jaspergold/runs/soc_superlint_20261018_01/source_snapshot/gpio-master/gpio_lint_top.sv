// =============================================================================
// Lint top for JasperGold Superlint: gpio_apb_wrap as the SoC instantiates it.
//
// gpio_apb_wrap takes its APB request/response as type parameters that default
// to `logic`, so it cannot be elaborated as a top on its own. This wrapper
// declares the same APB structs riscforge_soc_subsystem uses (APB_TYPEDEF_*
// macros, 32-bit address/data, 4-bit strobe) and exposes flat ports.
//
// Not a design file: it is for lint only and is not in any SoC filelist.
// =============================================================================

`include "apb/typedef.svh"

module gpio_lint_top (
  input  logic                                clk_i,
  input  logic                                rst_ni,

  // APB slave
  input  logic [31:0]                         paddr_i,
  input  logic                                psel_i,
  input  logic                                penable_i,
  input  logic                                pwrite_i,
  input  logic [31:0]                         pwdata_i,
  input  logic [3:0]                          pstrb_i,
  output logic                                pready_o,
  output logic [31:0]                         prdata_o,
  output logic                                pslverr_o,

  // Pads and interrupts
  input  logic [gpio_reg_pkg::GPIOCount-1:0]  gpio_in_i,
  output logic [gpio_reg_pkg::GPIOCount-1:0]  gpio_out_o,
  output logic [gpio_reg_pkg::GPIOCount-1:0]  gpio_tx_en_o,
  output logic [gpio_reg_pkg::GPIOCount-1:0]  gpio_in_sync_o,
  output logic                                global_interrupt_o,
  output logic [gpio_reg_pkg::GPIOCount-1:0]  pin_level_interrupts_o
);

  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;
  `APB_TYPEDEF_REQ_T(apb_req_t, addr_t, data_t, strb_t)
  `APB_TYPEDEF_RESP_T(apb_resp_t, data_t)

  apb_req_t  apb_req;
  apb_resp_t apb_rsp;

  // PPROT is not used by the GPIO; tied off here rather than exposed as an
  // unused top-level input.
  assign apb_req = '{paddr:   paddr_i,
                     pprot:   3'b000,
                     psel:    psel_i,
                     penable: penable_i,
                     pwrite:  pwrite_i,
                     pwdata:  pwdata_i,
                     pstrb:   pstrb_i};

  assign pready_o  = apb_rsp.pready;
  assign prdata_o  = apb_rsp.prdata;
  assign pslverr_o = apb_rsp.pslverr;

  gpio_apb_wrap #(
    .ADDR_WIDTH ( 32         ),
    .DATA_WIDTH ( 32         ),
    .apb_req_t  ( apb_req_t  ),
    .apb_rsp_t  ( apb_resp_t )
  ) i_gpio_apb_wrap (
    .clk_i                  ( clk_i                  ),
    .rst_ni                 ( rst_ni                 ),
    .gpio_in                ( gpio_in_i              ),
    .gpio_out               ( gpio_out_o             ),
    .gpio_tx_en_o           ( gpio_tx_en_o           ),
    .gpio_in_sync_o         ( gpio_in_sync_o         ),
    .global_interrupt_o     ( global_interrupt_o     ),
    .pin_level_interrupts_o ( pin_level_interrupts_o ),
    .apb_req_i              ( apb_req                ),
    .apb_rsp_o              ( apb_rsp                )
  );

endmodule
