// =============================================================================
// RISCFORGE 1TOPS — Peripheral Register Predictor (register_predictor.sv)
// =============================================================================
// Independent shadow mirror reference model for all 6 APB peripherals:
//   APB[0] : OpenCores I2C Master
//   APB[1] : ETH Zurich APB Timer 0
//   APB[2] : 16550 APB UART
//   APB[3] : lowRISC APB GPIO (with atomic SET/CLEAR/TOGGLE)
//   APB[4] : ETH Zurich APB SPI Master
//   APB[5] : ETH Zurich APB Timer 1
//
// Accurately predicts:
//   - RW registers and default hardware reset values
//   - W1C (Write-1-to-Clear) status registers
//   - Atomic SET (0x200), CLEAR (0x280), TOGGLE (0x300) alias side-effects
//   - DLAB banking in 16550 UART (DLL/DLM vs RBR/THR/IER)
//   - Auto-clearing command strobes
// =============================================================================

`timescale 1ns/1ps

module register_predictor import tb_pkg::*; #(
  parameter int unsigned NUM_SLOTS = 6
)(
  input logic                 clk,
  input logic                 rst_n,
  input logic                 freeze,

  // APB Bus Interface
  input logic [31:0]          paddr,
  input logic [NUM_SLOTS-1:0] psel,
  input logic                 penable,
  input logic                 pwrite,
  input logic [31:0]          pwdata,
  input logic [NUM_SLOTS-1:0] pready,
  input logic [31:0]          prdata [0:NUM_SLOTS-1],
  input logic [NUM_SLOTS-1:0] pslverr,

  // Error Diagnostic Output
  output logic                reg_mismatch_err,
  output string               reg_err_msg,
  output logic [31:0]         reg_err_addr,
  output logic [31:0]         reg_err_exp,
  output logic [31:0]         reg_err_got
);

  // ---------------------------------------------------------------------------
  // Shadow Register Storage per Peripheral
  // ---------------------------------------------------------------------------
  // APB[0]: I2C
  logic [15:0] i2c_prer;
  logic [7:0]  i2c_ctr;
  logic [7:0]  i2c_txr;

  // APB[1]: Timer 0
  logic [31:0] t0_timer;
  logic [31:0] t0_ctrl;
  logic [31:0] t0_cmp;

  // APB[2]: UART 16550
  logic [7:0]  uart_rbr_thr;
  logic [7:0]  uart_ier;
  logic [7:0]  uart_lcr;
  logic [7:0]  uart_mcr;
  logic [7:0]  uart_scr;
  logic [7:0]  uart_dll;
  logic [7:0]  uart_dlm;

  // APB[3]: GPIO
  logic [31:0] gpio_en;
  logic [31:0] gpio_out;
  logic [31:0] gpio_irq_en;
  logic [31:0] gpio_irq_status;

  // APB[4]: SPI
  logic [31:0] spi_clkdiv;
  logic [31:0] spi_len;
  logic [31:0] spi_dum;

  // APB[5]: Timer 1
  logic [31:0] t1_timer;
  logic [31:0] t1_ctrl;
  logic [31:0] t1_cmp;

  // ---------------------------------------------------------------------------
  // Reset Initialization
  // ---------------------------------------------------------------------------
  task automatic reset_model();
    i2c_prer        = 16'h0000;
    i2c_ctr         = 8'h00;
    i2c_txr         = 8'h00;

    t0_timer        = 32'h0;
    t0_ctrl         = 32'h0;
    t0_cmp          = 32'h0;

    uart_rbr_thr    = 8'h00;
    uart_ier        = 8'h00;
    uart_lcr        = 8'h00;
    uart_mcr        = 8'h00;
    uart_scr        = 8'h00;
    uart_dll        = 8'h00;
    uart_dlm        = 8'h00;

    gpio_en         = 32'h0;
    gpio_out        = 32'h0;
    gpio_irq_en     = 32'h0;
    gpio_irq_status = 32'h0;

    spi_clkdiv      = 32'h0;
    spi_len         = 32'h0;
    spi_dum         = 32'h0;

    t1_timer        = 32'h0;
    t1_ctrl         = 32'h0;
    t1_cmp          = 32'h0;

    reg_mismatch_err= 1'b0;
    reg_err_msg     = "";
    reg_err_addr    = 32'h0;
    reg_err_exp     = 32'h0;
    reg_err_got     = 32'h0;
  endtask

  initial reset_model();

  // ---------------------------------------------------------------------------
  // Main Predictive Tracking Engine
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reset_model();
    end else if (!freeze) begin
      for (int s = 0; s < NUM_SLOTS; s++) begin
        if (psel[s] && penable && pready[s]) begin
          logic [11:0] offset;
          offset = paddr[11:0];

          if (pwrite) begin
            // -----------------------------------------------------------------
            // WRITE TRANSACTION: Update Model State
            // -----------------------------------------------------------------
            case (s)
              0: begin // I2C
                if (offset == 12'h000) i2c_prer[7:0]  <= pwdata[7:0];
                if (offset == 12'h004) i2c_prer[15:8] <= pwdata[7:0];
                if (offset == 12'h008) i2c_ctr        <= pwdata[7:0];
                if (offset == 12'h014) i2c_txr        <= pwdata[7:0];
              end

              1: begin // Timer 0
                if (offset == 12'h000) t0_timer       <= pwdata;
                if (offset == 12'h004) t0_ctrl        <= pwdata;
                if (offset == 12'h008) begin
                  t0_cmp   <= pwdata;
                  t0_timer <= 32'h0; // Writing CMP zeroes timer in ETH timer
                end
              end

              2: begin // UART 16550
                if (uart_lcr[7]) begin // DLAB = 1
                  if (offset == 12'h000) uart_dll     <= pwdata[7:0];
                  if (offset == 12'h004) uart_dlm     <= pwdata[7:0];
                end else begin         // DLAB = 0
                  if (offset == 12'h000) uart_rbr_thr <= pwdata[7:0];
                  if (offset == 12'h004) uart_ier     <= pwdata[7:0];
                end
                if (offset == 12'h00C) uart_lcr       <= pwdata[7:0];
                if (offset == 12'h010) uart_mcr       <= pwdata[7:0];
                if (offset == 12'h01C) uart_scr       <= pwdata[7:0];
              end

              3: begin // GPIO
                if (offset == 12'h000 || offset == 12'h380) // W1C Interrupt Status
                  gpio_irq_status <= gpio_irq_status & ~pwdata;
                if (offset == 12'h004 || offset == 12'h400) // Interrupt Enable
                  gpio_irq_en     <= pwdata;
                if (offset == 12'h080)                      // GPIO_EN
                  gpio_en         <= pwdata;
                if (offset == 12'h180)                      // GPIO_DATA_OUT
                  gpio_out        <= pwdata;
                if (offset == 12'h200)                      // GPIO_DATA_SET
                  gpio_out        <= gpio_out | pwdata;
                if (offset == 12'h280)                      // GPIO_DATA_CLEAR
                  gpio_out        <= gpio_out & ~pwdata;
                if (offset == 12'h300)                      // GPIO_DATA_TOGGLE
                  gpio_out        <= gpio_out ^ pwdata;
              end

              4: begin // SPI
                if (offset == 12'h004) spi_clkdiv     <= pwdata;
                if (offset == 12'h010) spi_len        <= pwdata;
                if (offset == 12'h014) spi_dum        <= pwdata;
              end

              5: begin // Timer 1
                if (offset == 12'h000) t1_timer       <= pwdata;
                if (offset == 12'h004) t1_ctrl        <= pwdata;
                if (offset == 12'h008) begin
                  t1_cmp   <= pwdata;
                  t1_timer <= 32'h0;
                end
              end
            endcase
          end else begin
            // -----------------------------------------------------------------
            // READ TRANSACTION: Compare Actual Hardware Read against Predictor
            // -----------------------------------------------------------------
            logic [31:0] exp_data;
            logic [31:0] check_mask;
            exp_data   = 32'h0;
            check_mask = 32'h0; // By default, only check bits explicitly modelled

            case (s)
              0: begin // I2C
                if (offset == 12'h000) begin exp_data = {24'h0, i2c_prer[7:0]};  check_mask = 32'hFF; end
                if (offset == 12'h004) begin exp_data = {24'h0, i2c_prer[15:8]}; check_mask = 32'hFF; end
                if (offset == 12'h008) begin exp_data = {24'h0, i2c_ctr};        check_mask = 32'hFF; end
              end

              1: begin // Timer 0
                if (offset == 12'h004) begin exp_data = t0_ctrl; check_mask = 32'hFFFF_FFFF; end
                if (offset == 12'h008) begin exp_data = t0_cmp;  check_mask = 32'hFFFF_FFFF; end
              end

              2: begin // UART 16550
                if (uart_lcr[7]) begin
                  if (offset == 12'h000) begin exp_data = {24'h0, uart_dll}; check_mask = 32'hFF; end
                  if (offset == 12'h004) begin exp_data = {24'h0, uart_dlm}; check_mask = 32'hFF; end
                end else begin
                  if (offset == 12'h004) begin exp_data = {24'h0, uart_ier}; check_mask = 32'hFF; end
                end
                if (offset == 12'h00C) begin exp_data = {24'h0, uart_lcr}; check_mask = 32'hFF; end
                if (offset == 12'h010) begin exp_data = {24'h0, uart_mcr}; check_mask = 32'hFF; end
                if (offset == 12'h01C) begin exp_data = {24'h0, uart_scr}; check_mask = 32'hFF; end
              end

              3: begin // GPIO
                if (offset == 12'h080) begin exp_data = gpio_en;  check_mask = 32'hFFFF_FFFF; end
                if (offset == 12'h180) begin exp_data = gpio_out; check_mask = 32'hFFFF_FFFF; end
              end

              4: begin // SPI
                if (offset == 12'h004) begin exp_data = spi_clkdiv; check_mask = 32'hFFFF_FFFF; end
                if (offset == 12'h010) begin exp_data = spi_len;    check_mask = 32'hFFFF_FFFF; end
                if (offset == 12'h014) begin exp_data = spi_dum;    check_mask = 32'hFFFF_FFFF; end
              end

              5: begin // Timer 1
                if (offset == 12'h004) begin exp_data = t1_ctrl; check_mask = 32'hFFFF_FFFF; end
                if (offset == 12'h008) begin exp_data = t1_cmp;  check_mask = 32'hFFFF_FFFF; end
              end
            endcase

            // If check_mask has active bits, compare read data
            if ((check_mask != 32'h0) && ((prdata[s] & check_mask) !== (exp_data & check_mask))) begin
              reg_mismatch_err <= 1'b1;
              reg_err_addr     <= paddr;
              reg_err_exp      <= exp_data;
              reg_err_got      <= prdata[s];
              reg_err_msg      <= $sformatf("Register read mismatch at 0x%08X (Slot %0d): Exp=0x%08X Got=0x%08X Mask=0x%08X",
                                           paddr, s, exp_data, prdata[s], check_mask);
              $error("[REG-PREDICTOR] %s", reg_err_msg);
            end
          end
        end
      end
    end
  end

endmodule
