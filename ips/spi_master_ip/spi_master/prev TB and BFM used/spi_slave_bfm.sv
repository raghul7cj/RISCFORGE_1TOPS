`timescale 1ns/1ps

// SPI Slave BFM
// Loads a hex file at time 0 and drives spi_sdi from it, MSB-first,
// on negedge spi_clk (DUT samples on posedge).
//
// - inject_word(idx)          : shift out mem[idx] as a 32-bit word
// - inject_burst(start, num)  : shift out num back-to-back words starting at start

module spi_slave_bfm #(
  parameter int     MEM_DEPTH = 64,
  parameter string  MEM_FILE  = "instr.mem"
)(
  input  logic spi_clk,
  input  logic spi_csn,
  output logic spi_sdi
);

  logic [31:0] mem [0:MEM_DEPTH-1];

  initial begin
    spi_sdi = 1'b0;
    $readmemh(MEM_FILE, mem);
  end

  task automatic inject_word(input int idx);
    logic [31:0] w;
    int i;
    begin
      w = mem[idx];
      spi_sdi = 1'b0;
      wait (spi_csn === 1'b0);
      spi_sdi = w[31];
      for (i = 30; i >= 0; i--) begin
        @(negedge spi_clk);
        spi_sdi = w[i];
      end
      wait (spi_csn === 1'b1);
      spi_sdi = 1'b0;
    end
  endtask

  task automatic inject_burst(input int start_idx, input int num);
    int w, i;
    begin
      spi_sdi = 1'b0;
      wait (spi_csn === 1'b0);
      spi_sdi = mem[start_idx][31];
      for (w = 0; w < num; w++)
        for (i = (w == 0 ? 30 : 31); i >= 0; i--) begin
          @(negedge spi_clk);
          spi_sdi = mem[start_idx + w][i];
        end
      wait (spi_csn === 1'b1);
      spi_sdi = 1'b0;
    end
  endtask

endmodule
