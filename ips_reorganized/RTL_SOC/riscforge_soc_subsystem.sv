// =============================================================================
// RISCFORGE 1TOPS — SoC Peripheral Subsystem Top-Level
// =============================================================================
//
// Architecture:
//   RISC-V Core (real RV32IM, 5-stage — ips/riscv_core/rtl/top.v):
//     - Instruction fetch port → instr_fetch_demux
//         ├─ BootROM range (0x0000_0000) → boot_rom (reset vector; sets sp,
//         │                                 jumps to ISRAM base)
//         └─ ISRAM range   (0x0001_0000) → sram_mux[ISRAM] port 0 → ISRAM (32 KB)
//     - Load/store port       → hybrid_mem_interface, which splits:
//         ├─ DSRAM range  → sram_mux[DSRAM] port 0 → DSRAM (32 KB), direct
//         └─ MMIO range   → AXI-Lite master → axi_lite_xbar SLV[0]
//     Both SRAM paths are direct; only MMIO crosses the AXI fabric.
//
//   Bootloader (real):
//     - AXI-Lite master       → axi_lite_xbar SLV[1]   (SRAM writes only,
//                                awprot[0]=1 privileged — passes ISRAM gate)
//     - APB slave  ← APB bridge slot 4 (SPI address space)
//     - APB master → apb_spi_master  (boot: FSM drives; runtime: passthrough)
//     - Outputs: core_rst_ni, periph_rst_ni (clean-slate reset after load)
//
//   axi_lite_xbar (2 SLV → 3 MST):
//     MST[0] → axi_lite_sram_if (PRIV_WRITE_ONLY=1)
//                → sram_mux[ISRAM] port 1 → ISRAM
//     MST[1] → axi_lite_sram_if → sram_mux[DSRAM] port 1 → DSRAM
//     MST[2] → axi_lite_to_apb (1 AXI → 6 APB)
//               ├─ APB[0] → I2C
//               ├─ APB[1] → Timer 0
//               ├─ APB[2] → UART
//               ├─ APB[3] → GPIO
//               ├─ APB[4] → Bootloader APB slave (→ apb_spi_master)
//               └─ APB[5] → Timer 1
//
//   BootROM is directly connected to the core fetch demux (NOT on crossbar).
//   ISRAM writes via AXI are privilege-gated: only awprot[0]=1 (privileged)
//   transactions are accepted; unprivileged writes return SLVERR.
//
// ─────────────────────────────────────────────────────────────────────────────
// Address Map (Crossbar):
//   ISRAM:    0x0001_0000 – 0x0001_8000  (32 KB, privilege-gated writes)
//   DSRAM:    0x0002_0000 – 0x0002_8000  (32 KB)
//   APB:      0x4000_0000 – 0x5000_0000  (256 MB peripheral space)
//
// Address Map (Core-only, NOT on crossbar):
//   BootROM:  0x0000_0000 – 0x0000_0040  (64 B, 16 × 32-bit, read-only stub)
//
// Address Map (APB Bridge, within peripheral space):
//   I2C:      0x4000_0000 – 0x4000_1000  (4 KB)
//   Timer 0:  0x4000_1000 – 0x4000_2000  (4 KB)
//   UART:     0x4000_2000 – 0x4000_3000  (4 KB)
//   GPIO:     0x4000_3000 – 0x4000_4000  (4 KB)
//   SPI:      0x4000_4000 – 0x4000_5000  (4 KB)
//   Timer 1:  0x4000_5000 – 0x4000_6000  (4 KB)
//
// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY-MAPPED I/O REGISTER MAP
// ═══════════════════════════════════════════════════════════════════════════════
//
// ───────────────────────────────────────────────────────────────────────────────
// BootROM: 0x0000_0000 – 0x0000_003F  (64 B, 16 × 32-bit, read-only stub)
//   Core-only access via instruction fetch demux. Not on AXI crossbar.
// ───────────────────────────────────────────────────────────────────────────────
//   0x0000_0000 – 0x0000_003C   ROM data (16 × 32-bit words, NOP-filled stub)
//
// ───────────────────────────────────────────────────────────────────────────────
// ISRAM: 0x0001_0000 – 0x0001_7FFF  (32 KB, privilege-gated writes)
//   AXI writes require awprot[0]=1 (privileged). Unprivileged writes
//   return SLVERR. Core fetches via direct port (read-only, no AXI).
// ───────────────────────────────────────────────────────────────────────────────
//   0x0001_0000 – 0x0001_7FFC   Instruction SRAM (8192 × 32-bit words)
//
// ───────────────────────────────────────────────────────────────────────────────
// DSRAM: 0x0002_0000 – 0x0002_7FFF  (32 KB)
// ───────────────────────────────────────────────────────────────────────────────
//   0x0002_0000 – 0x0002_7FFC   Data SRAM (8192 × 32-bit words)
//
// ═══════════════════════════════════════════════════════════════════════════════
// APB PERIPHERAL SPACE: 0x4000_0000 – 0x4FFF_FFFF
// ═══════════════════════════════════════════════════════════════════════════════
//
// ───────────────────────────────────────────────────────────────────────────────
// I2C Master — APB[0]: 0x4000_0000 – 0x4000_0FFF  (4 KB)
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name   Width   Access  Description
//   0x00    PRE    16-bit  R/W     Clock prescaler (SCL = PCLK/(5×(PRE+1)))
//   0x04    CTR    8-bit   R/W     Control register
//             [7]   EN       R/W     Core enable
//             [6]   IEN      R/W     Interrupt enable
//             [5:0] —        —       Reserved
//   0x08    RXR    8-bit   R       Received byte
//   0x0C    SR     8-bit   R       Status register
//             [7]   RxACK    R       Received ACK from slave (0=ACK)
//             [6]   Busy     R       I2C bus busy
//             [5]   AL       R       Arbitration lost
//             [1]   TIP      R       Transfer in progress
//             [0]   IF       R       Interrupt flag
//   0x10    TXR    8-bit   W       Transmit byte / slave address
//   0x14    CR     8-bit   W       Command register
//             [7]   STA      W       Generate START condition
//             [6]   STO      W       Generate STOP condition
//             [5]   RD       W       Read from slave
//             [4]   WR       W       Write to slave
//             [3]   ACK      W       ACK value to send (0=ACK, 1=NACK)
//             [0]   IACK     W       Interrupt acknowledge
//
// ───────────────────────────────────────────────────────────────────────────────
// Timer 0 — APB[1]: 0x4000_1000 – 0x4000_1FFF  (4 KB, TIMER_CNT=2)
// ───────────────────────────────────────────────────────────────────────────────
//   Per-timer registers (Timer_N at offset N × 0x10):
//
//   Timer_0 (N=0):
//   Offset  Name         Width   Access  Description
//   0x00    TIMER_VAL    32-bit  R/W     Current timer value
//   0x04    TIMER_CTRL   32-bit  R/W     Timer control
//             [0]   EN        R/W     Timer enable
//             [5:3] PRESCALER R/W     Prescaler divider (0=bypass)
//   0x08    TIMER_CMP    32-bit  R/W     Compare value (resets timer on match)
//
//   Timer_1 (N=1):
//   0x10    TIMER_VAL    32-bit  R/W     Current timer value
//   0x14    TIMER_CTRL   32-bit  R/W     Timer control
//   0x18    TIMER_CMP    32-bit  R/W     Compare value
//
//   IRQ outputs: [2*N] = overflow,  [2*N+1] = compare match
//
// ───────────────────────────────────────────────────────────────────────────────
// UART — APB[2]: 0x4000_2000 – 0x4000_2FFF  (4 KB, 16550-compatible)
//   Note: apb_uart takes a 3-bit word address PADDR[4:2] (8 registers).
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name          Width   Access  Description
//   0x00    RBR/THR/DLL   8-bit   R/W     Receive buffer (R) / Transmit hold (W)
//                                          / Divisor latch LSB (when DLAB=1)
//   0x04    IER/DLM       8-bit   R/W     Interrupt enable (DLAB=0)
//                                          / Divisor latch MSB (DLAB=1)
//             [0]   ERBFI    R/W     Enable received data available IRQ
//             [1]   ETBEI    R/W     Enable TX hold empty IRQ
//             [2]   ELSI     R/W     Enable receiver line status IRQ
//             [3]   EDSSI    R/W     Enable modem status IRQ
//   0x08    IIR/FCR       8-bit   R/W     Interrupt identification (R)
//                                          / FIFO control (W)
//   0x0C    LCR           8-bit   R/W     Line control register
//             [7]   DLAB     R/W     Divisor latch access bit
//             [5:3] —        R/W     Parity config
//             [2]   STOP     R/W     Stop bits (0=1bit, 1=2bits)
//             [1:0] WLS      R/W     Word length (00=5, 11=8 bits)
//   0x10    MCR           8-bit   R/W     Modem control register
//   0x14    LSR           8-bit   R       Line status register
//             [0]   DR       R       Data ready
//             [5]   THRE     R       TX holding register empty
//             [6]   TEMT     R       Transmitter empty
//   0x18    MSR           8-bit   R       Modem status register
//   0x1C    SCR           8-bit   R/W     Scratch register
//
// ───────────────────────────────────────────────────────────────────────────────
// GPIO — APB[3]: 0x4000_3000 – 0x4000_37FF  (2 KB, 32 pins)
//   lowRISC reggen-generated register map (BlockAw=11).
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name                Width   Access  Description
//   0x000   INFO                32-bit  R       [9:0] GPIO count, [19:10] version
//   0x004   CFG                 32-bit  R/W     [0] global_intrpt_mode
//                                                [1] pin_lvl_intrpt_mode
//   0x008   GPIO_MODE_0         32-bit  R/W     2-bit mode per GPIO[0..15]
//   0x00C   GPIO_MODE_1         32-bit  R/W     2-bit mode per GPIO[16..31]
//   0x010   GPIO_EN             32-bit  R/W     Output enable per pin
//   0x014   GPIO_IN             32-bit  R       Sampled input value
//   0x018   GPIO_OUT            32-bit  R/W     Output data value
//   0x01C   GPIO_SET            32-bit  W       Set output pins (write-1-to-set)
//   0x020   GPIO_CLEAR          32-bit  W       Clear output pins (write-1-to-clear)
//   0x024   GPIO_TOGGLE         32-bit  W       Toggle output pins
//   0x028   INTRPT_RISE_EN      32-bit  R/W     Rising-edge interrupt enable
//   0x02C   INTRPT_FALL_EN      32-bit  R/W     Falling-edge interrupt enable
//   0x030   INTRPT_LVL_HIGH_EN  32-bit  R/W     Level-high interrupt enable
//   0x034   INTRPT_LVL_LOW_EN   32-bit  R/W     Level-low interrupt enable
//   0x038   INTRPT_STATUS       32-bit  R/W1C   Interrupt status
//   0x03C   INTRPT_RISE_STATUS  32-bit  R/W1C   Rising-edge interrupt status
//   0x040   INTRPT_FALL_STATUS  32-bit  R/W1C   Falling-edge interrupt status
//   0x044   INTRPT_LVL_HIGH_STS 32-bit  R       Level-high interrupt status
//   0x048   INTRPT_LVL_LOW_STS  32-bit  R       Level-low interrupt status
//
// ───────────────────────────────────────────────────────────────────────────────
// SPI Master — APB[4]: 0x4000_4000 – 0x4000_4FFF  (4 KB)
//   Accessible via bootloader APB mux; during boot: FSM-driven.
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name     Width   Access  Description
//   0x00    STATUS   32-bit  R       SPI status (TX/RX FIFO flags)
//             [0]   TX_FULL   R       TX FIFO full
//             [1]   TX_EMPTY  R       TX FIFO empty
//             [4]   RX_FULL   R       RX FIFO full
//             [5]   RX_EMPTY  R       RX FIFO empty
//             [8]   CS        R       Active chip select
//   0x04    CLKDIV   8-bit   R/W     SPI clock divider (f_SPI = f_CLK/(2×(CLKDIV+1)))
//   0x08    SPICMD   32-bit  R/W     SPI command value (MSB-aligned)
//   0x0C    SPIADR   32-bit  R/W     SPI address value (MSB-aligned)
//   0x10    SPILEN   32-bit  R/W     Transfer lengths
//             [5:0]   CMDLEN    R/W   Command length (bits)
//             [13:8]  ADRLEN    R/W   Address length (bits)
//             [31:16] DATALEN   R/W   Data length (bits)
//   0x14    SPIDUM   32-bit  R/W     Dummy cycle config
//             [15:0]  DUMMYRD   R/W   Dummy cycles for reads
//             [31:16] DUMMYWR   R/W   Dummy cycles for writes
//   0x18    TXFIFO   32-bit  W       TX FIFO data (push)
//   0x20    RXFIFO   32-bit  R       RX FIFO data (pop)
//   0x24    INTCFG   32-bit  R/W     Interrupt configuration
//   0x28    INTSTA   32-bit  R       Interrupt status
//
// ───────────────────────────────────────────────────────────────────────────────
// Timer 1 — APB[5]: 0x4000_5000 – 0x4000_5FFF  (4 KB, TIMER_CNT=2)
//   Same register layout as Timer 0.
// ───────────────────────────────────────────────────────────────────────────────
//   Timer_0 (N=0): 0x00 TIMER_VAL, 0x04 TIMER_CTRL, 0x08 TIMER_CMP
//   Timer_1 (N=1): 0x10 TIMER_VAL, 0x14 TIMER_CTRL, 0x18 TIMER_CMP
//   IRQ outputs: [2*N] = overflow,  [2*N+1] = compare match
//
// ─────────────────────────────────────────────────────────────────────────────
// Reset Topology:
//   hard_rst_ni  → cold boot, resets everything including bootloader
//   soft_rst_ni  → warm boot, SRAM preserved, bootloader runs clean-slate only
//   sys_rst_n    = sync(hard_rst_ni & soft_rst_ni) → crossbar, bridges, muxes
//                  Async assert (instant), sync de-assert (local 4-FF chain)
//   core_rst_n   ← bootloader output → RISC-V core
//   periph_rst_n ← bootloader output → non-boot peripherals (I2C, Timer 0,
//                                       Timer 1, UART, GPIO)
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
  parameter int unsigned TIMER0_CNT        = 2,
  parameter int unsigned TIMER1_CNT        = 2,
  parameter int unsigned SPI_BUFFER_DEPTH  = 10,
  parameter int unsigned BOOTROM_NUM_WORDS = 16,
  // Bootloader firmware image parameters (passed to bootloader)
  parameter int unsigned NUM_INSTR_WORDS   = 64,
  parameter int unsigned NUM_DATA_WORDS    = 0,
  parameter int unsigned FLASH_POWERUP_CYCLES = 30_000,
  // Number of APB slave ports (also sizes apb_timeout_sticky_o below)
  parameter int unsigned NUM_APB_SLAVES = 6,
  // Derived — do not override
  localparam int unsigned AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8,
  localparam int unsigned NR_GPIOS         = GPIOCount,
  localparam int unsigned BOOTROM_ADDR_WIDTH = $clog2(BOOTROM_NUM_WORDS)
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
  // Timer 0 IRQ
  // =========================================================================
  output logic [(TIMER0_CNT*2)-1:0]     timer0_irq_o,

  // =========================================================================
  // Timer 1 IRQ
  // =========================================================================
  output logic [(TIMER1_CNT*2)-1:0]     timer1_irq_o,

  // =========================================================================
  // UART External Interface (TX/RX only — modem lines tied off internally)
  // =========================================================================
  input  logic                          uart_sin_i,
  output logic                          uart_sout_o,
  output logic                          uart_int_o,

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
  // SPI Master External Interface (standard SPI only — quad lines tied off)
  //   spi_csn0_o : SPI flash (boot image source)
  //   spi_csn1_o : SPI slave device
  //   spi_sdo0_o : MOSI       spi_sdi1_i : MISO
  // =========================================================================
  output logic                          spi_clk_o,
  output logic                          spi_csn0_o,
  output logic                          spi_csn1_o,
  output logic                          spi_sdo0_o,
  input  logic                          spi_sdi1_i,
  output logic [1:0]                    spi_events_o,

  // =========================================================================
  // Bus Timeout Monitor Status (observation only — the CPU learns about a
  // timeout through the precise load/store access fault, mcause 5/7, so these
  // are not wired to any interrupt. Sticky until sys_rst_n.)
  // =========================================================================
  output logic [NUM_APB_SLAVES-1:0]     apb_timeout_sticky_o,
  output logic                          axi_wr_timeout_sticky_o,
  output logic                          axi_rd_timeout_sticky_o
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

  // NUM_APB_SLAVES is a module parameter (needed by the port list)
  localparam int unsigned NUM_APB_RULES  = NUM_APB_SLAVES;

  // ---------------------------------------------------------------------------
  //  Bus timeout thresholds (system clock cycles)
  // ---------------------------------------------------------------------------
  // Per APB slot, sized from the longest LEGITIMATE wait that slot can present
  // in one ACCESS phase, not from the length of a peripheral transfer:
  //   [0] I2C     PREADY tied 1 (apb_i2c.sv:214)                -> fault detector
  //   [1] Timer 0 PREADY tied 1 (timer.sv:44)                   -> fault detector
  //   [2] UART    1 wait state via apb_to_obi                   -> 8x margin
  //   [3] GPIO    feedthrough, 0 wait states                    -> fault detector
  //   [4] SPI     one 32-bit word, plus cmd+addr+dummy on the first word of a
  //               burst: (8+24+0+32) x 2 x (CLKDIV+1). 640 cycles at the
  //               bootloader's CLKDIV=4, 32768 at the maximum divider of 255.
  //               65536 keeps ~1.8x margin over the worst divider. An 8192-word
  //               transfer is 8192 separate APB reads and never approaches it.
  //   [5] Timer 1 as Timer 0                                    -> fault detector
  localparam int unsigned APB_TIMEOUT_CYCLES [NUM_APB_SLAVES] = '{
    16,      // [0] I2C
    16,      // [1] Timer 0
    16,      // [2] UART
    16,      // [3] GPIO
    65536,   // [4] SPI master (via bootloader passthrough)
    16       // [5] Timer 1
  };

  // AXI-Lite backstop at the core's master port, selected by address region.
  // SRAM is fixed latency (~4 cycles), so a small value catches a crossbar or
  // wrapper deadlock quickly. The APB region must stay above the largest APB
  // slot timeout so that apb_timeout_monitor always answers first.
  localparam int unsigned AXI_TIMEOUT_SRAM = 64;
  localparam int unsigned AXI_TIMEOUT_APB  = 131072;

  // ===========================================================================
  //  Section 5 — SRAM & BootROM Configuration
  // ===========================================================================

  localparam int unsigned ISRAM_NUM_WORDS  = 8192;  // 32 KB (8192 × 32-bit)
  localparam int unsigned DSRAM_NUM_WORDS  = 8192;  // 32 KB (8192 × 32-bit)
  localparam int unsigned SRAM_ADDR_WIDTH  = $clog2(ISRAM_NUM_WORDS);  // 13
  localparam int unsigned BYTE_OFFSET      = $clog2(AXI_DATA_WIDTH/8); // 2

  // ===========================================================================
  //  Section 6 — Internal Reset Signals
  // ===========================================================================

  // Derived internal resets
  logic       sys_rst_n_raw;   // Combinational: async assertion on either external reset
  logic [3:0] sys_rst_sync_q;  // 4-FF chain: async assert, sync de-assert
  logic [3:0] hard_rst_sync_q; // 4-FF chain: async assert, sync de-assert
  logic       sys_rst_n;       // Synchronized system reset (crossbar, bridges, muxes)
  logic       hard_rst_sync_n; // Synchronized hard reset (bootloader)
  logic       core_rst_n;      // For RISC-V core (from bootloader)
  logic       periph_rst_n;    // For non-boot peripherals (from bootloader)
  logic       spi_rst_n;       // For SPI master (from bootloader, independent timing)

  // Reset synchronizers -------------------------------------------------------
  // Assertion is asynchronous (instant when the input pin drops).
  // De-assertion is synchronized to clk_i through a 4-FF chain, so downstream
  // flops leave reset on a single clean clock edge instead of during their
  // recovery/removal window.
  //
  // sys_rst_n     : sourced from BOTH external resets ANDed together; feeds
  //                 the crossbar, AXI bridges, SRAM muxes, SRAM wrappers.
  // hard_rst_sync_n: sourced from hard_rst_ni only; feeds the bootloader, so
  //                 it leaves reset on the same edge as sys_rst_n (otherwise
  //                 the bootloader drives the crossbar while it is still in
  //                 reset). Warm boot leaves the bootloader clocked and lets
  //                 its own synchronous soft-reset handling take effect.
  assign sys_rst_n_raw = hard_rst_ni & soft_rst_ni;

  always_ff @(posedge clk_i or negedge sys_rst_n_raw) begin
    if (!sys_rst_n_raw) sys_rst_sync_q  <= 4'b0000;
    else                sys_rst_sync_q  <= {sys_rst_sync_q[2:0], 1'b1};
  end

  always_ff @(posedge clk_i or negedge hard_rst_ni) begin
    if (!hard_rst_ni)   hard_rst_sync_q <= 4'b0000;
    else                hard_rst_sync_q <= {hard_rst_sync_q[2:0], 1'b1};
  end

  assign sys_rst_n       = sys_rst_sync_q[3];
  assign hard_rst_sync_n = hard_rst_sync_q[3];

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
  apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp;      // bridge side (after the monitors)
  apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp_slv;  // slave side (before the monitors)

  // Bus timeout monitor status
  logic [NUM_APB_SLAVES-1:0] apb_timeout_pulse;
  logic                      axi_wr_timeout_pulse;
  logic                      axi_rd_timeout_pulse;

  // Core AXI-Lite master port, upstream of the AXI timeout monitor
  axi_req_t  core_axi_req;
  axi_resp_t core_axi_resp;

  // APB address map
  rule_t [NUM_APB_RULES-1:0] apb_addr_map;

  // --- Core instruction fetch port (core → fetch demux) ---
  // The core drives a raw SRAM-style fetch interface (enable + 30-bit word
  // address, 1-cycle read latency) with no req/gnt handshake. core_instr_gnt
  // and core_instr_rvalid are therefore left unread: the fetch port owns
  // sram_mux port 0, which has unconditional priority, and the ISRAM AXI
  // bridge is locked out at runtime — so a fetch is never denied.
  logic        core_instr_req;
  logic        core_instr_gnt;     // unused (see above)
  logic [31:0] core_instr_addr;
  logic [31:0] core_instr_rdata;
  logic        core_instr_rvalid;  // unused (see above)

  // --- Core fetch signals as driven by top.v ---
  logic        core_imem_en;
  logic [29:0] core_imem_addr_word;

  // --- Fetch demux → BootROM ---
  logic                           bootrom_cs;
  logic [BOOTROM_ADDR_WIDTH-1:0]  bootrom_addr;
  logic [31:0]                    bootrom_rdata;

  // --- Fetch demux → ISRAM mux port 0 ---
  logic        demux_isram_req;
  logic        demux_isram_gnt;
  logic [31:0] demux_isram_addr;
  logic [31:0] demux_isram_rdata;
  logic        demux_isram_rvalid;

  // --- Core LSU bus (top.v ↔ hybrid_mem_interface) ---
  logic        core_lsu_req;
  logic        core_lsu_we;
  logic [31:0] core_lsu_addr;
  logic [31:0] core_lsu_wdata;
  logic [3:0]  core_lsu_be;
  logic [31:0] core_lsu_rdata;
  logic        core_lsu_stall;
  logic        core_lsu_err;

  // --- Core data memory port (hybrid_mem_interface → DSRAM mux port 0) ---
  // As with the fetch port, core_data_gnt / core_data_rvalid are unread:
  // hybrid_mem_interface has no grant input and owns the read timing via its
  // own 1-cycle stall FSM. Port 0 has unconditional priority so it is never
  // denied. core_data_addr is a 30-bit ABSOLUTE word address (mem_addr[31:2]).
  logic        core_data_req;
  logic        core_data_gnt;      // unused (see above)
  logic        core_data_we;
  logic [3:0]  core_data_be;
  logic [29:0] core_data_addr;
  logic [31:0] core_data_wdata;
  logic [31:0] core_data_rdata;
  logic        core_data_rvalid;   // unused (see above)

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
  logic [31:0] i2c_prdata,   timer0_prdata,  uart_prdata;
  logic        i2c_pready,   timer0_pready,  uart_pready;
  logic        i2c_pslverr,  timer0_pslverr, uart_pslverr;

  // Timer 1 intermediate signals
  logic [31:0] timer1_prdata;
  logic        timer1_pready;
  logic        timer1_pslverr;

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

  // Crossbar address map (BootROM is NOT on crossbar — core-only access)
  assign xbar_addr_map[0] = '{idx: 32'd0, start_addr: 32'h0001_0000, end_addr: 32'h0001_8000}; // ISRAM (32 KB)
  assign xbar_addr_map[1] = '{idx: 32'd1, start_addr: 32'h0002_0000, end_addr: 32'h0002_8000}; // DSRAM (32 KB)
  assign xbar_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_0000, end_addr: 32'h5000_0000}; // APB

  // APB bridge address map
  assign apb_addr_map[0] = '{idx: 32'd0, start_addr: 32'h4000_0000, end_addr: 32'h4000_1000}; // I2C
  assign apb_addr_map[1] = '{idx: 32'd1, start_addr: 32'h4000_1000, end_addr: 32'h4000_2000}; // Timer 0
  assign apb_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_2000, end_addr: 32'h4000_3000}; // UART
  // GPIO: 2 KB. The register block decodes only 11 address bits, so mapping the
  // full 4 KB would alias 0x4000_3800-0x4000_3FFF onto the real registers.
  assign apb_addr_map[3] = '{idx: 32'd3, start_addr: 32'h4000_3000, end_addr: 32'h4000_3800}; // GPIO
  assign apb_addr_map[4] = '{idx: 32'd4, start_addr: 32'h4000_4000, end_addr: 32'h4000_5000}; // SPI Master (via bootloader)
  assign apb_addr_map[5] = '{idx: 32'd5, start_addr: 32'h4000_5000, end_addr: 32'h4000_6000}; // Timer 1

  // ===========================================================================
  //  Section 9 — (removed)
  // ===========================================================================
  // The RISC-V core's AXI-Lite master is hybrid_mem_interface, whose struct
  // ports connect directly to xbar_slv_req[0] / xbar_slv_resp[0] in Section 21.
  // The flat signal set and its pack/unpack that the stub required are gone.

  // ===========================================================================
  //  Section 10 — BootROM + Instruction Fetch Demux
  //  Core fetch → instr_fetch_demux → BootROM (direct)
  //                                 → sram_mux[ISRAM] port 0 (arbitrated)
  // ===========================================================================

  // BootROM (16-word stub, core-only access, NOT on crossbar)
  boot_rom #(
    .NUM_WORDS  ( BOOTROM_NUM_WORDS ),
    .DATA_WIDTH ( AXI_DATA_WIDTH    )
  ) i_boot_rom (
    .clk_i   ( clk_i        ),
    .rst_ni  ( core_rst_n    ),  // primes rdata_o with mem[0] for the first fetch
    .cs_i    ( bootrom_cs    ),
    .addr_i  ( bootrom_addr  ),
    .rdata_o ( bootrom_rdata )
  );

  // Instruction fetch address demux (routes core fetch to BootROM or ISRAM)
  instr_fetch_demux #(
    .BOOTROM_NUM_WORDS ( BOOTROM_NUM_WORDS ),
    .ISRAM_NUM_WORDS   ( ISRAM_NUM_WORDS   ),
    .BOOTROM_BASE      ( 32'h0000_0000     ),
    .ISRAM_BASE        ( 32'h0001_0000     ),
    // MUST match i_riscv_core's RESET_PC (Section 21). Selects the reset state
    // of the demux read-data mux so the reset-vector fetch is routed to the
    // right memory; a mismatch silently drops the instruction at RESET_PC.
    .RESET_PC          ( 32'h0000_0000     )
  ) i_instr_fetch_demux (
    .clk_i          ( clk_i              ),
    // core_rst_n, NOT sys_rst_n. The demux's only state is rom_accessed_q,
    // which selects the read-data source for the core's NEXT fetch. Its reset
    // value must still be intact when the core issues its FIRST fetch.
    // sys_rst_n releases ~121k cycles before core_rst_n (the whole boot), so in
    // that domain rom_accessed_q was clocked to 0 immediately and the reset
    // vector's fetch was routed to ISRAM instead of the BootROM — dropping the
    // instruction at RESET_PC. Sharing the core's reset holds it until the core
    // actually starts fetching. Safe: isram_req_o is combinational and already
    // gated by core_req_i, which is low while the core is in reset.
    .rst_ni         ( core_rst_n         ),
    // Core fetch port (upstream)
    .core_req_i     ( core_instr_req     ),
    .core_gnt_o     ( core_instr_gnt     ),
    .core_addr_i    ( core_instr_addr    ),
    .core_rdata_o   ( core_instr_rdata   ),
    .core_rvalid_o  ( core_instr_rvalid  ),
    // BootROM port (downstream)
    .rom_cs_o       ( bootrom_cs         ),
    .rom_addr_o     ( bootrom_addr       ),
    .rom_rdata_i    ( bootrom_rdata      ),
    // ISRAM mux port 0 (downstream)
    .isram_req_o    ( demux_isram_req    ),
    .isram_gnt_i    ( demux_isram_gnt    ),
    .isram_addr_o   ( demux_isram_addr   ),
    .isram_rdata_i  ( demux_isram_rdata  ),
    .isram_rvalid_i ( demux_isram_rvalid )
  );

  // ===========================================================================
  //  Section 11 — Instruction SRAM Subsystem
  //  (Crossbar MST[0] → AXI bridge → mux port 1; Demux → mux port 0)
  //  AXI bridge has PRIV_WRITE_ONLY=1: only privileged writes (bootloader)
  //  can modify ISRAM via AXI. Unprivileged writes return SLVERR.
  // ===========================================================================

  // AXI-Lite to SRAM bridge (crossbar MST[0] → mux port 1, privilege-gated)
  axi_lite_sram_if #(
    .AXI_ADDR_WIDTH  ( AXI_ADDR_WIDTH ),
    .AXI_DATA_WIDTH  ( AXI_DATA_WIDTH ),
    .SRAM_NUM_WORDS  ( ISRAM_NUM_WORDS ),
    .PRIV_WRITE_ONLY ( 1'b1            ),  // Only privileged writes accepted
    .axi_req_t       ( axi_req_t       ),
    .axi_resp_t      ( axi_resp_t      )
  ) i_isram_axi_if (
    .clk_i      ( clk_i              ),
    .rst_ni     ( sys_rst_n          ),
    .soft_rst_ni( soft_rst_ni        ),
    // Runtime lockout: once boot completes, ISRAM belongs to the core's fetch
    // port alone. AXI traffic is answered with SLVERR instead of contending
    // with (and being starved by) the every-cycle instruction fetch.
    .reject_i   ( boot_done_o        ),
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

  // 2:1 Priority Mux (port 0 = fetch demux, port 1 = AXI bridge)
  //
  // The two ports are never active simultaneously: during boot the core is held
  // in reset (port 0 idle) so the bootloader owns the SRAM, and after boot the
  // ISRAM AXI bridge rejects transactions (port 1 idle, see i_isram_axi_if's
  // reject_i). Plain port-0 priority is therefore sufficient.
  sram_mux #(
    .ADDR_WIDTH ( SRAM_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_isram_mux (
    .clk_i          ( clk_i       ),
    .rst_ni         ( sys_rst_n   ),
    // Port 0 — Fetch demux (read-only, from core via demux)
    .port0_req_i    ( demux_isram_req   ),
    .port0_gnt_o    ( demux_isram_gnt   ),
    .port0_we_i     ( 1'b0              ),  // instruction fetch is read-only
    .port0_addr_i   ( demux_isram_addr[BYTE_OFFSET +: SRAM_ADDR_WIDTH] ),
    .port0_wdata_i  ( '0                ),
    .port0_be_i     ( '0                ),
    .port0_rdata_o  ( demux_isram_rdata ),
    .port0_rvalid_o ( demux_isram_rvalid),
    // Port 1 — AXI bridge (bootloader / runtime AXI access, privilege-gated)
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

  // Instruction Memory (Instruction_Memory_new via sram_sp-compatible wrapper)
  imem_sram_wrapper #(
    .NUM_WORDS      ( ISRAM_NUM_WORDS ),
    .DATA_WIDTH     ( AXI_DATA_WIDTH  ),
    .IMEM_BASE_BYTE ( 32'h0001_0000  )   // Match crossbar ISRAM address map
  ) i_isram (
    .clk_i   ( clk_i       ),
    .rst_ni  ( sys_rst_n   ),
    .cs_i    ( isram_cs     ),
    .we_i    ( isram_we     ),
    .addr_i  ( isram_addr   ),
    .wdata_i ( isram_wdata  ),
    .wmask_i ( isram_wmask  ),
    .rdata_o ( isram_rdata  )
  );

  // ===========================================================================
  //  Section 12 — Data SRAM Subsystem
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
    .rst_ni     ( sys_rst_n          ),
    .soft_rst_ni( soft_rst_ni        ),
    .reject_i   ( 1'b0               ),  // DSRAM stays AXI-accessible at runtime
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
  //
  // Core data requests are intermittent (only load/store instructions assert
  // them), so port 1 gets cycles naturally under plain port-0 priority.
  sram_mux #(
    .ADDR_WIDTH ( SRAM_ADDR_WIDTH ),
    .DATA_WIDTH ( AXI_DATA_WIDTH  )
  ) i_dsram_mux (
    .clk_i          ( clk_i       ),
    .rst_ni         ( sys_rst_n   ),
    // Port 0 — Core data port (read/write)
    // core_data_addr is already a word address, so no byte-offset shift here;
    // the low SRAM_ADDR_WIDTH bits are the offset into DSRAM because its base
    // (0x0002_0000 = word 0x8000) is DSRAM_NUM_WORDS-aligned.
    .port0_req_i    ( core_data_req    ),
    .port0_gnt_o    ( core_data_gnt    ),
    .port0_we_i     ( core_data_we     ),
    .port0_addr_i   ( core_data_addr[SRAM_ADDR_WIDTH-1:0] ),
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

  // Data SRAM (32 KB)
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
  //  Section 13 — AXI-Lite Crossbar
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
  //  Section 14 — AXI-Lite → APB Bridge (Crossbar MST[2] → 6 APB Slaves)
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
  //  Section 14b — APB Timeout Monitors (one per slave port)
  // ===========================================================================
  //  Interposed on the RESPONSE path only: apb_req goes straight from the
  //  bridge to each slave, and only the response the bridge sees is muxed.
  //  A slave that holds PREADY low past its threshold is answered with
  //  PREADY=1 + PSLVERR=1, which axi_lite_to_apb turns into RESP_SLVERR and
  //  the core turns into a load/store access fault (mcause 5/7, mtval=addr).
  //  The slave's own PREADY is never driven, so an aborted SPI RXFIFO read
  //  pops nothing (spi_master_apb_if.sv:236).
  // ===========================================================================

  for (genvar i = 0; i < NUM_APB_SLAVES; i++) begin : gen_apb_timeout_mon
    apb_timeout_monitor #(
      .apb_req_t     ( apb_req_t              ),
      .apb_resp_t    ( apb_resp_t             ),
      .TimeoutCycles ( APB_TIMEOUT_CYCLES[i]  ),
      .TimeoutData   ( 32'hDEAD_BEEF          )
    ) i_apb_timeout_monitor (
      .clk_i            ( clk_i                    ),
      .rst_ni           ( sys_rst_n                ),
      .apb_req_i        ( apb_req[i]               ),
      .apb_resp_slv_i   ( apb_resp_slv[i]          ),
      .apb_resp_mst_o   ( apb_resp[i]              ),
      .timeout_pulse_o  ( apb_timeout_pulse[i]     ),
      .timeout_sticky_o ( apb_timeout_sticky_o[i]  )
    );
  end

  // ===========================================================================
  //  Section 15 — APB[0]: I2C Master
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

  assign apb_resp_slv[0] = '{pready: i2c_pready, prdata: i2c_prdata, pslverr: i2c_pslverr};

  // ===========================================================================
  //  Section 16 — APB[1]: Timer 0
  // ===========================================================================

  apb_timer #(
    .APB_ADDR_WIDTH ( 12         ),
    .TIMER_CNT      ( TIMER0_CNT )
  ) i_apb_timer0 (
    .HCLK    ( clk_i                    ),
    .HRESETn ( periph_rst_n             ),
    .PADDR   ( apb_req[1].paddr[11:0]   ),
    .PWDATA  ( apb_req[1].pwdata        ),
    .PWRITE  ( apb_req[1].pwrite        ),
    .PSEL    ( apb_req[1].psel          ),
    .PENABLE ( apb_req[1].penable       ),
    .PRDATA  ( timer0_prdata            ),
    .PREADY  ( timer0_pready            ),
    .PSLVERR ( timer0_pslverr           ),
    .irq_o   ( timer0_irq_o             )
  );

  assign apb_resp_slv[1] = '{pready: timer0_pready, prdata: timer0_prdata, pslverr: timer0_pslverr};

  // ===========================================================================
  //  Section 17 — APB[2]: UART
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
    // Modem lines not used: outputs left open, active-low inputs tied
    // inactive (1) so MSR reads 0x00 and the modem-status IRQ never fires.
    .OUT1N   (                          ),
    .OUT2N   (                          ),
    .RTSN    (                          ),
    .DTRN    (                          ),
    .CTSN    ( 1'b1                     ),
    .DSRN    ( 1'b1                     ),
    .DCDN    ( 1'b1                     ),
    .RIN     ( 1'b1                     ),
    .SIN     ( uart_sin_i               ),
    .SOUT    ( uart_sout_o              )
  );

  assign apb_resp_slv[2] = '{pready: uart_pready, prdata: uart_prdata, pslverr: uart_pslverr};

  // ===========================================================================
  //  Section 18 — APB[3]: GPIO
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
    .apb_rsp_o             ( apb_resp_slv[3]             )
  );

  // ===========================================================================
  //  Section 19 — APB[4]: SPI Master (via Bootloader APB mux)
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
    // Standard SPI only: CS2/CS3, pad-mode and quad data lines unused.
    // Unused data inputs tied 0 so a quad-mode trigger shifts in 0, not X.
    .spi_csn2(                              ),
    .spi_csn3(                              ),
    .spi_mode(                              ),
    .spi_sdo0( spi_sdo0_o                   ),
    .spi_sdo1(                              ),
    .spi_sdo2(                              ),
    .spi_sdo3(                              ),
    .spi_sdi0( 1'b0                         ),
    .spi_sdi1( spi_sdi1_i                   ),
    .spi_sdi2( 1'b0                         ),
    .spi_sdi3( 1'b0                         )
  );

  assign spi_apb_resp = '{pready: spi_pready, prdata: spi_prdata, pslverr: spi_pslverr};

  // ===========================================================================
  //  Section 20 — APB[5]: Timer 1
  //  Second timer instance (replaces CLIC at this APB slot).
  // ===========================================================================

  apb_timer #(
    .APB_ADDR_WIDTH ( 12         ),
    .TIMER_CNT      ( TIMER1_CNT )
  ) i_apb_timer1 (
    .HCLK    ( clk_i                    ),
    .HRESETn ( periph_rst_n             ),
    .PADDR   ( apb_req[5].paddr[11:0]   ),
    .PWDATA  ( apb_req[5].pwdata        ),
    .PWRITE  ( apb_req[5].pwrite        ),
    .PSEL    ( apb_req[5].psel          ),
    .PENABLE ( apb_req[5].penable       ),
    .PRDATA  ( timer1_prdata            ),
    .PREADY  ( timer1_pready            ),
    .PSLVERR ( timer1_pslverr           ),
    .irq_o   ( timer1_irq_o             )
  );

  assign apb_resp_slv[5] = '{pready: timer1_pready, prdata: timer1_prdata, pslverr: timer1_pslverr};

  // ===========================================================================
  //  Section 21 — RISC-V Core (RV32IM, 5-stage) + Data Memory Router
  // ===========================================================================
  // The core exposes two native buses and no AXI master of its own:
  //
  //   imem_sram_*  raw fetch interface — enable + 30-bit word address, 1-cycle
  //                read latency, no handshake. Feeds instr_fetch_demux, which
  //                routes to BootROM or ISRAM.
  //   lsu_mem_*    load/store bus. hybrid_mem_interface decodes it into either
  //                a direct DSRAM access (combinational, port 0 of the DSRAM
  //                mux) or an AXI-Lite transaction to the crossbar for MMIO.
  //
  // Only MMIO traffic crosses the AXI fabric; both SRAM paths are direct.
  //
  // fetch_enable_i / boot_addr_i are legacy top-level ports from the stub. The
  // reset vector is a parameter here (RESET_PC), since it is a register reset
  // value inside PC.v rather than a runtime input.
  // ===========================================================================

  top #(
    .RESET_PC ( 32'h0000_0000 )   // BootROM base — see boot_rom.sv for the image
  ) i_riscv_core (
    .clk            ( clk_i               ),
    .rst            ( core_rst_n          ),  // active-low
    .PCSrcE1        (                     ),  // debug only

    // ---- Instruction fetch (→ instr_fetch_demux) ----
    .imem_sram_en   ( core_imem_en        ),
    .imem_sram_we   (                     ),  // fetch path is read-only
    .imem_sram_wmask(                     ),
    .imem_sram_addr ( core_imem_addr_word ),
    .imem_sram_wdata(                     ),
    .imem_sram_rdata( core_instr_rdata    ),

    // ---- Load/store bus (→ hybrid_mem_interface) ----
    .lsu_mem_req    ( core_lsu_req        ),
    .lsu_mem_we     ( core_lsu_we         ),
    .lsu_mem_addr   ( core_lsu_addr       ),
    .lsu_mem_wdata  ( core_lsu_wdata      ),
    .lsu_mem_be     ( core_lsu_be         ),
    .lsu_mem_rdata  ( core_lsu_rdata      ),
    .lsu_mem_stall  ( core_lsu_stall      ),
    .lsu_mem_err    ( core_lsu_err        ),

    // ---- Interrupts (Two-Level Priority Class Architecture) ----
    // Evaluated via in-core irq_gateway (edge/pulse capture) and irq_arbiter:
    //   Class 2 (Fixed): timer compares 7,22,24,26, then overflows 20,21,23,25
    //   Class 1 (RR): UART (19), SPI threshold (18), SPI EOT (27)
    //   Class 0 (Background, RR):    I2C (FLI[1] mip[17])  <-> GPIO (FLI[0] mip[16])
    // MEIP and MSIP are tied off (no external PLIC / CLINT).
    .fast_irq_i     ( { 4'b0,
                        spi_events_o[1],          // FLI[11] → mip[27]  SPI end of transfer
                        timer1_irq_o[3],          // FLI[10] → mip[26]  Timer 1 ch1 compare
                        timer1_irq_o[2],          // FLI[9]  → mip[25]  Timer 1 ch1 overflow
                        timer1_irq_o[1],          // FLI[8]  → mip[24]  Timer 1 ch0 compare
                        timer1_irq_o[0],          // FLI[7]  → mip[23]  Timer 1 ch0 overflow
                        timer0_irq_o[3],          // FLI[6]  → mip[22]  Timer 0 ch1 compare
                        timer0_irq_o[2],          // FLI[5]  → mip[21]  Timer 0 ch1 overflow
                        timer0_irq_o[0],          // FLI[4]  → mip[20]  Timer 0 ch0 overflow
                        uart_int_o,               // FLI[3] → mip[19]
                        spi_events_o[0],          // FLI[2] → mip[18]
                        i2c_interrupt_o,          // FLI[1] → mip[17]
                        gpio_global_interrupt_o } ), // FLI[0] → mip[16]
    .timer_irq_i    ( timer0_irq_o[1]     ),  // MTIP — Timer 0 compare match
    .ext_irq_i      ( 1'b0                ),  // MEIP — no platform PLIC
    .sw_irq_i       ( 1'b0                )   // MSIP — no CLINT
  );

  // Fetch port adaptation: the demux takes a byte address, the core emits a
  // word address. No handshake to translate — port 0 is never denied.
  assign core_instr_req  = core_imem_en;
  assign core_instr_addr = { core_imem_addr_word, 2'b00 };

  // ---------------------------------------------------------------------------
  // Data memory router: DSRAM direct, MMIO over AXI-Lite to crossbar SLV[0]
  // ---------------------------------------------------------------------------
  hybrid_mem_interface #(
    .MEM_DEPTH      ( DSRAM_NUM_WORDS ),
    .DMEM_BASE_BYTE ( 32'h0002_0000   ),  // must match xbar_addr_map[1]
    .MMIO_BASE      ( 32'h4000_0000   ),  // must match xbar_addr_map[2]
    .MMIO_LIMIT     ( 32'h4FFF_FFFF   ),
    .axi_req_t      ( axi_req_t       ),
    .axi_resp_t     ( axi_resp_t      )
  ) i_core_data_if (
    .clk         ( clk_i            ),
    .rst_n       ( core_rst_n       ),

    // ---- From the core's LSU ----
    .mem_req     ( core_lsu_req     ),
    .mem_we      ( core_lsu_we      ),
    .mem_addr    ( core_lsu_addr    ),
    .mem_wdata   ( core_lsu_wdata   ),
    .mem_be      ( core_lsu_be      ),
    .mem_rdata   ( core_lsu_rdata   ),
    .mem_stall   ( core_lsu_stall   ),
    .mem_err     ( core_lsu_err     ),

    // ---- Direct DSRAM path (→ sram_mux port 0) ----
    .sram_en     ( core_data_req    ),
    .sram_we     ( core_data_we     ),
    .sram_wmask  ( core_data_be     ),
    .sram_addr   ( core_data_addr   ),
    .sram_wdata  ( core_data_wdata  ),
    .sram_rdata  ( core_data_rdata  ),

    // ---- MMIO path (→ crossbar SLV[0]) ----
    .m_axi_req_o ( core_axi_req  ),
    .m_axi_resp_i( core_axi_resp )
  );

  // ===========================================================================
  //  Section 21b — AXI-Lite Timeout Monitor (core master port)
  // ===========================================================================
  //  Backstop for anything the APB monitors cannot see: a crossbar deadlock,
  //  an SRAM wrapper that stops responding, or a future AXI slave. On a
  //  timeout it answers the core with SLVERR, keeps driving the stuck request
  //  downstream until the crossbar accepts it (AXI forbids withdrawing VALID),
  //  swallows the late response, and errors any new request while draining.
  //  Thresholds are per region so an SRAM deadlock is caught in 64 cycles
  //  while the APB region stays above the largest APB slot timeout.
  //  The bootloader's master port (xbar_slv[1]) is deliberately not monitored:
  //  it only writes to SRAM during boot, before the watchdog is enabled.
  // ===========================================================================

  axi_lite_timeout_monitor #(
    .axi_req_t      ( axi_req_t        ),
    .axi_resp_t     ( axi_resp_t       ),
    .AddrWidth      ( AXI_ADDR_WIDTH   ),
    .ApbBase        ( 32'h4000_0000    ),
    .ApbEnd         ( 32'h5000_0000    ),
    .TimeoutApb     ( AXI_TIMEOUT_APB  ),
    .TimeoutDefault ( AXI_TIMEOUT_SRAM ),
    .TimeoutData    ( 32'hDEAD_DEAD    )
  ) i_axi_lite_timeout_monitor (
    .clk_i               ( clk_i                   ),
    .rst_ni              ( sys_rst_n               ),
    .slv_req_i           ( core_axi_req            ),
    .slv_resp_o          ( core_axi_resp           ),
    .mst_req_o           ( xbar_slv_req[0]         ),
    .mst_resp_i          ( xbar_slv_resp[0]        ),
    .wr_timeout_pulse_o  ( axi_wr_timeout_pulse    ),
    .rd_timeout_pulse_o  ( axi_rd_timeout_pulse    ),
    .wr_timeout_sticky_o ( axi_wr_timeout_sticky_o ),
    .rd_timeout_sticky_o ( axi_rd_timeout_sticky_o )
  );

  // ===========================================================================
  //  Section 22 — Bootloader (Real Implementation)
  //  Connects directly via struct-based AXI-Lite to crossbar SLV[1].
  //  APB mux: during boot, FSM drives SPI master; at runtime, passthrough.
  //  AXI writes use awprot[0]=1 (privileged) to pass ISRAM privilege gate.
  // ===========================================================================

  bootloader #(
    .axi_req_t           ( axi_req_t           ),
    .axi_resp_t          ( axi_resp_t          ),
    .apb_req_t           ( apb_req_t           ),
    .apb_resp_t          ( apb_resp_t          ),
    .AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH      ),
    .AXI_DATA_WIDTH      ( AXI_DATA_WIDTH      ),
    .ISRAM_BASE_ADDR     ( 32'h0001_0000       ),
    .DSRAM_BASE_ADDR     ( 32'h0002_0000       ),
    .ISRAM_NUM_WORDS     ( ISRAM_NUM_WORDS     ),
    .DSRAM_NUM_WORDS     ( DSRAM_NUM_WORDS     ),
    .NUM_INSTR_WORDS     ( NUM_INSTR_WORDS     ),
    .NUM_DATA_WORDS      ( NUM_DATA_WORDS      ),
    .FLASH_POWERUP_CYCLES( FLASH_POWERUP_CYCLES)
  ) i_bootloader (
    .clk_i           ( clk_i             ),
    .hard_rst_ni     ( hard_rst_sync_n   ),
    .soft_rst_ni     ( soft_rst_ni       ),
    // AXI-Lite master (struct, not flat wires) — SRAM writes only
    .axi_req_o       ( xbar_slv_req[1]   ),
    .axi_resp_i      ( xbar_slv_resp[1]  ),
    // APB slave (from APB bridge slot 4)
    .apb_slv_req_i   ( apb_req[4]        ),
    .apb_slv_resp_o  ( apb_resp_slv[4]   ),
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
