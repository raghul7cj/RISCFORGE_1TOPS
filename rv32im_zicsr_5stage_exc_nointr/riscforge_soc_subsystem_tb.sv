`timescale 1ns / 1ps
// =============================================================================
// RISCFORGE 1TOPS — SoC Verification Top Wrapper (tb_riscof & compliance DUT)
// =============================================================================
// Encapsulates the 5-stage RISC-V core, Instruction Memory SRAM,
// Data Memory SRAM, and SystemVerilog hybrid_mem_interface.
//
// Compliant with axi_pkg standard AXI4-Lite interface. Unused AXI MMIO master
// is left open without requiring external peripheral or dummy slave IP.
// =============================================================================

module riscforge_soc_subsystem_tb #(
  parameter int unsigned AXI_ADDR_WIDTH    = 32,
  parameter int unsigned AXI_DATA_WIDTH    = 32,
  parameter int unsigned TIMER_CNT         = 2,
  parameter int unsigned SPI_BUFFER_DEPTH  = 10,
  parameter int unsigned NR_GPIOS          = 32,
  parameter int unsigned ISRAM_NUM_WORDS   = 1048576,       // 4 MB default
  parameter int unsigned DSRAM_NUM_WORDS   = 1048576,       // 4 MB default
  parameter [31:0]       ISRAM_BASE_ADDR   = 32'h8000_0000,
  parameter [31:0]       DSRAM_BASE_ADDR   = 32'h8000_1000,
  parameter int unsigned NUM_INSTR_WORDS   = 64,
  parameter int unsigned NUM_DATA_WORDS    = 0,
  parameter int unsigned FLASH_POWERUP_CYCLES = 30_000,
  localparam int unsigned AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8
)(
  // Global
  input  logic                          clk_i,
  input  logic                          hard_rst_ni,
  input  logic                          soft_rst_ni,
  input  logic                          test_mode_i,

  // Core Control & Observability
  input  logic                          fetch_enable_i,
  input  logic [31:0]                   boot_addr_i,
  output logic [31:0]                   core_pc_w_o,
  output logic                          boot_done_o,

  // Peripheral Interface Stubs
  input  logic                          i2c_scl_i,
  output logic                          i2c_scl_o,
  output logic                          i2c_scl_oen_o,
  input  logic                          i2c_sda_i,
  output logic                          i2c_sda_o,
  output logic                          i2c_sda_oen_o,
  output logic                          i2c_interrupt_o,

  output logic [(TIMER_CNT*2)-1:0]      timer_irq_o,

  input  logic                          uart_sin_i,
  output logic                          uart_sout_o,
  output logic                          uart_int_o,
  output logic                          uart_out1n_o,
  output logic                          uart_out2n_o,
  output logic                          uart_rtsn_o,
  output logic                          uart_dtrn_o,
  input  logic                          uart_ctsn_i,
  input  logic                          uart_dsrn_i,
  input  logic                          uart_dcdn_i,
  input  logic                          uart_rin_i,

  input  logic [NR_GPIOS-1:0]           gpio_in_i,
  output logic [NR_GPIOS-1:0]           gpio_out_o,
  output logic [NR_GPIOS-1:0]           gpio_tx_en_o,
  output logic [NR_GPIOS-1:0]           gpio_in_sync_o,
  output logic                          gpio_global_interrupt_o,
  output logic [NR_GPIOS-1:0]           gpio_pin_level_interrupts_o,

  output logic                          spi_clk_o,
  output logic                          spi_csn0_o,
  output logic                          spi_csn1_o,
  output logic                          spi_csn2_o,
  output logic                          spi_csn3_o,
  output logic [1:0]                    spi_mode_o,
  output logic                          spi_sdo0_o,
  output logic                          spi_sdo1_o,
  output logic                          spi_sdo2_o,
  output logic                          spi_sdo3_o,
  input  logic                          spi_sdi0_i,
  input  logic                          spi_sdi1_i,
  input  logic                          spi_sdi2_i,
  input  logic                          spi_sdi3_i,
  output logic [1:0]                    spi_events_o
);

  wire core_rst_n;
  assign core_rst_n = hard_rst_ni & soft_rst_ni;

  // Peripheral stubs
  assign boot_done_o                 = 1'b1;
  assign i2c_scl_o                   = 1'b1;
  assign i2c_scl_oen_o               = 1'b1;
  assign i2c_sda_o                   = 1'b1;
  assign i2c_sda_oen_o               = 1'b1;
  assign i2c_interrupt_o             = 1'b0;
  assign timer_irq_o                 = '0;
  assign uart_sout_o                 = 1'b1;
  assign uart_int_o                  = 1'b0;
  assign uart_out1n_o                = 1'b1;
  assign uart_out2n_o                = 1'b1;
  assign uart_rtsn_o                 = 1'b1;
  assign uart_dtrn_o                 = 1'b1;
  assign gpio_out_o                  = '0;
  assign gpio_tx_en_o                = '0;
  assign gpio_in_sync_o              = '0;
  assign gpio_global_interrupt_o     = 1'b0;
  assign gpio_pin_level_interrupts_o = '0;
  assign spi_clk_o                   = 1'b0;
  assign spi_csn0_o                  = 1'b1;
  assign spi_csn1_o                  = 1'b1;
  assign spi_csn2_o                  = 1'b1;
  assign spi_csn3_o                  = 1'b1;
  assign spi_mode_o                  = 2'b00;
  assign spi_sdo0_o                  = 1'b0;
  assign spi_sdo1_o                  = 1'b0;
  assign spi_sdo2_o                  = 1'b0;
  assign spi_sdo3_o                  = 1'b0;
  assign spi_events_o                = 2'b00;

  // Instruction Memory interface wires
  wire        core_imem_en;
  wire        core_imem_we;
  wire [3:0]  core_imem_wmask;
  wire [29:0] core_imem_addr;
  wire [31:0] core_imem_wdata;
  wire [31:0] core_imem_rdata;

  // LSU Data Memory interface wires
  wire        core_lsu_req;
  wire        core_lsu_we;
  wire [31:0] core_lsu_addr;
  wire [31:0] core_lsu_wdata;
  wire [3:0]  core_lsu_be;
  wire [31:0] core_lsu_rdata;
  wire        core_lsu_stall;
  wire        core_lsu_err;

  // HMIF to Data Memory SRAM wires
  wire        hmif_sram_en;
  wire        hmif_sram_we;
  wire [3:0]  hmif_sram_wmask;
  wire [29:0] hmif_sram_addr;
  wire [31:0] hmif_sram_wdata;
  wire [31:0] hmif_sram_rdata;

  // 1. RISC-V 5-Stage Core
  top i_riscv_core (
    .clk             ( clk_i           ),
    .rst             ( core_rst_n      ),
    .PCSrcE1         (                 ),

    .imem_sram_en    ( core_imem_en    ),
    .imem_sram_we    ( core_imem_we    ),
    .imem_sram_wmask ( core_imem_wmask ),
    .imem_sram_addr  ( core_imem_addr  ),
    .imem_sram_wdata ( core_imem_wdata ),
    .imem_sram_rdata ( core_imem_rdata ),

    .lsu_mem_req     ( core_lsu_req    ),
    .lsu_mem_we      ( core_lsu_we     ),
    .lsu_mem_addr    ( core_lsu_addr   ),
    .lsu_mem_wdata   ( core_lsu_wdata  ),
    .lsu_mem_be      ( core_lsu_be     ),
    .lsu_mem_rdata   ( core_lsu_rdata  ),
    .lsu_mem_stall   ( core_lsu_stall  ),
    .lsu_mem_err     ( core_lsu_err    ),

    .fast_irq_i      ( 16'b0           ),
    .timer_irq_i     ( 1'b0            ),
    .ext_irq_i       ( 1'b0            ),
    .sw_irq_i        ( 1'b0            )
  );

  assign core_pc_w_o = i_riscv_core.PC_W;

  // 2. Instruction Memory (SRAM)
  Instruction_Memory_new #(
    .MEM_DEPTH      ( ISRAM_NUM_WORDS ),
    .IMEM_BASE_BYTE ( ISRAM_BASE_ADDR )
  ) i_isram (
    .clk       ( clk_i           ),
    .rst_n     ( core_rst_n      ),
    .sram_en   ( core_imem_en    ),
    .sram_we   ( core_imem_we    ),
    .sram_wmask( core_imem_wmask ),
    .sram_addr ( core_imem_addr  ),
    .sram_wdata( core_imem_wdata ),
    .sram_rdata( core_imem_rdata )
  );

  // 3. LSU Hybrid Memory Router (SystemVerilog)
  axi_pkg::axi_lite_resp_t axi_mmio_resp;
  assign axi_mmio_resp = '0;

  hybrid_mem_interface #(
    .MEM_DEPTH      ( DSRAM_NUM_WORDS          ),
    .DMEM_BASE_BYTE ( DSRAM_BASE_ADDR          ),
    .MMIO_BASE      ( 32'h4000_0000            ),
    .MMIO_LIMIT     ( 32'h4FFF_FFFF            )
  ) i_hybrid_mem_if (
    .clk            ( clk_i           ),
    .rst_n          ( core_rst_n      ),

    .mem_req        ( core_lsu_req    ),
    .mem_we         ( core_lsu_we     ),
    .mem_addr       ( core_lsu_addr   ),
    .mem_wdata      ( core_lsu_wdata  ),
    .mem_be         ( core_lsu_be     ),
    .mem_rdata      ( core_lsu_rdata  ),
    .mem_stall      ( core_lsu_stall  ),
    .mem_err        ( core_lsu_err    ),

    .sram_en        ( hmif_sram_en    ),
    .sram_we        ( hmif_sram_we    ),
    .sram_wmask     ( hmif_sram_wmask ),
    .sram_addr      ( hmif_sram_addr  ),
    .sram_wdata     ( hmif_sram_wdata ),
    .sram_rdata     ( hmif_sram_rdata ),

    .m_axi_req_o    ( /* open */      ),
    .m_axi_resp_i   ( axi_mmio_resp   )
  );

  // 4. Data Memory (SRAM)
  Data_Memory #(
    .MEM_DEPTH      ( DSRAM_NUM_WORDS ),
    .DMEM_BASE_BYTE ( DSRAM_BASE_ADDR )
  ) i_dsram (
    .clk        ( clk_i           ),
    .rst_n      ( core_rst_n      ),
    .sram_en    ( hmif_sram_en    ),
    .sram_we    ( hmif_sram_we    ),
    .sram_wmask ( hmif_sram_wmask ),
    .sram_addr  ( hmif_sram_addr  ),
    .sram_wdata ( hmif_sram_wdata ),
    .sram_rdata ( hmif_sram_rdata )
  );

endmodule
