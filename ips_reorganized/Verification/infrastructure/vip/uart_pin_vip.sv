// =============================================================================
// RISCFORGE 1TOPS — UART Pin VIP (uart_pin_vip.sv)
// =============================================================================

`timescale 1ns/1ps

module uart_pin_vip #(
  parameter int unsigned CLK_FREQ_HZ = 100_000_000,
  parameter int unsigned BAUD_RATE   = 115200
)(
  input  logic clk,
  input  logic rst_n,
  input  logic uart_tx,      // DUT -> VIP
  output logic uart_rx       // VIP -> DUT
);

  localparam int unsigned BIT_PERIOD_CYCLES = CLK_FREQ_HZ / BAUD_RATE;

  // Internal state
  logic loopback_en;
  initial loopback_en = 1'b0;

  assign uart_rx = loopback_en ? uart_tx : 1'b1;

  // Passive TX Monitor: Decodes byte on uart_tx
  logic [7:0] rx_shift;
  int         cycle_cnt;

  task automatic enable_loopback(input logic enable);
    loopback_en = enable;
  endtask

  // Simple TX Byte Monitor
  initial begin
    forever begin
      @(negedge uart_tx); // Start bit
      #(BIT_PERIOD_CYCLES * 10ns * 1.5); // Center of bit 0
      for (int i = 0; i < 8; i++) begin
        rx_shift[i] = uart_tx;
        #(BIT_PERIOD_CYCLES * 10ns);
      end
      // Stop bit
      #(BIT_PERIOD_CYCLES * 10ns);
      $display("[UART VIP Monitor @ %0t] Captured Byte: 0x%02X ('%c')", $time, rx_shift, rx_shift);
    end
  end

endmodule
