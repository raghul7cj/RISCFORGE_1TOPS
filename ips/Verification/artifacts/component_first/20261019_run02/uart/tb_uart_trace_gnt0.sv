`timescale 1ns/1ps
module tb_uart_trace_force;
  logic CLK=0, RSTN=0;
  logic PSEL=0, PENABLE=0, PWRITE=0;
  logic [2:0] PADDR=0; logic [31:0] PWDATA=0, PRDATA;
  logic PREADY, PSLVERR, INT, OUT1N, OUT2N, RTSN, DTRN;
  logic CTSN=1, DSRN=1, DCDN=1, RIN=1, SIN=1, SOUT;
  always #5 CLK=~CLK;
  apb_uart dut(.*);
  initial begin
    force dut.i_apb_uart_wrap.obi_rsp.gnt = 1'b0;
    repeat(5) @(posedge CLK);
    @(negedge CLK); RSTN=1;
    @(negedge CLK); $display("FORCE before PSEL t=%0t",$time); PSEL=1; PADDR=3'h1;
    #1 $display("FORCE after 1ns t=%0t ready=%b",$time,PREADY);
    #20 $display("FORCE PASS"); $finish;
  end
endmodule

