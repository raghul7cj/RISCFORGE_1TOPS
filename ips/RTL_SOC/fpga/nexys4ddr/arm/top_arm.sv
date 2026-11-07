// =============================================================================
// RISCFORGE 1TOPS — Nexys 4 DDR board top, test "arm" (XC7A100T-1CSG324C)
// =============================================================================
// Build: build.bat   Program: program.bat   (both in this folder, fpga/nexys4ddr/arm/)
// Drives the WidowX-200 arm (7 x Dynamixel XL430-W250, Protocol 2.0, 1 Mbps)
// from riscforge_soc_subsystem. Same board top as test "pong" except:
//   - SoC clock 32 MHz (was 40 MHz), so the SoC UART reaches exactly 1 Mbps:
//     divisor {DLM,DLL} = 32 MHz / (16 x 1 Mbps) = 2.
//   - The SoC UART drives the Dynamixel half-duplex DATA line on Pmod JA
//     through an external 3.3 V <-> 5 V direction-controlled buffer
//     (e.g. 74LVC1T45). GPIO[16] (DXL_DIR) selects the direction.
//   - Switches and buttons are GPIO inputs; gpio_out drives LED[15:4].
// No SoC RTL is changed; the two board-specific parameters inside the SoC are
// set with defparam (see "Board overrides" below).
//
// Dynamixel bus (Pmod JA)
//   JA1  DXL_DATA  inout   to the buffer's A port (3.3 V side)
//   JA2  DXL_DIR   output  to the buffer's DIR: 1 = FPGA -> servos (transmit),
//                          0 = servos -> FPGA (receive)
//   JA5  GND, JA6  3.3 V   buffer VCCA
//   DXL_DIR = 1: JA1 drives uart_sout, the UART receiver sees idle (1), so the
//                SoC does not hear its own transmission.
//   DXL_DIR = 0: JA1 is high-Z (pulled up), the UART receiver reads JA1.
//   GPIO reset value is 0, so the bus is never driven before the firmware runs.
//   The PC USB-UART (UART_RXD_OUT) always mirrors uart_sout: a terminal at
//   1000000 baud shows the firmware's status text (sent with DXL_DIR = 0, so it
//   never reaches the servos) and, as binary noise, the servo packets.
//
// Link select: SW13 (set it before reset / power-on)
//   SW13 = 0  direct: the servo bus on Pmod JA as above.
//   SW13 = 1  laptop relay: no Pmod wiring. The SoC UART talks to the laptop
//             over the board's USB-UART (TX = UART_RXD_OUT, RX = UART_TXD_IN),
//             and the laptop's dxl_relay.py passes the servo packets to a U2D2
//             on the arm and the answers back. JA1 stays released and DXL_DIR
//             stays 0. The firmware also reads SW13 (gpio_in[13]) and waits
//             longer for servo answers (USB delay).
//
// GPIO map
//   gpio_in[15:0]   SW[15:0]
//   gpio_in[16]     BTNC   gpio_in[17] BTNU   gpio_in[18] BTND
//   gpio_in[19]     BTNL   gpio_in[20] BTNR
//   gpio_in[21]     PS2_CLK  pin level (keyboard from the USB HOST port)
//   gpio_in[22]     PS2_DATA pin level
//   gpio_out[11:0]  LED[15:4] = gpio_out[11:0]
//   gpio_out[16]    DXL_DIR
//   gpio_out[17]    1 = pull PS2_CLK low  (open drain; 0 = released)
//   gpio_out[18]    1 = pull PS2_DATA low (open drain; 0 = released)
//
// Keyboard: the Nexys 4 DDR's PIC24 turns a USB keyboard on the USB HOST
// connector into PS/2 on PS2_CLK (F4) / PS2_DATA (B2). Both pins are only
// wired to GPIO here, as open-drain lines; the firmware decodes PS/2.
//
// Boot flash = the on-board QSPI configuration flash (Spansion S25FL128S, 16 MB)
//   0x00_0000  FPGA bitstream (~3.8 MB for the XC7A100T)
//   0x40_0000  firmware image (arm_flash.mem as raw bytes), FLASH_IMAGE_ADDR
//   Both are merged into one .mcs by build.tcl (write_cfgmem).
//
// Flash clock: the flash SCK is the dedicated configuration pin CCLK (E9),
// which user logic can only drive through STARTUPE2.USRCCLKO. STARTUPE2 drops
// the first 3 USRCCLKO edges after end of configuration while it switches the
// clock source (UG470, "STARTUPE2"), so before the SoC is released from reset
// this wrapper sends PREBOOT_CLKS dummy clocks with the flash deselected. The
// bootloader's first 0x03 read then reaches the flash intact.
//
// Flash data pins, standard SPI only (the SoC has no quad mode):
//   DQ0 = MOSI (spi_sdo0_o)   DQ1 = MISO (spi_sdi1_i)   DQ2 = WP#  DQ3 = HOLD#
//   WP# and HOLD# are driven high.
//
// Clock: the SoC runs at 32 MHz from an MMCM (100 MHz x 8 / 25). Firmware must
// be built for SOC_CLK_HZ (mem/arm/arm.c CLK_HZ).
//
// Reset: CPU_RESETN (active low) holds the SoC in hard reset. Releasing it
// starts a cold boot, so the button re-runs boot from flash. The SoC
// synchronizes hard_rst_ni internally (hard_rst_sync_q).
//
// LEDs
//   LED[0]  boot_done (image loaded, core running)
//   LED[1]  pre-boot dummy clocks done
//   LED[2]  any bus-timeout monitor fired (should stay off)
//   LED[3]  UART TX activity (stretched)
//   LED[15:4] gpio_out_o[11:0] (meaning set by the firmware, see arm.c)
//
// Simulation: STARTUPE2 and the MMCM exist only under `SYNTHESIS (Vivado
// defines it). In simulation the SoC runs directly on CLK100MHZ, and the
// flash clock is the internal net flash_sck.
// =============================================================================

module top_arm
  import gpio_reg_pkg::GPIOCount;
#(
  // Boot ROM image. build.tcl passes an absolute path; the default is the
  // simulation run directory (ips/RTL_SOC/sim/).
  parameter string       BOOTROM_HEX      = "../mem/common/riscforge_bootrom.hex",
  // Flash byte address of the firmware image; must clear the bitstream.
  parameter logic [23:0] FLASH_IMAGE_ADDR = 24'h40_0000,
  // Dummy flash clocks after configuration (>= 3, see header)
  parameter int unsigned PREBOOT_CLKS     = 8
)(
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,

  input  logic        UART_TXD_IN,     // PC -> FPGA (used in laptop-relay mode, SW13 = 1)
  output logic        UART_RXD_OUT,    // FPGA -> PC (mirror of the SoC UART TX)

  output logic        QSPI_CSN,
  output logic        QSPI_DQ0,        // MOSI
  input  logic        QSPI_DQ1,        // MISO
  output logic        QSPI_DQ2,        // WP#
  output logic        QSPI_DQ3,        // HOLD#

  input  logic [15:0] SW,
  input  logic        BTNC,
  input  logic        BTNU,
  input  logic        BTND,
  input  logic        BTNL,
  input  logic        BTNR,

  inout  wire         DXL_DATA,        // Pmod JA1
  output logic        DXL_DIR,         // Pmod JA2

  inout  wire         PS2_CLK,         // from the PIC24 (USB HOST keyboard)
  inout  wire         PS2_DATA,

  output logic [15:0] LED
);

  // Firmware word counts (FW_NUM_INSTR_WORDS / FW_NUM_DATA_WORDS) generated
  // by mem/arm/build.py. Vivado: +incdir mem/arm.
  `include "fw_params.svh"

  localparam int unsigned NR_GPIOS   = GPIOCount;
  localparam int unsigned SOC_CLK_HZ = 32_000_000;

  localparam int unsigned GPIO_DXL_DIR      = 16;
  localparam int unsigned GPIO_PS2_CLK_LOW  = 17;
  localparam int unsigned GPIO_PS2_DATA_LOW = 18;

  // ───────────────────────────────────────────────────────────────────────
  //  SoC clock: 32 MHz from the 100 MHz oscillator
  // ───────────────────────────────────────────────────────────────────────
  logic clk;            // SoC clock, everything below runs on it
  logic clk_locked;

`ifdef SYNTHESIS
  logic clk_mmcm, clkfb_mmcm, clkfb_buf;

  MMCME2_BASE #(
    .CLKIN1_PERIOD    ( 10.000 ),   // 100 MHz
    .DIVCLK_DIVIDE    ( 1      ),
    .CLKFBOUT_MULT_F  ( 8.000  ),   // VCO 800 MHz
    .CLKOUT0_DIVIDE_F ( 25.000 )    // 32 MHz
  ) u_mmcm (
    .CLKIN1    ( CLK100MHZ  ),
    .CLKFBIN   ( clkfb_buf  ),
    .CLKFBOUT  ( clkfb_mmcm ),
    .CLKFBOUTB (            ),
    .CLKOUT0   ( clk_mmcm   ),
    .CLKOUT0B  (            ),
    .CLKOUT1   (            ),
    .CLKOUT1B  (            ),
    .CLKOUT2   (            ),
    .CLKOUT2B  (            ),
    .CLKOUT3   (            ),
    .CLKOUT3B  (            ),
    .CLKOUT4   (            ),
    .CLKOUT5   (            ),
    .CLKOUT6   (            ),
    .LOCKED    ( clk_locked ),
    .PWRDWN    ( 1'b0       ),
    .RST       ( 1'b0       )
  );

  BUFG u_bufg_fb  ( .I ( clkfb_mmcm ), .O ( clkfb_buf ) );
  BUFG u_bufg_clk ( .I ( clk_mmcm   ), .O ( clk       ) );
`else
  assign clk        = CLK100MHZ;
  assign clk_locked = 1'b1;
`endif

  // ───────────────────────────────────────────────────────────────────────
  //  STARTUPE2: flash clock and end-of-startup
  // ───────────────────────────────────────────────────────────────────────
  logic flash_sck;      // drives CCLK
  logic eos;            // end of startup: FPGA configuration finished

`ifdef SYNTHESIS
  STARTUPE2 #(
    .PROG_USR      ( "FALSE" ),
    .SIM_CCLK_FREQ ( 0.0     )
  ) u_startup (
    .CFGCLK    (           ),
    .CFGMCLK   (           ),
    .EOS       ( eos       ),
    .PREQ      (           ),
    .CLK       ( 1'b0      ),
    .GSR       ( 1'b0      ),
    .GTS       ( 1'b0      ),
    .KEYCLEARB ( 1'b1      ),
    .PACK      ( 1'b0      ),
    .USRCCLKO  ( flash_sck ),
    .USRCCLKTS ( 1'b0      ),   // CCLK driven by USRCCLKO
    .USRDONEO  ( 1'b1      ),
    .USRDONETS ( 1'b1      )
  );
`else
  assign eos = 1'b1;
`endif

  // ───────────────────────────────────────────────────────────────────────
  //  Pre-boot sequencer: wait for EOS and MMCM lock, send PREBOOT_CLKS dummy
  //  clocks with the flash deselected (SCK = clk / 16), then release the SoC.
  // ───────────────────────────────────────────────────────────────────────
  typedef enum logic [1:0] { PB_WAIT_EOS, PB_CLOCKS, PB_DONE } pb_state_e;

  pb_state_e   pb_state_q;
  logic [2:0]  pb_div_q;
  logic [7:0]  pb_cnt_q;
  logic        pb_sck_q;
  logic [1:0]  eos_sync_q;

  // Power-on: registers start at their init values after configuration.
  initial begin
    pb_state_q = PB_WAIT_EOS;
    pb_div_q   = '0;
    pb_cnt_q   = '0;
    pb_sck_q   = 1'b0;
    eos_sync_q = '0;
  end

  always_ff @(posedge clk) begin
    eos_sync_q <= {eos_sync_q[0], eos & clk_locked};
    case (pb_state_q)
      PB_WAIT_EOS:
        if (eos_sync_q[1]) pb_state_q <= PB_CLOCKS;
      PB_CLOCKS: begin
        pb_div_q <= pb_div_q + 3'd1;
        if (pb_div_q == 3'd7) begin
          pb_sck_q <= ~pb_sck_q;
          if (pb_sck_q) begin                       // falling edge: one clock done
            pb_cnt_q <= pb_cnt_q + 8'd1;
            if (pb_cnt_q + 8'd1 >= PREBOOT_CLKS[7:0])
              pb_state_q <= PB_DONE;
          end
        end
      end
      default: ;                                    // PB_DONE: stays
    endcase
  end

  wire preboot_done = (pb_state_q == PB_DONE);

  // ───────────────────────────────────────────────────────────────────────
  //  SoC
  // ───────────────────────────────────────────────────────────────────────
  logic                       boot_done;
  logic                       i2c_scl_o, i2c_scl_oen_o, i2c_sda_o, i2c_sda_oen_o, i2c_interrupt_o;
  logic [3:0]                 timer0_irq, timer1_irq;
  logic                       uart_sin, uart_sout, uart_int;
  logic [NR_GPIOS-1:0]        gpio_in, gpio_out, gpio_tx_en, gpio_in_sync, gpio_lvl_irq;
  logic                       gpio_global_irq;
  logic                       spi_clk, spi_csn0, spi_csn1, spi_sdo0;
  logic [1:0]                 spi_events;
  logic [5:0]                 apb_timeout_sticky;
  logic                       axi_wr_timeout_sticky, axi_rd_timeout_sticky;

  always_comb begin
    gpio_in        = '0;
    gpio_in[15:0]  = SW;
    gpio_in[16]    = BTNC;
    gpio_in[17]    = BTNU;
    gpio_in[18]    = BTND;
    gpio_in[19]    = BTNL;
    gpio_in[20]    = BTNR;
    gpio_in[21]    = PS2_CLK;
    gpio_in[22]    = PS2_DATA;
  end

  riscforge_soc_subsystem #(
    .TIMER0_CNT           ( 2                  ),
    .TIMER1_CNT           ( 2                  ),
    .SPI_BUFFER_DEPTH     ( 10                 ),
    .NUM_INSTR_WORDS      ( FW_NUM_INSTR_WORDS ),
    .NUM_DATA_WORDS       ( FW_NUM_DATA_WORDS  ),
    .FLASH_POWERUP_CYCLES ( 30_000             )   // 940 us at 32 MHz (S25FL128S tPU = 300 us)
  ) u_soc (
    .clk_i                       ( clk                         ),
    .hard_rst_ni                 ( CPU_RESETN & preboot_done   ),
    .soft_rst_ni                 ( 1'b1                        ),
    .test_mode_i                 ( 1'b0                        ),
    .fetch_enable_i              ( 1'b1                        ),
    .boot_addr_i                 ( 32'h0000_0000               ),
    .boot_done_o                 ( boot_done                   ),

    .i2c_scl_i                   ( 1'b1                        ),   // no I2C on this build
    .i2c_scl_o                   ( i2c_scl_o                   ),
    .i2c_scl_oen_o               ( i2c_scl_oen_o               ),
    .i2c_sda_i                   ( 1'b1                        ),
    .i2c_sda_o                   ( i2c_sda_o                   ),
    .i2c_sda_oen_o               ( i2c_sda_oen_o               ),
    .i2c_interrupt_o             ( i2c_interrupt_o             ),

    .timer0_irq_o                ( timer0_irq                  ),
    .timer1_irq_o                ( timer1_irq                  ),

    .uart_sin_i                  ( uart_sin                    ),
    .uart_sout_o                 ( uart_sout                   ),
    .uart_int_o                  ( uart_int                    ),

    .gpio_in_i                   ( gpio_in                     ),
    .gpio_out_o                  ( gpio_out                    ),
    .gpio_tx_en_o                ( gpio_tx_en                  ),
    .gpio_in_sync_o              ( gpio_in_sync                ),
    .gpio_global_interrupt_o     ( gpio_global_irq             ),
    .gpio_pin_level_interrupts_o ( gpio_lvl_irq                ),

    .spi_clk_o                   ( spi_clk                     ),
    .spi_csn0_o                  ( spi_csn0                    ),
    .spi_csn1_o                  ( spi_csn1                    ),
    .spi_sdo0_o                  ( spi_sdo0                    ),
    .spi_sdi1_i                  ( QSPI_DQ1                    ),
    .spi_events_o                ( spi_events                  ),

    .apb_timeout_sticky_o        ( apb_timeout_sticky          ),
    .axi_wr_timeout_sticky_o     ( axi_wr_timeout_sticky       ),
    .axi_rd_timeout_sticky_o     ( axi_rd_timeout_sticky       )
  );

  // Board overrides of parameters the SoC does not expose
  defparam u_soc.i_bootloader.FLASH_START_ADDR = FLASH_IMAGE_ADDR;
  defparam u_soc.i_boot_rom.HEX_FILE           = BOOTROM_HEX;

  // ───────────────────────────────────────────────────────────────────────
  //  Flash pins
  // ───────────────────────────────────────────────────────────────────────
  assign flash_sck    = preboot_done ? spi_clk  : pb_sck_q;
  assign QSPI_CSN     = preboot_done ? spi_csn0 : 1'b1;
  assign QSPI_DQ0     = spi_sdo0;
  assign QSPI_DQ2     = 1'b1;
  assign QSPI_DQ3     = 1'b1;

  // ───────────────────────────────────────────────────────────────────────
  //  Dynamixel half-duplex bus
  // ───────────────────────────────────────────────────────────────────────
  wire relay   = SW[13];                                   // 1 = laptop relay link
  wire dxl_dir = gpio_out[GPIO_DXL_DIR] & ~relay;

  assign DXL_DATA     = dxl_dir ? uart_sout : 1'bz;
  assign uart_sin     = relay   ? UART_TXD_IN :
                        dxl_dir ? 1'b1        : DXL_DATA;
  assign DXL_DIR      = dxl_dir;
  assign UART_RXD_OUT = uart_sout;

  // ───────────────────────────────────────────────────────────────────────
  //  PS/2 keyboard pins: open drain, decoded by the firmware through GPIO
  // ───────────────────────────────────────────────────────────────────────
  assign PS2_CLK  = gpio_out[GPIO_PS2_CLK_LOW]  ? 1'b0 : 1'bz;
  assign PS2_DATA = gpio_out[GPIO_PS2_DATA_LOW] ? 1'b0 : 1'bz;

  // ───────────────────────────────────────────────────────────────────────
  //  LEDs
  // ───────────────────────────────────────────────────────────────────────
  logic [21:0] tx_led_q;      // ~130 ms stretch at 32 MHz

  always_ff @(posedge clk) begin
    if (!uart_sout)          tx_led_q <= '1;
    else if (tx_led_q != 0)  tx_led_q <= tx_led_q - 22'd1;
  end

  assign LED[0]    = boot_done;
  assign LED[1]    = preboot_done;
  assign LED[2]    = |{apb_timeout_sticky, axi_wr_timeout_sticky, axi_rd_timeout_sticky};
  assign LED[3]    = (tx_led_q != 0);
  assign LED[15:4] = gpio_out[11:0];

endmodule : top_arm
