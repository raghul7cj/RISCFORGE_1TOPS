`timescale 1ns/1ps

module tb_top_mret;
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
      dut.Fetch.IMEM.mem[0]  = 32'h0200_0313; // addi x6, x0, 32
      dut.Fetch.IMEM.mem[1]  = 32'h3053_1073; // csrrw x0, mtvec, x6
      dut.Fetch.IMEM.mem[2]  = 32'h0000_0073; // ecall
      dut.Fetch.IMEM.mem[3]  = 32'h0550_0293; // addi x5, x0, 85
      dut.Fetch.IMEM.mem[4]  = 32'h0050_2023; // sw x5, 0(x0)
      dut.Fetch.IMEM.mem[5]  = 32'h0000_006f; // jal x0, 0
      dut.Fetch.IMEM.mem[8]  = 32'h00c0_0313; // addi x6, x0, 12
      dut.Fetch.IMEM.mem[9]  = 32'h3413_1073; // csrrw x0, mepc, x6
      dut.Fetch.IMEM.mem[10] = 32'h3020_0073; // mret
      dut.Fetch.IMEM.mem[11] = 32'h0000_006f; // jal x0, 0
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
    bit saw_mret;

    $display("=== tb_top_mret ===");

    #1;
    load_program();

    reset_dut();

    saw_mret = 1'b0;

    for (cycles = 0; cycles < 500; cycles++) begin
      @(posedge clk);
      if (dut.mret_commit === 1'b1) begin
        saw_mret = 1'b1;
      end

      // After MRET, mstatus.MIE should be restored
      if (saw_mret) begin
        #1;
        if (dut.csr_mstatus_sb[3] !== 1'b1)
          $fatal(1, "After MRET, MSTATUS.MIE expected 1");
      end

      // Signature: store should write 0x55 to DMEM word 0
      if (dut.Memory.dmem.mem[0] === 32'h0000_0055) begin
        $display("PASS: MRET roundtrip reached signature store");
        $finish;
      end
    end

    $fatal(1, "Timeout: signature store not observed; DMEM[0]=%h", dut.Memory.dmem.mem[0]);
  end

endmodule
