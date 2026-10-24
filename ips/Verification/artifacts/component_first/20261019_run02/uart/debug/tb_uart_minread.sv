`timescale 1ns/1ps
module tb_uart_minread;
  logic CLK=0, RSTN=0;
  logic PSEL=0, PENABLE=0, PWRITE=0;
  logic [2:0] PADDR=0; logic [31:0] PWDATA=0, PRDATA;
  logic PREADY, PSLVERR, INT, OUT1N, OUT2N, RTSN, DTRN;
  logic CTSN=1, DSRN=1, DCDN=1, RIN=1, SIN=1, SOUT;
  always #5 CLK=~CLK;
  apb_uart dut(.*);
  initial begin
    repeat(5) @(posedge CLK);
    @(negedge CLK); RSTN=1;
    @(negedge CLK); PSEL=1; PADDR=3'h1; PWRITE=0; PENABLE=0;
    @(negedge CLK); PENABLE=1;
    repeat(8) begin
      @(posedge CLK); #1;
      $display("MINREAD t=%0t psel=%b penable=%b ready=%b data=%08x", $time,PSEL,PENABLE,PREADY,PRDATA);
      if (PREADY) begin
        if (PRDATA !== 32'h0) $fatal(1,"IER reset mismatch %08x",PRDATA);
        $display("MINREAD_PASS"); $finish;
      end
    end
    $fatal(1,"MINREAD_TIMEOUT");
  end
endmodule
