// =============================================================================
// RISCFORGE 1TOPS — SPI Master & Core Datapath Verification Testbench
// =============================================================================

`timescale 1ns / 1ps

module tb_spi0;
  import gpio_reg_pkg::GPIOCount;

  // ---------------------------------------------------------------------------
  // Clock & Reset Generation
  // ---------------------------------------------------------------------------
  localparam real CLK_PERIOD = 10.0; // 100 MHz clock (10 ns)

  logic clk;
  logic hard_rst_ni;
  logic soft_rst_ni;

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2.0) clk = ~clk;

  // ---------------------------------------------------------------------------
  // SoC Wires & Tie-offs
  // ---------------------------------------------------------------------------
  logic boot_done;

  // I2C
  logic i2c_scl_i, i2c_scl_o, i2c_scl_oen_o;
  logic i2c_sda_i, i2c_sda_o, i2c_sda_oen_o;
  logic i2c_interrupt_o;

  // Timers
  logic [3:0] timer0_irq;
  logic [3:0] timer1_irq;

  // UART
  logic uart_sin_i, uart_sout_o, uart_int_o;
  logic uart_out1n_o, uart_out2n_o, uart_rtsn_o, uart_dtrn_o;
  logic uart_ctsn_i, uart_dsrn_i, uart_dcdn_i, uart_rin_i;

  // GPIO
  localparam int unsigned NR_GPIOS = GPIOCount;
  logic [NR_GPIOS-1:0] gpio_in_i, gpio_out_o, gpio_tx_en_o, gpio_in_sync_o;
  logic gpio_global_interrupt_o;
  logic [NR_GPIOS-1:0] gpio_pin_level_interrupts_o;

  // SPI
  logic spi_clk_o;
  logic spi_csn0_o, spi_csn1_o, spi_csn2_o, spi_csn3_o;
  logic [1:0] spi_mode_o;
  logic spi_sdo0_o, spi_sdo1_o, spi_sdo2_o, spi_sdo3_o;
  logic spi_sdi0_i, spi_sdi1_i, spi_sdi2_i, spi_sdi3_i;
  logic [1:0] spi_events_o;

  initial begin
    i2c_scl_i       = 1'b1;
    i2c_sda_i       = 1'b1;
    uart_sin_i      = 1'b1;
    uart_ctsn_i     = 1'b1;
    uart_dsrn_i     = 1'b1;
    uart_dcdn_i     = 1'b1;
    uart_rin_i      = 1'b1;
    gpio_in_i       = '0;
    spi_sdi0_i      = 1'b0;
    spi_sdi2_i      = 1'b0;
    spi_sdi3_i      = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // Infineon S25FS512S Vendor SPI Flash Model
  // ---------------------------------------------------------------------------
  wire flash_si;
  wire flash_so;
  wire flash_wpn;
  wire flash_resetn;

  assign flash_si     = spi_sdo0_o;   // MOSI from master
  assign spi_sdi1_i   = flash_so;     // MISO into master (IO1)
  assign flash_wpn    = 1'b1;         // write protect deasserted
  assign flash_resetn = 1'b1;         // chip not held in reset

  s25fs512s #(
    .UserPreload   ( 0                                                        ),
    .mem_file_name ( "none"                                                   ),
    .otp_file_name ( "../spi_slave_infinion/S25fs512s/model/s25fs512sOTP.mem" )
  ) u_flash (
    .SI       ( flash_si     ),
    .SO       ( flash_so     ),
    .SCK      ( spi_clk_o    ),
    .CSNeg    ( spi_csn0_o   ),
    .WPNeg    ( flash_wpn    ),
    .RESETNeg ( flash_resetn )
  );

  // ---------------------------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------------------------
  riscforge_soc_subsystem #(
    .AXI_ADDR_WIDTH       ( 32 ),
    .AXI_DATA_WIDTH       ( 32 ),
    .TIMER0_CNT           ( 2  ),
    .TIMER1_CNT           ( 2  ),
    .SPI_BUFFER_DEPTH     ( 10 ),
    .BOOTROM_NUM_WORDS    ( 16 ),
    .NUM_INSTR_WORDS      ( 0  ),
    .NUM_DATA_WORDS       ( 0  ),
    .FLASH_POWERUP_CYCLES ( 10 )
  ) dut (
    .clk_i                    ( clk                     ),
    .hard_rst_ni              ( hard_rst_ni              ),
    .soft_rst_ni              ( soft_rst_ni              ),
    .test_mode_i              ( 1'b0                     ),
    .fetch_enable_i           ( 1'b0                     ),
    .boot_addr_i              ( 32'h0000_0000            ),
    .boot_done_o              ( boot_done                ),

    // I2C
    .i2c_scl_i                ( i2c_scl_i                ),
    .i2c_scl_o                ( i2c_scl_o                ),
    .i2c_scl_oen_o            ( i2c_scl_oen_o            ),
    .i2c_sda_i                ( i2c_sda_i                ),
    .i2c_sda_o                ( i2c_sda_o                ),
    .i2c_sda_oen_o            ( i2c_sda_oen_o            ),
    .i2c_interrupt_o          ( i2c_interrupt_o          ),

    // Timers
    .timer0_irq_o             ( timer0_irq               ),
    .timer1_irq_o             ( timer1_irq               ),

    // UART
    .uart_sin_i               ( uart_sin_i               ),
    .uart_sout_o              ( uart_sout_o              ),
    .uart_int_o               ( uart_int_o               ),

    // GPIO
    .gpio_in_i                ( gpio_in_i                ),
    .gpio_out_o               ( gpio_out_o               ),
    .gpio_tx_en_o             ( gpio_tx_en_o             ),
    .gpio_in_sync_o           ( gpio_in_sync_o           ),
    .gpio_global_interrupt_o  ( gpio_global_interrupt_o ),
    .gpio_pin_level_interrupts_o ( gpio_pin_level_interrupts_o ),

    // SPI
    .spi_clk_o                ( spi_clk_o                ),
    .spi_csn0_o               ( spi_csn0_o               ),
    .spi_csn1_o               ( spi_csn1_o               ),
    .spi_sdo0_o               ( spi_sdo0_o               ),
    .spi_sdi1_i               ( spi_sdi1_i               ),
    .spi_events_o             ( spi_events_o             )
  );

  // ---------------------------------------------------------------------------
  // Memory Preloading Task
  // ---------------------------------------------------------------------------
  string imem_hex = "../datapath_verification/spi0/imem.hex";
  string dmem_hex = "../datapath_verification/spi0/dmem.hex";

  initial begin
    #1;
    if ($value$plusargs("IMEM_HEX=%s", imem_hex)) begin
      $display("[TB] Using custom IMEM hex: %s", imem_hex);
    end
    if ($value$plusargs("DMEM_HEX=%s", dmem_hex)) begin
      $display("[TB] Using custom DMEM hex: %s", dmem_hex);
    end

    $display("[TB] Loading ISRAM from '%s'...", imem_hex);
    $readmemh(imem_hex, dut.i_isram.u_imem.mem_array);
    $display("[TB] Loading DSRAM from '%s'...", dmem_hex);
    $readmemh(dmem_hex, dut.i_dsram.mem);
  end

  // ---------------------------------------------------------------------------
  // UART Serial Receiver Monitor
  // ---------------------------------------------------------------------------
  string rx_string = "";
  bit    test_passed = 1'b0;

  task automatic monitor_uart_tx();
    logic [7:0] rx_byte;
    realtime bit_time;

    bit_time = 32.0 * CLK_PERIOD; // 32 clocks per bit for DLL=2

    forever begin
      @(negedge uart_sout_o);
      #(bit_time / 2.0);

      if (uart_sout_o == 1'b0) begin
        rx_byte = 8'h00;
        for (int b = 0; b < 8; b++) begin
          #bit_time;
          rx_byte[b] = uart_sout_o;
        end
        #bit_time;

        $write("%c", rx_byte);
        $fflush();

        rx_string = {rx_string, string'(rx_byte)};

        if (rx_string.len() >= 31) begin
          if (rx_string.substr(rx_string.len()-31, rx_string.len()-1) == ">>> TEST RESULT: [ PASSED ] <<<") begin
            test_passed = 1'b1;
          end
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Diagnostic Monitors
  // ---------------------------------------------------------------------------
  always @(posedge dut.core_rst_n) begin
    $display("[TB-DIAG] @%0t Core Reset Released! boot_done=%b, PC=0x%08h", $time, dut.boot_done_o, dut.i_riscv_core.Fetch.PCF);
  end

  always @(dut.i_bootloader.state_q) begin
    $display("[TB-DIAG] @%0t Bootloader State -> %s", $time, dut.i_bootloader.state_q.name());
  end

  // ---------------------------------------------------------------------------
  // Simulation Main Process
  // ---------------------------------------------------------------------------
  initial begin
    $display("===============================================================");
    $display("    RISCFORGE 1TOPS — SPI MASTER & DATAPATH SIMULATION        ");
    $display("===============================================================");

    // Warm Boot: hard_rst_ni=1, pulse soft_rst_ni to preserve preloaded SRAMs
    hard_rst_ni = 1'b1;
    soft_rst_ni = 1'b0;

    // hard_rst_ni is never asserted here, so the SoC soft-reset filter flops
    // (async-reset by hard_rst_ni only) would start X and stay X. Give them the
    // state they hold after power-up with soft_rst_ni low, then let them run.
    force dut.soft_rst_meta_q   = 2'b00;
    force dut.soft_rst_cnt_q    = '0;
    force dut.soft_rst_n_filt_q = 1'b0;
    @(posedge clk);
    release dut.soft_rst_meta_q;
    release dut.soft_rst_cnt_q;
    release dut.soft_rst_n_filt_q;

    repeat (19) @(posedge clk);
    soft_rst_ni = 1'b1;
    $display("[TB] Warm reset de-asserted at t = %0t ns\n", $time);

    fork
      monitor_uart_tx();
    join_none

    fork
      begin
        wait(test_passed == 1'b1);
        repeat (2000) @(posedge clk);
        $display("\n===============================================================");
        $display(" [SIMULATION SUCCESS] All 5 SPI Master tests verified successfully!");
        $display("===============================================================");
        $finish(0);
      end
      begin
        repeat (1000000) @(posedge clk);
        $display("\n===============================================================");
        $display(" [SIMULATION TIMEOUT] Reached maximum cycle limit.");
        if (test_passed) begin
          $display(" Status: PASSED (banner received before timeout)");
        end else begin
          $display(" Status: FAILED (no final PASSED banner received)");
        end
        $display("===============================================================");
        $finish(1);
      end
    join_any
  end

endmodule
