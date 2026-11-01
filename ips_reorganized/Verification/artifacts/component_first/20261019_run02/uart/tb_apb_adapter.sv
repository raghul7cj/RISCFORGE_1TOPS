`timescale 1ns/1ps
`include "obi/typedef.svh"
`include "apb/typedef.svh"
module tb_apb_adapter;
 import obi_pkg::*;
 localparam obi_cfg_t CFG = obi_pkg::obi_default_cfg(5,32,1,obi_pkg::ObiMinimalOptionalConfig);
 `OBI_TYPEDEF_DEFAULT_ALL(obi, CFG)
 `APB_TYPEDEF_ALL(apb, logic [4:0], logic [31:0], logic [3:0])
 logic clk=0, rstn=0;
 apb_req_t apb_req; apb_resp_t apb_rsp;
 obi_req_t obi_req; obi_rsp_t obi_rsp;
 always #5 clk=~clk;
 always_comb begin obi_rsp='0; obi_rsp.gnt=obi_req.req; end
 apb_to_obi #(.ObiCfg(CFG),.apb_req_t(apb_req_t),.apb_rsp_t(apb_resp_t),.obi_req_t(obi_req_t),.obi_rsp_t(obi_rsp_t)) dut
 (.clk_i(clk),.rst_ni(rstn),.apb_req_i(apb_req),.apb_rsp_o(apb_rsp),.obi_req_o(obi_req),.obi_rsp_i(obi_rsp));
 initial begin
   apb_req='0;
   repeat(5) @(posedge clk);
   @(negedge clk); rstn=1;
   @(negedge clk); $display("ADAPTER before PSEL %0t",$time); apb_req.psel=1;
   #1 $display("ADAPTER after PSEL %0t req=%b gnt=%b",$time,obi_req.req,obi_rsp.gnt);
   #20 $display("ADAPTER PASS"); $finish;
 end
endmodule
