`timescale 1ns/1ps

module sram_sp_component_tb;
  localparam int WORDS = 16;
  localparam int AW = $clog2(WORDS);
  logic clk = 0;
  logic cs, we;
  logic [AW-1:0] addr;
  logic [31:0] wdata, rdata;
  logic [3:0] wmask;
  int pass_cnt = 0;
  int fail_cnt = 0;

  always #5 clk = ~clk;

  sram_sp #(.NUM_WORDS(WORDS)) dut (
    .clk_i(clk), .cs_i(cs), .we_i(we), .addr_i(addr),
    .wdata_i(wdata), .wmask_i(wmask), .rdata_o(rdata)
  );

  task automatic check32(input string label, input logic [31:0] got, exp);
    if (got === exp) begin
      $display("[PASS] %s got=%08h expected=%08h", label, got, exp);
      pass_cnt++;
    end else begin
      $display("[FAIL] %s got=%08h expected=%08h", label, got, exp);
      fail_cnt++;
    end
  endtask

  task automatic write_word(input logic [AW-1:0] a,
                            input logic [31:0] d,
                            input logic [3:0] m);
    @(negedge clk); cs=1; we=1; addr=a; wdata=d; wmask=m;
    @(posedge clk); #1;
    @(negedge clk); cs=0; we=0; wmask=0;
  endtask

  task automatic read_word(input logic [AW-1:0] a,
                           output logic [31:0] d);
    @(negedge clk); cs=1; we=0; addr=a; wmask=0;
    @(posedge clk); #1; d=rdata;
    @(negedge clk); cs=0;
  endtask

  logic [31:0] got;
  initial begin
    cs=0; we=0; addr=0; wdata=0; wmask=0;
    repeat (2) @(posedge clk);

    write_word(0, 32'hAABB_CCDD, 4'hF);
    read_word(0, got);
    check32("word zero full write/read", got, 32'hAABB_CCDD);

    write_word(0, 32'h1122_3344, 4'b0101);
    read_word(0, got);
    check32("byte lanes 0 and 2 update only", got, 32'hAA22_CC44);

    write_word(0, 32'hFFFF_FFFF, 4'b0000);
    read_word(0, got);
    check32("zero byte mask leaves word unchanged", got, 32'hAA22_CC44);

    write_word(WORDS-1, 32'h5A96_3CC3, 4'hF);
    read_word(WORDS-1, got);
    check32("last valid word address", got, 32'h5A96_3CC3);

    // SRAM model is read-first: rdata captures the old word on a write edge.
    @(negedge clk); cs=1; we=1; addr=0; wdata=32'hDEAD_BEEF; wmask=4'hF;
    @(posedge clk); #1; check32("same-cycle write returns pre-write data", rdata, 32'hAA22_CC44);
    @(negedge clk); cs=0; we=0;
    read_word(0, got);
    check32("write data visible on following read", got, 32'hDEAD_BEEF);

    // With chip select low, the registered output must hold its prior value.
    @(negedge clk); cs=0; we=0; addr=WORDS-1;
    repeat (2) @(posedge clk);
    #1; check32("chip-select low holds output", rdata, 32'hDEAD_BEEF);

    $display("SRAM_SP_SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) $fatal(1, "sram_sp component checks failed");
    $finish;
  end
endmodule
