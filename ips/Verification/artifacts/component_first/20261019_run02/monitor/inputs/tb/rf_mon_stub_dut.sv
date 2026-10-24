// =============================================================================
// Module Name : rf_mon_stub_dut.sv
// Description : Structural stub of `riscforge_soc_subsystem` + its RV32IM core,
//               reproducing EXACTLY the hierarchical probe points that
//               rf_mon_probe.sv references. Lets the whole monitor layer be
//               elaborated, linked and regression-tested without the real SoC.
//
//               Deterministic stimulus so the ring buffers are NON-VACUOUS:
//                 cyc  20-60 : MMIO write  UART   0x4000_2000 -> APB slot 2
//                 cyc  80-120: MMIO read   TIMER0 0x4000_1000 -> APB slot 1
//                 cyc 150-190: UART TX byte on the pin
//                 cyc 240-280: UART IRQ  -> gateway pend -> arbiter pending
//                 cyc    260 : trap_commit_is_interrupt   (the irq_ack point)
//                 cyc    300 : mret_commit
// =============================================================================

`timescale 1ns/1ps

module rf_mon_stub_fetch;
  logic [31:0] PCF, PCPlus4F, PC_next, InstrF, exc_tval_F;
  logic [5:0]  exc_cause_F;
  logic        imem_stall, exc_valid_F;
endmodule

module rf_mon_stub_arbiter;
  logic [1:0] irq_class_o;
endmodule

module rf_mon_stub_gateway;
  logic [5:0] pend_o;
endmodule

module rf_mon_stub_core;

  rf_mon_stub_fetch    Fetch();
  rf_mon_stub_arbiter  u_irq_arbiter();
  rf_mon_stub_gateway  u_irq_gateway();

  logic        imem_sram_en, StallF;

  logic        valid_M;
  logic [31:0] PC_M;
  logic [4:0]  lsunitM;
  logic        lsu_mem_req, lsu_mem_we, lsu_mem_stall, lsu_mem_err;
  logic [31:0] lsu_mem_addr, lsu_mem_wdata, lsu_mem_rdata;
  logic [3:0]  lsu_mem_be;

  logic        valid_W, wb_commit, RegWriteW_gated;
  logic [31:0] PC_W, ResultW;
  logic [4:0]  RDW;
  logic        trap_commit_valid, trap_commit_is_interrupt, mret_commit, is_mret_W;
  logic [30:0] trap_commit_cause;
  logic [31:0] trap_commit_pc;
  logic        csr_write_en_W;
  logic [11:0] csr_addr_W;
  logic [31:0] new_csr_W;
  logic        exc_valid_W;
  logic [5:0]  exc_cause_W;
  logic [31:0] exc_tval_W, exc_pc_W;

  logic [15:0] fast_irq_i;
  logic        timer_irq_i;
  logic [31:0] csr_mip_sb, csr_mie_sb, csr_mintprio_sb;
  logic        csr_mstatus_mie_sb;
  logic        irq_valid, irq_pending;
  logic [4:0]  irq_cause_enc;
  logic [30:0] irq_id;
endmodule

module rf_mon_stub_dut import tb_pkg::*; (input logic clk);

  // ---- AXI-Lite, packed exactly as axi_lite_to_apb declares them ----
  typedef struct packed { logic [31:0] addr; logic [2:0] prot; } rf_aw_chan_t;
  typedef struct packed { logic [31:0] data; logic [3:0] strb; } rf_w_chan_t;
  typedef struct packed { logic [1:0]  resp; }                    rf_b_chan_t;
  typedef struct packed { logic [31:0] addr; logic [2:0] prot; } rf_ar_chan_t;
  typedef struct packed { logic [31:0] data; logic [1:0] resp; } rf_r_chan_t;

  typedef struct packed {
    rf_aw_chan_t aw; logic aw_valid;
    rf_w_chan_t  w;  logic w_valid;
                logic b_ready;
    rf_ar_chan_t ar; logic ar_valid;
                logic r_ready;
  } rf_axi_req_t;

  typedef struct packed {
    logic aw_ready, w_ready;
    rf_b_chan_t b; logic b_valid;
    logic ar_ready;
    rf_r_chan_t r; logic r_valid;
  } rf_axi_resp_t;

  // ---- APB ----
  typedef struct packed {
    logic [31:0] paddr;  logic [2:0] pprot;
    logic psel, penable, pwrite;
    logic [31:0] pwdata; logic [3:0] pstrb;
  } rf_apb_req_t;

  typedef struct packed {
    logic pready; logic [31:0] prdata; logic pslverr;
  } rf_apb_resp_t;

  rf_axi_req_t  core_axi_req;
  rf_axi_resp_t core_axi_resp;
  rf_apb_req_t  apb_req  [6];
  rf_apb_resp_t apb_resp [6];

  rf_mon_stub_core i_riscv_core();

  logic        gpio_global_interrupt_o, i2c_interrupt_o, uart_int_o;
  logic [1:0]  spi_events_o;
  logic [3:0]  timer0_irq_o, timer1_irq_o;
  logic [31:0] gpio_in_sync_o, gpio_pin_level_interrupts_o;
  logic        i2c_scl_i, i2c_sda_i, i2c_scl_o, i2c_scl_oen_o;
  logic        i2c_sda_o, i2c_sda_oen_o;
  logic        spi_sdi1_i;

  int unsigned cyc = 0;

  // Fabric-wide common APB controls (driven onto every apb_req[g].* like
  // axi_lite_to_apb does).
  logic        apb_penable, apb_wr;
  logic [31:0] apb_addr, apb_wdata;
  logic [3:0]  apb_strb;

  // UART TX pin waveform: 8N1 at 16 clk-cycles per bit -> 'A' (0x41)
  logic        uart_tx   = 1'b1;
  logic [15:0] uart_bits = 16'h03F;   // stop(1) + 8 data LSB-first + start(0)

  always_ff @(posedge clk) begin

    cyc <= cyc + 1;

    // ================= fetch / retire =================
    i_riscv_core.imem_sram_en         <= (cyc >= 4) && (cyc < 400);
    i_riscv_core.StallF               <= 1'b0;
    i_riscv_core.Fetch.PCF            <= 32'h0000_0000 + (cyc[31:0] * 4);
    i_riscv_core.Fetch.PCPlus4F       <= 32'h0000_0004 + (cyc[31:0] * 4);
    i_riscv_core.Fetch.PC_next        <= ((cyc % 8) == 0)
                                          ? (32'h0000_0000 + (cyc[31:0] * 4) + 32'h40)
                                          : (32'h0000_0004 + (cyc[31:0] * 4));
    i_riscv_core.Fetch.InstrF         <= 32'h0010_0093;   // addi x1, x0, 1
    i_riscv_core.Fetch.imem_stall     <= 1'b0;
    i_riscv_core.Fetch.exc_valid_F    <= 1'b0;
    i_riscv_core.Fetch.exc_cause_F    <= 6'd0;
    i_riscv_core.Fetch.exc_tval_F     <= 32'h0;

    i_riscv_core.valid_W              <= (cyc >= 8) && (cyc < 420);
    i_riscv_core.wb_commit            <= (cyc >= 8) && (cyc < 420);
    i_riscv_core.PC_W                 <= 32'h0000_0100;
    i_riscv_core.RDW                  <= 5'd1;
    i_riscv_core.ResultW              <= 32'h0000_0001;
    i_riscv_core.RegWriteW_gated      <= 1'b1;
    i_riscv_core.is_mret_W            <= 1'b0;
    i_riscv_core.mret_commit          <= (cyc == 320);
    i_riscv_core.csr_write_en_W       <= 1'b0;
    i_riscv_core.csr_addr_W           <= 12'd0;
    i_riscv_core.new_csr_W            <= 32'h0;
    i_riscv_core.exc_valid_W          <= 1'b0;
    i_riscv_core.exc_cause_W          <= 6'd0;
    i_riscv_core.exc_tval_W           <= 32'h0;
    i_riscv_core.exc_pc_W             <= 32'h0;

    // ================= LSU + AXI-Lite + APB : UART write =================
    // AXI-Lite beats and the LSU request are single-cycle pulses: every pulse is
    // one transfer, which is how axi_lite_sram_if / axi_lite_to_apb behave.
    i_riscv_core.valid_M       <= (cyc == 25) || (cyc == 32);
    i_riscv_core.PC_M          <= 32'h0000_0100;
    i_riscv_core.lsunitM       <= 5'b11000;             // store word
    i_riscv_core.lsu_mem_we    <= 1'b1;
    i_riscv_core.lsu_mem_addr  <= 32'h4000_2000;        // APB_UART
    i_riscv_core.lsu_mem_wdata <= 32'h0000_0055;
    i_riscv_core.lsu_mem_be    <= 4'hF;
    i_riscv_core.lsu_mem_req   <= (cyc == 25) || (cyc == 32);
    i_riscv_core.lsu_mem_stall <= 1'b0;
    i_riscv_core.lsu_mem_err   <= 1'b0;
    i_riscv_core.lsu_mem_rdata <= 32'h0;

    core_axi_req.aw.addr   <= 32'h4000_2000;
    core_axi_req.aw.prot   <= 3'b000;
    core_axi_req.aw_valid  <= (cyc == 25) || (cyc == 32);
    core_axi_req.w.data    <= 32'h0000_0055;
    core_axi_req.w.strb    <= 4'hF;
    core_axi_req.w_valid   <= (cyc == 26) || (cyc == 33);   // W skewed vs AW
    core_axi_req.b_ready   <= 1'b1;
    core_axi_resp.aw_ready <= (cyc == 25) || (cyc == 32);
    core_axi_resp.w_ready  <= (cyc == 26) || (cyc == 33);
    core_axi_resp.b_valid  <= (cyc == 30) || (cyc == 37);
    core_axi_resp.b.resp   <= AXI_RESP_OKAY;

    // ================= LSU + AXI-Lite + APB : TIMER0 read =================
    core_axi_req.ar.addr   <= 32'h4000_1000;
    core_axi_req.ar_valid  <= (cyc == 85) || (cyc == 92);
    core_axi_req.r_ready   <= 1'b1;
    core_axi_resp.ar_ready <= (cyc == 85) || (cyc == 92);
    core_axi_resp.r_valid  <= (cyc == 90) || (cyc == 97);
    core_axi_resp.r.data   <= 32'h0000_1234;
    core_axi_resp.r.resp   <= AXI_RESP_OKAY;

// ================= APB slot decode =================
    // Each APB request field is meaningful only on its selected slot. Drive
    // independent payloads to catch monitor wiring that incorrectly samples
    // APB[0] while another slot is selected.
    for (int i = 0; i < 6; i++) begin
      apb_req[i].psel    <= 1'b0;
      apb_req[i].penable <= 1'b0;
      apb_req[i].pwrite  <= 1'b0;
      apb_req[i].paddr   <= '0;
      apb_req[i].pwdata  <= '0;
      apb_req[i].pstrb   <= '0;
      apb_resp[i].pready <= 1'b1;
      apb_resp[i].prdata <= '0;
      apb_resp[i].pslverr<= 1'b0;
    end

    // Two cross-layer transactions link the LSU/AXI/APB predictors.
    // UART write: one setup cycle, two wait cycles, one completed access.
    if ((cyc >= 27) && (cyc <= 30)) begin
      apb_req[2].psel    <= 1'b1;
      apb_req[2].penable <= (cyc >= 28);
      apb_req[2].pwrite  <= 1'b1;
      apb_req[2].paddr   <= 32'h4000_2000;
      apb_req[2].pwdata  <= 32'h0000_0055;
      apb_req[2].pstrb   <= 4'hF;
      apb_resp[2].pready <= (cyc == 30);
    end
    // Timer0 read: one setup cycle, one wait cycle, one completed access.
    if ((cyc >= 87) && (cyc <= 89)) begin
      apb_req[1].psel    <= 1'b1;
      apb_req[1].penable <= (cyc >= 88);
      apb_req[1].pwrite  <= 1'b0;
      apb_req[1].paddr   <= 32'h4000_1000;
      apb_resp[1].pready <= (cyc == 89);
      apb_resp[1].prdata <= 32'h0000_1234;
    end

    // A deterministic six-slot monitor probe. One transfer per APB slot,
    // with unique payload fields and an injected slave error on SPI/APB[4].
    if ((cyc >= 450) && (cyc < 474)) begin
      int unsigned slot_id;
      int unsigned phase;
      slot_id = (cyc - 450) / 4;
      phase   = (cyc - 450) % 4;
      apb_req[slot_id].psel    <= 1'b1;
      apb_req[slot_id].penable <= (phase != 0);
      apb_req[slot_id].pwrite  <= slot_id[0];
      apb_req[slot_id].paddr   <= 32'h4000_0000 + (slot_id * 32'h1000) + 32'h24;
      apb_req[slot_id].pwdata  <= 32'hA500_0000 | slot_id;
      apb_req[slot_id].pstrb   <= 4'hF ^ slot_id[3:0];
      apb_resp[slot_id].pready <= (phase == 3);
      apb_resp[slot_id].prdata <= 32'h5A00_0000 | slot_id;
      apb_resp[slot_id].pslverr<= (slot_id == 4);
    end

    // ================= interrupt sequence =================
    uart_int_o                        <= (cyc == 240);
    timer0_irq_o                      <= 1'b0;
    timer1_irq_o                      <= 1'b0;
    i2c_interrupt_o                   <= 1'b0;
    gpio_global_interrupt_o           <= 1'b0;
    spi_events_o                      <= 2'b00;
    gpio_pin_level_interrupts_o       <= '0;

    i_riscv_core.fast_irq_i           <= ((cyc >= 240) && (cyc < 285)) ? 16'h0008 : 16'h0;
    i_riscv_core.timer_irq_i          <= 1'b0;
    i_riscv_core.csr_mip_sb           <= ((cyc >= 240) && (cyc < 285)) ? 32'h0008_0000 : '0;
    i_riscv_core.csr_mie_sb           <= 32'h0008_0000;
    i_riscv_core.csr_mintprio_sb      <= 32'h0000_0001;
    i_riscv_core.csr_mstatus_mie_sb   <= 1'b1;
    i_riscv_core.u_irq_gateway.pend_o <= ((cyc >= 240) && (cyc < 285)) ? 6'b001000 : 6'b0;

    i_riscv_core.irq_valid                <= ((cyc >= 240) && (cyc < 285));
    i_riscv_core.irq_pending              <= ((cyc >= 250) && (cyc < 300));
    i_riscv_core.irq_cause_enc            <= 5'd19;      // UART
    i_riscv_core.irq_id                   <= 31'd19;
    i_riscv_core.u_irq_arbiter.irq_class_o<= 2'd1;       // Stream

    i_riscv_core.trap_commit_valid        <= (cyc == 260);
    i_riscv_core.trap_commit_is_interrupt <= (cyc == 260);
    i_riscv_core.trap_commit_cause        <= 31'd19;
    i_riscv_core.trap_commit_pc           <= 32'h0000_0100;

    // ================= external pins =================
    i2c_scl_i <= 1'b1;
    i2c_sda_i <= 1'b1;
    i2c_scl_o <= 1'b1;
    i2c_scl_oen_o <= 1'b0;
    i2c_sda_o <= 1'b1;
    i2c_sda_oen_o <= 1'b0;
    spi_sdi1_i <= 1'b0;
    gpio_in_sync_o <= '0;

    // UART TX: hold START for 16 cycles from cyc 150, then stream the bits.
    if ((cyc >= 150) && (cyc < 182))
      uart_tx <= uart_bits[(cyc - 150) / 16];
    else if (cyc >= 182)
      uart_tx <= 1'b1;

    // retire the bit once its 16-cycle window is over
    if (((cyc - 149) % 16) == 0)
      uart_bits <= {1'b1, uart_bits[15:1]};
  end

endmodule
