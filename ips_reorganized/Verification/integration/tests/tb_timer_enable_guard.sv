// Directed regression for malay timer ENABLE-qualified interrupt behavior.
// Invoke from ips_reorganized/: xrun -sv -f Verification/filelists/tier1_unit/tb_timer_enable_guard.f
`timescale 1ns/1ps
module tb_timer_enable_guard;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic [11:0] paddr = '0;
  logic [31:0] pwdata = '0;
  logic pwrite = 0, psel = 0, penable = 0;
  logic [31:0] prdata;
  logic pready, pslverr;
  logic [1:0] irq;

  timer dut (
    .HCLK(clk), .HRESETn(rst_n), .PADDR(paddr), .PWDATA(pwdata),
    .PWRITE(pwrite), .PSEL(psel), .PENABLE(penable),
    .PRDATA(prdata), .PREADY(pready), .PSLVERR(pslverr), .irq_o(irq)
  );

  task automatic write_reg(input logic [11:0] a, input logic [31:0] d);
    @(negedge clk);
    paddr = a; pwdata = d; pwrite = 1; psel = 1; penable = 1;
    @(posedge clk); #1;
    psel = 0; penable = 0; pwrite = 0;
  endtask

  task automatic expect_irq(input logic [1:0] expected, input string label);
    if (irq !== expected)
      $fatal(1, "timer guard %s: expected irq=%b got=%b", label, expected, irq);
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1;
    // Disabled timer must retain a software-written overflow value.
    write_reg(12'h000, 32'hFFFF_FFFF);
    repeat (2) begin @(posedge clk); #1; expect_irq(2'b00, "disabled overflow"); end
    if (dut.regs_q[0] !== 32'hFFFF_FFFF)
      $fatal(1, "disabled timer auto-cleared its counter");
    // The comparison condition must also be silent while disabled.
    write_reg(12'h008, 32'd7);
    write_reg(12'h000, 32'd7);
    repeat (2) begin @(posedge clk); #1; expect_irq(2'b00, "disabled compare"); end
    if (dut.regs_q[0] !== 32'd7)
      $fatal(1, "disabled timer changed comparison value");
    // Enabling with a match raises compare IRQ; subsequent clock clears count.
    write_reg(12'h004, 32'd1);
    expect_irq(2'b10, "enabled compare");
    @(posedge clk); #1;
    expect_irq(2'b00, "compare auto-clear");
    // Re-disable; MAX must not fire until re-enabled.
    write_reg(12'h004, 32'd0);
    write_reg(12'h000, 32'hFFFF_FFFF);
    @(posedge clk); #1; expect_irq(2'b00, "disabled overflow again");
    write_reg(12'h004, 32'd1);
    expect_irq(2'b01, "enabled overflow");
    @(posedge clk); #1; expect_irq(2'b00, "overflow auto-clear");
    $display("PASS tb_timer_enable_guard");
    $finish;
  end
  initial begin #10000; $fatal(1, "timer guard watchdog"); end
endmodule
