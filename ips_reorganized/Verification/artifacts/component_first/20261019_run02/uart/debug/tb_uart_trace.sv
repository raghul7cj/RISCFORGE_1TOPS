`timescale 1ns/1ps
module tb_uart_trace;
  logic CLK=0, RSTN=0;
  logic PSEL=0, PENABLE=0, PWRITE=0;
  logic [2:0] PADDR=0; logic [31:0] PWDATA=0, PRDATA;
  logic PREADY, PSLVERR, INT, OUT1N, OUT2N, RTSN, DTRN;
  logic CTSN=1, DSRN=1, DCDN=1, RIN=1, SIN=1, SOUT;
  always #5 CLK=~CLK;
  apb_uart dut(.*);
  initial begin
    $display("TRACE start t=%0t",$time);
    repeat(5) @(posedge CLK);
    @(negedge CLK); RSTN=1; $display("TRACE reset released t=%0t",$time);
    repeat(2) @(negedge CLK);
    $display("TRACE before PSEL t=%0t",$time);
    PSEL=1; PADDR=3'h1;
    $display("TRACE after PSEL t=%0t ready=%b",$time,PREADY);
    #1 $display("TRACE +1ns t=%0t ready=%b",$time,PREADY);
    PENABLE=1;
    repeat(5) begin @(posedge CLK); #1; $display("TRACE tick t=%0t sel=%b en=%b ready=%b data=%08x",$time,PSEL,PENABLE,PREADY,PRDATA); end
    $display("TRACE finish"); $finish;
  end
endmodule
