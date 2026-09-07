// =============================================================================
// RISCFORGE / SONIC-MCU — Bootloader (Boot Controller FSM + Reset Controller)
// =============================================================================
//
// ARCHITECTURE (per Bootloader_specification.pdf):
//   The bootloader sits between the APB bridge and apb_spi_master, with:
//     1. An AXI-Lite master port — for writing firmware words into ISRAM/DSRAM
//        via the crossbar during boot.
//     2. An APB slave port  — receives core APB traffic from the APB bridge
//        (slot 4) during runtime.
//     3. An APB master port — directly drives apb_spi_master's APB interface.
//     4. An APB mux — during boot, the Boot FSM drives the APB master;
//        during runtime, the APB slave port passes through to APB master.
//
//   SPI Hardware DMA FSM (spi_master_controller.sv inside apb_spi_master):
//     Once triggered by the Boot Controller, the SPI IP autonomously shifts
//     data bit-by-bit and pushes 32-bit words into its RX FIFO. When the
//     Boot Controller reads the RX FIFO via APB, PREADY stalls (=0) while
//     the FIFO is empty and asserts (=1) when a word is ready. This is the
//     hardware synchronization — no polling loops needed.
//
// RESET CONTROLLER (per reset_sequence_v5.pdf):
//   Inputs:
//     hard_rst_ni — External pin for full hardware initialisation (cold boot).
//     soft_rst_ni — External pin for system restart with memory retention
//                   (warm boot).
//   Outputs:
//     core_rst_ni_o   — Drives RISC-V core reset. LOW during boot.
//     periph_rst_ni_o — Drives non-boot peripheral resets (I2C, Timer, UART,
//                       GPIO, CLIC). LOW during boot.
//     spi_rst_ni_o    — Drives apb_spi_master clean-slate reset. HIGH during
//                       boot (SPI operational), LOW during clean-slate phase,
//                       HIGH during runtime.
//
//   *** FIX (this revision) ***
//   spi_rst_ni_o previously went straight from its power-up X value to 1'b1
//   on cold-boot entry (X -> 1 is a RISING transition). apb_spi_master's
//   internal always_ff blocks are all `posedge clk, negedge rstn` -
//   they never saw a falling edge on HRESETn (=spi_rst_ni_o), so every
//   register inside apb_spi_master (spi_master_controller's FSM state,
//   spi_master_apb_if's config regs, both FIFOs' pointers) stayed latched
//   at X forever in simulation. Since spi_master_controller's case(state)
//   has no default branch, state_next = state self-latched at X
//   indefinitely, so spi_cs never asserted and the SPI transfer never
//   started - the boot FSM parked forever in S_READ_FIFO waiting on
//   PREADY that could never come.
//
//   Fix: spi_rst_q now starts LOW (0) on cold-boot entry (a genuine
//   power-on-reset assertion), and is explicitly released HIGH once the
//   FSM moves past S_RESET into S_CLEAR_SRAM / S_INIT_CLKDIV - guaranteeing
//   a real negedge->posedge transition on spi_rst_ni_o before the SPI IP
//   is ever accessed. There are >5000 idle cycles in S_CLEAR_SRAM before
//   SPI is needed, so this costs nothing timing-wise.
//
// BOOT FLOW:
//   Cold Boot (hard_rst_ni LOW→HIGH):
//     S_RESET → S_CLEAR_SRAM → SPI config → per-word SPI read/SRAM write →
//     S_CLEAN_ASSERT → S_CLEAN_HOLD → S_CLEAN_RELEASE → S_DONE
//
//   Warm Boot (soft_rst_ni LOW→HIGH):
//     S_RESET → S_CLEAN_ASSERT → S_CLEAN_HOLD → S_CLEAN_RELEASE → S_DONE
//     (SRAM data preserved, SPI fetch skipped)
//
// POST-LOAD CLEAN-SLATE RESET:
//   After firmware is loaded (cold) or immediately (warm), ALL peripherals,
//   the core, and the SPI master are pulsed into reset for RESET_HOLD_CYCLES
//   clock cycles. This guarantees a blank state for runtime — no leftover
//   SPI configuration from boot leaks into the core execution environment.
//
// APB MUX:
//   boot_active (state != S_DONE):
//     APB master port ← Boot FSM drives SPI register reads/writes.
//     APB slave port  → idle response (core is in reset, no traffic).
//   !boot_active (S_DONE):
//     APB master port ← APB slave port (transparent passthrough).
//     APB slave response ← SPI master response (passthrough).
//
// MSB ALIGNMENT WARNING:
//   SPICMD and SPIADR are MSB-aligned (left-justified) — spi_master_tx.sv
//   always shifts from bit 31 downward regardless of cmd_len/addr_len.
//
// TYPE PARAMETERS:
//   axi_req_t / axi_resp_t must match the packed structs used by
//   axi_lite_xbar (aw_chan_t, w_chan_t, b_chan_t, ar_chan_t, r_chan_t).
//   apb_req_t / apb_resp_t must match the packed structs used by
//   axi_lite_to_apb (paddr, pprot, psel, penable, pwrite, pwdata, pstrb /
//   pready, prdata, pslverr).
// =============================================================================

module bootloader #(
  // --- Bus interface type parameters (from SoC top-level typedefs) ---
  parameter type          axi_req_t        = logic,
  parameter type          axi_resp_t       = logic,
  parameter type          apb_req_t        = logic,
  parameter type          apb_resp_t       = logic,


  // parameter type means it is a custom data type
  // they are set equal to logic, so incase they are not defined later on they do not 
  // give back a error

  // --- Bus widths ---
  //fixed right now
  parameter int unsigned  AXI_ADDR_WIDTH   = 32,
  parameter int unsigned  AXI_DATA_WIDTH   = 32,

  // --- Destination regions (must match SoC crossbar address map) ---
  // these are to be decided later
  parameter logic [31:0]  ISRAM_BASE_ADDR  = 32'h0000_0000,
  parameter logic [31:0]  DSRAM_BASE_ADDR  = 32'h0001_0000,
  parameter int unsigned  ISRAM_NUM_WORDS  = 1024,    // Parametrized SRAM capacity
  parameter int unsigned  DSRAM_NUM_WORDS  = 1024,    // Parametrized SRAM capacity

  // --- Firmware image layout: contiguous in flash, split to ISRAM/DSRAM ---
  //these are parameterized and are changed when instantiated
  parameter int unsigned  NUM_INSTR_WORDS  = 64,
  parameter int unsigned  NUM_DATA_WORDS   = 0,

  parameter logic [23:0]  FLASH_START_ADDR = 24'h00_0000,

  // --- SPI flash read parameters ---

  parameter logic [7:0]   FLASH_READ_CMD   = 8'h03,   // Standard SPI NOR "Read Data"
  parameter logic [5:0]   CMD_LEN_BITS     = 6'd8, //it specifies each command is of 8bits
  // so the 03 will be 00000011
  parameter logic [5:0]   ADDR_LEN_BITS    = 6'd24, // it tells which address to start
  // reading from
  parameter logic [15:0]  DATA_LEN_BITS    = 16'd32,  // One 32-bit word per transaction
  parameter logic [7:0]   SPI_CLK_DIV      = 8'd4,
  parameter logic [3:0]   CS_FLASH         = 4'b0001, // CSN0 = SPI Flash

  // --- Flash model power-up wait (simulation only) ---
  // The vendor S25FS512S model defaults to a 300us power-up delay.
  // At a 10ns system clock, that is 30,000 cycles.

  //the flash model has an internal PoweredUp flag
  parameter int unsigned  FLASH_POWERUP_CYCLES = 30_000,

  // --- Post-load clean-slate reset hold duration ---
  // 4 is for exactly 4 clock cycles
  parameter int unsigned  RESET_HOLD_CYCLES = 4
)(
  input  logic      clk_i,
//singular clock
  // =========================================================================
  // Dual Reset Inputs (from SoC top-level)
  // =========================================================================
  input  logic      hard_rst_ni,    // External: full hardware init (cold boot)
  input  logic      soft_rst_ni,    // External: memory-retaining restart (warm boot)

  // =========================================================================
  // AXI-Lite Master Interface (to crossbar SLV[1] — SRAM writes only)
  // =========================================================================
  output axi_req_t  axi_req_o,
  input  axi_resp_t axi_resp_i,

  // =========================================================================
  // APB Slave Port (from APB bridge slot 4 — runtime SPI passthrough)
  // =========================================================================
  input  apb_req_t  apb_slv_req_i,
  output apb_resp_t apb_slv_resp_o,

  // =========================================================================
  // APB Master Port (to apb_spi_master — boot config + runtime passthrough)
  // =========================================================================
  output apb_req_t  apb_mst_req_o,
  input  apb_resp_t apb_mst_resp_i,

  // =========================================================================
  // Reset Outputs (to SoC — managed by this boot controller)
  // =========================================================================
  output logic      core_rst_ni_o,    // RISC-V core reset
  output logic      periph_rst_ni_o,  // Non-boot peripherals (I2C, Timer, etc.)
  output logic      spi_rst_ni_o,     // SPI master clean-slate reset

  // =========================================================================
  // Boot Status
  // =========================================================================
  output logic      boot_done_o
);

  // ===========================================================================
  //  SPI Master register offsets (APB address space, lower 12 bits)
  //  Validated against spi_master_apb_if.sv and spi_master_m_bfm_tb.sv.
  // ===========================================================================
  localparam logic [11:0] REG_STATUS_OFF = 12'h000;
  localparam logic [11:0] REG_CLKDIV_OFF = 12'h004;
  localparam logic [11:0] REG_SPICMD_OFF = 12'h008;
  localparam logic [11:0] REG_SPIADR_OFF = 12'h00C;
  localparam logic [11:0] REG_SPILEN_OFF = 12'h010;
  localparam logic [11:0] REG_SPIDUM_OFF = 12'h014;
  localparam logic [11:0] REG_RXFIFO_OFF = 12'h020;

  // ===========================================================================
  //  Derived Constants
  // ===========================================================================

  //TOTAL_CLEAR_WORDS -> the sram entries,TOTAL_WORDS -> the memory to be entered
  localparam int unsigned TOTAL_WORDS       = NUM_INSTR_WORDS + NUM_DATA_WORDS;
  localparam int unsigned TOTAL_CLEAR_WORDS = ISRAM_NUM_WORDS + DSRAM_NUM_WORDS;

  // Initial firmware destination: skip to DSRAM if no instruction words.
  localparam logic [AXI_ADDR_WIDTH-1:0] DEST_ADDR_INIT =
      (NUM_INSTR_WORDS == 0) ? DSRAM_BASE_ADDR : ISRAM_BASE_ADDR;

  // Initial clear address: skip to DSRAM if no ISRAM.
  localparam logic [AXI_ADDR_WIDTH-1:0] CLEAR_ADDR_INIT =
      (ISRAM_NUM_WORDS == 0) ? DSRAM_BASE_ADDR : ISRAM_BASE_ADDR;

  // clog2(n) means log base 2, means the bits required for n
  // Counter widths (guarded against zero-size edge cases)
  //localparams mean protected parameter, unsigned for positive value only
  localparam int unsigned WORD_CNT_W     = (TOTAL_WORDS > 0)
                                           ? $clog2(TOTAL_WORDS + 1) : 1;
  // width of counter, counting words

  localparam int unsigned CLEAR_CNT_W    = (TOTAL_CLEAR_WORDS > 0)// The actual SRAM clear counter
                                           ? $clog2(TOTAL_CLEAR_WORDS + 1) : 1;
  localparam int unsigned FLASH_WAIT_CNT_W = (FLASH_POWERUP_CYCLES > 1)// The actual flash power-up counter
                                              ? $clog2(FLASH_POWERUP_CYCLES + 1) : 1;
  localparam int unsigned RST_HOLD_CNT_W = (RESET_HOLD_CYCLES > 1) // The actual reset hold counter
                                           ? $clog2(RESET_HOLD_CYCLES + 1) : 1;

  // ===========================================================================
  //  Assertions
  // ===========================================================================
  // pragma translate_off // this means to say that don't convert this to hardware
  initial begin
    assert (NUM_INSTR_WORDS <= ISRAM_NUM_WORDS) else
      $error("bootloader: NUM_INSTR_WORDS (%0d) exceeds ISRAM_NUM_WORDS (%0d)",
             NUM_INSTR_WORDS, ISRAM_NUM_WORDS);
    assert (NUM_DATA_WORDS <= DSRAM_NUM_WORDS) else
      $error("bootloader: NUM_DATA_WORDS (%0d) exceeds DSRAM_NUM_WORDS (%0d)",
             NUM_DATA_WORDS, DSRAM_NUM_WORDS);
    assert (FLASH_POWERUP_CYCLES >= 1) else
      $error("bootloader: FLASH_POWERUP_CYCLES must be >= 1");
    assert (RESET_HOLD_CYCLES >= 1) else
      $error("bootloader: RESET_HOLD_CYCLES must be >= 1");
  end
  // pragma translate_on

  // ===========================================================================
  //  FSM State Encoding
  // ===========================================================================
  typedef enum logic [3:0] {
    S_RESET,            // Wait for reset release, branch cold/warm
    S_CLEAR_SRAM,       // AXI write: zero every ISRAM then DSRAM word
    S_FLASH_WAIT,       // Wait for external SPI flash model power-up
    S_INIT_CLKDIV,      // APB write: SPI clock divider
    S_INIT_SPICMD,      // APB write: SPI command (flash read opcode)
    S_INIT_SPILEN,      // APB write: SPI transaction bit lengths
    S_INIT_SPIDUM,      // APB write: SPI dummy cycles (0 for opcode 0x03)
    S_CFG_SPIADR,       // APB write: per-word flash address
    S_TRIGGER,          // APB write: trigger SPI read transfer
    S_READ_FIFO,        // APB read:  RX FIFO (stalls on PREADY=0 until ready)
    S_WRITE_SRAM,       // AXI write: captured word to ISRAM/DSRAM
    S_CHECK_DONE,       // Increment counters, check completion
    S_CLEAN_ASSERT,     // Assert all resets LOW for clean-slate
    S_CLEAN_HOLD,       // Hold clean-slate reset for RESET_HOLD_CYCLES
    S_CLEAN_RELEASE,    // Release all resets HIGH → runtime
    S_DONE              // Terminal state: runtime mode, APB passthrough
  } state_e;

  // ===========================================================================
  //  Registers
  // ===========================================================================
  state_e state_q, state_d;

  // Boot state
  logic [23:0]                flash_addr_q;     // Current flash read address
  logic [AXI_ADDR_WIDTH-1:0]  dest_addr_q;      // Current SRAM write address
  logic [WORD_CNT_W-1:0]      word_cnt_q;       // Firmware words transferred
  logic [31:0]                rxfifo_data_q;    // Captured RX FIFO word

  // SRAM clear pass
  logic [AXI_ADDR_WIDTH-1:0]  clear_addr_q;     // Current SRAM clear address
  logic [CLEAR_CNT_W-1:0]     clear_cnt_q;      // SRAM words cleared

  // Flash power-up wait (simulation alignment for vendor flash model)
  logic [FLASH_WAIT_CNT_W-1:0] flash_wait_cnt_q;

  // AXI-Lite write handshake latches (per-channel completion)
  logic aw_done_q, w_done_q;

  // APB phase tracking: 0 = setup, 1 = access
  logic apb_phase_q;

  // Clean-slate reset hold counter
  logic [RST_HOLD_CNT_W-1:0] rst_hold_cnt_q;

  // Warm boot flag (set by soft reset, cleared by hard reset)
  logic warm_boot_q;

  // Reset output registers
  logic core_rst_q;       // 0 = core in reset
  logic periph_rst_q;     // 0 = peripherals in reset
  logic spi_rst_q;        // 0 = SPI master in reset

  // ===========================================================================
  //  Helper Functions
  // ===========================================================================

  // States that issue APB transactions (to SPI master)
  function automatic bit is_apb_state(state_e s);
    return (s == S_INIT_CLKDIV) || (s == S_INIT_SPICMD) || (s == S_INIT_SPILEN) ||
           (s == S_INIT_SPIDUM) || (s == S_CFG_SPIADR)  || (s == S_TRIGGER)     ||
           (s == S_READ_FIFO);
  endfunction

  // APB write states (subset of APB states)
  function automatic bit is_apb_write_state(state_e s);
    return (s == S_INIT_CLKDIV) || (s == S_INIT_SPICMD) || (s == S_INIT_SPILEN) ||
           (s == S_INIT_SPIDUM) || (s == S_CFG_SPIADR)  || (s == S_TRIGGER);
  endfunction

  // States that issue AXI-Lite write transactions (to SRAM via crossbar)
  function automatic bit is_axi_write_state(state_e s);
    return (s == S_CLEAR_SRAM) || (s == S_WRITE_SRAM);
  endfunction

  // Boot active: APB mux in boot mode (not passthrough)
  wire boot_active = (state_q != S_DONE);

  // ===========================================================================
  //  APB Boot Address / Data Mux (for SPI register access during boot)
  // ===========================================================================
  logic [AXI_ADDR_WIDTH-1:0] apb_boot_paddr;
  logic [31:0]               apb_boot_pwdata;
  logic                      apb_boot_pwrite;

  always_comb begin
    apb_boot_paddr  = '0;
    apb_boot_pwdata = '0;
    apb_boot_pwrite = 1'b1;    // Default: write

    unique case (state_q)
      S_INIT_CLKDIV: begin
        apb_boot_paddr[11:0] = REG_CLKDIV_OFF;
        apb_boot_pwdata      = {24'h0, SPI_CLK_DIV};
      end
      S_INIT_SPICMD: begin
        apb_boot_paddr[11:0] = REG_SPICMD_OFF;
        // MSB-aligned: top CMD_LEN_BITS bits are shifted out by spi_master_tx.
        apb_boot_pwdata      = {FLASH_READ_CMD, 24'h0};
      end
      S_INIT_SPILEN: begin
        apb_boot_paddr[11:0] = REG_SPILEN_OFF;
        apb_boot_pwdata      = {DATA_LEN_BITS, 2'b00, ADDR_LEN_BITS,
                                2'b00, CMD_LEN_BITS};
      end
      S_INIT_SPIDUM: begin
        apb_boot_paddr[11:0] = REG_SPIDUM_OFF;
        apb_boot_pwdata      = 32'h0;          // No dummy cycles for opcode 0x03
      end
      S_CFG_SPIADR: begin
        apb_boot_paddr[11:0] = REG_SPIADR_OFF;
        // MSB-aligned: top ADDR_LEN_BITS bits are shifted out.
        apb_boot_pwdata      = {flash_addr_q, 8'h0};
      end
      S_TRIGGER: begin
        apb_boot_paddr[11:0] = REG_STATUS_OFF;
        apb_boot_pwdata      = {20'h0, CS_FLASH, 4'h0, 4'b0001}; // csreg + spi_rd=1
      end
      S_READ_FIFO: begin
        apb_boot_paddr[11:0] = REG_RXFIFO_OFF;
        apb_boot_pwrite      = 1'b0;           // Read
      end
      default: ;
    endcase
  end

  // ===========================================================================
  //  APB Output Mux: Boot FSM (during boot) ↔ Passthrough (during runtime)
  // ===========================================================================
  always_comb begin
    if (boot_active) begin
      // ---- Boot mode: FSM drives APB master to SPI master ----
      apb_mst_req_o = '0;
      if (is_apb_state(state_q)) begin
        apb_mst_req_o.paddr   = apb_boot_paddr;
        apb_mst_req_o.pprot   = '0;
        apb_mst_req_o.psel    = 1'b1;
        apb_mst_req_o.penable = apb_phase_q;     // 0=setup, 1=access
        apb_mst_req_o.pwrite  = apb_boot_pwrite;
        apb_mst_req_o.pwdata  = apb_boot_pwdata;
        apb_mst_req_o.pstrb   = '1;              // All byte lanes valid
      end
      // APB slave port: idle response (core is in reset, shouldn't see this)
      apb_slv_resp_o.pready  = 1'b1;
      apb_slv_resp_o.prdata  = '0;
      apb_slv_resp_o.pslverr = 1'b0;
    end else begin
      // ---- Runtime mode: transparent passthrough ----
      apb_mst_req_o  = apb_slv_req_i;
      apb_slv_resp_o = apb_mst_resp_i;
    end
  end

  // ===========================================================================
  //  AXI-Lite Address / Data Mux (SRAM writes only)
  // ===========================================================================
  logic [AXI_ADDR_WIDTH-1:0] axi_wr_addr;
  logic [31:0]               axi_wr_data;

  always_comb begin
    axi_wr_addr = '0;
    axi_wr_data = '0;
    unique case (state_q)
      S_CLEAR_SRAM: begin
        axi_wr_addr = clear_addr_q;
        axi_wr_data = 32'h0;
      end
      S_WRITE_SRAM: begin
        axi_wr_addr = dest_addr_q;
        axi_wr_data = rxfifo_data_q;
      end
      default: ;
    endcase
  end

  // ===========================================================================
  //  AXI-Lite Request Struct Assembly
  // ===========================================================================
  always_comb begin
    axi_req_o = '0;

    // -- Write Address channel --
    axi_req_o.aw.addr  = axi_wr_addr;
    axi_req_o.aw.prot  = axi_pkg::prot_t'(3'b001);  // privileged access (bit[0]=1)
    axi_req_o.aw_valid = is_axi_write_state(state_q) && !aw_done_q;

    // -- Write Data channel --
    axi_req_o.w.data   = axi_wr_data;
    axi_req_o.w.strb   = {(AXI_DATA_WIDTH/8){1'b1}};
    axi_req_o.w_valid  = is_axi_write_state(state_q) && !w_done_q;

    // -- Write Response channel --
    axi_req_o.b_ready  = is_axi_write_state(state_q);

    // -- Read channels: unused (SPI reads are now via direct APB) --
    // ar, r channels default to '0 from the initial assignment above.
  end

  // ===========================================================================
  //  Sequential Logic
  // ===========================================================================
  always_ff @(posedge clk_i or negedge hard_rst_ni or negedge soft_rst_ni) begin
    if (!hard_rst_ni) begin
      // ===== Cold Boot Reset =====
      state_q        <= S_RESET;
      warm_boot_q    <= 1'b0;
      flash_addr_q   <= FLASH_START_ADDR;
      dest_addr_q    <= DEST_ADDR_INIT;
      word_cnt_q     <= '0;
      rxfifo_data_q  <= '0;
      clear_addr_q   <= CLEAR_ADDR_INIT;
      clear_cnt_q    <= '0;
      flash_wait_cnt_q <= '0;
      aw_done_q      <= 1'b0;
      w_done_q       <= 1'b0;
      apb_phase_q    <= 1'b0;
      rst_hold_cnt_q <= '0;
      // Reset outputs: core + peripherals held LOW.
      // FIX: spi_rst_q now starts LOW too (genuine POR assertion) instead
      // of jumping straight from X to 1 - see header comment for why the
      // old X->1 "transition" never actually reset apb_spi_master's
      // internal negedge-triggered flops. It gets released to 1 explicitly
      // below once the FSM advances past S_RESET (see state_d case block).
      core_rst_q     <= 1'b0;
      periph_rst_q   <= 1'b0;
      spi_rst_q      <= 1'b0;    // CHANGED: was 1'b1

    end else if (!soft_rst_ni) begin
      // ===== Warm Boot Reset =====
      state_q        <= S_RESET;
      warm_boot_q    <= 1'b1;    // Flag: skip SPI fetch
      flash_addr_q   <= FLASH_START_ADDR;
      dest_addr_q    <= DEST_ADDR_INIT;
      word_cnt_q     <= '0;
      rxfifo_data_q  <= '0;
      clear_addr_q   <= CLEAR_ADDR_INIT;
      clear_cnt_q    <= '0;
      flash_wait_cnt_q <= '0;
      aw_done_q      <= 1'b0;
      w_done_q       <= 1'b0;
      apb_phase_q    <= 1'b0;
      rst_hold_cnt_q <= '0;
      // Reset outputs: everything held LOW (SPI not needed for warm boot)
      core_rst_q     <= 1'b0;
      periph_rst_q   <= 1'b0;
      spi_rst_q      <= 1'b0;

    end else begin
      // ===== Normal Clocked Operation =====
      state_q <= state_d;

      // -----------------------------------------------------------------
      // AXI-Lite write handshake tracking
      // -----------------------------------------------------------------
      if (is_axi_write_state(state_q)) begin
        if (axi_req_o.aw_valid && axi_resp_i.aw_ready) aw_done_q <= 1'b1;
        if (axi_req_o.w_valid  && axi_resp_i.w_ready)  w_done_q  <= 1'b1;
        if (axi_resp_i.b_valid) begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
        end
      end

      // -----------------------------------------------------------------
      // APB phase tracking: 0=setup → 1=access → 0 (on PREADY)
      // -----------------------------------------------------------------
      if (is_apb_state(state_q)) begin
        if (!apb_phase_q)
          apb_phase_q <= 1'b1;              // Setup → Access
        else if (apb_mst_resp_i.pready)
          apb_phase_q <= 1'b0;              // Access complete → reset
      end else begin
        apb_phase_q <= 1'b0;                // Reset between APB states
      end

      // -----------------------------------------------------------------
      // Capture RX FIFO data on APB read completion
      // -----------------------------------------------------------------
      if (state_q == S_READ_FIFO && apb_phase_q && apb_mst_resp_i.pready)
        rxfifo_data_q <= {apb_mst_resp_i.prdata[7:0],
                          apb_mst_resp_i.prdata[15:8],
                          apb_mst_resp_i.prdata[23:16],
                          apb_mst_resp_i.prdata[31:24]};

      // -----------------------------------------------------------------
      // SRAM clear counter / address management
      // -----------------------------------------------------------------
      if (state_q == S_CLEAR_SRAM && axi_resp_i.b_valid) begin
        clear_cnt_q <= clear_cnt_q + 1'b1;
        if (clear_cnt_q + 1 == ISRAM_NUM_WORDS[CLEAR_CNT_W-1:0])
          clear_addr_q <= DSRAM_BASE_ADDR;        // Cross from ISRAM to DSRAM
        else
          clear_addr_q <= clear_addr_q + AXI_ADDR_WIDTH'(4);
      end

      // -----------------------------------------------------------------
      // Firmware word counter / address management
      // -----------------------------------------------------------------
      if (state_q == S_CHECK_DONE) begin
        flash_addr_q <= flash_addr_q + 24'd4;
        word_cnt_q   <= word_cnt_q + 1'b1;
        if (word_cnt_q + 1 == NUM_INSTR_WORDS[WORD_CNT_W-1:0])
          dest_addr_q <= DSRAM_BASE_ADDR;         // Cross from ISRAM to DSRAM
        else
          dest_addr_q <= dest_addr_q + AXI_ADDR_WIDTH'(4);
      end

      // -----------------------------------------------------------------
      // Flash power-up wait counter
      // -----------------------------------------------------------------
      if (state_q == S_FLASH_WAIT)
        flash_wait_cnt_q <= flash_wait_cnt_q + 1'b1;
      else
        flash_wait_cnt_q <= '0;

      // -----------------------------------------------------------------
      // Clean-slate reset hold counter
      // -----------------------------------------------------------------
      if (state_q == S_CLEAN_HOLD)
        rst_hold_cnt_q <= rst_hold_cnt_q + 1'b1;
      else
        rst_hold_cnt_q <= '0;

      // -----------------------------------------------------------------
      // Reset output register management
      // -----------------------------------------------------------------
      // FIX: added S_RESET/S_CLEAR_SRAM/S_INIT_CLKDIV branch below to
      // explicitly RELEASE spi_rst_q (0 -> 1) as soon as the FSM leaves
      // S_RESET. This produces the genuine negedge->posedge pulse on
      // spi_rst_ni_o that apb_spi_master's internal flops need to
      // actually initialize, since spi_rst_q now starts at 0 (not X->1)
      // on cold-boot entry above.
      unique case (state_d)
        S_CLEAR_SRAM, S_FLASH_WAIT, S_INIT_CLKDIV: begin
          // First real states after S_RESET: release SPI IP from reset early,
          // long before any APB access is made. Keep core/periph in reset
          // until the clean-slate phase.
          spi_rst_q <= 1'b1;
        end
        S_CLEAN_ASSERT, S_CLEAN_HOLD: begin
          // Assert all resets LOW for clean-slate
          core_rst_q   <= 1'b0;
          periph_rst_q <= 1'b0;
          spi_rst_q    <= 1'b0;
        end
        S_CLEAN_RELEASE, S_DONE: begin
          // Release all resets HIGH → runtime
          core_rst_q   <= 1'b1;
          periph_rst_q <= 1'b1;
          spi_rst_q    <= 1'b1;
        end
        default: ;   // Retain current values (set by async reset)
      endcase
    end
  end

  // ===========================================================================
  //  Next-State Logic
  // ===========================================================================
  always_comb begin
    state_d = state_q;

    unique case (state_q)

      // --- Entry point: branch cold vs warm ---
      S_RESET: begin
        if (warm_boot_q) begin
          state_d = S_CLEAN_ASSERT;           // Warm boot: skip SPI fetch
        end else if (TOTAL_CLEAR_WORDS == 0) begin
          state_d = (TOTAL_WORDS == 0) ? S_CLEAN_ASSERT : S_FLASH_WAIT;
        end else begin
          state_d = S_CLEAR_SRAM;
        end
      end

      // --- SRAM clear pass (AXI writes) ---
      S_CLEAR_SRAM: begin
        if (axi_resp_i.b_valid)
          state_d = (clear_cnt_q + 1 < TOTAL_CLEAR_WORDS[CLEAR_CNT_W-1:0])
                    ? S_CLEAR_SRAM
                    : ((TOTAL_WORDS == 0) ? S_CLEAN_ASSERT : S_FLASH_WAIT);
      end

      // --- Flash power-up wait ---
      S_FLASH_WAIT: begin
        if (flash_wait_cnt_q + 1 >= FLASH_POWERUP_CYCLES[FLASH_WAIT_CNT_W-1:0])
          state_d = S_INIT_CLKDIV;
      end

      // --- One-time SPI config (APB writes) ---
      S_INIT_CLKDIV: if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_INIT_SPICMD;
      S_INIT_SPICMD: if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_INIT_SPILEN;
      S_INIT_SPILEN: if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_INIT_SPIDUM;
      S_INIT_SPIDUM: if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_CFG_SPIADR;

      // --- Per-word SPI read + SRAM write loop ---
      S_CFG_SPIADR:  if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_TRIGGER;
      S_TRIGGER:     if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_READ_FIFO;
      S_READ_FIFO:   if (apb_phase_q && apb_mst_resp_i.pready) state_d = S_WRITE_SRAM;
      S_WRITE_SRAM:  if (axi_resp_i.b_valid)                   state_d = S_CHECK_DONE;

      S_CHECK_DONE: begin
        state_d = (word_cnt_q + 1 < TOTAL_WORDS[WORD_CNT_W-1:0])
                  ? S_CFG_SPIADR
                  : S_CLEAN_ASSERT;
      end

      // --- Clean-slate reset sequence ---
      S_CLEAN_ASSERT:  state_d = S_CLEAN_HOLD;

      S_CLEAN_HOLD: begin
        if (rst_hold_cnt_q + 1 >= RESET_HOLD_CYCLES[RST_HOLD_CNT_W-1:0])
          state_d = S_CLEAN_RELEASE;
      end

      S_CLEAN_RELEASE: state_d = S_DONE;

      // --- Terminal ---
      S_DONE: state_d = S_DONE;

      default: state_d = S_RESET;
    endcase
  end

  // ===========================================================================
  //  Output Assignments
  // ===========================================================================
  assign core_rst_ni_o   = core_rst_q;
  assign periph_rst_ni_o = periph_rst_q;
  assign spi_rst_ni_o    = spi_rst_q;
  assign boot_done_o     = (state_q == S_DONE);

endmodule
