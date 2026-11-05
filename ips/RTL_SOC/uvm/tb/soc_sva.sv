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
  input logic        uart_sout,
  input logic [5:0]  apb_timeout,
  input logic        axi_wr_timeout,
  input logic        axi_rd_timeout,
  input logic        allow_err
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  a_pc: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(pc))
    else `uvm_error("CORE_SVA", "PC is X")

  a_lsu_err: assert property (@(posedge clk) disable iff (!rst_n || allow_err === 1'b1)
    !(lsu_req && lsu_err))
    else `uvm_error("CORE_SVA", "LSU bus error")

  a_sout: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(uart_sout))
    else `uvm_error("CORE_SVA", "uart_sout is X")

  a_apb_timeout: assert property (@(posedge clk) disable iff (!rst_n || allow_err === 1'b1)
    apb_timeout == '0)
    else `uvm_error("CORE_SVA", $sformatf("APB timeout on slave mask 0x%02h", apb_timeout))

  a_axi_timeout: assert property (@(posedge clk) disable iff (!rst_n || allow_err === 1'b1)
    !axi_wr_timeout && !axi_rd_timeout)
    else `uvm_error("CORE_SVA", "AXI timeout")
endmodule
