`timescale 1ns/1ps
`include "obi/typedef.svh"
`include "apb/typedef.svh"

// Original DUT with always_comb assigning obi_req_o.req = 0 then req = psel
module apb_to_obi_orig #(
  parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
  parameter type apb_req_t = logic,
  parameter type apb_rsp_t = logic,
  parameter type obi_req_t = logic,
  parameter type obi_rsp_t = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  apb_req_t apb_req_i,
  output apb_rsp_t apb_rsp_o,
  output obi_req_t obi_req_o,
  input  obi_rsp_t obi_rsp_i
);
  typedef enum logic {RESP, ADDR} obi_phase_e;
  obi_phase_e obi_phase_d, obi_phase_q;

  assign obi_req_o.a = '0;
  assign apb_rsp_o.prdata = '0;
  assign apb_rsp_o.pslverr = '0;

  always_comb begin : obi_fsm
    obi_req_o.req    = 1'b0;
    apb_rsp_o.pready = 1'b0;
    obi_phase_d      = obi_phase_q;
    unique case (obi_phase_q)
      ADDR: begin
        obi_req_o.req = apb_req_i.psel;
        if (obi_req_o.req && obi_rsp_i.gnt) obi_phase_d = RESP;
      end
      RESP: begin
        if (obi_rsp_i.rvalid) begin
          apb_rsp_o.pready = 1'b1;
          obi_phase_d = ADDR;
        end
      end
      default: obi_phase_d = ADDR;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) obi_phase_q <= ADDR;
    else         obi_phase_q <= obi_phase_d;
  end
endmodule

// Fixed DUT with continuous assign for obi_req_o.req
module apb_to_obi_fixed #(
  parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
  parameter type apb_req_t = logic,
  parameter type apb_rsp_t = logic,
  parameter type obi_req_t = logic,
  parameter type obi_rsp_t = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  apb_req_t apb_req_i,
  output apb_rsp_t apb_rsp_o,
  output obi_req_t obi_req_o,
  input  obi_rsp_t obi_rsp_i
);
  typedef enum logic {RESP, ADDR} obi_phase_e;
  obi_phase_e obi_phase_d, obi_phase_q;

  assign obi_req_o.a = '0;
  assign apb_rsp_o.prdata = '0;
  assign apb_rsp_o.pslverr = '0;

  // Key change: req is cleanly decoupled from obi_fsm and obi_rsp_i
  assign obi_req_o.req = (obi_phase_q == ADDR) ? apb_req_i.psel : 1'b0;

  always_comb begin : obi_fsm
    apb_rsp_o.pready = 1'b0;
    obi_phase_d      = obi_phase_q;
    unique case (obi_phase_q)
      ADDR: begin
        if (apb_req_i.psel && obi_rsp_i.gnt) obi_phase_d = RESP;
      end
      RESP: begin
        if (obi_rsp_i.rvalid) begin
          apb_rsp_o.pready = 1'b1;
          obi_phase_d = ADDR;
        end
      end
      default: obi_phase_d = ADDR;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) obi_phase_q <= ADDR;
    else         obi_phase_q <= obi_phase_d;
  end
endmodule

module tb_test_compare;
  import obi_pkg::*;
  localparam obi_cfg_t CFG = obi_pkg::obi_default_cfg(5,32,1,obi_pkg::ObiMinimalOptionalConfig);
  `OBI_TYPEDEF_DEFAULT_ALL(obi, CFG)
  `APB_TYPEDEF_ALL(apb, logic [4:0], logic [31:0], logic [3:0])

  logic clk = 0, rstn = 0;
  always #5 clk = ~clk;

  apb_req_t apb_req;
  apb_resp_t apb_rsp;
  obi_req_t obi_req;
  obi_rsp_t obi_rsp;

  // Combinational responder like obi_uart_register: gnt = req
  always_comb begin
    obi_rsp = '0;
    obi_rsp.gnt = obi_req.req;
  end

`ifdef TEST_ORIG
  apb_to_obi_orig #(.ObiCfg(CFG),.apb_req_t(apb_req_t),.apb_rsp_t(apb_resp_t),.obi_req_t(obi_req_t),.obi_rsp_t(obi_rsp_t)) dut
  (.clk_i(clk),.rst_ni(rstn),.apb_req_i(apb_req),.apb_rsp_o(apb_rsp),.obi_req_o(obi_req),.obi_rsp_i(obi_rsp));
`else
  apb_to_obi_fixed #(.ObiCfg(CFG),.apb_req_t(apb_req_t),.apb_rsp_t(apb_resp_t),.obi_req_t(obi_req_t),.obi_rsp_t(obi_rsp_t)) dut
  (.clk_i(clk),.rst_ni(rstn),.apb_req_i(apb_req),.apb_rsp_o(apb_rsp),.obi_req_o(obi_req),.obi_rsp_i(obi_rsp));
`endif

  initial begin
    $display("[START] Running with %s", `ifdef TEST_ORIG "ORIGINAL DUT" `else "FIXED DUT" `endif);
    apb_req = '0;
    repeat(5) @(posedge clk);
    @(negedge clk); rstn = 1;
    @(negedge clk);
    $display("ADAPTER before PSEL %0t", $time);
    apb_req.psel = 1;
    #1;
    $display("ADAPTER after PSEL %0t req=%b gnt=%b", $time, obi_req.req, obi_rsp.gnt);
    #20;
    $display("[SUCCESS] ADAPTER PASSED WITHOUT DELTA LOOP!");
    $finish;
  end
endmodule
