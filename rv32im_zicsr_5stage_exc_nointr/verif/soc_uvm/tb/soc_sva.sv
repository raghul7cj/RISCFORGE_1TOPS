module apb_sva (
  input logic        clk,
  input logic        rst_n,
  input logic        psel,
  input logic        penable,
  input logic        pready,
  input logic [31:0] paddr
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  a_setup: assert property (@(posedge clk) disable iff (!rst_n)
    psel && !penable |=> psel && penable)
    else `uvm_error("APB_SVA", $sformatf("%m: no access phase after setup"))

  a_hold: assert property (@(posedge clk) disable iff (!rst_n)
    psel && penable && !pready |=> psel && penable && $stable(paddr))
    else `uvm_error("APB_SVA", $sformatf("%m: signals changed while waiting"))

  a_known: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(psel))
    else `uvm_error("APB_SVA", $sformatf("%m: psel is X"))
endmodule

module core_sva (
  input logic        clk,
  input logic        rst_n,
  input logic [31:0] pc,
  input logic        lsu_req,
  input logic        lsu_err,
  input logic        uart_sout
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  bit allow_err;
  initial allow_err = $test$plusargs("ALLOW_LSU_ERR");

  a_pc: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(pc))
    else `uvm_error("CORE_SVA", "PC is X")

  a_lsu_err: assert property (@(posedge clk) disable iff (!rst_n || allow_err)
    !(lsu_req && lsu_err))
    else `uvm_error("CORE_SVA", "LSU bus error")

  a_sout: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(uart_sout))
    else `uvm_error("CORE_SVA", "uart_sout is X")
endmodule
