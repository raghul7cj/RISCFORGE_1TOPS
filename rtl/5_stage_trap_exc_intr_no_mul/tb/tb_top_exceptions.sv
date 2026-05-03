`timescale 1ns/1ps

module tb_top_exceptions;
  localparam int CLK_HALF = 5;

  logic clk;
  logic rst; // active-low reset in this design

  wire PCSrcE1;

  top dut (
    .clk(clk),
    .rst(rst),
    .PCSrcE1(PCSrcE1)
  );

  initial clk = 1'b0;
  always #(CLK_HALF) clk = ~clk;

  task automatic load_program();
    begin
      dut.Fetch.IMEM.mem[0] = 32'h0800_0313; // addi x6, x0, 128
      dut.Fetch.IMEM.mem[1] = 32'h3053_1073; // csrrw x0, mtvec, x6
      dut.Fetch.IMEM.mem[2] = 32'h0000_0013; // nop
      dut.Fetch.IMEM.mem[3] = 32'h0000_0013; // nop
      dut.Fetch.IMEM.mem[4] = 32'h0000_0073; // ecall
      dut.Fetch.IMEM.mem[5] = 32'h0000_006f; // jal x0, 0
    end
  endtask

  task automatic reset_dut();
    rst = 1'b0;
    repeat (6) @(posedge clk);
    rst = 1'b1;
    repeat (2) @(posedge clk);
  endtask

  initial begin
    int cycles;

    $display("=== tb_top_exceptions ===");

    #1;
    load_program();

    reset_dut();

    // Run until trap redirects or timeout
    cycles = 0;
    while ((dut.wb_trap_redirect !== 1'b1) && (cycles < 200)) begin
      @(posedge clk);
      cycles++;
    end

    if (dut.wb_trap_redirect !== 1'b1) begin
      $fatal(1, "Timeout: trap redirect not observed");
    end

    // Same-cycle combinational checks at commit
    #1;
    if (dut.trap_target !== 32'h0000_0080)
      $fatal(1, "Trap target mismatch: got %h expected 00000080", dut.trap_target);

    // After CSR update edge, check CSR state
    @(posedge clk);
    #1;
    if (dut.csr_file.mepc_r !== 32'h0000_0010)
      $fatal(1, "MEPC mismatch: got %h expected 00000010", dut.csr_file.mepc_r);

    if (dut.csr_file.mcause_r !== 32'h0000_000B)
      $fatal(1, "MCAUSE mismatch: got %h expected 0000000B", dut.csr_file.mcause_r);

    if (dut.csr_file.mtval_r !== 32'h0000_0000)
      $fatal(1, "MTVAL mismatch: got %h expected 00000000", dut.csr_file.mtval_r);

    if (dut.csr_mstatus_sb[3] !== 1'b0)
      $fatal(1, "MSTATUS.MIE should be 0 after trap");

    if (dut.csr_mstatus_sb[7] !== 1'b1)
      $fatal(1, "MSTATUS.MPIE should be 1 after trap (old MIE)");

    if (dut.csr_mstatus_sb[12:11] !== 2'b11)
      $fatal(1, "MSTATUS.MPP should be 11 after trap");

    $display("PASS: exception trap-entry integration checks");
    $finish;
  end

endmodule
