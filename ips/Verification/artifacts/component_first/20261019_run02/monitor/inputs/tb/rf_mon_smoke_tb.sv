// =============================================================================
// Module Name : rf_mon_smoke_tb.sv
// Description : Monitor-layer self-test. Elaborates and runs the FULL Step-3
//               monitor stack against rf_mon_stub_dut, then asserts that the
//               layer is NON-VACUOUS and that the expected cross-layer joins
//               hold. Any change to tb_pkg / rf_monitor_if / rf_monitors /
//               rf_monitor_env / rf_mon_probe that breaks elaboration, the
//               shared cycle counter, the ring buffers, or the LSU->AXI->APB
//               join is caught here without needing the full SoC.
//
// Run:  xvlog --sv -f rf_mon_smoke.f && xelab rf_mon_smoke_tb -s rf_mon_smoke
//       xsim rf_mon_smoke -runall
// =============================================================================

`timescale 1ns/1ps

module rf_mon_smoke_tb import tb_pkg::*;;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #5 clk = ~clk;                 // 100 MHz

  // ---- external pin wires owned by the TB (same idiom as soc_tb_top) ----
  logic uart_rx_wire = 1'b1;
  wire  uart_tx_wire = u_dut.uart_tx;   // the stub drives the DUT TX pin
  logic spi_miso_wire = 1'b0;
  logic [31:0] gpio_in_wire  = '0;
  logic [31:0] gpio_out_wire = '0;
  logic [31:0] gpio_oe_wire  = '0;

  wire i2c_scl_wire = 1'b1;             // pull-up only, DUT never drives
  wire i2c_sda_wire = 1'b1;
  wire spi_sclk_wire = 1'b0;
  wire spi_csn0_wire = 1'b1;            // ACTIVE LOW, idle high
  wire spi_csn1_wire = 1'b1;
  wire spi_mosi_wire = 1'b0;

  // ---- DUT ----
  rf_mon_stub_dut u_dut (.clk(clk));

  // ---- monitor layer ----
  rf_mon_probe u_mon (
    .clk           (clk),
    .rst_n         (rst_n),
    .freeze        (1'b0),
    .uart_rx_wire  (uart_rx_wire),
    .uart_tx_wire  (uart_tx_wire),
    .i2c_scl_wire  (i2c_scl_wire),
    .i2c_sda_wire  (i2c_sda_wire),
    .spi_sclk_wire (spi_sclk_wire),
    .spi_csn0_wire (spi_csn0_wire),
    .spi_csn1_wire (spi_csn1_wire),
    .spi_mosi_wire (spi_mosi_wire),
    .spi_miso_wire (spi_miso_wire),
    .gpio_in_wire  (gpio_in_wire),
    .gpio_out_wire (gpio_out_wire),
    .gpio_oe_wire  (gpio_oe_wire)
  );

  // route the stub's UART pin onto the TB wire is done by the wire declaration

  int unsigned errors;

  // =========================================================================
  task automatic tb_check(string id, bit cond, string msg = "");
    if (!cond) begin
      errors++;
      $display("[SMOKE] FAIL  %-22s %s", id, msg);
    end else begin
      $display("[SMOKE] pass  %-22s %s", id, msg);
    end
  endtask

  initial begin
    errors = 0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
  end

  // =========================================================================
  initial begin
    bit [5:0] found_apb_probe;
    int unsigned apb_probe_errors;
    bit [5:0] found_class_apb_probe;
    int unsigned class_apb_probe_errors;
    #20000;                             // ~1000 cycles
    $display("");
    $display("================ MONITOR LAYER SELF-TEST ================");

    // ---- 1. every monitor produced events (the check is not vacuous) ----
    tb_check("M1.fetch",  u_mon.env.m_fetch .n_events > 0,
             $sformatf("fetch events=%0d",  u_mon.env.m_fetch .n_events));
    tb_check("M2.retire", u_mon.env.m_retire.n_events > 0,
             $sformatf("retire events=%0d", u_mon.env.m_retire.n_events));
    tb_check("M3.lsu",    u_mon.env.m_lsu   .n_events > 0,
             $sformatf("lsu events=%0d",    u_mon.env.m_lsu   .n_events));
    tb_check("M4.axil",   u_mon.env.m_axil  .n_events > 0,
             $sformatf("axil events=%0d",   u_mon.env.m_axil  .n_events));
    tb_check("M5.apb",    u_mon.env.m_apb   .n_events > 0,
             $sformatf("apb events=%0d",    u_mon.env.m_apb   .n_events));
    tb_check("M6.irq",    u_mon.env.m_irq   .n_events > 0,
             $sformatf("irq events=%0d",    u_mon.env.m_irq   .n_events));

    // ---- 2. all five AXI-Lite channels were seen independently ----
    tb_check("A1.aw", u_mon.env.m_axil.n_aw > 0, "AW handshake logged");
    tb_check("A2.w",  u_mon.env.m_axil.n_w  > 0, "W  handshake logged");
    tb_check("A3.b",  u_mon.env.m_axil.n_b  > 0, "B  handshake logged");
    tb_check("A4.ar", u_mon.env.m_axil.n_ar > 0, "AR handshake logged");
    tb_check("A5.r",  u_mon.env.m_axil.n_r  > 0, "R  handshake logged");

    // ---- 3. every APB slot receives a unique, nonzero monitor probe ----
    for (int slot = 0; slot < 6; slot++) begin
      tb_check($sformatf("P.slot%0d", slot), u_mon.env.m_apb.n_xfer[slot] > 0,
               $sformatf("slot=%0d transfers=%0d", slot, u_mon.env.m_apb.n_xfer[slot]));
    end
    found_apb_probe = '0;
    apb_probe_errors = 0;
    for (int i = 0; i < 64; i++) begin
      int unsigned slot;
      slot = u_mon.u_apb_mon.ring_buffer[i].slot;
      if (u_mon.u_apb_mon.ring_buffer[i].paddr >= 32'h4000_0024 &&
          u_mon.u_apb_mon.ring_buffer[i].paddr <= 32'h4000_5024 &&
          u_mon.u_apb_mon.ring_buffer[i].paddr[11:0] == 12'h024) begin
        if (slot > 5) begin
          apb_probe_errors++;
        end else begin
          found_apb_probe[slot] = 1'b1;
          if (u_mon.u_apb_mon.ring_buffer[i].paddr !== (32'h4000_0000 + slot*32'h1000 + 32'h24) ||
              u_mon.u_apb_mon.ring_buffer[i].pwdata !== (32'hA500_0000 | slot) ||
              u_mon.u_apb_mon.ring_buffer[i].prdata !== (32'h5A00_0000 | slot) ||
              u_mon.u_apb_mon.ring_buffer[i].pwrite !== slot[0] ||
              u_mon.u_apb_mon.ring_buffer[i].pstrb !== (4'hF ^ slot[3:0]) ||
              u_mon.u_apb_mon.ring_buffer[i].wait_states !== 2 ||
              u_mon.u_apb_mon.ring_buffer[i].pslverr !== (slot == 4))
            apb_probe_errors++;
        end
      end
    end
    tb_check("P.payloads", (&found_apb_probe) && apb_probe_errors == 0,
             $sformatf("slot mask=%b payload errors=%0d", found_apb_probe, apb_probe_errors));
    found_class_apb_probe = '0;
    class_apb_probe_errors = 0;
    for (int i = 0; i < u_mon.env.m_apb.q_apb.size(); i++) begin
      apb_txn_t tr;
      int unsigned slot;
      tr = u_mon.env.m_apb.q_apb[i];
      slot = tr.slot;
      if (tr.paddr >= 32'h4000_0024 && tr.paddr <= 32'h4000_5024 && tr.paddr[11:0] == 12'h024) begin
        if (slot > 5) begin
          class_apb_probe_errors++;
        end else begin
          found_class_apb_probe[slot] = 1'b1;
          if (tr.paddr !== (32'h4000_0000 + slot*32'h1000 + 32'h24) ||
              tr.pwdata !== (32'hA500_0000 | slot) ||
              tr.prdata !== (32'h5A00_0000 | slot) ||
              tr.pwrite !== slot[0] ||
              tr.pstrb !== (4'hF ^ slot[3:0]) ||
              tr.wait_states !== 2 ||
              tr.pslverr !== (slot == 4)) begin
            class_apb_probe_errors++;
            $display("[SMOKE] APB class slot %0d captured: addr=%08h w=%08h r=%08h wr=%b strb=%h ws=%0d err=%b",
                     slot, tr.paddr, tr.pwdata, tr.prdata, tr.pwrite, tr.pstrb, tr.wait_states, tr.pslverr);
          end
        end
      end
    end
    tb_check("P.class_payloads", (&found_class_apb_probe) && class_apb_probe_errors == 0,
             $sformatf("slot mask=%b payload errors=%0d", found_class_apb_probe, class_apb_probe_errors));

    // ---- 4. shared cycle counter: strictly monotonic, identical across
    //         monitors for the same simulation edge ----
    tb_check("T1.monotonic", u_mon.env.m_lsu.last_cycle > u_mon.env.m_fetch.first_cycle,
             $sformatf("lsu.last=%0d fetch.first=%0d",
                       u_mon.env.m_lsu.last_cycle, u_mon.env.m_fetch.first_cycle));
    tb_check("T2.tb_cycle", u_mon.env.m_lsu.cur_cycle == u_mon.env.m_axil.cur_cycle,
             $sformatf("lsu cyc=%0d axil cyc=%0d",
                       u_mon.env.m_lsu.cur_cycle, u_mon.env.m_axil.cur_cycle));

    // ---- 5. ring buffers retained entries (cyclic history works) ----
    tb_check("R1.ring_lsu",  u_mon.env.m_lsu.ring.size()   > 0,
             $sformatf("lsu ring=%0d",  u_mon.env.m_lsu.ring.size()));
    tb_check("R2.ring_apb",  u_mon.env.m_apb.ring.size()   > 0,
             $sformatf("apb ring=%0d",  u_mon.env.m_apb.ring.size()));
    tb_check("R3.ring_ret",  u_mon.env.m_retire.ring.size()> 0,
             $sformatf("retire ring=%0d", u_mon.env.m_retire.ring.size()));

    // ---- 6. cross-layer join: one MMIO write -> one AXI WR -> one APB WR ----
    tb_check("J1.mmio_cnt", u_mon.env.db.q_lsu.size() > 0,
             $sformatf("lsu stream=%0d", u_mon.env.db.q_lsu.size()));
    tb_check("J2.axil_wr",  u_mon.env.db.q_axi.size() >= 2,
             $sformatf("axi stream=%0d", u_mon.env.db.q_axi.size()));
    tb_check("J3.no_wrong_slot", u_mon.env.db.count_wrong_slot(32'h4000_2000) == 0,
             "no MMIO access decoded onto the wrong APB slot");

    // ---- 7. interrupt lifecycle: assert -> grant -> ack ----
    tb_check("I1.grant", u_mon.env.m_irq.n_grant > 0,
             $sformatf("grants=%0d", u_mon.env.m_irq.n_grant));
    tb_check("I2.ack",   u_mon.env.m_irq.n_ack   > 0,
             $sformatf("acks=%0d",   u_mon.env.m_irq.n_ack));
    tb_check("I3.mret",  u_mon.env.m_irq.n_mret  > 0,
             $sformatf("mrets=%0d",  u_mon.env.m_irq.n_mret));

    // ---- 8. decode helpers agree with the RTL map ----
    tb_check("D1.i2c",    get_expected_apb_slot(32'h4000_0000) == int'(RF_APB_I2C),    "0x4000_0000 -> I2C");
    tb_check("D2.t0",     get_expected_apb_slot(32'h4000_1FFF) == int'(RF_APB_TIMER0), "0x4000_1FFF -> TIMER0");
    tb_check("D3.uart",   get_expected_apb_slot(32'h4000_2000) == int'(RF_APB_UART),   "0x4000_2000 -> UART");
    tb_check("D4.gpio",   get_expected_apb_slot(32'h4000_37FF) == int'(RF_APB_GPIO),   "0x4000_37FF -> GPIO (2KB)");
    tb_check("D5.gap",    get_expected_apb_slot(32'h4000_3FFF) == int'(RF_APB_NONE),   "0x4000_3FFF -> unmapped");
    tb_check("D6.spi",    get_expected_apb_slot(32'h4000_4000) == int'(RF_APB_SPI),    "0x4000_4000 -> SPI");
    tb_check("D7.t1",     get_expected_apb_slot(32'h4000_5000) == int'(RF_APB_TIMER1), "0x4000_5000 -> TIMER1");
    tb_check("D8.isram",  decode_region(32'h0001_0000) == RF_REGION_ISRAM, "ISRAM region");
    tb_check("D9.dsram",  decode_region(32'h0002_0000) == RF_REGION_DSRAM, "DSRAM region");
    tb_check("D10.mmio",  decode_region(32'h4000_1234) == RF_REGION_MMIO,  "MMIO region");

    // ---- 9. post-mortem report renders ----
    tb_check("M1.report", u_mon.env.postmortem(8).len() > 500,
             $sformatf("report length=%0d", u_mon.env.postmortem(8).len()));

    // ---- 10. freeze latches the rings ----
    u_mon.env.db.note_fatal(LAYER_PATH, "SMOKE-99", "self-test injected fatal", 12345, 32'h100);
    tb_check("F1.frozen", u_mon.env.db.frozen == 1, "freeze asserted");
    tb_check("F2.cycle",  u_mon.env.db.freeze_cycle == 12345, "freeze cycle recorded");

    $display("==========================================================");
    if (errors == 0) $display("SMOKE TEST PASSED");
    else             $display("SMOKE TEST FAILED with %0d error(s)", errors);
    $display("==========================================================");
    $display("");
    $display("%s", u_mon.env.postmortem(12));
    $finish;
  end

  // hard stop
  initial begin
    #40000;
    $display("[SMOKE] TIMEOUT");
    $finish;
  end

endmodule
