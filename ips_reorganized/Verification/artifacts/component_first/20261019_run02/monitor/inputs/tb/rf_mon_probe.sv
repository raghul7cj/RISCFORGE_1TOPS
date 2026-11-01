// =============================================================================
// Module Name : rf_mon_probe.sv
// Description : Drop-in wiring module for the RISCFORGE SoC passive monitor layer.
//
//               Instantiate as `rf_mon_probe u_mon (...)` in soc_tb_top, AFTER
//               the DUT instance (`u_dut`). It owns:
//                 * the single shared timebase (rf_timebase_if)
//                 * all 7 sampling interfaces + the pin interface
//                 * the class environment, and forks it
//                 * the end-of-test post-mortem dump
//
//               Hierarchical probe points below are taken verbatim from the
//               working TBs in ../RTL_SOC/ (soc_regtest_tb.sv,
//               soc_montest_tb.sv, soc_i2c_regtest_tb.sv). If a hierarchical
//               name is elided by a Verilator/XSim elaboration order, add it to
//               `-sv` scope with `+define+RF_HIER_WEAK` and guard it.
//
//                                       AXI-Lite note
//                                       ------------
//               The SoC has NO flat awaddr/awvalid nets. The AXI-Lite signals
//               live in the packed structs `axi_req_t` / `axi_resp_t`. This
//               module flattens the CORE-side copy (dut.core_axi_req/resp, i.e.
//               the core <-> axi_lite_timeout_monitor boundary) onto the
//               interface. To watch the crossbar or the APB bridge instead,
//               repoint the g_axil_flatten generate at
//                 dut.xbar_slv_req[0] / dut.xbar_slv_resp[0]        (xbar input)
//                 dut.xbar_mst_req[2] / dut.xbar_mst_resp[2]        (APB bridge)
// =============================================================================

`timescale 1ns/1ps

`ifndef FETCH_MONITOR_SV
`include "monitors/fetch_monitor.sv"
`endif
`ifndef RETIRE_MONITOR_SV
`include "monitors/retire_monitor.sv"
`endif
`ifndef LSU_MONITOR_SV
`include "monitors/lsu_monitor.sv"
`endif
`ifndef AXI_LITE_MONITOR_SV
`include "monitors/axi_lite_monitor.sv"
`endif
`ifndef APB_MONITOR_SV
`include "monitors/apb_monitor.sv"
`endif
`ifndef IRQ_MONITOR_SV
`include "monitors/irq_monitor.sv"
`endif

module rf_mon_probe import tb_pkg::*; #(
  parameter int unsigned RING_DEPTH = 256,
  parameter int unsigned DUMP_N     = 24,
  parameter bit          RUN_MONITORS = 1'b1
) (
  input logic clk,
  input logic rst_n,

  // freeze, driven by failure_reporter.freeze_monitors
  input logic freeze,

  // ---- resolved external pin wires (tri-state nets owned by soc_tb_top) ----
  input logic uart_rx_wire,      // uart_sin_i
  input logic uart_tx_wire,      // uart_sout_o
  input logic i2c_scl_wire,      // pull-up + DUT open-drain, resolved
  input logic i2c_sda_wire,
  input logic spi_sclk_wire,
  input logic spi_csn0_wire,     // ACTIVE LOW
  input logic spi_csn1_wire,     // ACTIVE LOW
  input logic spi_mosi_wire,     // spi_sdo0_o
  input logic spi_miso_wire,     // spi_sdi1_i
  input logic [31:0] gpio_in_wire,
  input logic [31:0] gpio_out_wire,
  input logic [31:0] gpio_oe_wire
);

  // ===========================================================================
  // 0. THE single shared cycle counter
  // ===========================================================================
  rf_timebase_if #(.CYCLE_W(64)) tb_if (.clk(clk), .rst_n(rst_n));

  // ===========================================================================
  // 1. Interfaces
  // ===========================================================================
  rf_fetch_if  fetch_if  (.clk(clk), .rst_n(rst_n));
  rf_retire_if retire_if (.clk(clk), .rst_n(rst_n));
  rf_lsu_if    lsu_if    (.clk(clk), .rst_n(rst_n));
  rf_axil_if   axil_if   (.clk(clk), .rst_n(rst_n));
  rf_apb_if    apb_if    (.clk(clk), .rst_n(rst_n));
  rf_irq_if    irq_if    (.clk(clk), .rst_n(rst_n));
  rf_pin_if    pin_if    (.clk(clk), .rst_n(rst_n));

  // ===========================================================================
  // 2. CORE FETCH  (dut.i_riscv_core.*)
  // ===========================================================================
  // Fetch.PCF / Fetch.PCPlus4F / Fetch.PC_next / Fetch.InstrF
  assign fetch_if.pc        = u_dut.i_riscv_core.Fetch.PCF;
  assign fetch_if.pc_plus4  = u_dut.i_riscv_core.Fetch.PCPlus4F;
  assign fetch_if.pc_next   = u_dut.i_riscv_core.Fetch.PC_next;
  assign fetch_if.instr     = u_dut.i_riscv_core.Fetch.InstrF;
  // imem_sram_en is the fetch request; there is no if_valid/imem_ready on this
  // core. Fetch.imem_stall is the IF-side backpressure.
  assign fetch_if.fetch_en  = u_dut.i_riscv_core.imem_sram_en;
  assign fetch_if.stall_f   = u_dut.i_riscv_core.Fetch.imem_stall |
                              u_dut.i_riscv_core.StallF;
  assign fetch_if.exc_valid = u_dut.i_riscv_core.Fetch.exc_valid_F;
  assign fetch_if.exc_cause = u_dut.i_riscv_core.Fetch.exc_cause_F;
  assign fetch_if.exc_tval  = u_dut.i_riscv_core.Fetch.exc_tval_F;

  // ===========================================================================
  // 3. CORE RETIRE  (architectural commit; there is no irq_ack net)
  // ===========================================================================
  assign retire_if.valid_w           = u_dut.i_riscv_core.valid_W;
  assign retire_if.wb_commit         = u_dut.i_riscv_core.valid_W & ~u_dut.i_riscv_core.exc_valid_W & ~u_dut.i_riscv_core.mret_commit;
  assign retire_if.pc_w              = u_dut.i_riscv_core.PC_W;
  // instr is deliberately left 0 - RISCFORGE does not export a retired
  // instruction word. rf_retire_monitor back-fills it from the fetch monitor's
  // PC -> instruction shadow.
  assign retire_if.instr             = 32'h0;
  assign retire_if.rd_addr           = u_dut.i_riscv_core.RDW;
  assign retire_if.rd_wdata          = u_dut.i_riscv_core.ResultW;
  assign retire_if.reg_we            = u_dut.i_riscv_core.RegWriteW_gated;

  assign retire_if.trap              = u_dut.i_riscv_core.trap_commit_valid;
  assign retire_if.trap_is_interrupt = u_dut.i_riscv_core.trap_commit_is_interrupt;
  assign retire_if.trap_cause        = u_dut.i_riscv_core.trap_commit_cause;
  assign retire_if.trap_pc           = u_dut.i_riscv_core.trap_commit_pc;
  assign retire_if.is_mret           = u_dut.i_riscv_core.is_mret_W |
                                      u_dut.i_riscv_core.mret_commit;

  assign retire_if.csr_we            = u_dut.i_riscv_core.csr_write_en_W;
  assign retire_if.csr_addr          = u_dut.i_riscv_core.csr_addr_W;
  assign retire_if.csr_wdata         = u_dut.i_riscv_core.new_csr_W;

  assign retire_if.exc_valid         = u_dut.i_riscv_core.exc_valid_W;
  assign retire_if.exc_cause         = u_dut.i_riscv_core.exc_cause_W;
  assign retire_if.exc_tval          = u_dut.i_riscv_core.exc_tval_W;
  assign retire_if.exc_pc            = u_dut.i_riscv_core.exc_pc_W;

  // ===========================================================================
  // 4. LSU  (memory_cycle.v memory port)
  // ===========================================================================
  assign lsu_if.valid_m = u_dut.i_riscv_core.valid_M;
  assign lsu_if.pc_m    = u_dut.i_riscv_core.PC_M;
  assign lsu_if.lsunit  = u_dut.i_riscv_core.lsunitM;
  assign lsu_if.req     = u_dut.i_riscv_core.lsu_mem_req;
  assign lsu_if.we      = u_dut.i_riscv_core.lsu_mem_we;
  assign lsu_if.addr    = u_dut.i_riscv_core.lsu_mem_addr;
  assign lsu_if.wdata   = u_dut.i_riscv_core.lsu_mem_wdata;
  assign lsu_if.be      = u_dut.i_riscv_core.lsu_mem_be;
  assign lsu_if.rdata   = u_dut.i_riscv_core.lsu_mem_rdata;
  assign lsu_if.stall   = u_dut.i_riscv_core.lsu_mem_stall;
  assign lsu_if.err     = u_dut.i_riscv_core.lsu_mem_err;

  // ===========================================================================
  // 5. AXI-LITE  (flatten the packed axi_req_t / axi_resp_t structs)
  // ===========================================================================
  // master side: core_axi_req {aw, aw_valid, w, w_valid, b_ready, ar, ar_valid, r_ready}
  assign axil_if.awaddr  = u_dut.core_axi_req.aw.addr;
  assign axil_if.awprot  = u_dut.core_axi_req.aw.prot;
  assign axil_if.awvalid = u_dut.core_axi_req.aw_valid;
  assign axil_if.wdata   = u_dut.core_axi_req.w.data;
  assign axil_if.wstrb   = u_dut.core_axi_req.w.strb;
  assign axil_if.wvalid  = u_dut.core_axi_req.w_valid;
  assign axil_if.bready  = u_dut.core_axi_req.b_ready;
  assign axil_if.araddr  = u_dut.core_axi_req.ar.addr;
  assign axil_if.arprot  = u_dut.core_axi_req.ar.prot;
  assign axil_if.arvalid = u_dut.core_axi_req.ar_valid;
  assign axil_if.rready  = u_dut.core_axi_req.r_ready;

  // slave side: core_axi_resp {aw_ready, w_ready, b, b_valid, ar_ready, r, r_valid}
  assign axil_if.awready = u_dut.core_axi_resp.aw_ready;
  assign axil_if.wready  = u_dut.core_axi_resp.w_ready;
  assign axil_if.bresp   = u_dut.core_axi_resp.b.resp;
  assign axil_if.bvalid  = u_dut.core_axi_resp.b_valid;
  assign axil_if.arready = u_dut.core_axi_resp.ar_ready;
  assign axil_if.rdata   = u_dut.core_axi_resp.r.data;
  assign axil_if.rresp   = u_dut.core_axi_resp.r.resp;
  assign axil_if.rvalid  = u_dut.core_axi_resp.r_valid;

  // ===========================================================================
  // 6. APB  (6 slots, bridge side: dut.apb_req[g] / dut.apb_resp[g])
  //    PRDATA rides in one flat packed bus because XSim 2022.2 rejects unpacked
  //    arrays inside interfaces and inside clocking blocks.
  // ===========================================================================
  genvar g_apb;
  generate
    for (g_apb = 0; g_apb < 6; g_apb++) begin : g_apb_flatten
      assign apb_if.psel   [g_apb]           = u_dut.apb_req [g_apb].psel;
      assign apb_if.pready [g_apb]           = u_dut.apb_resp[g_apb].pready;
      assign apb_if.pslverr[g_apb]           = u_dut.apb_resp[g_apb].pslverr;
      assign apb_if.prdata_flat[g_apb*32 +: 32] = u_dut.apb_resp[g_apb].prdata;
    end
  endgenerate

  // The bridge defines request payload fields only on the selected slot.
  // Flatten each slot independently; apb_req[0] is not a valid source for a
  // transaction selected on APB[1..5].
  generate
    for (g_apb = 0; g_apb < 6; g_apb++) begin : g_apb_payload_flatten
      assign apb_if.paddr_flat[g_apb*32 +: 32] = u_dut.apb_req[g_apb].paddr;
      assign apb_if.pprot_flat[g_apb*3 +: 3]   = u_dut.apb_req[g_apb].pprot;
      assign apb_if.penable[g_apb]             = u_dut.apb_req[g_apb].penable;
      assign apb_if.pwrite[g_apb]              = u_dut.apb_req[g_apb].pwrite;
      assign apb_if.pwdata_flat[g_apb*32 +: 32]= u_dut.apb_req[g_apb].pwdata;
      assign apb_if.pstrb_flat[g_apb*4 +: 4]   = u_dut.apb_req[g_apb].pstrb;
    end
  endgenerate

  always_comb begin
    apb_if.active_paddr  = '0;
    apb_if.active_pwdata = '0;
    apb_if.active_prdata = '0;
    apb_if.active_pstrb  = '0;
    apb_if.active_pwrite = 1'b0;
    for (int active_slot = 0; active_slot < 6; active_slot++) begin
      if (apb_if.psel[active_slot]) begin
        apb_if.active_paddr  = apb_if.paddr_flat[active_slot*32 +: 32];
        apb_if.active_pwdata = apb_if.pwdata_flat[active_slot*32 +: 32];
        apb_if.active_prdata = apb_if.prdata_flat[active_slot*32 +: 32];
        apb_if.active_pstrb  = apb_if.pstrb_flat[active_slot*4 +: 4];
        apb_if.active_pwrite = apb_if.pwrite[active_slot];
      end
    end
  end

  // ===========================================================================
  // 7. INTERRUPTS
  // ===========================================================================
  // raw peripheral sources
  assign irq_if.gpio_irq      = u_dut.gpio_global_interrupt_o;
  assign irq_if.gpio_pin_irq  = u_dut.gpio_pin_level_interrupts_o;
  assign irq_if.i2c_irq       = u_dut.i2c_interrupt_o;
  assign irq_if.spi_irq       = u_dut.spi_events_o;
  assign irq_if.uart_irq      = u_dut.uart_int_o;
  assign irq_if.timer0_irq    = u_dut.timer0_irq_o;
  assign irq_if.timer1_irq    = u_dut.timer1_irq_o;

  // gateway (riscv_core/rtl/irq_gateway.v : pend_o[5:0])
  assign irq_if.gateway_pend  = u_dut.i_riscv_core.u_irq_gateway.pend_o;

  // core inbound + CSR view
  assign irq_if.fast_irq      = u_dut.i_riscv_core.fast_irq_i;
  assign irq_if.timer_irq     = u_dut.i_riscv_core.timer_irq_i;
  assign irq_if.mip           = u_dut.i_riscv_core.csr_mip_sb;
  assign irq_if.mie           = u_dut.i_riscv_core.csr_mie_sb;
  assign irq_if.mintprio      = u_dut.i_riscv_core.csr_mintprio_sb;
  assign irq_if.mstatus_mie   = u_dut.i_riscv_core.csr_mstatus_mie_sb;

  // arbiter (riscv_core/rtl/irq_arbiter.v)
  assign irq_if.irq_valid     = u_dut.i_riscv_core.irq_valid;
  assign irq_if.irq_pending   = u_dut.i_riscv_core.irq_pending;
  assign irq_if.irq_cause_enc = u_dut.i_riscv_core.irq_cause_enc;
  assign irq_if.irq_id        = u_dut.i_riscv_core.irq_id;
  assign irq_if.irq_class     = u_dut.i_riscv_core.u_irq_arbiter.irq_class_o;

  // acknowledgement point
  assign irq_if.trap_is_interrupt = u_dut.i_riscv_core.trap_commit_is_interrupt;
  assign irq_if.trap_cause        = u_dut.i_riscv_core.trap_commit_cause;
  assign irq_if.trap_pc           = u_dut.i_riscv_core.trap_commit_pc;
  assign irq_if.mret_commit       = u_dut.i_riscv_core.mret_commit;

`ifdef RF_FULL_SOC
  assign irq_if.gateway_pend_q   = u_dut.i_riscv_core.u_irq_gateway.pend_q;
  assign irq_if.rr_ptr_c1        = u_dut.i_riscv_core.u_irq_arbiter.rr_ptr_c1;
  assign irq_if.rr_ptr_c0        = u_dut.i_riscv_core.u_irq_arbiter.rr_ptr_c0;
  assign irq_if.nest_depth       = u_dut.i_riscv_core.csr_file.nest_depth;
  assign irq_if.cur_class        = u_dut.i_riscv_core.csr_file.cur_class_r;
  assign irq_if.mepc_stack_flat  = {u_dut.i_riscv_core.csr_file.mepc_stack[1], u_dut.i_riscv_core.csr_file.mepc_stack[0]};
  assign irq_if.mcause_stack_flat= {u_dut.i_riscv_core.csr_file.mcause_stack[1], u_dut.i_riscv_core.csr_file.mcause_stack[0]};
`else
  assign irq_if.gateway_pend_q   = 6'b0;
  assign irq_if.rr_ptr_c1        = 1'b0;
  assign irq_if.rr_ptr_c0        = 1'b0;
  assign irq_if.nest_depth       = 2'b0;
  assign irq_if.cur_class        = 2'b0;
  assign irq_if.mepc_stack_flat  = 64'b0;
  assign irq_if.mcause_stack_flat= 64'b0;
`endif

  // ===========================================================================
  // 8. EXTERNAL PINS
  // ===========================================================================
  assign pin_if.uart_rx  = uart_rx_wire;      // uart_sin_i
  assign pin_if.uart_tx  = uart_tx_wire;      // uart_sout_o
  assign pin_if.uart_irq = u_dut.uart_int_o;

  // I2C: resolved line + raw open-drain drivers. The tri-state wires live in
  // soc_tb_top: pullup(wire); wire = (oen && !out) ? 1'b0 : 1'bz;
  assign pin_if.scl      = i2c_scl_wire;
  assign pin_if.sda      = i2c_sda_wire;
  assign pin_if.scl_i    = u_dut.i2c_scl_i;
  assign pin_if.sda_i    = u_dut.i2c_sda_i;
  assign pin_if.scl_o    = u_dut.i2c_scl_o;
  assign pin_if.scl_oen  = u_dut.i2c_scl_oen_o;
  assign pin_if.sda_o    = u_dut.i2c_sda_o;
  assign pin_if.sda_oen  = u_dut.i2c_sda_oen_o;
  assign pin_if.i2c_irq  = u_dut.i2c_interrupt_o;

  // SPI: CSn are ACTIVE LOW
  assign pin_if.sclk       = spi_sclk_wire;
  assign pin_if.csn0       = spi_csn0_wire;
  assign pin_if.csn1       = spi_csn1_wire;
  assign pin_if.mosi       = spi_mosi_wire;
  assign pin_if.miso       = spi_miso_wire;
  assign pin_if.spi_events = u_dut.spi_events_o;

  // GPIO
  assign pin_if.gpio_in         = gpio_in_wire;
  assign pin_if.gpio_out        = gpio_out_wire;
  assign pin_if.gpio_oe         = gpio_oe_wire;
  assign pin_if.gpio_in_sync    = u_dut.gpio_in_sync_o;
  assign pin_if.gpio_pin_irq    = u_dut.gpio_pin_level_interrupts_o;
  assign pin_if.gpio_global_irq = u_dut.gpio_global_interrupt_o;

  // Edge history used by the class monitors to compute transitions. Kept here
  // so the monitors stay stateless with respect to the interface.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pin_if.scl_d    <= 1'b1;
      pin_if.sda_d    <= 1'b1;
      pin_if.sclk_d   <= 1'b0;
      pin_if.mosi_d   <= 1'b0;
      pin_if.miso_d   <= 1'b0;
      pin_if.uart_tx_d<= 1'b1;
      pin_if.uart_rx_d<= 1'b1;
      pin_if.gpio_in_d<= '0;
    end else begin
      pin_if.scl_d    <= pin_if.scl;
      pin_if.sda_d    <= pin_if.sda;
      pin_if.sclk_d   <= pin_if.sclk;
      pin_if.mosi_d   <= pin_if.mosi;
      pin_if.miso_d   <= pin_if.miso;
      pin_if.uart_tx_d<= pin_if.uart_tx;
      pin_if.uart_rx_d<= pin_if.uart_rx;
      pin_if.gpio_in_d<= pin_if.gpio_in;
    end
  end

  // ===========================================================================
  // 9. ENVIRONMENT
  // ===========================================================================
  rf_monitor_env env;
  rf_if_ports    ports;

  initial begin
    ports = new();
    ports.tb     = tb_if;
    ports.fetch  = fetch_if;
    ports.retire = retire_if;
    ports.lsu    = lsu_if;
    ports.axil   = axil_if;
    ports.apb    = apb_if;
    ports.irq    = irq_if;
    ports.pin    = pin_if;

    env = new();
    env.dump_depth = DUMP_N;
    env.build(ports);
    if (RUN_MONITORS) env.start();
  end

  // ===========================================================================
  // 10. SHARED CYCLE COUNTER FAN-OUT (module scope on purpose)
  // ===========================================================================
  // One free-running counter (rf_timebase_if) is replicated onto every monitor
  // interface every clock, so all monitors sample the SAME preponed value at the
  // SAME edge. That invariant is what makes the post-mortem windows line up
  // column-for-column and what makes cross-monitor joins (LSU -> AXI -> APB ->
  // RETIRE) exact rather than approximate.
  //
  // This must be MODULE scope. XSim 2022.2 silently drops writes to an
  // interface variable performed through a virtual interface handle from
  // inside a class, which would leave every transaction stamped with cycle 0.
  // Freeze broadcast is continuous to guarantee cycle-0 freeze visibility in Preponed sampling
  assign fetch_if.freeze  = freeze;
  assign retire_if.freeze = freeze;
  assign lsu_if.freeze    = freeze;
  assign axil_if.freeze   = freeze;
  assign apb_if.freeze    = freeze;
  assign irq_if.freeze    = freeze;
  assign pin_if.freeze    = freeze;

  always_ff @(posedge clk or negedge rst_n) begin : fanout_timebase
    if (!rst_n) begin
      fetch_if .tb_cycle     <= '0;  fetch_if .tb_rel_cycle <= '0;
      retire_if.tb_cycle     <= '0;  retire_if.tb_rel_cycle <= '0;
      lsu_if   .tb_cycle     <= '0;  lsu_if   .tb_rel_cycle <= '0;
      axil_if  .tb_cycle     <= '0;  axil_if  .tb_rel_cycle <= '0;
      apb_if   .tb_cycle     <= '0;  apb_if   .tb_rel_cycle <= '0;
      irq_if   .tb_cycle     <= '0;  irq_if   .tb_rel_cycle <= '0;
      pin_if   .tb_cycle     <= '0;  pin_if   .tb_rel_cycle <= '0;
    end else begin
      fetch_if .tb_cycle     <= tb_if.cycle;
      fetch_if .tb_rel_cycle <= tb_if.rel_cycle;
      retire_if.tb_cycle     <= tb_if.cycle;
      retire_if.tb_rel_cycle <= tb_if.rel_cycle;
      lsu_if   .tb_cycle     <= tb_if.cycle;
      lsu_if   .tb_rel_cycle <= tb_if.rel_cycle;
      axil_if  .tb_cycle     <= tb_if.cycle;
      axil_if  .tb_rel_cycle <= tb_if.rel_cycle;
      apb_if   .tb_cycle     <= tb_if.cycle;
      apb_if   .tb_rel_cycle <= tb_if.rel_cycle;
      irq_if   .tb_cycle     <= tb_if.cycle;
      irq_if   .tb_rel_cycle <= tb_if.rel_cycle;
      pin_if   .tb_cycle     <= tb_if.cycle;
      pin_if   .tb_rel_cycle <= tb_if.rel_cycle;
    end
  end

  // First-fatal latch: failure_reporter drives `freeze`; mirror it into the
  // trace db so the scoreboard, coverage and the ring dumps all stop together.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if (env != null) env.db.frozen <= 1'b0;
    end else begin
      if (env != null) env.db.frozen <= freeze;
    end
  end

  // ===========================================================================
  // 11. PASSIVE PROTOCOL & PIPELINE MODULE MONITORS (64-ENTRY RING BUFFERS)
  // ===========================================================================
  fetch_monitor #(.RING_BUFFER_DEPTH(64)) u_fetch_mon (
    .clk         (clk),
    .rst_n       (rst_n),
    .freeze      (freeze),
    .pc_f        (fetch_if.pc),
    .instr_f     (fetch_if.instr),
    .imem_en     (fetch_if.fetch_en),
    .stall_f     (fetch_if.stall_f),
    .pc_next     (fetch_if.pc_next),
    .exc_valid_f (fetch_if.exc_valid),
    .exc_cause_f (fetch_if.exc_cause),
    .exc_tval_f  (fetch_if.exc_tval)
  );

  retire_monitor #(.RING_BUFFER_DEPTH(64)) u_retire_mon (
    .clk               (clk),
    .rst_n             (rst_n),
    .freeze            (freeze),
    .valid_w           (retire_if.valid_w),
    .exc_valid_w       (retire_if.exc_valid),
    .pc_w              (retire_if.pc_w),
    .instr_w           (retire_if.instr),
    .rd_addr_w         (retire_if.rd_addr),
    .rd_wdata_w        (retire_if.rd_wdata),
    .reg_we_w          (retire_if.reg_we),
    .trap_w            (retire_if.trap),
    .trap_is_interrupt (retire_if.trap_is_interrupt),
    .trap_cause        (retire_if.trap_cause),
    .is_mret_w         (retire_if.is_mret),
    .csr_we_w          (retire_if.csr_we),
    .csr_addr_w        (retire_if.csr_addr),
    .csr_wdata_w       (retire_if.csr_wdata)
  );

  lsu_monitor #(.RING_BUFFER_DEPTH(64)) u_lsu_mon (
    .clk       (clk),
    .rst_n     (rst_n),
    .freeze    (freeze),
    .lsu_req   (lsu_if.req),
    .lsu_we    (lsu_if.we),
    .lsu_addr  (lsu_if.addr),
    .lsu_wdata (lsu_if.wdata),
    .lsu_be    (lsu_if.be),
    .lsu_rdata (lsu_if.rdata),
    .lsu_stall (lsu_if.stall),
    .lsu_err   (lsu_if.err),
    .pc_m      (lsu_if.pc_m),
    .lsunit_m  (lsu_if.lsunit),
    .valid_m   (lsu_if.valid_m)
  );

  axi_lite_monitor #(.RING_BUFFER_DEPTH(64)) u_axi_mon (
    .clk     (clk),
    .rst_n   (rst_n),
    .freeze  (freeze),
    .awaddr  (axil_if.awaddr),
    .awprot  (axil_if.awprot),
    .awvalid (axil_if.awvalid),
    .awready (axil_if.awready),
    .wdata   (axil_if.wdata),
    .wstrb   (axil_if.wstrb),
    .wvalid  (axil_if.wvalid),
    .wready  (axil_if.wready),
    .bresp   (axil_if.bresp),
    .bvalid  (axil_if.bvalid),
    .bready  (axil_if.bready),
    .araddr  (axil_if.araddr),
    .arprot  (axil_if.arprot),
    .arvalid (axil_if.arvalid),
    .arready (axil_if.arready),
    .rdata   (axil_if.rdata),
    .rresp   (axil_if.rresp),
    .rvalid  (axil_if.rvalid),
    .rready  (axil_if.rready)
  );

  apb_monitor #(.NUM_SLOTS(6), .RING_BUFFER_DEPTH(64)) u_apb_mon (
    .clk         (clk),
    .rst_n       (rst_n),
    .freeze      (freeze),
    .paddr_flat  (apb_if.paddr_flat),
    .psel        (apb_if.psel),
    .penable     (apb_if.penable),
    .pwrite      (apb_if.pwrite),
    .pwdata_flat (apb_if.pwdata_flat),
    .pstrb_flat  (apb_if.pstrb_flat),
    .pready      (apb_if.pready),
    .prdata_flat (apb_if.prdata_flat),
    .pslverr     (apb_if.pslverr)
  );

  irq_monitor #(.RING_BUFFER_DEPTH(64)) u_irq_mon (
    .clk                (clk),
    .rst_n              (rst_n),
    .freeze             (freeze),
    .gpio_irq           (irq_if.gpio_irq),
    .i2c_irq            (irq_if.i2c_irq),
    .spi_irq            (irq_if.spi_irq),
    .uart_irq           (irq_if.uart_irq),
    .timer0_irq         (irq_if.timer0_irq),
    .timer1_irq         (irq_if.timer1_irq),
    .gateway_pend_q     (irq_if.gateway_pend_q),
    .gateway_pend_o     (irq_if.gateway_pend),
    .fast_irq_i         (irq_if.fast_irq),
    .timer_irq_i        (irq_if.timer_irq),
    .irq_pending        (irq_if.irq_pending),
    .irq_id             (irq_if.irq_cause_enc),
    .irq_class          (irq_if.irq_class),
    .rr_ptr_c1          (irq_if.rr_ptr_c1),
    .rr_ptr_c0          (irq_if.rr_ptr_c0),
    .nest_depth         (irq_if.nest_depth),
    .cur_class          (irq_if.cur_class),
    .trap_commit_valid  (irq_if.trap_is_interrupt),
    .trap_is_interrupt  (irq_if.trap_is_interrupt),
    .trap_commit_cause  (irq_if.trap_cause),
    .trap_commit_pc     (irq_if.trap_pc),
    .mret_commit        (irq_if.mret_commit)
  );

  final begin
    if (env != null)
      env.write_postmortem("monitor_postmortem.txt", DUMP_N);
  end

endmodule : rf_mon_probe
