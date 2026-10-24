`timescale 1ns/1ps

class my_env;
  int fd;
  function void write_file();
    fd = $fopen("final_test.txt", "w");
    $fdisplay(fd, "Hello from final");
    $fclose(fd);
    $display("[MY_ENV] written from final");
  endfunction
endclass

module test_finish_arg;
  bit clk = 0;
  always #5 clk = ~clk;

  my_env env;
  initial begin
    env = new();
    fork
      forever begin
        @(posedge clk);
      end
    join_none
    #20;
    $finish(1);
  end

  final begin
    if (env != null)
      env.write_file();
  end
endmodule
