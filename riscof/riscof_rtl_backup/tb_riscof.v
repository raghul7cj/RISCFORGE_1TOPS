`timescale 1ns / 1ps

module tb;

    reg clk;
    reg rst;

    RISC_top dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;

        #20;
        rst = 0;

        #5000;

        $finish;
    end

endmodule