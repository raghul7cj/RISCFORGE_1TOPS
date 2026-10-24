`timescale 1ns/1ps

class dummy_env;
  int q[$];
  function void write_postmortem(string path, int n);
    int fd;
    string s;
    fd = $fopen(path, "w");
    if (fd == 0) return;
    s = "Header\n";
    for (int i = 0; i < q.size(); i++) begin
      s = {s, $sformatf("item %0d = %0d\n", i, q[i])};
    end
    $fdisplay(fd, "%s", s);
    $fclose(fd);
    $display("[DUMMY] written to %s", path);
  endfunction
endclass

module test_final_crash;
  dummy_env env;
  initial begin
    env = new();
    for (int i = 0; i < 50; i++) env.q.push_back(i);
    #10;
    $finish(1);
  end

  final begin
    if (env != null)
      env.write_postmortem("test_out.txt", 10);
  end
endmodule
