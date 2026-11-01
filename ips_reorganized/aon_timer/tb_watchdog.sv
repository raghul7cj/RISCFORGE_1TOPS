// =============================================================================
// tb_watchdog — standalone directed testbench for the OpenTitan aon_timer
// =============================================================================
// Scope: the watchdog IP on its own. The testbench drives aon_timer's TL-UL
// device port directly (no APB bridge, no SoC). tlul_cmd_intg_gen adds the
// command/data integrity bits that aon_timer_reg_top checks on every request.
//
// Tie-offs match the intended SoC integration:
//   lc_escalate_en_i = lc_ctrl_pkg::Off  (any other value stops both counters)
//   alert_rx_i       = ALERT_RX_DEFAULT  (differential idle levels)
//   sleep_mode_i     = 1'b0
//
// Clocking: WDT_AON_DIV = 1 -> clk_aon_i is clk_i.
//           WDT_AON_DIV = N -> clk_aon_i is N x slower and phase-shifted, which
//                              exercises the prim_reg_cdc handshakes.
//
// Tests
//   T1  reset values of all 14 registers
//   T2  register read/write
//   T3  watchdog counts when enabled, stops when disabled
//   T4  bark: interrupt + NMI + INTR_STATE, W1C clear, edge-triggered, re-arm on pet
//   T5  bite: aon_timer_rst_req_o, sticky until rst_aon_ni
//   T6  petting holds off bark and bite; bark then bite once petting stops
//   T7  WDOG_REGWEN lock: thresholds/ctrl frozen, W0C, pet still works, reset unlocks
//   T8  INTR_TEST
//   T9  error responses: unmapped, sub-word, misaligned
//   T10 CDC back-pressure: a_ready low cycles for back-to-back same-register access
//   plus: no bus-integrity alert and no wakeup-timer interrupt during the whole run
//
// Run from the aon_timer/ directory on the CentOS tree:
//   xrun -f tb_watchdog.f
//   xrun -f tb_watchdog.f +define+WDT_AON_DIV=4
// =============================================================================
`timescale 1ns/1ps

`ifndef WDT_AON_DIV
  `define WDT_AON_DIV 1
`endif

module tb_watchdog;
  import tlul_pkg::*;
  import aon_timer_reg_pkg::*;

  localparam int unsigned AonDiv        = `WDT_AON_DIV;
  localparam realtime     ClkPeriod     = 10ns;
  localparam int unsigned AccessTimeout = 1000;  // clk_i cycles per TL-UL channel wait

  // Thresholds, in clk_aon_i cycles
  localparam int unsigned BarkT     = 40;   // T4
  localparam int unsigned BiteBarkT = 20;   // T5
  localparam int unsigned BiteT     = 60;   // T5
  localparam int unsigned PetBarkT  = 100;  // T6
  localparam int unsigned PetBiteT  = 200;  // T6
  localparam int unsigned PetPeriod = 40;   // T6
  localparam int unsigned PetCount  = 10;   // T6

  // ---------------------------------------------------------------------------
  // Clocks and resets
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  always #(ClkPeriod/2) clk = ~clk;

  logic clk_aon_div = 1'b0;
  initial begin
    #3ns;
    forever #(ClkPeriod*AonDiv/2) clk_aon_div = ~clk_aon_div;
  end

  logic clk_aon;
  assign clk_aon = (AonDiv == 1) ? clk : clk_aon_div;

  logic rst_n;
  logic rst_aon_n;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  tl_h2d_t tl_h2d_raw;  // driven by tl_access()
  tl_h2d_t tl_h2d;      // tl_h2d_raw with integrity bits added
  tl_d2h_t tl_d2h;

  prim_alert_pkg::alert_rx_t [NumAlerts-1:0] alert_rx;
  prim_alert_pkg::alert_tx_t [NumAlerts-1:0] alert_tx;

  logic intr_wkup;
  logic intr_bark;
  logic nmi_bark;
  logic wkup_req;
  logic rst_req;

  for (genvar i = 0; i < NumAlerts; i++) begin : g_alert_rx
    assign alert_rx[i] = prim_alert_pkg::ALERT_RX_DEFAULT;
  end

  tlul_cmd_intg_gen u_intg_gen (
    .tl_i ( tl_h2d_raw ),
    .tl_o ( tl_h2d     )
  );

  aon_timer dut (
    .clk_i                     ( clk               ),
    .clk_aon_i                 ( clk_aon           ),
    .rst_ni                    ( rst_n             ),
    .rst_aon_ni                ( rst_aon_n         ),
    .tl_i                      ( tl_h2d            ),
    .tl_o                      ( tl_d2h            ),
    .alert_rx_i                ( alert_rx          ),
    .alert_tx_o                ( alert_tx          ),
    .lc_escalate_en_i          ( lc_ctrl_pkg::Off  ),
    .intr_wkup_timer_expired_o ( intr_wkup         ),
    .intr_wdog_timer_bark_o    ( intr_bark         ),
    .nmi_wdog_timer_bark_o     ( nmi_bark          ),
    .wkup_req_o                ( wkup_req          ),
    .aon_timer_rst_req_o       ( rst_req           ),
    .sleep_mode_i              ( 1'b0              )
  );

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  int unsigned n_checks;
  int unsigned n_errors;
  int unsigned last_stall;  // clk_i cycles a_ready was low during the last access

  function automatic void check(input bit cond, input string msg);
    n_checks++;
    if (cond) begin
      $display("[%0t]   pass: %s", $time, msg);
    end else begin
      n_errors++;
      $display("[%0t]   FAIL: %s", $time, msg);
    end
  endfunction

  // Whole-run monitors: alerts[0] is aon_timer_reg_top.intg_err_o (TL-UL
  // integrity / write-enable one-hot fault). The wakeup timer is never enabled.
  bit alert_seen;
  bit wkup_intr_seen;
  always @(posedge clk) begin
    if (rst_n === 1'b1 && dut.alerts[0] === 1'b1) alert_seen     <= 1'b1;
    if (rst_n === 1'b1 && intr_wkup     === 1'b1) wkup_intr_seen <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // TL-UL host
  // ---------------------------------------------------------------------------
  // Drives on the falling edge, samples 1 ns later, so every sample is taken
  // mid-cycle with all combinational outputs settled.
  task automatic tl_access(input  logic        write,
                           input  logic [31:0] addr,
                           input  logic [31:0] wdata,
                           input  logic [3:0]  mask,
                           input  logic [1:0]  size,
                           output logic [31:0] rdata,
                           output logic        err);
    int unsigned wait_cnt;

    @(negedge clk);
    tl_h2d_raw           = TL_H2D_DEFAULT;
    tl_h2d_raw.a_valid   = 1'b1;
    if (!write)            tl_h2d_raw.a_opcode = Get;
    else if (mask == 4'hF) tl_h2d_raw.a_opcode = PutFullData;
    else                   tl_h2d_raw.a_opcode = PutPartialData;
    tl_h2d_raw.a_size    = size;
    tl_h2d_raw.a_address = addr;
    tl_h2d_raw.a_mask    = mask;
    tl_h2d_raw.a_data    = wdata;
    tl_h2d_raw.d_ready   = 1'b1;

    // A channel: a_ready is low while the addressed CDC register is busy
    wait_cnt = 0;
    #1ns;
    while (tl_d2h.a_ready !== 1'b1) begin
      if (wait_cnt == AccessTimeout) begin
        n_errors++;
        $display("[%0t]   FAIL: a_ready timeout, addr 0x%08h", $time, addr);
        break;
      end
      @(negedge clk);
      #1ns;
      wait_cnt++;
    end
    last_stall = wait_cnt;
    @(posedge clk);  // request accepted on this edge
    @(negedge clk);
    tl_h2d_raw.a_valid = 1'b0;

    // D channel
    wait_cnt = 0;
    #1ns;
    while (tl_d2h.d_valid !== 1'b1) begin
      if (wait_cnt == AccessTimeout) begin
        n_errors++;
        $display("[%0t]   FAIL: d_valid timeout, addr 0x%08h", $time, addr);
        break;
      end
      @(negedge clk);
      #1ns;
      wait_cnt++;
    end
    rdata = tl_d2h.d_data;
    err   = tl_d2h.d_error;
    @(posedge clk);  // response consumed (d_ready = 1)
  endtask

  task automatic csr_wr(input logic [BlockAw-1:0] off, input logic [31:0] data);
    logic [31:0] rd;
    logic        err;
    tl_access(1'b1, 32'(off), data, 4'hF, 2'd2, rd, err);
    if (err !== 1'b0) begin
      n_errors++;
      $display("[%0t]   FAIL: write 0x%08h to offset 0x%02h returned d_error", $time, data, off);
    end
  endtask

  task automatic csr_rd(input logic [BlockAw-1:0] off, output logic [31:0] data);
    logic err;
    tl_access(1'b0, 32'(off), 32'h0, 4'hF, 2'd2, data, err);
    if (err !== 1'b0) begin
      n_errors++;
      $display("[%0t]   FAIL: read of offset 0x%02h returned d_error", $time, off);
    end
  endtask

  task automatic check_rd(input logic [BlockAw-1:0] off, input logic [31:0] exp,
                          input string what);
    logic [31:0] rd;
    csr_rd(off, rd);
    check(rd === exp, $sformatf("%s (read 0x%08h, expected 0x%08h)", what, rd, exp));
  endtask

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  typedef enum {SigBark, SigRstReq} sig_e;

  function automatic logic sig_val(input sig_e s);
    case (s)
      SigBark:   return intr_bark;
      SigRstReq: return rst_req;
      default:   return 1'bx;
    endcase
  endfunction

  // Waits up to max_aon clk_aon_i cycles for the signal to go high.
  // waited = clk_aon_i cycles elapsed (max_aon + 1 if it never went high).
  task automatic wait_high(input sig_e s, input int unsigned max_aon,
                           output int unsigned waited);
    waited = 0;
    while (sig_val(s) !== 1'b1 && waited <= max_aon) begin
      @(posedge clk_aon);
      waited++;
    end
  endtask

  // Both domains reset together, as the SoC bite reset will do.
  task automatic apply_reset();
    rst_n     = 1'b0;
    rst_aon_n = 1'b0;
    repeat (4) @(posedge clk);
    repeat (4) @(posedge clk_aon);
    @(negedge clk);
    rst_n     = 1'b1;
    rst_aon_n = 1'b1;
    repeat (4) @(posedge clk_aon);
    repeat (4) @(posedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Global timeout
  // ---------------------------------------------------------------------------
  initial begin
    #(ClkPeriod * 400_000 * AonDiv);
    $display("[%0t] TEST FAILED: global timeout", $time);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  initial begin
    logic [31:0] rd;
    logic [31:0] c1, c2, c3, c4;
    logic        err;
    int unsigned waited;
    int unsigned stall_rd, stall_wr;

    n_checks       = 0;
    n_errors       = 0;
    alert_seen     = 1'b0;
    wkup_intr_seen = 1'b0;
    tl_h2d_raw     = TL_H2D_DEFAULT;
    rst_n          = 1'b0;
    rst_aon_n      = 1'b0;

    $display("==== tb_watchdog: aon_timer standalone, WDT_AON_DIV = %0d ====", AonDiv);
    apply_reset();

    // -------------------------------------------------------------------------
    $display("---- T1: reset values");
    check_rd(AON_TIMER_ALERT_TEST_OFFSET,      32'h0, "ALERT_TEST reads 0");
    check_rd(AON_TIMER_WKUP_CTRL_OFFSET,       32'h0, "WKUP_CTRL reset");
    check_rd(AON_TIMER_WKUP_THOLD_HI_OFFSET,   32'h0, "WKUP_THOLD_HI reset");
    check_rd(AON_TIMER_WKUP_THOLD_LO_OFFSET,   32'h0, "WKUP_THOLD_LO reset");
    check_rd(AON_TIMER_WKUP_COUNT_HI_OFFSET,   32'h0, "WKUP_COUNT_HI reset");
    check_rd(AON_TIMER_WKUP_COUNT_LO_OFFSET,   32'h0, "WKUP_COUNT_LO reset");
    check_rd(AON_TIMER_WDOG_REGWEN_OFFSET,     32'h1, "WDOG_REGWEN reset = 1 (unlocked)");
    check_rd(AON_TIMER_WDOG_CTRL_OFFSET,       32'h0, "WDOG_CTRL reset");
    check_rd(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'h0, "WDOG_BARK_THOLD reset");
    check_rd(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'h0, "WDOG_BITE_THOLD reset");
    check_rd(AON_TIMER_WDOG_COUNT_OFFSET,      32'h0, "WDOG_COUNT reset");
    check_rd(AON_TIMER_INTR_STATE_OFFSET,      32'h0, "INTR_STATE reset");
    check_rd(AON_TIMER_INTR_TEST_OFFSET,       32'h0, "INTR_TEST reads 0");
    check_rd(AON_TIMER_WKUP_CAUSE_OFFSET,      32'h0, "WKUP_CAUSE reset");
    check(intr_bark === 1'b0 && nmi_bark === 1'b0 && rst_req === 1'b0 &&
          wkup_req === 1'b0 && intr_wkup === 1'b0, "all outputs idle after reset");

    // -------------------------------------------------------------------------
    $display("---- T2: register read/write");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'hA5A5_1234);
    check_rd(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'hA5A5_1234, "WDOG_BARK_THOLD r/w");
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'h5A5A_4321);
    check_rd(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'h5A5A_4321, "WDOG_BITE_THOLD r/w");
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0000_1234);  // disabled, so the value holds
    check_rd(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0000_1234, "WDOG_COUNT r/w (watchdog disabled)");
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET, 32'h0000_0002);   // pause_in_sleep = 1, enable = 0
    check_rd(AON_TIMER_WDOG_CTRL_OFFSET, 32'h0000_0002, "WDOG_CTRL r/w (pause_in_sleep)");
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET, 32'hFFFF_FFFC);   // only bits [1:0] exist
    check_rd(AON_TIMER_WDOG_CTRL_OFFSET, 32'h0000_0000, "WDOG_CTRL bits [31:2] read 0");
    csr_wr(AON_TIMER_WKUP_CTRL_OFFSET, 32'h0000_1578);   // prescaler = 0xABC, enable = 0
    check_rd(AON_TIMER_WKUP_CTRL_OFFSET, 32'h0000_1578, "WKUP_CTRL r/w (prescaler)");
    csr_wr(AON_TIMER_WKUP_THOLD_LO_OFFSET, 32'h1111_2222);
    check_rd(AON_TIMER_WKUP_THOLD_LO_OFFSET, 32'h1111_2222, "WKUP_THOLD_LO r/w");
    csr_wr(AON_TIMER_WKUP_THOLD_HI_OFFSET, 32'h3333_4444);
    check_rd(AON_TIMER_WKUP_THOLD_HI_OFFSET, 32'h3333_4444, "WKUP_THOLD_HI r/w");
    csr_wr(AON_TIMER_WKUP_CTRL_OFFSET,     32'h0);
    csr_wr(AON_TIMER_WKUP_THOLD_LO_OFFSET, 32'h0);
    csr_wr(AON_TIMER_WKUP_THOLD_HI_OFFSET, 32'h0);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET,    32'h0);

    // -------------------------------------------------------------------------
    $display("---- T3: counting");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'hFFFF_FFF0);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'hFFFF_FFFF);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET,      32'h0);
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,       32'h1);
    repeat (100) @(posedge clk_aon);
    csr_rd(AON_TIMER_WDOG_COUNT_OFFSET, c1);
    check(c1 >= 70 && c1 <= 110,
          $sformatf("WDOG_COUNT = %0d after 100 clk_aon cycles (expected 70..110)", c1));
    repeat (50) @(posedge clk_aon);
    csr_rd(AON_TIMER_WDOG_COUNT_OFFSET, c2);
    check(c2 > c1 && (c2 - c1) >= 35 && (c2 - c1) <= 65,
          $sformatf("WDOG_COUNT advanced by %0d in 50 clk_aon cycles (expected 35..65)", c2 - c1));
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET, 32'h0);
    repeat (20) @(posedge clk_aon);
    csr_rd(AON_TIMER_WDOG_COUNT_OFFSET, c3);
    repeat (30) @(posedge clk_aon);
    csr_rd(AON_TIMER_WDOG_COUNT_OFFSET, c4);
    check(c4 === c3, $sformatf("WDOG_CTRL.enable = 0 stops the count (%0d -> %0d)", c3, c4));

    // -------------------------------------------------------------------------
    $display("---- T4: bark");
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET,      32'h0);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'd1000);
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, BarkT);
    csr_wr(AON_TIMER_INTR_STATE_OFFSET,      32'h3);
    check(intr_bark === 1'b0, "no bark before enable");
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET, 32'h1);
    wait_high(SigBark, BarkT + 40, waited);
    check(intr_bark === 1'b1 && waited >= BarkT - 1,
          $sformatf("bark fired %0d clk_aon cycles after enable (threshold %0d)", waited, BarkT));
    check(nmi_bark === 1'b1, "nmi_wdog_timer_bark_o follows the bark");
    check(rst_req === 1'b0, "no bite at bark");
    csr_rd(AON_TIMER_INTR_STATE_OFFSET, rd);
    check(rd === 32'h2, $sformatf("INTR_STATE = 0x%0h (expected 0x2, wdog_timer_bark)", rd));
    repeat (5) @(posedge clk_aon);
    check(wkup_req === 1'b1, "wkup_req_o set by the bark");

    csr_wr(AON_TIMER_INTR_STATE_OFFSET, 32'h2);
    repeat (3) @(posedge clk);
    check(intr_bark === 1'b0 && nmi_bark === 1'b0, "INTR_STATE W1C clears the bark interrupt");
    repeat (20) @(posedge clk_aon);
    check(intr_bark === 1'b0,
          "bark is edge-triggered: no re-assert while the count stays above the threshold");

    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);  // pet: count drops below the threshold
    wait_high(SigBark, BarkT + 40, waited);
    check(intr_bark === 1'b1, $sformatf("bark re-fires after a pet (%0d clk_aon cycles)", waited));

    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET, 32'h0);
    repeat (10) @(posedge clk_aon);
    csr_wr(AON_TIMER_INTR_STATE_OFFSET, 32'h3);
    csr_wr(AON_TIMER_WKUP_CAUSE_OFFSET, 32'h0);
    repeat (10) @(posedge clk_aon);
    check(intr_bark === 1'b0 && wkup_req === 1'b0,
          "bark interrupt and wkup_req_o clear once the watchdog is stopped");

    // -------------------------------------------------------------------------
    $display("---- T5: bite");
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET,      32'h0);
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, BiteBarkT);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, BiteT);
    csr_wr(AON_TIMER_INTR_STATE_OFFSET,      32'h3);
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,       32'h1);
    wait_high(SigRstReq, BiteT + 40, waited);
    check(rst_req === 1'b1 && waited >= BiteT - 1,
          $sformatf("bite: aon_timer_rst_req_o %0d clk_aon cycles after enable (threshold %0d)",
                    waited, BiteT));
    check(intr_bark === 1'b1, "bark fired before the bite");
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,  32'h0);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);
    repeat (20) @(posedge clk_aon);
    check(rst_req === 1'b1, "aon_timer_rst_req_o is sticky: disable + pet do not clear it");
    apply_reset();
    check(rst_req === 1'b0, "aon_timer_rst_req_o clears on rst_aon_ni");
    check_rd(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0, "WDOG_COUNT back to 0 after reset");
    check_rd(AON_TIMER_WDOG_CTRL_OFFSET,  32'h0, "WDOG_CTRL back to 0 after reset");

    // -------------------------------------------------------------------------
    $display("---- T6: petting");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, PetBarkT);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, PetBiteT);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET,      32'h0);
    csr_wr(AON_TIMER_INTR_STATE_OFFSET,      32'h3);
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,       32'h1);
    for (int i = 0; i < PetCount; i++) begin
      repeat (PetPeriod) @(posedge clk_aon);
      csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);
    end
    check(intr_bark === 1'b0 && rst_req === 1'b0,
          $sformatf("%0d pets every %0d clk_aon cycles hold off bark (%0d) and bite (%0d)",
                    PetCount, PetPeriod, PetBarkT, PetBiteT));
    wait_high(SigBark, PetBarkT + 40, waited);
    check(intr_bark === 1'b1, $sformatf("bark %0d clk_aon cycles after petting stops", waited));
    wait_high(SigRstReq, (PetBiteT - PetBarkT) + 40, waited);
    check(rst_req === 1'b1, $sformatf("bite %0d clk_aon cycles after the bark", waited));
    apply_reset();

    // -------------------------------------------------------------------------
    $display("---- T7: configuration lock (WDOG_REGWEN)");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'd300);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'd600);
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,       32'h1);
    csr_wr(AON_TIMER_WDOG_REGWEN_OFFSET,     32'h0);
    check_rd(AON_TIMER_WDOG_REGWEN_OFFSET, 32'h0, "WDOG_REGWEN cleared by writing 0");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'd5);
    csr_wr(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'd6);
    csr_wr(AON_TIMER_WDOG_CTRL_OFFSET,       32'h0);
    check_rd(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'd300, "locked: WDOG_BARK_THOLD write ignored");
    check_rd(AON_TIMER_WDOG_BITE_THOLD_OFFSET, 32'd600, "locked: WDOG_BITE_THOLD write ignored");
    check_rd(AON_TIMER_WDOG_CTRL_OFFSET, 32'h1,
             "locked: WDOG_CTRL write ignored (watchdog cannot be disabled)");
    csr_wr(AON_TIMER_WDOG_REGWEN_OFFSET, 32'h1);
    check_rd(AON_TIMER_WDOG_REGWEN_OFFSET, 32'h0, "WDOG_REGWEN is W0C: writing 1 does not unlock");
    repeat (50) @(posedge clk_aon);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);
    repeat (5) @(posedge clk_aon);
    csr_rd(AON_TIMER_WDOG_COUNT_OFFSET, rd);
    check(rd < 20, $sformatf("locked: pet still works (WDOG_COUNT = %0d after pet)", rd));
    apply_reset();
    check_rd(AON_TIMER_WDOG_REGWEN_OFFSET, 32'h1, "reset clears the lock");

    // -------------------------------------------------------------------------
    $display("---- T8: INTR_TEST");
    csr_wr(AON_TIMER_INTR_TEST_OFFSET, 32'h2);
    repeat (3) @(posedge clk);
    check(intr_bark === 1'b1 && nmi_bark === 1'b1,
          "INTR_TEST.wdog_timer_bark raises the bark interrupt");
    check_rd(AON_TIMER_INTR_STATE_OFFSET, 32'h2, "INTR_STATE shows the test interrupt");
    csr_wr(AON_TIMER_INTR_STATE_OFFSET, 32'h2);
    repeat (3) @(posedge clk);
    check(intr_bark === 1'b0, "W1C clears the test interrupt");

    // -------------------------------------------------------------------------
    $display("---- T9: error responses");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'h1122_3344);
    tl_access(1'b0, 32'h0000_0038, 32'h0, 4'hF, 2'd2, rd, err);
    check(err === 1'b1, "read of unmapped offset 0x38 returns d_error");
    tl_access(1'b1, 32'h0000_003C, 32'hDEAD_BEEF, 4'hF, 2'd2, rd, err);
    check(err === 1'b1, "write to unmapped offset 0x3C returns d_error");
    tl_access(1'b1, 32'(AON_TIMER_WDOG_BARK_THOLD_OFFSET), 32'h0000_00FF, 4'b0001, 2'd0, rd, err);
    check(err === 1'b1, "sub-word (byte) write to WDOG_BARK_THOLD returns d_error");
    check_rd(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'h1122_3344,
             "rejected sub-word write left WDOG_BARK_THOLD unchanged");
    tl_access(1'b1, 32'h0000_0021, 32'h0, 4'hF, 2'd2, rd, err);
    check(err === 1'b1, "misaligned word write (0x21) returns d_error");

    // -------------------------------------------------------------------------
    $display("---- T10: CDC back-pressure");
    csr_wr(AON_TIMER_WDOG_BARK_THOLD_OFFSET, 32'h1);
    csr_rd(AON_TIMER_WDOG_BARK_THOLD_OFFSET, rd);   // same register straight after the write
    stall_rd = last_stall;
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);
    csr_wr(AON_TIMER_WDOG_COUNT_OFFSET, 32'h0);     // back-to-back pets
    stall_wr = last_stall;
    $display("    a_ready low: read-after-write %0d, write-after-write %0d clk_i cycles",
             stall_rd, stall_wr);
    check(stall_rd > 0 && stall_wr > 0,
          "back-to-back access to a CDC register is back-pressured (a_ready low)");
    check(stall_rd < 20*AonDiv + 20 && stall_wr < 20*AonDiv + 20,
          $sformatf("CDC back-pressure is bounded (< %0d clk_i cycles)", 20*AonDiv + 20));

    // -------------------------------------------------------------------------
    $display("---- whole-run monitors");
    check(!alert_seen, "no bus-integrity alert (alerts[0]) during the run");
    check(!wkup_intr_seen, "wakeup-timer interrupt never fired (wakeup timer unused)");

    $display("==== tb_watchdog: %0d checks, %0d errors (WDT_AON_DIV = %0d) ====",
             n_checks, n_errors, AonDiv);
    if (n_errors == 0) $display("TEST PASSED");
    else               $display("TEST FAILED");
    $finish;
  end

endmodule
