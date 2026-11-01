// =============================================================================
// RISCFORGE 1TOPS — Unified SoC Verification Top Testbench (soc_tb_top.sv)
// =============================================================================
// Firmware is stimulus, Testbench is the judge.
// Supports Dual Boot:
//   +BOOT_MODE=WARM (Default): Backdoor preloads ISRAM/DSRAM for 0-cycle start.
//   +BOOT_MODE=COLD          : Preloads SPI flash & boots via Hardware Bootloader.
// =============================================================================

`timescale 1ns/1ps

module soc_tb_top;

  import tb_pkg::*;
  import gpio_reg_pkg::GPIOCount;

  // ---------------------------------------------------------------------------
  // Clock & Reset Generation
  // ---------------------------------------------------------------------------
  logic clk;
  logic hard_rst_n;
  logic soft_rst_n;
  logic test_mode;
  logic fetch_enable;
  logic [31:0] boot_addr;

  localparam time CLK_PERIOD = 10ns; // 100 MHz

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT Signals & Interconnect
  // ---------------------------------------------------------------------------
  logic boot_done;

  // I2C
  logic i2c_scl_in, i2c_scl_out, i2c_scl_oen;
  logic i2c_sda_in, i2c_sda_out, i2c_sda_oen;
  wire  i2c_scl_wire, i2c_sda_wire;
  logic i2c_interrupt;

  pullup(i2c_scl_wire);
  pullup(i2c_sda_wire);
  assign i2c_scl_wire = (i2c_scl_oen && !i2c_scl_out) ? 1'b0 : 1'bz;
  assign i2c_sda_wire = (i2c_sda_oen && !i2c_sda_out) ? 1'b0 : 1'bz;
  assign i2c_scl_in   = i2c_scl_wire;
  assign i2c_sda_in   = i2c_sda_wire;

  // Timers
  logic [3:0] timer0_irq;
  logic [3:0] timer1_irq;

  // UART
  logic uart_sin;
  logic uart_sout;
  logic uart_int;

  // GPIO
  logic [GPIOCount-1:0] gpio_in;
  logic [GPIOCount-1:0] gpio_out;
  logic [GPIOCount-1:0] gpio_tx_en;
  logic [GPIOCount-1:0] gpio_in_sync;
  logic                 gpio_global_irq;
  logic [GPIOCount-1:0] gpio_pin_irqs;

  // SPI
  logic       spi_clk;
  logic       spi_csn0;
  logic       spi_csn1;
  logic       spi_sdo0;
  logic       spi_sdi1;
  logic [1:0] spi_events;

  // Timeout Sticky Flags
  logic [5:0] apb_timeout_sticky;
  logic       axi_wr_timeout_sticky;
  logic       axi_rd_timeout_sticky;

  // ---------------------------------------------------------------------------
  // DUT Instantiation: riscforge_soc_subsystem
  // ---------------------------------------------------------------------------
  riscforge_soc_subsystem #(
    .TIMER0_CNT        (2),
    .TIMER1_CNT        (2),
    .SPI_BUFFER_DEPTH  (10),
    .BOOTROM_NUM_WORDS (16),
    .NUM_INSTR_WORDS   (64),
    .NUM_DATA_WORDS    (0),
    .FLASH_POWERUP_CYCLES(100), // Shortened for simulation
    .NUM_APB_SLAVES    (6)
  ) dut (
    .clk_i                       (clk),
    .hard_rst_ni                 (hard_rst_n),
    .soft_rst_ni                 (soft_rst_n),
    .test_mode_i                 (test_mode),
    .fetch_enable_i              (fetch_enable),
    .boot_addr_i                 (boot_addr),
    .boot_done_o                 (boot_done),

    .i2c_scl_i                   (i2c_scl_in),
    .i2c_scl_o                   (i2c_scl_out),
    .i2c_scl_oen_o               (i2c_scl_oen),
    .i2c_sda_i                   (i2c_sda_in),
    .i2c_sda_o                   (i2c_sda_out),
    .i2c_sda_oen_o               (i2c_sda_oen),
    .i2c_interrupt_o             (i2c_interrupt),

    .timer0_irq_o                (timer0_irq),
    .timer1_irq_o                (timer1_irq),

    .uart_sin_i                  (uart_sin),
    .uart_sout_o                 (uart_sout),
    .uart_int_o                  (uart_int),

    .gpio_in_i                   (gpio_in),
    .gpio_out_o                  (gpio_out),
    .gpio_tx_en_o                (gpio_tx_en),
    .gpio_in_sync_o              (gpio_in_sync),
    .gpio_global_interrupt_o     (gpio_global_irq),
    .gpio_pin_level_interrupts_o (gpio_pin_irqs),

    .spi_clk_o                   (spi_clk),
    .spi_csn0_o                  (spi_csn0),
    .spi_csn1_o                  (spi_csn1),
    .spi_sdo0_o                  (spi_sdo0),
    .spi_sdi1_i                  (spi_sdi1),
    .spi_events_o                (spi_events),

    .apb_timeout_sticky_o        (apb_timeout_sticky),
    .axi_wr_timeout_sticky_o     (axi_wr_timeout_sticky),
    .axi_rd_timeout_sticky_o     (axi_rd_timeout_sticky)
  );

  // ---------------------------------------------------------------------------
  // External VIP Models
  // ---------------------------------------------------------------------------
  uart_pin_vip #(.CLK_FREQ_HZ(100_000_000), .BAUD_RATE(115200)) u_uart_vip (
    .clk     (clk),
    .rst_n   (hard_rst_n),
    .uart_tx (uart_sout),
    .uart_rx (uart_sin)
  );

  gpio_pin_vip u_gpio_vip (
    .clk        (clk),
    .rst_n      (hard_rst_n),
    .gpio_out_o (gpio_out),
    .gpio_oe_o  (gpio_tx_en),
    .gpio_in_i  (gpio_in)
  );

  i2c_eeprom_at24c02 #(.I2C_ADDR(7'h50)) u_i2c_vip (
    .scl (i2c_scl_wire),
    .sda (i2c_sda_wire)
  );

  spi_flash_s25fs512s u_spi_flash_vip (
    .spi_clk (spi_clk),
    .spi_csn (spi_csn0),
    .spi_si  (spi_sdo0),
    .spi_so  (spi_sdi1)
  );

  // ---------------------------------------------------------------------------
  // Failure Reporter & Freeze Control
  // ---------------------------------------------------------------------------
  logic freeze_monitors;
  failure_reporter u_failure_reporter (
    .clk             (clk),
    .rst_n           (hard_rst_n),
    .freeze_monitors (freeze_monitors)
  );

  // ---------------------------------------------------------------------------
  // Passive Protocol & Pipeline Monitors
  //
  // NOTE ON HIERARCHICAL NET NAMES
  //   riscv_core/rtl/top.v has NO irq_req / irq_ack / irq_ret nets. The
  //   architectural acknowledgement point is the commit of an interrupt trap,
  //   which the RTL exposes as trap_commit_valid & trap_commit_is_interrupt,
  //   and the return point is mret_commit. Probing dut.i_riscv_core.irq_req (etc.)
  //   silently elaborates to nothing and leaves the monitors dead, so the
  //   correct nets are used here and documented so the mistake is not repeated:
  //     request  : dut.i_riscv_core.irq_pending
  //     granted id: dut.i_riscv_core.irq_winner_id        [4:0]
  //     ack      : dut.i_riscv_core.trap_commit_valid & dut.i_riscv_core.trap_commit_is_interrupt
  //     ret      : dut.i_riscv_core.mret_commit
  // ---------------------------------------------------------------------------
  logic core_irq_ack;
  assign core_irq_ack = dut.i_riscv_core.trap_commit_valid &
                        dut.i_riscv_core.trap_commit_is_interrupt;

  fetch_monitor u_fetch_mon (
    .clk      (clk),
    .rst_n    (hard_rst_n),
    .freeze   (freeze_monitors),
    .pc_f     (dut.i_riscv_core.Fetch.PCF),
    .instr_f  (dut.i_riscv_core.Fetch.InstrF),
    .imem_en  (dut.i_riscv_core.imem_sram_en),
    .stall_f  (dut.i_riscv_core.StallF),
    .pc_next  (dut.i_riscv_core.Fetch.PC_next)
  );

  retire_monitor u_retire_mon (
    .clk        (clk),
    .rst_n      (hard_rst_n),
    .freeze     (freeze_monitors),
    .valid_w    (dut.i_riscv_core.valid_W),
    .exc_valid_w(dut.i_riscv_core.exc_valid_W),
    .pc_w       (dut.i_riscv_core.PC_W),
    .instr_w    (32'b0),
    .rd_addr_w  (dut.i_riscv_core.RDW),
    .rd_wdata_w (dut.i_riscv_core.ResultW),
    .reg_we_w   (dut.i_riscv_core.RegWriteW),
    .trap_w     (dut.i_riscv_core.trap_commit_valid),
    .trap_is_interrupt(dut.i_riscv_core.trap_commit_is_interrupt),
    .trap_cause (dut.i_riscv_core.trap_commit_cause),
    .is_mret_w  (dut.i_riscv_core.is_mret_W),
    .csr_we_w   (dut.i_riscv_core.csr_write_en_W),
    .csr_addr_w (dut.i_riscv_core.csr_addr_W),
    .csr_wdata_w(dut.i_riscv_core.new_csr_W)
  );

  lsu_monitor u_lsu_mon (
    .clk       (clk),
    .rst_n     (hard_rst_n),
    .freeze    (freeze_monitors),
    .lsu_req   (dut.i_riscv_core.lsu_mem_req),
    .lsu_we    (dut.i_riscv_core.lsu_mem_we),
    .lsu_addr  (dut.i_riscv_core.lsu_mem_addr),
    .lsu_wdata (dut.i_riscv_core.lsu_mem_wdata),
    .lsu_be    (dut.i_riscv_core.lsu_mem_be),
    .lsu_rdata (dut.i_riscv_core.lsu_mem_rdata),
    .lsu_stall (dut.i_riscv_core.lsu_mem_stall),
    .lsu_err   (dut.i_riscv_core.lsu_mem_err),
    .pc_m      (dut.i_riscv_core.PC_M),
    .valid_m   (dut.i_riscv_core.valid_M)
  );

  axi_lite_monitor u_axi_mon (
    .clk     (clk),
    .rst_n   (hard_rst_n),
    .freeze  (freeze_monitors),
    .awaddr  (dut.core_axi_req.aw.addr),
    .awprot  (dut.core_axi_req.aw.prot),
    .awvalid (dut.core_axi_req.aw_valid),
    .awready (dut.core_axi_resp.aw_ready),
    .wdata   (dut.core_axi_req.w.data),
    .wstrb   (dut.core_axi_req.w.strb),
    .wvalid  (dut.core_axi_req.w_valid),
    .wready  (dut.core_axi_resp.w_ready),
    .bresp   (dut.core_axi_resp.b.resp),
    .bvalid  (dut.core_axi_resp.b_valid),
    .bready  (dut.core_axi_req.b_ready),
    .araddr  (dut.core_axi_req.ar.addr),
    .arprot  (dut.core_axi_req.ar.prot),
    .arvalid (dut.core_axi_req.ar_valid),
    .arready (dut.core_axi_resp.ar_ready),
    .rdata   (dut.core_axi_resp.r.data),
    .rresp   (dut.core_axi_resp.r.resp),
    .rvalid  (dut.core_axi_resp.r_valid),
    .rready  (dut.core_axi_req.r_ready)
  );

  logic [NUM_APB_SLOTS-1:0]     apb_psel_flat, apb_pready_flat, apb_pslverr_flat;
  genvar g_apb_ctl;
  generate
    for (g_apb_ctl = 0; g_apb_ctl < NUM_APB_SLOTS; g_apb_ctl++) begin : g_apb_ctl_flat
      assign apb_psel_flat  [g_apb_ctl] = dut.apb_req [g_apb_ctl].psel;
      assign apb_pready_flat[g_apb_ctl] = dut.apb_resp[g_apb_ctl].pready;
      assign apb_pslverr_flat[g_apb_ctl] = dut.apb_resp[g_apb_ctl].pslverr;
    end
  endgenerate

  // apb_monitor's per-slot payload and PRDATA ports use packed buses because XSim
  // packed bus (see monitors/apb_monitor.sv:26 and tb/rf_mon_probe.sv:192 -- XSim
  // 2022.2 cannot elaborate an unpacked array through this port). The SoC top has
  // no flat `apb_prdata` net: it carries the APB fabric as packed struct arrays
  // `apb_req[N]` / `apb_resp[N]` (riscforge_soc_subsystem.sv:544-546), so the flat
  // rejects unpacked arrays through module ports. Each slot is flattened
  // separately because the bridge leaves inactive-slot payload fields undefined.
  logic [NUM_APB_SLOTS*32-1:0] apb_paddr_flat, apb_pwdata_flat;
  logic [NUM_APB_SLOTS*3-1:0] apb_pprot_flat;
  logic [NUM_APB_SLOTS*4-1:0] apb_pstrb_flat;
  logic [NUM_APB_SLOTS-1:0] apb_penable_flat, apb_pwrite_flat;
  genvar g_apb_req;
  generate
    for (g_apb_req = 0; g_apb_req < NUM_APB_SLOTS; g_apb_req++) begin : g_apb_req_flat
      assign apb_paddr_flat[g_apb_req*32 +: 32] = dut.apb_req[g_apb_req].paddr;
      assign apb_pprot_flat[g_apb_req*3 +: 3] = dut.apb_req[g_apb_req].pprot;
      assign apb_penable_flat[g_apb_req] = dut.apb_req[g_apb_req].penable;
      assign apb_pwrite_flat[g_apb_req] = dut.apb_req[g_apb_req].pwrite;
      assign apb_pwdata_flat[g_apb_req*32 +: 32] = dut.apb_req[g_apb_req].pwdata;
      assign apb_pstrb_flat[g_apb_req*4 +: 4] = dut.apb_req[g_apb_req].pstrb;
    end
  endgenerate
  logic [31:0] apb_active_paddr, apb_active_pwdata;
  logic apb_active_penable, apb_active_pwrite;
  always_comb begin
    apb_active_paddr   = '0;
    apb_active_pwdata  = '0;
    apb_active_penable = 1'b0;
    apb_active_pwrite  = 1'b0;
    for (int apb_sel = 0; apb_sel < NUM_APB_SLOTS; apb_sel++) begin
      if (apb_psel_flat[apb_sel]) begin
        apb_active_paddr   = apb_paddr_flat[apb_sel*32 +: 32];
        apb_active_pwdata  = apb_pwdata_flat[apb_sel*32 +: 32];
        apb_active_penable = apb_penable_flat[apb_sel];
        apb_active_pwrite  = apb_pwrite_flat[apb_sel];
      end
    end
  end
  logic [NUM_APB_SLOTS*32-1:0] apb_prdata_flat;
  genvar g_apb_pd;
  generate
    for (g_apb_pd = 0; g_apb_pd < NUM_APB_SLOTS; g_apb_pd++) begin : g_apb_prdata_flat
      assign apb_prdata_flat[g_apb_pd*32 +: 32] = dut.apb_resp[g_apb_pd].prdata;
    end
  endgenerate

  apb_monitor #(.NUM_SLOTS(NUM_APB_SLOTS)) u_apb_mon (
    .clk         (clk),
    .rst_n       (hard_rst_n),
    .freeze      (freeze_monitors),
    .paddr_flat  (apb_paddr_flat),
    .psel        (apb_psel_flat),
    .penable     (apb_penable_flat),
    .pwrite      (apb_pwrite_flat),
    .pwdata_flat (apb_pwdata_flat),
    .pstrb_flat  (apb_pstrb_flat),
    .pready      (apb_pready_flat),
    .prdata_flat (apb_prdata_flat),
    .pslverr     (apb_pslverr_flat)
  );

  // The legacy irq_monitor takes the raw peripheral IRQ lines, the gateway
  // pend vector, and the architectural commit points - NOT the port names this
  // file used to connect (irq_req_to_core / irq_ack_from_core / irq_ret_from_core),
  // which do not exist in the core.
  logic [5:0] gateway_pend;
  assign gateway_pend = dut.i_riscv_core.pend_gateway;

  irq_monitor u_irq_mon (
    .clk               (clk),
    .rst_n             (hard_rst_n),
    .freeze            (freeze_monitors),
    .gpio_irq          (gpio_global_irq),
    .i2c_irq           (i2c_interrupt),
    .spi_irq           (spi_events),
    .uart_irq          (uart_int),
    .timer0_irq        (timer0_irq),
    .timer1_irq        (timer1_irq),
    .gateway_pend_q    (6'b0),
    .gateway_pend_o    (gateway_pend),
    .fast_irq_i        (dut.i_riscv_core.fast_intr_core),
    .timer_irq_i       (dut.i_riscv_core.timer_intr_core),
    .irq_pending       (dut.i_riscv_core.irq_pending),
    .irq_id            (dut.i_riscv_core.irq_winner_id),
    .irq_class         (dut.i_riscv_core.irq_winner_class),
    .rr_ptr_c1         (1'b0),
    .rr_ptr_c0         (1'b0),
    .nest_depth        (dut.i_riscv_core.nest_depth_sb),
    .cur_class         (dut.i_riscv_core.cur_class_sb),
    .trap_commit_valid (dut.i_riscv_core.trap_commit_valid),
    .trap_is_interrupt (dut.i_riscv_core.trap_commit_is_interrupt),
    .trap_commit_cause (dut.i_riscv_core.trap_commit_cause),
    .trap_commit_pc    (dut.i_riscv_core.trap_commit_pc),
    .mret_commit       (dut.i_riscv_core.mret_commit)
  );

  // ---------------------------------------------------------------------------
  // Checkers, Scoreboards & Predictor Reference Models
  // ---------------------------------------------------------------------------
  // APB fabric is carried as struct arrays dut.apb_req[0..5] / dut.apb_resp[0..5].
  // The scoreboard/predictor/SVA use a selected-slot view. The slot payload
  // itself is flattened above because inactive-slot request fields are undefined.
  logic [31:0] apb_prdata_arr [0:NUM_APB_SLOTS-1];
  genvar g_apb_arr;
  generate
    for (g_apb_arr = 0; g_apb_arr < NUM_APB_SLOTS; g_apb_arr++) begin : g_apb_prdata_arr
      assign apb_prdata_arr[g_apb_arr] = dut.apb_resp[g_apb_arr].prdata;
    end
  endgenerate

  mmio_path_scoreboard u_path_scoreboard (
    .clk       (clk),
    .rst_n     (hard_rst_n),
    .lsu_req   (dut.i_riscv_core.lsu_mem_req),
    .lsu_we    (dut.i_riscv_core.lsu_mem_we),
    .lsu_addr  (dut.i_riscv_core.lsu_mem_addr),
    .lsu_wdata (dut.i_riscv_core.lsu_mem_wdata),
    .lsu_be    (dut.i_riscv_core.lsu_mem_be),
    .lsu_stall (dut.i_riscv_core.lsu_mem_stall),
    .paddr     (apb_active_paddr),
    .psel      (apb_psel_flat),
    .penable   (apb_active_penable),
    .pwrite    (apb_active_pwrite),
    .pwdata    (apb_active_pwdata),
    .pready    (apb_pready_flat)
  );

  logic        reg_pred_err;
  string       reg_pred_msg;
  logic [31:0] reg_pred_addr, reg_pred_exp, reg_pred_got;

  register_predictor #(.NUM_SLOTS(6)) u_reg_predictor (
    .clk              (clk),
    .rst_n            (hard_rst_n),
    .freeze           (freeze_monitors),
    .paddr            (apb_active_paddr),
    .psel             (apb_psel_flat),
    .penable          (apb_active_penable),
    .pwrite           (apb_active_pwrite),
    .pwdata           (apb_active_pwdata),
    .pready           (apb_pready_flat),
    .prdata           (apb_prdata_arr),
    .pslverr          (apb_pslverr_flat),
    .reg_mismatch_err (reg_pred_err),
    .reg_err_msg      (reg_pred_msg),
    .reg_err_addr     (reg_pred_addr),
    .reg_err_exp      (reg_pred_exp),
    .reg_err_got      (reg_pred_got)
  );

  logic       irq_pred_err;
  string      irq_pred_msg;
  logic [4:0] irq_pred_exp, irq_pred_got;

  // timer0_irq must be the COMPARE bit (irq_o[1]), not the overflow bit.
  // riscforge_soc_subsystem.sv:1249 wires timer0_irq_o[1] to the core's
  // timer_irq_i (MTIP, interrupt ID 7). Feeding the predictor timer0_irq[0]
  // (overflow) would model a source the core never sees, and the shadow stack
  // would disagree with the hardware on the very first interrupt.
  irq_predictor u_irq_predictor (
    .clk              (clk),
    .rst_n            (hard_rst_n),
    .freeze           (freeze_monitors),
    .fast_irq         (dut.i_riscv_core.fast_intr_core),
    .timer0_irq       (timer0_irq[1]),
    .core_irq_req     (dut.i_riscv_core.irq_pending),
    .core_irq_id      (dut.i_riscv_core.irq_winner_id),
    .core_irq_ack     (core_irq_ack),
    .core_irq_ret     (dut.i_riscv_core.mret_commit),
    .irq_mismatch_err (irq_pred_err),
    .irq_err_msg      (irq_pred_msg),
    .irq_exp_id       (irq_pred_exp),
    .irq_got_id       (irq_pred_got)
  );

  axi_lite_protocol_sva u_axi_sva (
    .clk     (clk),
    .rst_n   (hard_rst_n),
    .awaddr  (dut.core_axi_req.aw.addr),
    .awprot  (dut.core_axi_req.aw.prot),
    .awvalid (dut.core_axi_req.aw_valid),
    .awready (dut.core_axi_resp.aw_ready),
    .wdata   (dut.core_axi_req.w.data),
    .wstrb   (dut.core_axi_req.w.strb),
    .wvalid  (dut.core_axi_req.w_valid),
    .wready  (dut.core_axi_resp.w_ready),
    .bresp   (dut.core_axi_resp.b.resp),
    .bvalid  (dut.core_axi_resp.b_valid),
    .bready  (dut.core_axi_req.b_ready),
    .araddr  (dut.core_axi_req.ar.addr),
    .arprot  (dut.core_axi_req.ar.prot),
    .arvalid (dut.core_axi_req.ar_valid),
    .arready (dut.core_axi_resp.ar_ready),
    .rdata   (dut.core_axi_resp.r.data),
    .rresp   (dut.core_axi_resp.r.resp),
    .rvalid  (dut.core_axi_resp.r_valid),
    .rready  (dut.core_axi_req.r_ready)
  );

  apb_protocol_sva #(.NUM_SLOTS(6)) u_apb_sva (
    .clk     (clk),
    .rst_n   (hard_rst_n),
    .paddr   (apb_active_paddr),
    .psel    (apb_psel_flat),
    .penable (apb_active_penable),
    .pwrite  (apb_active_pwrite),
    .pwdata  (apb_active_pwdata),
    .pready  (apb_pready_flat),
    .prdata  (apb_prdata_arr),
    .pslverr (apb_pslverr_flat)
  );

  // ---------------------------------------------------------------------------
  // Dynamic Mailbox Watcher & Test Driver
  // ---------------------------------------------------------------------------
  string boot_mode_str = "WARM";
  string imem_hex_path = "imem.hex";
  string dmem_hex_path = "dmem.hex";
  string flash_mem_path = "flash.mem";
  longint unsigned max_watchdog_cycles = 1_000_000;
  longint unsigned sim_cycle_cnt = 0;

  // Mailbox Snooping
  logic [31:0] mb_cmd;
  logic [31:0] mb_test_id;
  logic [31:0] mb_arg0, mb_arg1, mb_arg2;
  logic [31:0] mb_char_out;
  logic [31:0] mb_error_code;
  logic [31:0] mb_activity;

  // Sample Mailbox at word offset 0 of DSRAM
  assign mb_cmd        = dut.i_dsram.mem[0];
  assign mb_test_id    = dut.i_dsram.mem[1];
  assign mb_arg0       = dut.i_dsram.mem[2];
  assign mb_arg1       = dut.i_dsram.mem[3];
  assign mb_arg2       = dut.i_dsram.mem[4];
  assign mb_char_out   = dut.i_dsram.mem[5];
  assign mb_error_code = dut.i_dsram.mem[6];
  assign mb_activity   = dut.i_dsram.mem[7];  // +0x1C: firmware attestation word

  // ===========================================================================
  // ANTI-VACUITY GUARD
  // ===========================================================================
  // A bare-metal stage that reports PASS without the hardware having done
  // anything is the worst possible regression outcome: the suite goes green
  // while the DUT is dead. A firmware PASS is therefore treated as a REQUEST,
  // not a verdict. Before this testbench will call a run green it requires ALL
  // of the following, every one of which the firmware cannot forge:
  //
  //   G1  total_retired_instr > 0            the core actually executed
  //   G2  AXI-Lite beats (wr+rd) > 0         the MMIO fabric moved transactions
  //   G3  APB transfers > 0                   a peripheral slave answered
  //   G4  n_find == 0                        no checker fired at any point
  //   G5  firmware attestation word != 0     the firmware itself saw bus traffic
  //   G6  minstret advanced past the boot     the core's own retired counter moved
  //
  // G1/G2/G3 come from the passive monitors, G4 from the failure reporter, and
  // G5/G6 from signals the firmware can only change by really performing the
  // accesses. Together they make a vacuous pass structurally impossible while
  // keeping the firmware and the testbench independent of one another.
  // ===========================================================================
  localparam longint unsigned MIN_RETIRED_INSTR = 1;
  localparam longint unsigned MIN_AXI_BEATS      = 1;
  localparam longint unsigned MIN_APB_TRANS      = 1;
  localparam longint unsigned STAGE2_TEST_ID     = 32'h0000_0002;

  function automatic longint unsigned axi_beats();
    return u_axi_mon.total_axi_writes + u_axi_mon.total_axi_reads;
  endfunction

  function automatic longint unsigned lsu_beats();
    return u_lsu_mon.total_reads + u_lsu_mon.total_writes;
  endfunction

  // Emit a full evidence dump, then blame the firmware layer.
  task automatic fail_vacuous(input string check_id, input string msg);
    $display("\n[VACUITY VIOLATION] %s", check_id);
    $display("  message           : %s", msg);
    $display("  retired_instr     : %0d", u_retire_mon.total_retired_instr);
    $display("  axi writes/reads  : %0d / %0d",
             u_axi_mon.total_axi_writes, u_axi_mon.total_axi_reads);
    $display("  apb transfers     : %0d", u_apb_mon.total_apb_trans);
    $display("  lsu reads/writes  : %0d / %0d",
             u_lsu_mon.total_reads, u_lsu_mon.total_writes);
    $display("  fw attestation    : 0x%08X (mmio_rd=%0d mmio_wr=%0d)",
             mb_activity, mb_activity[15:0], mb_activity[31:16]);
    $display("  fatals recorded   : %0d", u_failure_reporter.n_find);
    $display("  test id           : 0x%08X", mb_test_id);
    u_failure_reporter.report_failure(LAYER_FIRMWARE, check_id, msg, dut.i_riscv_core.PC_W);
    u_retire_mon.dump_recent_retires(10);
    u_lsu_mon.dump_recent_lsu(10);
    u_axi_mon.dump_recent_trans(10);
    u_apb_mon.dump_recent_trans(10);
  endtask

  // Lossless character streaming monitor with sequence tag tracking
  logic [15:0] last_char_seq;
  initial last_char_seq = 16'h0000;


  always @(posedge clk) begin
    if (hard_rst_n && soft_rst_n) begin
      logic [15:0] cur_seq;
      cur_seq = mb_char_out[31:16];
      if (cur_seq != 0 && cur_seq != last_char_seq) begin
        $write("%c", mb_char_out[7:0]);
        last_char_seq <= cur_seq;
      end
    end
  end

  // Testbench Main Flow
  initial begin
    $timeformat(-9, 2, " ns", 20);
    $display("\n================================================================================");
    $display("               RISCFORGE SoC Verification Testbench Launch                      ");
    $display("================================================================================");

    // Read plusargs
    void'($value$plusargs("BOOT_MODE=%s", boot_mode_str));
    void'($value$plusargs("IMEM_HEX=%s", imem_hex_path));
    void'($value$plusargs("DMEM_HEX=%s", dmem_hex_path));
    void'($value$plusargs("FLASH_MEM=%s", flash_mem_path));
    void'($value$plusargs("TIMEOUT=%d", max_watchdog_cycles));

    $display("  BOOT MODE       : %s", boot_mode_str);
    $display("  WATCHDOG LIMIT  : %0d cycles", max_watchdog_cycles);

    // Initial signals
    hard_rst_n   = 1'b0;
    soft_rst_n   = 1'b0;
    test_mode    = 1'b0;
    fetch_enable = 1'b1;
    boot_addr    = 32'h0001_0000;

    #100ns;

    if (boot_mode_str == "WARM") begin : warm_boot_setup
      integer reset_wait_cycles;
      $display("[TB Reset] Releasing hard reset while warm soft reset remains asserted.");
      #100ns;
      hard_rst_n = 1'b1;
      // Wait for the SoC's hard-reset synchronizer and then the bootloader's
      // soft-reset synchronizer. Releasing both together (or before the
      // nested synchronizers settle) enters the cold S_CLEAR_SRAM path.
      reset_wait_cycles = 0;
      while ((dut.hard_rst_sync_n !== 1'b1) && (reset_wait_cycles < 20)) begin
        @(negedge clk);
        reset_wait_cycles++;
      end
      if (dut.hard_rst_sync_n !== 1'b1)
        $fatal(1, "WARM setup failed: hard reset synchronizer did not release");
      while ((dut.i_bootloader.warm_boot_q !== 1'b1) && (reset_wait_cycles < 40)) begin
        @(negedge clk);
        reset_wait_cycles++;
      end
      if (dut.i_bootloader.warm_boot_q !== 1'b1)
        $fatal(1, "WARM setup failed: bootloader did not observe soft reset");
      $display("[TB Preload] Backdooring SRAM after warm reset synchronization...");
      $readmemh(imem_hex_path, dut.i_isram.u_imem.mem_array);
      $readmemh(dmem_hex_path, dut.i_dsram.mem);
      soft_rst_n = 1'b1;
      $display("[TB Reset] Released hard reset, then warm soft reset. Core running at ISRAM 0x0001_0000.");
    end else begin
      $display("[TB Flash Preload] Loading SPI Flash model (COLD BOOT)...");
      u_spi_flash_vip.preload_hex(flash_mem_path);

      #100ns;
      hard_rst_n = 1'b1;
      soft_rst_n = 1'b1;
      $display("[TB Bootloader] Waiting for boot_done_o from Bootloader FSM...");
      @(posedge boot_done);
      $display("[TB Bootloader] Boot complete at %0t. Core starting execution.", $time);
    end

    // Watchdog and Completion Loop
    fork
      // Watchdog
      begin
        while (sim_cycle_cnt < max_watchdog_cycles) begin
          @(posedge clk);
          sim_cycle_cnt++;
        end

        $display("\n[WATCHDOG EXPIRED] Simulation reached watchdog limit (%0d cycles)", max_watchdog_cycles);
        $display("[WATCHDOG DEBUG] hard=%b soft=%b sys_rst=%b hard_sync=%b core_rst=%b boot_done=%b boot_state=%0d warm_boot=%b soft_sync=%b PC=%08X imem[0]=%08X imem[1]=%08X",
                 hard_rst_n, soft_rst_n, dut.sys_rst_n, dut.hard_rst_sync_n,
                 dut.core_rst_n, boot_done, dut.i_bootloader.state_q,
                 dut.i_bootloader.warm_boot_q, dut.i_bootloader.soft_rst_sync_n,
                 dut.i_riscv_core.PC_W,
                 dut.i_isram.u_imem.mem_array[0], dut.i_isram.u_imem.mem_array[1]);
        u_failure_reporter.report_failure(
          LAYER_FIRMWARE,
          "WATCHDOG_TIMEOUT",
          $sformatf("Test exceeded maximum allowed simulation cycles (%0d). Retired=%0d AXI=%0d APB=%0d FW_ATTEST=0x%08X",
                    max_watchdog_cycles, u_retire_mon.total_retired_instr,
                    axi_beats(), u_apb_mon.total_apb_trans, mb_activity),
          dut.i_riscv_core.PC_W
        );
        u_retire_mon.dump_recent_retires(10);
        u_lsu_mon.dump_recent_lsu(10);
        u_axi_mon.dump_recent_trans(10);
        u_apb_mon.dump_recent_trans(10);

        // ---- Stage 2 inversion ------------------------------------------
        // Stage 2's only correct outcome IS this timeout. Reaching it proves
        // the watchdog fired and blame reporting + monitor freezing worked.
        // We demand:
        //  1. Retired instruction count >= MIN_RETIRED_INSTR
        //  2. Exactly 1 failure was recorded, attributed to LAYER_FIRMWARE:WATCHDOG_TIMEOUT
        //  3. Monitor freeze buffers were successfully dumped
        //  4. Firmware attestation is present in mailbox
        //  5. Prior bus activity occurred (not dead at cycle 0)
        if (mb_test_id == STAGE2_TEST_ID) begin
          if (u_retire_mon.total_retired_instr < MIN_RETIRED_INSTR) begin
            $display("\n[STAGE2 FAIL] Watchdog fired but retired instruction count (%0d) < MIN (%0d)",
                     u_retire_mon.total_retired_instr, MIN_RETIRED_INSTR);
            $finish(1);
          end
          if (u_failure_reporter.n_find != 1) begin
            $display("\n[STAGE2 FAIL] Expected exactly 1 failure finding (LAYER_FIRMWARE watchdog), but found %0d",
                     u_failure_reporter.n_find);
            #500ns;
            $finish(1);
          end
          if (u_failure_reporter.failing_layer != LAYER_FIRMWARE ||
              u_failure_reporter.failing_check_id != "WATCHDOG_TIMEOUT") begin
            $display("\n[STAGE2 FAIL] Expected failure finding LAYER_FIRMWARE:WATCHDOG_TIMEOUT, got %s:%s",
                     layer_name(u_failure_reporter.failing_layer),
                     u_failure_reporter.failing_check_id);
            #500ns;
            $finish(1);
          end
          if (mb_activity == 32'h0) begin
            $display("\n[STAGE2 FAIL] Firmware attestation mailbox was empty (0x00000000)");
            #500ns;
            $finish(1);
          end
          if (u_axi_mon.total_axi_writes == 0 || u_apb_mon.total_apb_trans == 0) begin
            $display("\n[STAGE2 FAIL] Expected bus activity before watchdog spin, got AXI_WR=%0d APB=%0d",
                     u_axi_mon.total_axi_writes, u_apb_mon.total_apb_trans);
            #500ns;
            $finish(1);
          end

          $display("\n[STAGE2 PASS] Watchdog fired as designed at cycle %0d", sim_cycle_cnt);
          $display("  blame attribution : %s -> %s",
                   layer_name(u_failure_reporter.failing_layer),
                   u_failure_reporter.failing_check_id);
          $display("  freeze buffers    : dumped successfully (retire, lsu, axi, apb)");
          $display("  retired_instr     : %0d", u_retire_mon.total_retired_instr);
          $display("  axi writes/reads  : %0d / %0d",
                   u_axi_mon.total_axi_writes, u_axi_mon.total_axi_reads);
          $display("  apb transfers     : %0d", u_apb_mon.total_apb_trans);
          $display("  fw attestation    : 0x%08X", mb_activity);
          #500ns;
          $finish(0);
        end
        else begin
          $display("\n[FATAL TIMEOUT] Simulation exceeded watchdog limit (%0d cycles)!", max_watchdog_cycles);
          #500ns;
          $finish(2);
        end
      end

      // Mailbox & Checker Watcher
      begin
        forever begin
          @(posedge clk);
          if (hard_rst_n && soft_rst_n) begin
            // 1. Check Register Predictor
            if (reg_pred_err) begin
              $display("\n[FATAL REGISTER PREDICTOR MISMATCH] %s at addr 0x%08X (Exp: 0x%08X, Got: 0x%08X)",
                reg_pred_msg, reg_pred_addr, reg_pred_exp, reg_pred_got);
              u_failure_reporter.report_failure(
                LAYER_REG,
                "REG_PREDICTOR_MISMATCH",
                reg_pred_msg,
                dut.i_riscv_core.PC_W
              );
              u_retire_mon.dump_recent_retires(20);
              u_lsu_mon.dump_recent_lsu(30);
              u_axi_mon.dump_recent_trans(30);
              u_apb_mon.dump_recent_trans(30);
              #500ns;
              $finish(1);
            end

            // 2. Check Interrupt Predictor
            if (irq_pred_err) begin
              $display("\n[FATAL INTERRUPT PREDICTOR MISMATCH] %s (Exp ID: %0d, Got ID: %0d)",
                irq_pred_msg, irq_pred_exp, irq_pred_got);
              u_failure_reporter.report_failure(
                LAYER_IRQ,
                "IRQ_PREDICTOR_MISMATCH",
                irq_pred_msg,
                dut.i_riscv_core.PC_W
              );
              u_retire_mon.dump_recent_retires(20);
              u_lsu_mon.dump_recent_lsu(30);
              u_axi_mon.dump_recent_trans(30);
              u_apb_mon.dump_recent_trans(30);
              #500ns;
              $finish(1);
            end

            // 3. Mailbox Command Check + Anti-Vacuity Guard
            if (mb_cmd == CMD_PASS) begin
              // --- Stage 2 is the inverted case -----------------------------
              // Stage 2 exists to prove the watchdog fires. Its only correct
              // outcome is a timeout, so if its firmware ever reaches PASS the
              // watchdog is broken and the run must NOT be called green.
              if (mb_test_id == STAGE2_TEST_ID) begin
                fail_vacuous("STAGE2_UNEXPECTED_PASS",
                             "Stage 2 watchdog test reported PASS - the watchdog did not fire");
                #500ns;
                $finish(1);
              end

              // --- G1: instructions must have retired -----------------------
              if (u_retire_mon.total_retired_instr < MIN_RETIRED_INSTR) begin
                fail_vacuous("VACUOUS_ZERO_RETIRE",
                             $sformatf("Firmware reported PASS but only %0d instructions retired",
                                       u_retire_mon.total_retired_instr));
                #500ns;
                $finish(1);
              end

              // --- G2: the AXI-Lite fabric must have moved transactions -----
              if (axi_beats() < MIN_AXI_BEATS) begin
                fail_vacuous("VACUOUS_ZERO_AXI",
                             $sformatf("Firmware reported PASS but %0d AXI-Lite beats were observed",
                                       axi_beats()));
                #500ns;
                $finish(1);
              end

              // --- G3: a peripheral must have answered on APB --------------
              if (u_apb_mon.total_apb_trans < MIN_APB_TRANS) begin
                fail_vacuous("VACUOUS_ZERO_APB",
                             $sformatf("Firmware reported PASS but %0d APB transfers were observed",
                                       u_apb_mon.total_apb_trans));
                #500ns;
                $finish(1);
              end

              // --- G4: no checker may have fired --------------------------
              if (u_failure_reporter.n_find != 0) begin
                fail_vacuous("VACUOUS_FATAL_LATCHED",
                             $sformatf("Firmware reported PASS but %0d fatal checks had fired",
                                       u_failure_reporter.n_find));
                #500ns;
                $finish(1);
              end

              // --- G5: the firmware's own attestation must be non-zero -----
              if (mb_activity == 32'h0) begin
                fail_vacuous("VACUOUS_NO_FW_ATTESTATION",
                             "Firmware reported PASS without publishing any verified MMIO activity");
                #500ns;
                $finish(1);
              end

              // --- G6: the core's own retired counter must have moved ------
              if (dut.i_riscv_core.csr_file.minstret_r == 64'h0) begin
                fail_vacuous("VACUOUS_ZERO_MINSTRET",
                             "Firmware reported PASS but the core minstret counter never advanced");
                #500ns;
                $finish(1);
              end

              $display("\n[MAILBOX PASS] Test completed successfully");
              $display("  test id           : 0x%08X", mb_test_id);
              $display("  retired_instr     : %0d", u_retire_mon.total_retired_instr);
              $display("  minstret          : %0d", dut.i_riscv_core.csr_file.minstret_r);
              $display("  axi writes/reads  : %0d / %0d",
                       u_axi_mon.total_axi_writes, u_axi_mon.total_axi_reads);
              $display("  apb transfers     : %0d", u_apb_mon.total_apb_trans);
              $display("  lsu reads/writes  : %0d / %0d",
                       u_lsu_mon.total_reads, u_lsu_mon.total_writes);
              $display("  fw attestation    : 0x%08X (mmio_rd=%0d mmio_wr=%0d)",
                       mb_activity, mb_activity[15:0], mb_activity[31:16]);
              #500ns;
              $finish(0);
            end else if (mb_cmd == CMD_FAIL) begin
              $display("\n[MAILBOX FAIL] Test reported failure (ID: 0x%08X, Err: 0x%08X, line %0d, exp 0x%08X, got 0x%08X)",
                mb_test_id, mb_error_code, mb_arg0, mb_arg1, mb_arg2);
              u_failure_reporter.report_failure(
                LAYER_FIRMWARE,
                "FW_ASSERT_FAIL",
                $sformatf("Firmware assertion 0x%08X at source line %0d (expected 0x%08X, got 0x%08X)",
                          mb_error_code, mb_arg0, mb_arg1, mb_arg2),
                dut.i_riscv_core.PC_W
              );
              u_retire_mon.dump_recent_retires(20);
              u_lsu_mon.dump_recent_lsu(30);
              u_axi_mon.dump_recent_trans(30);
              u_apb_mon.dump_recent_trans(30);
              #500ns;
              $finish(1);
            end else if (mb_cmd == CMD_HALT) begin
              $display("\n[MAILBOX HALT] Firmware halted deliberately (ID: 0x%08X, arg0 %0d, arg1 0x%08X, arg2 0x%08X)",
                mb_test_id, mb_arg0, mb_arg1, mb_arg2);
              u_failure_reporter.report_failure(
                LAYER_FIRMWARE,
                "FW_HALT",
                "Firmware reached a deliberate halt tripwire - the test exceeded its own budget",
                dut.i_riscv_core.PC_W
              );
              #500ns;
              $finish(1);
            end
          end
        end
      end
    join_any
  end

endmodule
