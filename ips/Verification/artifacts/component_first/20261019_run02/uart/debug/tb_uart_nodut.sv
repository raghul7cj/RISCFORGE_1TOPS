`timescale 1ns/1ps
module tb_uart_nodut;
  logic clk=0;
  always #5 clk=~clk;
  initial begin
    $display("NODUT_START t=%0t",$time);
    repeat(5) @(posedge clk);
    #1 $display("NODUT_PASS t=%0t",$time);
    $finish;
  end
endmodule
