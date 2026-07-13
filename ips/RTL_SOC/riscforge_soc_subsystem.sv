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
//   Bootloader (stub):
//     - AXI-Lite master       → axi_lite_xbar SLV[1]
//
//   axi_lite_xbar (2 SLV → 3 MST):
//     MST[0] → axi_lite_sram_if → sram_mux[ISRAM] port 1 → ISRAM
//     MST[1] → axi_lite_sram_if → sram_mux[DSRAM] port 1 → DSRAM
//     MST[2] → axi_lite_to_apb (1 AXI → 6 APB)
//               ├─ APB[0] → I2C
//               ├─ APB[1] → Timer
//               ├─ APB[2] → UART
//               ├─ APB[3] → GPIO
//               ├─ APB[4] → SPI Master
//               └─ APB[5] → CLIC
//
//   CLIC ↔ Core interrupt handshake is an internal closed loop.
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
//   CLIC:   0x4000_5000 – 0x4000_6000  (4 KB)
//
// =============================================================================

module riscforge_soc_subsystem
  import gpio_reg_pkg::GPIOCount;
#(
  parameter int unsigned AXI_ADDR_WIDTH    = 32,
  parameter int unsigned AXI_DATA_WIDTH    = 32,
  parameter int unsigned CLIC_N_SOURCE     = 256,
  parameter int unsigned CLIC_INTCTLBITS   = 8,
  parameter int unsigned TIMER_CNT         = 2,
  parameter int unsigned SPI_BUFFER_DEPTH  = 10,
  // Derived — do not override
  localparam int unsigned AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8,
  localparam int unsigned NR_GPIOS         = GPIOCount,
  localparam int unsigned CLIC_SRC_W       = $clog2(CLIC_N_SOURCE)
)(
  // =========================================================================
  // Global
  // =========================================================================
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          test_mode_i,

  // =========================================================================
  // RISC-V Core Control
  // =========================================================================
  input  logic                          fetch_enable_i,
  input  logic [31:0]                   boot_addr_i,

  // =========================================================================
  // Bootloader Control & SPI Flash
  // =========================================================================
  output logic                          boot_done_o,
  output logic                          boot_spi_clk_o,
  output logic                          boot_spi_csn_o,
  output logic [3:0]                    boot_spi_sdo_o,
  input  logic [3:0]                    boot_spi_sdi_i,
  output logic [1:0]                    boot_spi_mode_o,

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
  output logic [1:0]                    spi_events_o,

  // =========================================================================
  // CLIC External Interface (observability outputs only)
  // =========================================================================
  input  logic [CLIC_N_SOURCE-1:0]      clic_intr_src_i,
  output logic                          clic_irq_valid_o,
  output logic [CLIC_SRC_W-1:0]         clic_irq_id_o,
  output logic [7:0]                    clic_irq_level_o,
  output logic                          clic_irq_shv_o,
  output logic [1:0]                    clic_irq_priv_o,
  output logic                          clic_irq_kill_req_o
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

  localparam int unsigned NUM_APB_SLAVES = 6;
  localparam int unsigned NUM_APB_RULES  = 6;

  // ===========================================================================
  //  Section 5 — SRAM Configuration
  // ===========================================================================

  localparam int unsigned ISRAM_NUM_WORDS  = 1024;  // 4 KB (1024 × 32-bit)
  localparam int unsigned DSRAM_NUM_WORDS  = 1024;  // 4 KB (1024 × 32-bit)
  localparam int unsigned SRAM_ADDR_WIDTH  = $clog2(ISRAM_NUM_WORDS);  // 10
  localparam int unsigned BYTE_OFFSET      = $clog2(AXI_DATA_WIDTH/8); // 2

  // ===========================================================================
  //  Section 6 — Internal Signals
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

  // --- RISC-V Core AXI-Lite flat signals (core → crossbar SLV[0]) ---
  logic [AXI_ADDR_WIDTH-1:0] riscv_aw_addr;
  logic [2:0]                riscv_aw_prot;
  logic                      riscv_aw_valid;
  logic                      riscv_aw_ready;
  logic [AXI_DATA_WIDTH-1:0] riscv_w_data;
  logic [AXI_STRB_WIDTH-1:0] riscv_w_strb;
  logic                      riscv_w_valid;
  logic                      riscv_w_ready;
  logic [1:0]                riscv_b_resp;
  logic                      riscv_b_valid;
  logic                      riscv_b_ready;
  logic [AXI_ADDR_WIDTH-1:0] riscv_ar_addr;
  logic [2:0]                riscv_ar_prot;
  logic                      riscv_ar_valid;
  logic                      riscv_ar_ready;
  logic [AXI_DATA_WIDTH-1:0] riscv_r_data;
  logic [1:0]                riscv_r_resp;
  logic                      riscv_r_valid;
  logic                      riscv_r_ready;

  // --- Bootloader AXI-Lite flat signals (bootloader → crossbar SLV[1]) ---
  logic [AXI_ADDR_WIDTH-1:0] boot_aw_addr;
  logic [2:0]                boot_aw_prot;
  logic                      boot_aw_valid;
  logic                      boot_aw_ready;
  logic [AXI_DATA_WIDTH-1:0] boot_w_data;
  logic [AXI_STRB_WIDTH-1:0] boot_w_strb;
  logic                      boot_w_valid;
  logic                      boot_w_ready;
  logic [1:0]                boot_b_resp;
  logic                      boot_b_valid;
  logic                      boot_b_ready;
  logic [AXI_ADDR_WIDTH-1:0] boot_ar_addr;
  logic [2:0]                boot_ar_prot;
  logic                      boot_ar_valid;
  logic                      boot_ar_ready;
  logic [AXI_DATA_WIDTH-1:0] boot_r_data;
  logic [1:0]                boot_r_resp;
  logic                      boot_r_valid;
  logic                      boot_r_ready;

  // --- Core instruction fetch port (core → ISRAM mux port 0) ---
  logic        core_instr_req;
  logic        core_instr_gnt;
  logic [31:0] core_instr_addr;
  logic [31:0] core_instr_rdata;
  logic        core_instr_rvalid;

  // --- Core data memory port (core → DSRAM mux port 0) ---
  logic        core_data_req;
  logic        core_data_gnt;
  logic        core_data_we;
  logic [3:0]  core_data_be;
  logic [31:0] core_data_addr;
  logic [31:0] core_data_wdata;
  logic [31:0] core_data_rdata;
  logic        core_data_rvalid;

  // --- CLIC ↔ Core interrupt handshake (internal closed loop) ---
  logic core_irq_ready;
  logic core_irq_kill_ack;

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
  logic [31:0] i2c_prdata,   timer_prdata,   uart_prdata,   spi_prdata;
  logic        i2c_pready,   timer_pready,   uart_pready,   spi_pready;
  logic        i2c_pslverr,  timer_pslverr,  uart_pslverr,  spi_pslverr;

  // CLIC intermediate signals
  logic [31:0] clic_prdata;
  logic        clic_pready;
  logic        clic_pslverr;

  // Default master port controls (disabled)
  localparam int unsigned MST_IDX_W = (NUM_MST_PORTS > 1) ? $clog2(NUM_MST_PORTS) : 1;
  logic [NUM_SLV_PORTS-1:0]                 en_default_mst;
  logic [NUM_SLV_PORTS-1:0][MST_IDX_W-1:0] default_mst;

  assign en_default_mst = '0;
  assign default_mst    = '0;

  // ===========================================================================
  //  Section 7 — Address Maps
  // ===========================================================================

  // Crossbar address map
  assign xbar_addr_map[0] = '{idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 32'h0000_1000}; // ISRAM (4 KB)
  assign xbar_addr_map[1] = '{idx: 32'd1, start_addr: 32'h0001_0000, end_addr: 32'h0001_1000}; // DSRAM (4 KB)
  assign xbar_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_0000, end_addr: 32'h5000_0000}; // APB

  // APB bridge address map
  assign apb_addr_map[0] = '{idx: 32'd0, start_addr: 32'h4000_0000, end_addr: 32'h4000_1000}; // I2C
  assign apb_addr_map[1] = '{idx: 32'd1, start_addr: 32'h4000_1000, end_addr: 32'h4000_2000}; // Timer
  assign apb_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_2000, end_addr: 32'h4000_3000}; // UART
  assign apb_addr_map[3] = '{idx: 32'd3, start_addr: 32'h4000_3000, end_addr: 32'h4000_4000}; // GPIO
  assign apb_addr_map[4] = '{idx: 32'd4, start_addr: 32'h4000_4000, end_addr: 32'h4000_5000}; // SPI Master
  assign apb_addr_map[5] = '{idx: 32'd5, start_addr: 32'h4000_5000, end_addr: 32'h4000_6000}; // CLIC

  // ===========================================================================
  //  Section 8 — Flat ↔ Struct Packing (RISC-V Core Stub → Crossbar SLV[0])
  // ===========================================================================

  assign xbar_slv_req[0] = '{
    aw:       '{addr: riscv_aw_addr, prot: axi_pkg::prot_t'(riscv_aw_prot)},
    aw_valid: riscv_aw_valid,
    w:        '{data: riscv_w_data, strb: riscv_w_strb},
    w_valid:  riscv_w_valid,
    b_ready:  riscv_b_ready,
    ar:       '{addr: riscv_ar_addr, prot: axi_pkg::prot_t'(riscv_ar_prot)},
    ar_valid: riscv_ar_valid,
    r_ready:  riscv_r_ready
  };

  assign riscv_aw_ready = xbar_slv_resp[0].aw_ready;
  assign riscv_w_ready  = xbar_slv_resp[0].w_ready;
  assign riscv_b_resp   = xbar_slv_resp[0].b.resp;
  assign riscv_b_valid  = xbar_slv_resp[0].b_valid;
  assign riscv_ar_ready = xbar_slv_resp[0].ar_ready;
  assign riscv_r_data   = xbar_slv_resp[0].r.data;
  assign riscv_r_resp   = xbar_slv_resp[0].r.resp;
  assign riscv_r_valid  = xbar_slv_resp[0].r_valid;

  // ===========================================================================
  //  Section 9 — Flat ↔ Struct Packing (Bootloader Stub → Crossbar SLV[1])
  // ===========================================================================

  assign xbar_slv_req[1] = '{
    aw:       '{addr: boot_aw_addr, prot: axi_pkg::prot_t'(boot_aw_prot)},
    aw_valid: boot_aw_valid,
    w:        '{data: boot_w_data, strb: boot_w_strb},
    w_valid:  boot_w_valid,
    b_ready:  boot_b_ready,
    ar:       '{addr: boot_ar_addr, prot: axi_pkg::prot_t'(boot_ar_prot)},
    ar_valid: boot_ar_valid,
    r_ready:  boot_r_ready
  };

  assign boot_aw_ready = xbar_slv_resp[1].aw_ready;
  assign boot_w_ready  = xbar_slv_resp[1].w_ready;
  assign boot_b_resp   = xbar_slv_resp[1].b.resp;
  assign boot_b_valid  = xbar_slv_resp[1].b_valid;
  assign boot_ar_ready = xbar_slv_resp[1].ar_ready;
  assign boot_r_data   = xbar_slv_resp[1].r.data;
  assign boot_r_resp   = xbar_slv_resp[1].r.resp;
  assign boot_r_valid  = xbar_slv_resp[1].r_valid;

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
    .rst_ni     ( rst_ni             ),
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
    .rst_ni         ( rst_ni      ),
    // Port 0 — Core instruction fetch (read-only)
    .port0_req_i    ( core_instr_req   ),
    .port0_gnt_o    ( core_instr_gnt   ),
    .port0_we_i     ( 1'b0             ),  // instruction fetch is read-only
    .port0_addr_i   ( core_instr_addr[BYTE_OFFSET +: SRAM_ADDR_WIDTH] ),
    .port0_wdata_i  ( '0               ),
    .port0_be_i     ( '0               ),
    .port0_rdata_o  ( core_instr_rdata ),
    .port0_rvalid_o ( core_instr_rvalid),
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

  // Instruction SRAM (4 KB)
  sram_sp #(
    .NUM_WORDS  ( ISRAM_NUM_WORDS ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_isram (
    .clk_i   ( clk_i       ),
    .cs_i    ( isram_cs     ),
    .we_i    ( isram_we     ),
    .addr_i  ( isram_addr   ),
    .wdata_i ( isram_wdata  ),
    .wmask_i ( isram_wmask  ),
    .rdata_o ( isram_rdata  )
  );

  // ===========================================================================
  //  Section 11 — Data SRAM Subsystem
  //  (Crossbar MST[1] → AXI bridge → mux port 1; Core data → mux port 0)
  // ===========================================================================

  // AXI-Lite to SRAM bridge (crossbar MST[1] → mux port 1)
  axi_lite_sram_if #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
    .SRAM_NUM_WORDS ( DSRAM_NUM_WORDS ),
    .axi_req_t      ( axi_req_t      ),
    .axi_resp_t     ( axi_resp_t     )
  ) i_dsram_axi_if (
    .clk_i      ( clk_i              ),
    .rst_ni     ( rst_ni             ),
    .axi_req_i  ( xbar_mst_req[1]    ),
    .axi_resp_o ( xbar_mst_resp[1]   ),
    .sram_req_o    ( dsram_axi_req    ),
    .sram_gnt_i    ( dsram_axi_gnt    ),
    .sram_we_o     ( dsram_axi_we     ),
    .sram_addr_o   ( dsram_axi_addr   ),
    .sram_wdata_o  ( dsram_axi_wdata  ),
    .sram_be_o     ( dsram_axi_be     ),
    .sram_rdata_i  ( dsram_axi_rdata  ),
    .sram_rvalid_i ( dsram_axi_rvalid )
  );

  // 2:1 Priority Mux (port 0 = core data, port 1 = AXI bridge)
  sram_mux #(
    .ADDR_WIDTH ( SRAM_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_dsram_mux (
    .clk_i          ( clk_i       ),
    .rst_ni         ( rst_ni      ),
    // Port 0 — Core data port (read/write)
    .port0_req_i    ( core_data_req    ),
    .port0_gnt_o    ( core_data_gnt    ),
    .port0_we_i     ( core_data_we     ),
    .port0_addr_i   ( core_data_addr[BYTE_OFFSET +: SRAM_ADDR_WIDTH] ),
    .port0_wdata_i  ( core_data_wdata  ),
    .port0_be_i     ( core_data_be     ),
    .port0_rdata_o  ( core_data_rdata  ),
    .port0_rvalid_o ( core_data_rvalid ),
    // Port 1 — AXI bridge (bootloader / runtime AXI access)
    .port1_req_i    ( dsram_axi_req    ),
    .port1_gnt_o    ( dsram_axi_gnt    ),
    .port1_we_i     ( dsram_axi_we     ),
    .port1_addr_i   ( dsram_axi_addr   ),
    .port1_wdata_i  ( dsram_axi_wdata  ),
    .port1_be_i     ( dsram_axi_be     ),
    .port1_rdata_o  ( dsram_axi_rdata  ),
    .port1_rvalid_o ( dsram_axi_rvalid ),
    // SRAM
    .sram_cs_o      ( dsram_cs         ),
    .sram_we_o      ( dsram_we         ),
    .sram_addr_o    ( dsram_addr       ),
    .sram_wdata_o   ( dsram_wdata      ),
    .sram_wmask_o   ( dsram_wmask      ),
    .sram_rdata_i   ( dsram_rdata      )
  );

  // Data SRAM (4 KB)
  sram_sp #(
    .NUM_WORDS  ( DSRAM_NUM_WORDS ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_dsram (
    .clk_i   ( clk_i       ),
    .cs_i    ( dsram_cs     ),
    .we_i    ( dsram_we     ),
    .addr_i  ( dsram_addr   ),
    .wdata_i ( dsram_wdata  ),
    .wmask_i ( dsram_wmask  ),
    .rdata_o ( dsram_rdata  )
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
    .rst_ni               ( rst_ni          ),
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
    .rst_ni         ( rst_ni            ),
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
    .HRESETn    ( rst_ni                   ),
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
    .HRESETn ( rst_ni                   ),
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
    .RSTN    ( rst_ni                   ),
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
    .rst_ni                ( rst_ni                      ),
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
  //  Section 18 — APB[4]: SPI Master
  // ===========================================================================

  apb_spi_master #(
    .BUFFER_DEPTH   ( SPI_BUFFER_DEPTH ),
    .APB_ADDR_WIDTH ( 12               )
  ) i_apb_spi_master (
    .HCLK    ( clk_i                    ),
    .HRESETn ( rst_ni                   ),
    .PADDR   ( apb_req[4].paddr[11:0]   ),
    .PWDATA  ( apb_req[4].pwdata        ),
    .PWRITE  ( apb_req[4].pwrite        ),
    .PSEL    ( apb_req[4].psel          ),
    .PENABLE ( apb_req[4].penable       ),
    .PRDATA  ( spi_prdata               ),
    .PREADY  ( spi_pready               ),
    .PSLVERR ( spi_pslverr              ),
    .events_o( spi_events_o             ),
    .spi_clk ( spi_clk_o                ),
    .spi_csn0( spi_csn0_o               ),
    .spi_csn1( spi_csn1_o               ),
    .spi_csn2( spi_csn2_o               ),
    .spi_csn3( spi_csn3_o               ),
    .spi_mode( spi_mode_o               ),
    .spi_sdo0( spi_sdo0_o               ),
    .spi_sdo1( spi_sdo1_o               ),
    .spi_sdo2( spi_sdo2_o               ),
    .spi_sdo3( spi_sdo3_o               ),
    .spi_sdi0( spi_sdi0_i               ),
    .spi_sdi1( spi_sdi1_i               ),
    .spi_sdi2( spi_sdi2_i               ),
    .spi_sdi3( spi_sdi3_i               )
  );

  assign apb_resp[4] = '{pready: spi_pready, prdata: spi_prdata, pslverr: spi_pslverr};

  // ===========================================================================
  //  Section 19 — APB[5]: CLIC (Core-Local Interrupt Controller)
  //  Note: clic_apb uses flat APB signals, not struct. Decompose manually.
  //  FIX: irq_ready / irq_kill_ack now come from core (closed internal loop).
  // ===========================================================================

  clic_apb #(
    .N_SOURCE           ( CLIC_N_SOURCE   ),
    .INTCTLBITS         ( CLIC_INTCTLBITS ),
    .REG_BUS_ADDR_WIDTH ( AXI_ADDR_WIDTH  ),
    .REG_BUS_DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_clic_apb (
    .clk_i       ( clk_i                     ),
    .rst_ni      ( rst_ni                    ),
    .penable_i   ( apb_req[5].penable        ),
    .pwrite_i    ( apb_req[5].pwrite         ),
    .paddr_i     ( apb_req[5].paddr          ),
    .psel_i      ( apb_req[5].psel           ),
    .pwdata_i    ( apb_req[5].pwdata         ),
    .prdata_o    ( clic_prdata               ),
    .pready_o    ( clic_pready               ),
    .pslverr_o   ( clic_pslverr              ),
    // Interrupt sources
    .intr_src_i  ( clic_intr_src_i           ),
    // Interrupt notification — closed loop with core
    .irq_valid_o    ( clic_irq_valid_o       ),
    .irq_ready_i    ( core_irq_ready         ),  // from core (was: top-level input)
    .irq_id_o       ( clic_irq_id_o          ),
    .irq_level_o    ( clic_irq_level_o       ),
    .irq_shv_o      ( clic_irq_shv_o         ),
    .irq_priv_o     ( clic_irq_priv_o        ),
    .irq_kill_req_o ( clic_irq_kill_req_o    ),
    .irq_kill_ack_i ( core_irq_kill_ack      )   // from core (was: top-level input)
  );

  assign apb_resp[5] = '{pready: clic_pready, prdata: clic_prdata, pslverr: clic_pslverr};

  // ===========================================================================
  //  Section 20 — RISC-V Core Stub
  // ===========================================================================

  riscv_core_stub #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH )
  ) i_riscv_core (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    // Instruction fetch port (direct to ISRAM mux)
    .instr_req_o    ( core_instr_req    ),
    .instr_gnt_i    ( core_instr_gnt    ),
    .instr_addr_o   ( core_instr_addr   ),
    .instr_rdata_i  ( core_instr_rdata  ),
    .instr_rvalid_i ( core_instr_rvalid ),
    // Data memory port (direct to DSRAM mux)
    .data_req_o     ( core_data_req     ),
    .data_gnt_i     ( core_data_gnt     ),
    .data_we_o      ( core_data_we      ),
    .data_be_o      ( core_data_be      ),
    .data_addr_o    ( core_data_addr    ),
    .data_wdata_o   ( core_data_wdata   ),
    .data_rdata_i   ( core_data_rdata   ),
    .data_rvalid_i  ( core_data_rvalid  ),
    // AXI-Lite master (to crossbar for peripheral access)
    .axi_aw_addr_o  ( riscv_aw_addr     ),
    .axi_aw_prot_o  ( riscv_aw_prot     ),
    .axi_aw_valid_o ( riscv_aw_valid    ),
    .axi_aw_ready_i ( riscv_aw_ready    ),
    .axi_w_data_o   ( riscv_w_data      ),
    .axi_w_strb_o   ( riscv_w_strb      ),
    .axi_w_valid_o  ( riscv_w_valid     ),
    .axi_w_ready_i  ( riscv_w_ready     ),
    .axi_b_resp_i   ( riscv_b_resp      ),
    .axi_b_valid_i  ( riscv_b_valid     ),
    .axi_b_ready_o  ( riscv_b_ready     ),
    .axi_ar_addr_o  ( riscv_ar_addr     ),
    .axi_ar_prot_o  ( riscv_ar_prot     ),
    .axi_ar_valid_o ( riscv_ar_valid    ),
    .axi_ar_ready_i ( riscv_ar_ready    ),
    .axi_r_data_i   ( riscv_r_data      ),
    .axi_r_resp_i   ( riscv_r_resp      ),
    .axi_r_valid_i  ( riscv_r_valid     ),
    .axi_r_ready_o  ( riscv_r_ready     ),
    // Control
    .fetch_enable_i ( fetch_enable_i    ),
    .boot_addr_i    ( boot_addr_i       ),
    // CLIC interrupt — closed internal loop
    .irq_valid_i    ( clic_irq_valid_o  ),
    .irq_ready_o    ( core_irq_ready    ),   // → clic_apb.irq_ready_i
    .irq_id_i       ( clic_irq_id_o     ),
    .irq_level_i    ( clic_irq_level_o   ),
    .irq_shv_i      ( clic_irq_shv_o     ),
    .irq_priv_i     ( clic_irq_priv_o    ),
    .irq_kill_req_i ( clic_irq_kill_req_o),
    .irq_kill_ack_o ( core_irq_kill_ack  )   // → clic_apb.irq_kill_ack_i
  );

  // ===========================================================================
  //  Section 21 — Bootloader Stub
  // ===========================================================================

  bootloader_stub #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH )
  ) i_bootloader (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    // AXI-Lite master
    .axi_aw_addr_o  ( boot_aw_addr      ),
    .axi_aw_prot_o  ( boot_aw_prot      ),
    .axi_aw_valid_o ( boot_aw_valid     ),
    .axi_aw_ready_i ( boot_aw_ready     ),
    .axi_w_data_o   ( boot_w_data       ),
    .axi_w_strb_o   ( boot_w_strb       ),
    .axi_w_valid_o  ( boot_w_valid      ),
    .axi_w_ready_i  ( boot_w_ready      ),
    .axi_b_resp_i   ( boot_b_resp       ),
    .axi_b_valid_i  ( boot_b_valid      ),
    .axi_b_ready_o  ( boot_b_ready      ),
    .axi_ar_addr_o  ( boot_ar_addr      ),
    .axi_ar_prot_o  ( boot_ar_prot      ),
    .axi_ar_valid_o ( boot_ar_valid     ),
    .axi_ar_ready_i ( boot_ar_ready     ),
    .axi_r_data_i   ( boot_r_data       ),
    .axi_r_resp_i   ( boot_r_resp       ),
    .axi_r_valid_i  ( boot_r_valid      ),
    .axi_r_ready_o  ( boot_r_ready      ),
    // Boot control
    .boot_done_o    ( boot_done_o       ),
    // SPI Flash (direct external)
    .spi_clk_o      ( boot_spi_clk_o    ),
    .spi_csn_o      ( boot_spi_csn_o    ),
    .spi_sdo_o      ( boot_spi_sdo_o    ),
    .spi_sdi_i      ( boot_spi_sdi_i    ),
    .spi_mode_o     ( boot_spi_mode_o   )
  );

endmodule
