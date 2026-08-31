// =============================================================================
// RISCFORGE 1TOPS — SoC Peripheral Subsystem Top-Level
// =============================================================================
//
// Architecture:
//   RISC-V Core (stub):
//     - Instruction fetch port → sram_mux[ISRAM] port 0 → ISRAM (4 KB)
//     - Data memory port      → sram_mux[DSRAM] port 0 → DSRAM (4 KB)
//     - AXI-Lite master       → axi_lite_xbar SLV[0]
//
//   Bootloader (real):
//     - AXI-Lite master       → axi_lite_xbar SLV[1]   (SRAM writes only)
//     - APB slave  ← APB bridge slot 4 (SPI address space)
//     - APB master → apb_spi_master  (boot: FSM drives; runtime: passthrough)
//     - Outputs: core_rst_ni, periph_rst_ni (clean-slate reset after load)
//
//   axi_lite_xbar (2 SLV → 3 MST):
//     MST[0] → axi_lite_sram_if → sram_mux[ISRAM] port 1 → ISRAM
//     MST[1] → axi_lite_sram_if → sram_mux[DSRAM] port 1 → DSRAM
//     MST[2] → axi_lite_to_apb (1 AXI → 5 APB)
//               ├─ APB[0] → I2C
//               ├─ APB[1] → Timer
//               ├─ APB[2] → UART
//               ├─ APB[3] → GPIO
//               └─ APB[4] → Bootloader APB slave (→ apb_spi_master)
//
// Address Map (Crossbar):
//   ISRAM:  0x0000_0000 – 0x0000_1000  (4 KB)
//   DSRAM:  0x0001_0000 – 0x0001_1000  (4 KB)
//   APB:    0x4000_0000 – 0x5000_0000  (256 MB peripheral space)
//
// Address Map (APB Bridge, within peripheral space):
//   I2C:    0x4000_0000 – 0x4000_1000  (4 KB)
//   Timer:  0x4000_1000 – 0x4000_2000  (4 KB)
//   UART:   0x4000_2000 – 0x4000_3000  (4 KB)
//   GPIO:   0x4000_3000 – 0x4000_4000  (4 KB)
//   SPI:    0x4000_4000 – 0x4000_5000  (4 KB)
//
// Reset Topology:
//   hard_rst_ni  → cold boot, resets everything including bootloader
//   soft_rst_ni  → warm boot, SRAM preserved, bootloader runs clean-slate only
//   sys_rst_n    = hard_rst_ni & soft_rst_ni → crossbar, bridges, muxes
//   core_rst_n   ← bootloader output → RISC-V core
//   periph_rst_n ← bootloader output → non-boot peripherals (I2C, Timer, UART,
//                                       GPIO)
//   spi_rst_n    ← bootloader output → SPI master (independent timing: HIGH
//                                       during boot, pulsed LOW for clean-slate,
//                                       HIGH for runtime)
//
// =============================================================================

module riscforge_soc_subsystem
  import gpio_reg_pkg::GPIOCount;
#(
  parameter int unsigned AXI_ADDR_WIDTH    = 32,
  parameter int unsigned AXI_DATA_WIDTH    = 32,
  parameter int unsigned TIMER_CNT         = 2,
  parameter int unsigned SPI_BUFFER_DEPTH  = 10,
  // Bootloader firmware image parameters (passed to bootloader)
  parameter int unsigned NUM_INSTR_WORDS   = 64,
  parameter int unsigned NUM_DATA_WORDS    = 0,
  parameter int unsigned FLASH_POWERUP_CYCLES = 30_000,
  // Derived — do not override
  localparam int unsigned AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8,
  localparam int unsigned NR_GPIOS         = GPIOCount
)(
  // =========================================================================
  // Global
  // =========================================================================
  input  logic                          clk_i,
  input  logic                          hard_rst_ni,
  input  logic                          soft_rst_ni,
  input  logic                          test_mode_i,

  // =========================================================================
  // RISC-V Core Control
  // =========================================================================
  input  logic                          fetch_enable_i,
  input  logic [31:0]                   boot_addr_i,

  // =========================================================================
  // Bootloader Status
  // =========================================================================
  output logic                          boot_done_o,

  // =========================================================================
  // I2C External Interface
  // =========================================================================
  input  logic                          i2c_scl_i,
  output logic                          i2c_scl_o,
  output logic                          i2c_scl_oen_o,
  input  logic                          i2c_sda_i,
  output logic                          i2c_sda_o,
  output logic                          i2c_sda_oen_o,
  output logic                          i2c_interrupt_o,

  // =========================================================================
  // Timer IRQ
  // =========================================================================
  output logic [(TIMER_CNT*2)-1:0]      timer_irq_o,

  // =========================================================================
  // UART External Interface
  // =========================================================================
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

  // =========================================================================
  // GPIO External Interface
  // =========================================================================
  input  logic [NR_GPIOS-1:0]           gpio_in_i,
  output logic [NR_GPIOS-1:0]           gpio_out_o,
  output logic [NR_GPIOS-1:0]           gpio_tx_en_o,
  output logic [NR_GPIOS-1:0]           gpio_in_sync_o,
  output logic                          gpio_global_interrupt_o,
  output logic [NR_GPIOS-1:0]           gpio_pin_level_interrupts_o,

  // =========================================================================
  // SPI Master External Interface (APB peripheral SPI, not boot SPI)
  // =========================================================================
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

  // ===========================================================================
  //  Section 1 — AXI-Lite Type Definitions
  //  (Must match the struct layout expected by axi_lite_xbar / axi_lite_to_apb)
  // ===========================================================================

  typedef logic [AXI_ADDR_WIDTH-1:0]    addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0]    data_t;
  typedef logic [AXI_STRB_WIDTH-1:0]    strb_t;

  // -- AXI-Lite channel structs --
  typedef struct packed {
    addr_t          addr;
    axi_pkg::prot_t prot;
  } aw_chan_t;

  typedef struct packed {
    data_t data;
    strb_t strb;
  } w_chan_t;

  typedef struct packed {
    axi_pkg::resp_t resp;
  } b_chan_t;

  typedef struct packed {
    addr_t          addr;
    axi_pkg::prot_t prot;
  } ar_chan_t;

  typedef struct packed {
    data_t          data;
    axi_pkg::resp_t resp;
  } r_chan_t;

  // -- Request struct: master → xbar slave port --
  typedef struct packed {
    aw_chan_t aw;
    logic     aw_valid;
    w_chan_t  w;
    logic     w_valid;
    logic     b_ready;
    ar_chan_t ar;
    logic     ar_valid;
    logic     r_ready;
  } axi_req_t;

  // -- Response struct: xbar slave port → master --
  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    b_chan_t b;
    logic    b_valid;
    logic    ar_ready;
    r_chan_t r;
    logic    r_valid;
  } axi_resp_t;

  // -- Address decode rule (32-bit addresses) --
  typedef struct packed {
    int unsigned idx;
    addr_t       start_addr;
    addr_t       end_addr;
  } rule_t;

  // ===========================================================================
  //  Section 2 — APB Type Definitions
  //  (Must match the struct layout expected by axi_lite_to_apb)
  // ===========================================================================

  typedef struct packed {
    addr_t          paddr;
    axi_pkg::prot_t pprot;
    logic           psel;
    logic           penable;
    logic           pwrite;
    data_t          pwdata;
    strb_t          pstrb;
  } apb_req_t;

  typedef struct packed {
    logic  pready;
    data_t prdata;
    logic  pslverr;
  } apb_resp_t;

  // ===========================================================================
  //  Section 3 — Crossbar Configuration
  // ===========================================================================

  localparam int unsigned NUM_SLV_PORTS = 2;   // RISC-V core + Bootloader
  localparam int unsigned NUM_MST_PORTS = 3;   // ISRAM + DSRAM + APB bridge
  localparam int unsigned NUM_XBAR_RULES = 3;
  localparam int unsigned MAX_MST_TRANS  = 4;
  localparam int unsigned MAX_SLV_TRANS  = 4;

  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         NUM_SLV_PORTS,
    NoMstPorts:         NUM_MST_PORTS,
    MaxMstTrans:        MAX_MST_TRANS,
    MaxSlvTrans:        MAX_SLV_TRANS,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_AX,
    PipelineStages:     0,
    AxiIdWidthSlvPorts: 0,
    AxiIdUsedSlvPorts:  0,
    UniqueIds:          0,
    AxiAddrWidth:       AXI_ADDR_WIDTH,
    AxiDataWidth:       AXI_DATA_WIDTH,
    NoAddrRules:        NUM_XBAR_RULES
  };

  // ===========================================================================
  //  Section 4 — APB Bridge Configuration
  // ===========================================================================

  localparam int unsigned NUM_APB_SLAVES = 5;
  localparam int unsigned NUM_APB_RULES  = 5;

  // ===========================================================================
  //  Section 5 — SRAM Configuration
  // ===========================================================================

  localparam int unsigned ISRAM_NUM_WORDS  = 1024;  // 4 KB (1024 × 32-bit)
  localparam int unsigned DSRAM_NUM_WORDS  = 1024;  // 4 KB (1024 × 32-bit)
  localparam int unsigned SRAM_ADDR_WIDTH  = $clog2(ISRAM_NUM_WORDS);  // 10
  localparam int unsigned BYTE_OFFSET      = $clog2(AXI_DATA_WIDTH/8); // 2

  // ===========================================================================
  //  Section 6 — Internal Reset Signals
  // ===========================================================================

  // Derived internal resets
  logic sys_rst_n;             // For crossbar, SRAM bridges, SRAM mux
  logic core_rst_n;            // For RISC-V core (from bootloader)
  logic periph_rst_n;          // For non-boot peripherals (from bootloader)
  logic spi_rst_n;             // For SPI master (from bootloader, independent timing)

  assign sys_rst_n = hard_rst_ni & soft_rst_ni;  // Reset on either external reset

  // ===========================================================================
  //  Section 7 — Internal Signals
  // ===========================================================================

  // Crossbar ports
  axi_req_t  [NUM_SLV_PORTS-1:0] xbar_slv_req;
  axi_resp_t [NUM_SLV_PORTS-1:0] xbar_slv_resp;
  axi_req_t  [NUM_MST_PORTS-1:0] xbar_mst_req;
  axi_resp_t [NUM_MST_PORTS-1:0] xbar_mst_resp;

  // Crossbar address map
  rule_t [NUM_XBAR_RULES-1:0] xbar_addr_map;

  // APB bridge
  apb_req_t  [NUM_APB_SLAVES-1:0] apb_req;
  apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp;

  // APB address map
  rule_t [NUM_APB_RULES-1:0] apb_addr_map;

  // --- Core Instruction Memory (SRAM) Interface (core → ISRAM mux port 0) ---
  logic        core_imem_en;
  logic        core_imem_we;
  logic [3:0]  core_imem_wmask;
  logic [29:0] core_imem_addr;
  logic [31:0] core_imem_wdata;
  logic [31:0] core_imem_rdata;

  // --- Core LSU Interface (core → hybrid_mem_interface) ---
  logic        core_lsu_req;
  logic        core_lsu_we;
  logic [31:0] core_lsu_addr;
  logic [31:0] core_lsu_wdata;
  logic [3:0]  core_lsu_be;
  logic [31:0] core_lsu_rdata;
  logic        core_lsu_stall;
  logic        core_lsu_err;

  // --- hybrid_mem_interface SRAM Interface (hmif → DSRAM mux port 0) ---
  logic        hmif_sram_en;
  logic        hmif_sram_we;
  logic [3:0]  hmif_sram_wmask;
  logic [29:0] hmif_sram_addr;
  logic [31:0] hmif_sram_wdata;
  logic [31:0] hmif_sram_rdata;

  // --- ISRAM: AXI bridge ↔ mux port 1 ---
  logic                        isram_axi_req;
  logic                        isram_axi_gnt;
  logic                        isram_axi_we;
  logic [SRAM_ADDR_WIDTH-1:0]  isram_axi_addr;
  logic [AXI_DATA_WIDTH-1:0]   isram_axi_wdata;
  logic [AXI_STRB_WIDTH-1:0]   isram_axi_be;
  logic [AXI_DATA_WIDTH-1:0]   isram_axi_rdata;
  logic                        isram_axi_rvalid;

  // --- ISRAM: mux ↔ SRAM ---
  logic                        isram_cs;
  logic                        isram_we;
  logic [SRAM_ADDR_WIDTH-1:0]  isram_addr;
  logic [AXI_DATA_WIDTH-1:0]   isram_wdata;
  logic [AXI_STRB_WIDTH-1:0]   isram_wmask;
  logic [AXI_DATA_WIDTH-1:0]   isram_rdata;

  // --- DSRAM: AXI bridge ↔ mux port 1 ---
  logic                        dsram_axi_req;
  logic                        dsram_axi_gnt;
  logic                        dsram_axi_we;
  logic [SRAM_ADDR_WIDTH-1:0]  dsram_axi_addr;
  logic [AXI_DATA_WIDTH-1:0]   dsram_axi_wdata;
  logic [AXI_STRB_WIDTH-1:0]   dsram_axi_be;
  logic [AXI_DATA_WIDTH-1:0]   dsram_axi_rdata;
  logic                        dsram_axi_rvalid;

  // --- DSRAM: mux ↔ SRAM ---
  logic                        dsram_cs;
  logic                        dsram_we;
  logic [SRAM_ADDR_WIDTH-1:0]  dsram_addr;
  logic [AXI_DATA_WIDTH-1:0]   dsram_wdata;
  logic [AXI_STRB_WIDTH-1:0]   dsram_wmask;
  logic [AXI_DATA_WIDTH-1:0]   dsram_rdata;

  // Peripheral intermediate signals for APB response construction
  logic [31:0] i2c_prdata,   timer_prdata,   uart_prdata;
  logic        i2c_pready,   timer_pready,   uart_pready;
  logic        i2c_pslverr,  timer_pslverr,  uart_pslverr;

  // SPI Master APB signals (from/to bootloader APB master port)
  apb_req_t  spi_apb_req;
  apb_resp_t spi_apb_resp;
  logic [31:0] spi_prdata;
  logic        spi_pready;
  logic        spi_pslverr;

  // Default master port controls (disabled)
  localparam int unsigned MST_IDX_W = (NUM_MST_PORTS > 1) ? $clog2(NUM_MST_PORTS) : 1;
  logic [NUM_SLV_PORTS-1:0]                 en_default_mst;
  logic [NUM_SLV_PORTS-1:0][MST_IDX_W-1:0] default_mst;

  assign en_default_mst = '0;
  assign default_mst    = '0;

  // ===========================================================================
  //  Section 8 — Address Maps
  // ===========================================================================

  // Crossbar address map
  assign xbar_addr_map[0] = '{idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 32'h0000_1000}; // ISRAM (4 KB)
  assign xbar_addr_map[1] = '{idx: 32'd1, start_addr: 32'h0001_0000, end_addr: 32'h0001_1000}; // DSRAM (4 KB)
  assign xbar_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_0000, end_addr: 32'h5000_0000}; // APB

  // APB bridge address map (5 APB slots: I2C, Timer, UART, GPIO, SPI)
  assign apb_addr_map[0] = '{idx: 32'd0, start_addr: 32'h4000_0000, end_addr: 32'h4000_1000}; // I2C
  assign apb_addr_map[1] = '{idx: 32'd1, start_addr: 32'h4000_1000, end_addr: 32'h4000_2000}; // Timer
  assign apb_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_2000, end_addr: 32'h4000_3000}; // UART
  assign apb_addr_map[3] = '{idx: 32'd3, start_addr: 32'h4000_3000, end_addr: 32'h4000_4000}; // GPIO
  assign apb_addr_map[4] = '{idx: 32'd4, start_addr: 32'h4000_4000, end_addr: 32'h4000_5000}; // SPI Master (via bootloader)

  // ===========================================================================
  //  Section 9 — Crossbar SLV[0] (Driven directly by hybrid_mem_interface in Section 20)
  // ===========================================================================

  // ===========================================================================
  //  Section 10 — Instruction SRAM Subsystem
  //  (Crossbar MST[0] → AXI bridge → mux port 1; Core fetch → mux port 0)
  // ===========================================================================

  // AXI-Lite to SRAM bridge (crossbar MST[0] → mux port 1)
  axi_lite_sram_if #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
    .SRAM_NUM_WORDS ( ISRAM_NUM_WORDS ),
    .axi_req_t      ( axi_req_t      ),
    .axi_resp_t     ( axi_resp_t     )
  ) i_isram_axi_if (
    .clk_i      ( clk_i              ),
    .rst_ni     ( sys_rst_n          ),
    .soft_rst_ni( soft_rst_ni        ),
    .axi_req_i  ( xbar_mst_req[0]    ),
    .axi_resp_o ( xbar_mst_resp[0]   ),
    .sram_req_o    ( isram_axi_req    ),
    .sram_gnt_i    ( isram_axi_gnt    ),
    .sram_we_o     ( isram_axi_we     ),
    .sram_addr_o   ( isram_axi_addr   ),
    .sram_wdata_o  ( isram_axi_wdata  ),
    .sram_be_o     ( isram_axi_be     ),
    .sram_rdata_i  ( isram_axi_rdata  ),
    .sram_rvalid_i ( isram_axi_rvalid )
  );

  // 2:1 Priority Mux (port 0 = core fetch, port 1 = AXI bridge)
  sram_mux #(
    .ADDR_WIDTH ( SRAM_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_isram_mux (
    .clk_i          ( clk_i       ),
    .rst_ni         ( sys_rst_n   ),
    // Port 0 — Core instruction fetch (read-only)
    .port0_req_i    ( core_imem_en   ),
    .port0_gnt_o    (                ),
    .port0_we_i     ( core_imem_we   ),
    .port0_addr_i   ( core_imem_addr[SRAM_ADDR_WIDTH-1:0] ),
    .port0_wdata_i  ( core_imem_wdata),
    .port0_be_i     ( core_imem_wmask),
    .port0_rdata_o  ( core_imem_rdata),
    .port0_rvalid_o (                ),
    // Port 1 — AXI bridge (bootloader / runtime AXI access)
    .port1_req_i    ( isram_axi_req    ),
    .port1_gnt_o    ( isram_axi_gnt    ),
    .port1_we_i     ( isram_axi_we     ),
    .port1_addr_i   ( isram_axi_addr   ),
    .port1_wdata_i  ( isram_axi_wdata  ),
    .port1_be_i     ( isram_axi_be     ),
    .port1_rdata_o  ( isram_axi_rdata  ),
    .port1_rvalid_o ( isram_axi_rvalid ),
    // SRAM
    .sram_cs_o      ( isram_cs         ),
    .sram_we_o      ( isram_we         ),
    .sram_addr_o    ( isram_addr       ),
    .sram_wdata_o   ( isram_wdata      ),
    .sram_wmask_o   ( isram_wmask      ),
    .sram_rdata_i   ( isram_rdata      )
  );

  // Instruction Memory (Instruction_Memory_new)
  Instruction_Memory_new #(
    .MEM_DEPTH      ( ISRAM_NUM_WORDS ),
    .IMEM_BASE_BYTE ( 32'h0000_0000  )   // Match crossbar ISRAM address map
  ) i_isram (
    .clk       ( clk_i       ),
    .rst_n     ( sys_rst_n   ),
    .sram_en   ( isram_cs    ),
    .sram_we   ( isram_we    ),
    .sram_wmask( isram_wmask ),
    .sram_addr ( 30'(isram_addr) ),
    .sram_wdata( isram_wdata ),
    .sram_rdata( isram_rdata )
  );

  // ===========================================================================
  //  Section 11 — Data SRAM Subsystem
  //  (Crossbar MST[1] → AXI bridge → mux port 1; Core LSU HMIF → mux port 0)
  // ===========================================================================

  // AXI-Lite to SRAM bridge (crossbar MST[1] → mux port 1, active during boot)
  axi_lite_sram_if #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
    .SRAM_NUM_WORDS ( DSRAM_NUM_WORDS ),
    .axi_req_t      ( axi_req_t      ),
    .axi_resp_t     ( axi_resp_t     )
  ) i_dsram_axi_if (
    .clk_i         ( clk_i           ),
    .rst_ni        ( sys_rst_n       ),
    .soft_rst_ni   ( soft_rst_ni     ),
    .axi_req_i     ( xbar_mst_req[1] ),
    .axi_resp_o    ( xbar_mst_resp[1]),
    .sram_req_o    ( dsram_axi_req   ),
    .sram_gnt_i    ( dsram_axi_gnt   ),
    .sram_we_o     ( dsram_axi_we    ),
    .sram_addr_o   ( dsram_axi_addr  ),
    .sram_wdata_o  ( dsram_axi_wdata ),
    .sram_be_o     ( dsram_axi_be    ),
    .sram_rdata_i  ( dsram_axi_rdata ),
    .sram_rvalid_i ( dsram_axi_rvalid)
  );

  // 2:1 Priority Mux (port 0 = core data from HMIF, port 1 = AXI bridge during boot)
  sram_mux #(
    .ADDR_WIDTH ( SRAM_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_dsram_mux (
    .clk_i          ( clk_i       ),
    .rst_ni         ( sys_rst_n   ),
    // Port 0 — Core data port (read/write from hybrid_mem_interface during normal operation)
    .port0_req_i    ( hmif_sram_en   ),
    .port0_gnt_o    (                ),
    .port0_we_i     ( hmif_sram_we   ),
    .port0_addr_i   ( hmif_sram_addr[SRAM_ADDR_WIDTH-1:0] ),
    .port0_wdata_i  ( hmif_sram_wdata),
    .port0_be_i     ( hmif_sram_wmask),
    .port0_rdata_o  ( hmif_sram_rdata),
    .port0_rvalid_o (                ),
    // Port 1 — AXI bridge (bootloader / runtime AXI access)
    .port1_req_i    ( dsram_axi_req    ),
    .port1_gnt_o    ( dsram_axi_gnt    ),
    .port1_we_i     ( dsram_axi_we     ),
    .port1_addr_i   ( dsram_axi_addr   ),
    .port1_wdata_i  ( dsram_axi_wdata  ),
    .port1_be_i     ( dsram_axi_be     ),
    .port1_rdata_o  ( dsram_axi_rdata  ),
    .port1_rvalid_o ( dsram_axi_rvalid ),
    // SRAM outputs to Data_Memory
    .sram_cs_o      ( dsram_cs         ),
    .sram_we_o      ( dsram_we         ),
    .sram_addr_o    ( dsram_addr       ),
    .sram_wdata_o   ( dsram_wdata      ),
    .sram_wmask_o   ( dsram_wmask      ),
    .sram_rdata_i   ( dsram_rdata      )
  );

  // Data SRAM (4 KB Native Synchronous SRAM)
  Data_Memory #(
    .MEM_DEPTH      ( DSRAM_NUM_WORDS ),
    .DMEM_BASE_BYTE ( 32'h0001_0000  )
  ) i_dsram (
    .clk        ( clk_i       ),
    .rst_n      ( sys_rst_n   ),
    .sram_en    ( dsram_cs    ),
    .sram_we    ( dsram_we    ),
    .sram_wmask ( dsram_wmask ),
    .sram_addr  ( 30'(32'h0001_0000 >> 2) + 30'(dsram_addr) ),
    .sram_wdata ( dsram_wdata ),
    .sram_rdata ( dsram_rdata )
  );

  // ===========================================================================
  //  Section 12 — AXI-Lite Crossbar
  // ===========================================================================

  axi_lite_xbar #(
    .Cfg        ( XbarCfg    ),
    .aw_chan_t  ( aw_chan_t   ),
    .w_chan_t   ( w_chan_t    ),
    .b_chan_t   ( b_chan_t    ),
    .ar_chan_t  ( ar_chan_t   ),
    .r_chan_t   ( r_chan_t    ),
    .axi_req_t  ( axi_req_t  ),
    .axi_resp_t ( axi_resp_t ),
    .rule_t     ( rule_t     )
  ) i_axi_lite_xbar (
    .clk_i                ( clk_i           ),
    .rst_ni               ( sys_rst_n       ),
    .test_i               ( test_mode_i     ),
    .slv_ports_req_i      ( xbar_slv_req    ),
    .slv_ports_resp_o     ( xbar_slv_resp   ),
    .mst_ports_req_o      ( xbar_mst_req    ),
    .mst_ports_resp_i     ( xbar_mst_resp   ),
    .addr_map_i           ( xbar_addr_map   ),
    .en_default_mst_port_i( en_default_mst  ),
    .default_mst_port_i   ( default_mst     )
  );

  // ===========================================================================
  //  Section 13 — AXI-Lite → APB Bridge (Crossbar MST[2] → 6 APB Slaves)
  // ===========================================================================

  axi_lite_to_apb #(
    .NoApbSlaves     ( NUM_APB_SLAVES  ),
    .NoRules         ( NUM_APB_RULES   ),
    .AddrWidth       ( AXI_ADDR_WIDTH  ),
    .DataWidth       ( AXI_DATA_WIDTH  ),
    .PipelineRequest ( 1'b0            ),
    .PipelineResponse( 1'b0            ),
    .axi_lite_req_t  ( axi_req_t       ),
    .axi_lite_resp_t ( axi_resp_t      ),
    .apb_req_t       ( apb_req_t       ),
    .apb_resp_t      ( apb_resp_t      ),
    .rule_t          ( rule_t          )
  ) i_axi_lite_to_apb (
    .clk_i          ( clk_i             ),
    .rst_ni         ( sys_rst_n         ),
    .axi_lite_req_i ( xbar_mst_req[2]   ),
    .axi_lite_resp_o( xbar_mst_resp[2]  ),
    .apb_req_o      ( apb_req           ),
    .apb_resp_i     ( apb_resp          ),
    .addr_map_i     ( apb_addr_map      )
  );

  // ===========================================================================
  //  Section 14 — APB[0]: I2C Master
  // ===========================================================================

  apb_i2c #(
    .APB_ADDR_WIDTH ( 12 )
  ) i_apb_i2c (
    .HCLK       ( clk_i                    ),
    .HRESETn    ( periph_rst_n             ),
    .PADDR      ( apb_req[0].paddr[11:0]   ),
    .PWDATA     ( apb_req[0].pwdata        ),
    .PWRITE     ( apb_req[0].pwrite        ),
    .PSEL       ( apb_req[0].psel          ),
    .PENABLE    ( apb_req[0].penable       ),
    .PRDATA     ( i2c_prdata               ),
    .PREADY     ( i2c_pready               ),
    .PSLVERR    ( i2c_pslverr              ),
    .interrupt_o( i2c_interrupt_o           ),
    .scl_pad_i  ( i2c_scl_i                ),
    .scl_pad_o  ( i2c_scl_o                ),
    .scl_padoen_o( i2c_scl_oen_o           ),
    .sda_pad_i  ( i2c_sda_i                ),
    .sda_pad_o  ( i2c_sda_o                ),
    .sda_padoen_o( i2c_sda_oen_o           )
  );

  assign apb_resp[0] = '{pready: i2c_pready, prdata: i2c_prdata, pslverr: i2c_pslverr};

  // ===========================================================================
  //  Section 15 — APB[1]: Timer
  // ===========================================================================

  apb_timer #(
    .APB_ADDR_WIDTH ( 12        ),
    .TIMER_CNT      ( TIMER_CNT )
  ) i_apb_timer (
    .HCLK    ( clk_i                    ),
    .HRESETn ( periph_rst_n             ),
    .PADDR   ( apb_req[1].paddr[11:0]   ),
    .PWDATA  ( apb_req[1].pwdata        ),
    .PWRITE  ( apb_req[1].pwrite        ),
    .PSEL    ( apb_req[1].psel          ),
    .PENABLE ( apb_req[1].penable       ),
    .PRDATA  ( timer_prdata             ),
    .PREADY  ( timer_pready             ),
    .PSLVERR ( timer_pslverr            ),
    .irq_o   ( timer_irq_o             )
  );

  assign apb_resp[1] = '{pready: timer_pready, prdata: timer_prdata, pslverr: timer_pslverr};

  // ===========================================================================
  //  Section 16 — APB[2]: UART
  //  Note: apb_uart takes a 3-bit word address PADDR[2:0].
  //        The bridge outputs full byte address; extract bits [4:2].
  // ===========================================================================

  apb_uart i_apb_uart (
    .CLK     ( clk_i                    ),
    .RSTN    ( periph_rst_n             ),
    .PSEL    ( apb_req[2].psel          ),
    .PENABLE ( apb_req[2].penable       ),
    .PWRITE  ( apb_req[2].pwrite        ),
    .PADDR   ( apb_req[2].paddr[4:2]    ),
    .PWDATA  ( apb_req[2].pwdata        ),
    .PRDATA  ( uart_prdata              ),
    .PREADY  ( uart_pready              ),
    .PSLVERR ( uart_pslverr             ),
    .INT     ( uart_int_o               ),
    .OUT1N   ( uart_out1n_o             ),
    .OUT2N   ( uart_out2n_o             ),
    .RTSN    ( uart_rtsn_o              ),
    .DTRN    ( uart_dtrn_o              ),
    .CTSN    ( uart_ctsn_i              ),
    .DSRN    ( uart_dsrn_i              ),
    .DCDN    ( uart_dcdn_i              ),
    .RIN     ( uart_rin_i               ),
    .SIN     ( uart_sin_i               ),
    .SOUT    ( uart_sout_o              )
  );

  assign apb_resp[2] = '{pready: uart_pready, prdata: uart_prdata, pslverr: uart_pslverr};

  // ===========================================================================
  //  Section 17 — APB[3]: GPIO
  //  Note: gpio_apb_wrap accepts parameterized APB struct types directly.
  // ===========================================================================

  gpio_apb_wrap #(
    .ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH ),
    .apb_req_t  ( apb_req_t      ),
    .apb_rsp_t  ( apb_resp_t     )
  ) i_gpio_apb_wrap (
    .clk_i                 ( clk_i                       ),
    .rst_ni                ( periph_rst_n                 ),
    .gpio_in               ( gpio_in_i                   ),
    .gpio_out              ( gpio_out_o                  ),
    .gpio_tx_en_o          ( gpio_tx_en_o                ),
    .gpio_in_sync_o        ( gpio_in_sync_o              ),
    .global_interrupt_o    ( gpio_global_interrupt_o      ),
    .pin_level_interrupts_o( gpio_pin_level_interrupts_o  ),
    .apb_req_i             ( apb_req[3]                  ),
    .apb_rsp_o             ( apb_resp[3]                 )
  );

  // ===========================================================================
  //  Section 18 — APB[4]: SPI Master (via Bootloader APB mux)
  //  The bootloader sits between the APB bridge and the SPI master.
  //  During boot: bootloader drives SPI master directly
  //  At runtime: APB bridge slot 4 passes through bootloader to SPI master
  // ===========================================================================

  apb_spi_master #(
    .BUFFER_DEPTH   ( SPI_BUFFER_DEPTH ),
    .APB_ADDR_WIDTH ( 12               )
  ) i_apb_spi_master (
    .HCLK    ( clk_i                        ),
    .HRESETn ( spi_rst_n                    ),
    .PADDR   ( spi_apb_req.paddr[11:0]      ),
    .PWDATA  ( spi_apb_req.pwdata           ),
    .PWRITE  ( spi_apb_req.pwrite           ),
    .PSEL    ( spi_apb_req.psel             ),
    .PENABLE ( spi_apb_req.penable          ),
    .PRDATA  ( spi_prdata                   ),
    .PREADY  ( spi_pready                   ),
    .PSLVERR ( spi_pslverr                  ),
    .events_o( spi_events_o                 ),
    .spi_clk ( spi_clk_o                    ),
    .spi_csn0( spi_csn0_o                   ),
    .spi_csn1( spi_csn1_o                   ),
    .spi_csn2( spi_csn2_o                   ),
    .spi_csn3( spi_csn3_o                   ),
    .spi_mode( spi_mode_o                   ),
    .spi_sdo0( spi_sdo0_o                   ),
    .spi_sdo1( spi_sdo1_o                   ),
    .spi_sdo2( spi_sdo2_o                   ),
    .spi_sdo3( spi_sdo3_o                   ),
    .spi_sdi0( spi_sdi0_i                   ),
    .spi_sdi1( spi_sdi1_i                   ),
    .spi_sdi2( spi_sdi2_i                   ),
    .spi_sdi3( spi_sdi3_i                   )
  );

  assign spi_apb_resp = '{pready: spi_pready, prdata: spi_prdata, pslverr: spi_pslverr};



  // ===========================================================================
  //  Section 20 — RISC-V Core & Hybrid Memory Router
  // ===========================================================================

  // Direct-Line Fast Local Interrupts (Custom Bits 16-31) & Timer
  // mcause ID 19 (Rank 1): UART   -> core_fast_irq[3] (mip[19])
  // mcause ID 18 (Rank 2): SPI    -> core_fast_irq[2] (mip[18])
  // mcause ID 17 (Rank 3): I2C    -> core_fast_irq[1] (mip[17])
  // mcause ID 16 (Rank 4): GPIO   -> core_fast_irq[0] (mip[16])
  // Bits [31:20]: Reserved for future Fast Local Interrupt extensions
  logic [15:0] core_fast_irq;
  assign core_fast_irq[0]    = gpio_global_interrupt_o;   // Bit 16: GPIO
  assign core_fast_irq[1]    = i2c_interrupt_o;           // Bit 17: I2C
  assign core_fast_irq[2]    = spi_events_o[0];           // Bit 18: SPI
  assign core_fast_irq[3]    = uart_int_o;                // Bit 19: UART
  assign core_fast_irq[15:4] = '0;                        // Bits 31:20: Reserved

  logic core_timer_irq;
  assign core_timer_irq      = timer_irq_o[0];            // Bit 7: MTIP

  top i_riscv_core (
    .clk             ( clk_i           ),
    .rst             ( core_rst_n      ), // active-low core reset (from bootloader)
    .PCSrcE1         (                 ),

    // Instruction Memory (SRAM) Interface
    .imem_sram_en    ( core_imem_en    ),
    .imem_sram_we    ( core_imem_we    ),
    .imem_sram_wmask ( core_imem_wmask ),
    .imem_sram_addr  ( core_imem_addr  ),
    .imem_sram_wdata ( core_imem_wdata ),
    .imem_sram_rdata ( core_imem_rdata ),

    // LSU Data Memory Interface
    .lsu_mem_req     ( core_lsu_req    ),
    .lsu_mem_we      ( core_lsu_we     ),
    .lsu_mem_addr    ( core_lsu_addr   ),
    .lsu_mem_wdata   ( core_lsu_wdata  ),
    .lsu_mem_be      ( core_lsu_be     ),
    .lsu_mem_rdata   ( core_lsu_rdata  ),
    .lsu_mem_stall   ( core_lsu_stall  ),
    .lsu_mem_err     ( core_lsu_err    ),

    // Direct-Line Interrupt Inputs
    .fast_irq_i      ( core_fast_irq   ),
    .timer_irq_i     ( core_timer_irq  ),
    .ext_irq_i       ( 1'b0            ),
    .sw_irq_i        ( 1'b0            )
  );

  hybrid_mem_interface #(
    .axi_req_t      ( axi_req_t       ),
    .axi_resp_t     ( axi_resp_t      ),
    .MEM_DEPTH      ( DSRAM_NUM_WORDS ),
    .DMEM_BASE_BYTE ( 32'h0001_0000   ),
    .MMIO_BASE      ( 32'h4000_0000   ),
    .MMIO_LIMIT     ( 32'h4FFF_FFFF   )
  ) i_hybrid_mem_if (
    .clk            ( clk_i           ),
    .rst_n          ( core_rst_n      ),

    // LSU Core Interface
    .mem_req        ( core_lsu_req    ),
    .mem_we         ( core_lsu_we     ),
    .mem_addr       ( core_lsu_addr   ),
    .mem_wdata      ( core_lsu_wdata  ),
    .mem_be         ( core_lsu_be     ),
    .mem_rdata      ( core_lsu_rdata  ),
    .mem_stall      ( core_lsu_stall  ),
    .mem_err        ( core_lsu_err    ),

    // Native SRAM Interface (to DSRAM mux port 0)
    .sram_en        ( hmif_sram_en    ),
    .sram_we        ( hmif_sram_we    ),
    .sram_wmask     ( hmif_sram_wmask ),
    .sram_addr      ( hmif_sram_addr  ),
    .sram_wdata     ( hmif_sram_wdata ),
    .sram_rdata     ( hmif_sram_rdata ),

    // AXI4-Lite master (crossbar SLV[0])
    .m_axi_req_o    ( xbar_slv_req[0] ),
    .m_axi_resp_i   ( xbar_slv_resp[0] )
  );

  // ===========================================================================
  //  Section 21 — Bootloader (Real Implementation)
  //  Connects directly via struct-based AXI-Lite to crossbar SLV[1].
  //  APB mux: during boot, FSM drives SPI master; at runtime, passthrough.
  // ===========================================================================

  bootloader #(
    .axi_req_t           ( axi_req_t           ),
    .axi_resp_t          ( axi_resp_t          ),
    .apb_req_t           ( apb_req_t           ),
    .apb_resp_t          ( apb_resp_t          ),
    .AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH      ),
    .AXI_DATA_WIDTH      ( AXI_DATA_WIDTH      ),
    .ISRAM_BASE_ADDR     ( 32'h0000_0000       ),
    .DSRAM_BASE_ADDR     ( 32'h0001_0000       ),
    .ISRAM_NUM_WORDS     ( ISRAM_NUM_WORDS     ),
    .DSRAM_NUM_WORDS     ( DSRAM_NUM_WORDS     ),
    .NUM_INSTR_WORDS     ( NUM_INSTR_WORDS     ),
    .NUM_DATA_WORDS      ( NUM_DATA_WORDS      ),
    .FLASH_POWERUP_CYCLES( FLASH_POWERUP_CYCLES)
  ) i_bootloader (
    .clk_i           ( clk_i             ),
    .hard_rst_ni     ( hard_rst_ni       ),
    .soft_rst_ni     ( soft_rst_ni       ),
    // AXI-Lite master (struct, not flat wires) — SRAM writes only
    .axi_req_o       ( xbar_slv_req[1]   ),
    .axi_resp_i      ( xbar_slv_resp[1]  ),
    // APB slave (from APB bridge slot 4)
    .apb_slv_req_i   ( apb_req[4]        ),
    .apb_slv_resp_o  ( apb_resp[4]       ),
    // APB master (to apb_spi_master)
    .apb_mst_req_o   ( spi_apb_req       ),
    .apb_mst_resp_i  ( spi_apb_resp      ),
    // Reset outputs
    .core_rst_ni_o   ( core_rst_n        ),
    .periph_rst_ni_o ( periph_rst_n      ),
    .spi_rst_ni_o    ( spi_rst_n         ),
    // Boot status
    .boot_done_o     ( boot_done_o       )
  );

endmodule
