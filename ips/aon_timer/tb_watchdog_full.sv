// =============================================================================
// tb_watchdog_full — detailed self-checking testbench for the OpenTitan aon_timer
// =============================================================================
// Scope: the watchdog IP on its own, driven through its TL-UL device port.
// Test content follows OpenTitan's signed-off plan for this block
// (hw/ip/aon_timer/data/aon_timer_testplan.hjson and the common CSR, TL-UL,
// interrupt, alert and bus-integrity testplans it imports).
//
//   A  Registers    A1 csr_hw_reset   A2 csr_rw   A3 csr_bit_bash
//                   A4 csr_aliasing   A5 regwen + lockable registers
//   B  TL-UL        B1 out-of-range address   B2 illegal requests
//                   B3 partial access   B4 outstanding / d_ready back-pressure
//                   B5 bus-integrity faults + reg-we one-hot fault (sec_cm_bus_integrity)
//   C  Alerts       C1 ALERT_TEST
//   D  Interrupts   D1 INTR_TEST, all bit combinations
//   E  Watchdog     E1 count/enable/disable   E2 bark/bite detail   E3 jump
//                   E4 threshold 0 / 2^32 wrap   E5 petting   E6 lock while running
//                   E7 pause_in_sleep   E8 lc_escalate_en_i
//   F  Wakeup       F1 prescaler rate   F2 64-bit carry   F3 threshold + WKUP_CAUSE
//                   F4 prescaler change while running   F5 jump
//   H  CDC          H1 back-to-back same-register back-pressure (measured)
//   G  Stress       G1 random mix of E2/E3/E5/F3/F5/D1   G2 random reset mid-activity
//   Whole run:      no unexpected alert, receiver integrity never fails,
//                   nmi_wdog_timer_bark_o == intr_wdog_timer_bark_o,
//                   aon_timer_rst_req_o never drops while rst_aon_ni is high.
//
// Not tested on purpose: asserting only one of rst_ni / rst_aon_ni. Earl Grey
// drives them from the same reset level (rst_lc_io_div4_n / rst_lc_aon_n), and
// the SoC integration must do the same.
//
// DUT inputs are driven by the testbench: lc_escalate_en_i (lc_esc) and
// sleep_mode_i (sleep_mode). The alert channel is closed by OpenTitan's own
// prim_alert_receiver (tb_files/prim_alert_receiver.sv, unmodified copy).
//
// Run from the aon_timer/ directory on the CentOS tree:
//   xrun -f tb_watchdog_full.f                                  clk_aon_i = clk_i
//   xrun -f tb_watchdog_full.f +define+WDT_AON_DIV=4            clk_aon_i 4x slower
//   xrun -f tb_watchdog_full.f +define+WDT_AON_ASYNC            clk_aon_i 13.7 ns (async)
//   xrun -f tb_watchdog_full.f -svseed random                   new stress sequence
//   +define+WDT_STRESS_ITERS=<n>   stress iterations (default 20)
//   +verbose                       print every passing check
// =============================================================================
`timescale 1ns/1ps

`ifndef WDT_AON_DIV
  `define WDT_AON_DIV 1
`endif
`ifndef WDT_STRESS_ITERS
  `define WDT_STRESS_ITERS 20
`endif

module tb_watchdog_full;
  import tlul_pkg::*;
  import aon_timer_reg_pkg::*;

  localparam int unsigned AonDiv        = `WDT_AON_DIV;
  localparam int unsigned StressIters   = `WDT_STRESS_ITERS;
`ifdef WDT_AON_ASYNC
  localparam bit          AonAsync      = 1'b1;
`else
  localparam bit          AonAsync      = 1'b0;
`endif
  localparam realtime     ClkPeriod     = 10ns;
  localparam realtime     AonPeriod     = AonAsync ? (ClkPeriod * AonDiv + 3.7ns)
                                                   : (ClkPeriod * AonDiv);
  localparam int unsigned AccessTimeout = 2000;  // clk_i cycles per TL-UL channel wait
  localparam int unsigned Slack         = 20;    // clk_aon_i cycles allowed for CDC/sync latency
  localparam int unsigned NumRegs       = 14;

  localparam prim_mubi_pkg::mubi4_t MuFalse = prim_mubi_pkg::MuBi4False;
  localparam prim_mubi_pkg::mubi4_t MuTrue  = prim_mubi_pkg::MuBi4True;

  // Register offsets (index i <-> offset 4*i)
  localparam logic [BlockAw-1:0] OffAlertTest   = AON_TIMER_ALERT_TEST_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupCtrl    = AON_TIMER_WKUP_CTRL_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupTholdHi = AON_TIMER_WKUP_THOLD_HI_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupTholdLo = AON_TIMER_WKUP_THOLD_LO_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupCountHi = AON_TIMER_WKUP_COUNT_HI_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupCountLo = AON_TIMER_WKUP_COUNT_LO_OFFSET;
  localparam logic [BlockAw-1:0] OffRegwen      = AON_TIMER_WDOG_REGWEN_OFFSET;
  localparam logic [BlockAw-1:0] OffWdogCtrl    = AON_TIMER_WDOG_CTRL_OFFSET;
  localparam logic [BlockAw-1:0] OffBark        = AON_TIMER_WDOG_BARK_THOLD_OFFSET;
  localparam logic [BlockAw-1:0] OffBite        = AON_TIMER_WDOG_BITE_THOLD_OFFSET;
  localparam logic [BlockAw-1:0] OffWdogCount   = AON_TIMER_WDOG_COUNT_OFFSET;
  localparam logic [BlockAw-1:0] OffIntrState   = AON_TIMER_INTR_STATE_OFFSET;
  localparam logic [BlockAw-1:0] OffIntrTest    = AON_TIMER_INTR_TEST_OFFSET;
  localparam logic [BlockAw-1:0] OffWkupCause   = AON_TIMER_WKUP_CAUSE_OFFSET;

  // ---------------------------------------------------------------------------
  // Clocks and DUT inputs
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  always #(ClkPeriod/2) clk = ~clk;

  logic clk_aon_gen = 1'b0;
  initial begin
    #3ns;
    forever #(AonPeriod/2) clk_aon_gen = ~clk_aon_gen;
  end

  logic clk_aon;
  assign clk_aon = (AonDiv == 1 && !AonAsync) ? clk : clk_aon_gen;

  logic                rst_n;
  logic                rst_aon_n;
  lc_ctrl_pkg::lc_tx_t lc_esc;
  logic                sleep_mode;

  // ---------------------------------------------------------------------------
  // TL-UL host path: tl_h2d_raw -> integrity generator -> fault injection -> DUT
  // ---------------------------------------------------------------------------
  tl_h2d_t tl_h2d_raw;  // driven by tl_raw()
  tl_h2d_t tl_h2d_gen;  // with correct integrity
  tl_h2d_t tl_h2d;      // after optional single-bit fault injection
  tl_d2h_t tl_d2h;

  tlul_cmd_intg_gen u_intg_gen (
    .tl_i ( tl_h2d_raw ),
    .tl_o ( tl_h2d_gen )
  );

  typedef enum int {InjNone, InjCmdIntg, InjDataIntg, InjAddr, InjMask, InjData} inj_e;
  inj_e        inj_mode;
  int unsigned inj_bit;

  always_comb begin
    tl_h2d = tl_h2d_gen;
    case (inj_mode)
      InjCmdIntg:  tl_h2d.a_user.cmd_intg[inj_bit]  = ~tl_h2d_gen.a_user.cmd_intg[inj_bit];
      InjDataIntg: tl_h2d.a_user.data_intg[inj_bit] = ~tl_h2d_gen.a_user.data_intg[inj_bit];
      InjAddr:     tl_h2d.a_address[inj_bit]        = ~tl_h2d_gen.a_address[inj_bit];
      InjMask:     tl_h2d.a_mask[inj_bit]           = ~tl_h2d_gen.a_mask[inj_bit];
      InjData:     tl_h2d.a_data[inj_bit]           = ~tl_h2d_gen.a_data[inj_bit];
      default:     ;
    endcase
  end

  // ---------------------------------------------------------------------------
  // DUT + alert receiver
  // ---------------------------------------------------------------------------
  prim_alert_pkg::alert_rx_t [NumAlerts-1:0] alert_rx;
  prim_alert_pkg::alert_tx_t [NumAlerts-1:0] alert_tx;

  logic intr_wkup;
  logic intr_bark;
  logic nmi_bark;
  logic wkup_req;
  logic rst_req;

  aon_timer dut (
    .clk_i                     ( clk        ),
    .clk_aon_i                 ( clk_aon    ),
    .rst_ni                    ( rst_n      ),
    .rst_aon_ni                ( rst_aon_n  ),
    .tl_i                      ( tl_h2d     ),
    .tl_o                      ( tl_d2h     ),
    .alert_rx_i                ( alert_rx   ),
    .alert_tx_o                ( alert_tx   ),
    .lc_escalate_en_i          ( lc_esc     ),
    .intr_wkup_timer_expired_o ( intr_wkup  ),
    .intr_wdog_timer_bark_o    ( intr_bark  ),
    .nmi_wdog_timer_bark_o     ( nmi_bark   ),
    .wkup_req_o                ( wkup_req   ),
    .aon_timer_rst_req_o       ( rst_req    ),
    .sleep_mode_i              ( sleep_mode )
  );

  logic rx_alert;
  logic rx_integ_fail;
  logic rx_ping_ok;

  prim_alert_receiver #(
    .AsyncOn ( 1'b1 )
  ) u_alert_rx (
    .clk_i        ( clk           ),
    .rst_ni       ( rst_n         ),
    .init_trig_i  ( MuFalse       ),
    .ping_req_i   ( 1'b0          ),
    .ping_ok_o    ( rx_ping_ok    ),
    .integ_fail_o ( rx_integ_fail ),
    .alert_o      ( rx_alert      ),
    .alert_rx_o   ( alert_rx[0]   ),
    .alert_tx_i   ( alert_tx[0]   )
  );

  initial if (NumAlerts != 1) $fatal(1, "tb_watchdog_full assumes NumAlerts == 1");

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  bit          verbose;
  string       cur_test;
  string       results[$];
  int unsigned n_checks, n_errors;
  int unsigned grp_checks, grp_errors;
  int unsigned last_stall;  // clk_i cycles a_ready was low during the last access

  initial verbose = $test$plusargs("verbose");

  function automatic void check(input bit cond, input string msg);
    n_checks++;
    grp_checks++;
    if (!cond) begin
      n_errors++;
      grp_errors++;
      $display("[%0t]   FAIL [%s]: %s", $time, cur_test, msg);
    end else if (verbose) begin
      $display("[%0t]   pass: %s", $time, msg);
    end
  endfunction

  task automatic begin_test(input string name);
    cur_test   = name;
    grp_checks = 0;
    grp_errors = 0;
    $display("[%0t] ---- %s", $time, name);
  endtask

  task automatic end_test();
    string line;
    line = $sformatf("%s  %s: %0d checks, %0d errors", (grp_errors == 0) ? "PASS" : "FAIL",
                     cur_test, grp_checks, grp_errors);
    results.push_back(line);
    $display("[%0t]      %s", $time, line);
  endtask

  // ---------------------------------------------------------------------------
  // Whole-run monitors
  // ---------------------------------------------------------------------------
  bit          alert_expected;
  int unsigned alert_pulses;       // prim_alert_receiver.alert_o pulses
  int unsigned unexpected_alerts;
  int unsigned integ_fail_pulses;
  int unsigned nmi_mismatch;
  int unsigned rst_req_drops;
  logic        rst_req_q;

  always @(posedge clk) begin
    if (rst_n === 1'b1) begin
      if (rx_alert === 1'b1) begin
        alert_pulses++;
        if (!alert_expected) unexpected_alerts++;
      end
      if (!alert_expected && dut.alerts[0] === 1'b1) unexpected_alerts++;
      if (rx_integ_fail === 1'b1) integ_fail_pulses++;
      if (nmi_bark !== intr_bark) nmi_mismatch++;
    end
  end

  always @(posedge clk_aon or negedge rst_aon_n) begin
    if (!rst_aon_n) begin
      rst_req_q <= 1'b0;
    end else begin
      if (rst_req_q === 1'b1 && rst_req !== 1'b1) rst_req_drops++;
      rst_req_q <= rst_req;
    end
  end

  // ---------------------------------------------------------------------------
  // TL-UL host
  // ---------------------------------------------------------------------------
  // Drives on the falling edge, samples 1 ns later (combinational outputs settled).
  task automatic tl_raw(input  tl_a_op_e              op,
                        input  logic [31:0]           addr,
                        input  logic [31:0]           wdata,
                        input  logic [3:0]            mask,
                        input  logic [1:0]            size,
                        input  prim_mubi_pkg::mubi4_t instr,
                        output logic [31:0]           rdata,
                        output logic                  err);
    int unsigned wait_cnt;

    @(negedge clk);
    tl_h2d_raw                   = TL_H2D_DEFAULT;
    tl_h2d_raw.a_valid           = 1'b1;
    tl_h2d_raw.a_opcode          = op;
    tl_h2d_raw.a_size            = size;
    tl_h2d_raw.a_address         = addr;
    tl_h2d_raw.a_mask            = mask;
    tl_h2d_raw.a_data            = wdata;
    tl_h2d_raw.a_user.instr_type = instr;
    tl_h2d_raw.d_ready           = 1'b1;

    // A channel: a_ready is low while the addressed CDC register is busy
    wait_cnt = 0;
    #1ns;
    while (tl_d2h.a_ready !== 1'b1) begin
      if (wait_cnt == AccessTimeout) begin
        check(1'b0, $sformatf("a_ready timeout, addr 0x%08h", addr));
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
        check(1'b0, $sformatf("d_valid timeout, addr 0x%08h", addr));
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
    tl_raw(PutFullData, 32'(off), data, 4'hF, 2'd2, MuFalse, rd, err);
    if (err !== 1'b0) check(1'b0, $sformatf("write 0x%08h to 0x%02h returned d_error", data, off));
  endtask

  task automatic csr_rd(input logic [BlockAw-1:0] off, output logic [31:0] data);
    logic err;
    tl_raw(Get, 32'(off), 32'h0, 4'hF, 2'd2, MuFalse, data, err);
    if (err !== 1'b0) check(1'b0, $sformatf("read of 0x%02h returned d_error", off));
  endtask

  task automatic check_rd(input logic [BlockAw-1:0] off, input logic [31:0] exp,
                          input string what);
    logic [31:0] rd;
    csr_rd(off, rd);
    check(rd === exp, $sformatf("%s (read 0x%08h, expected 0x%08h)", what, rd, exp));
  endtask

  // ---------------------------------------------------------------------------
  // Register map helpers
  // ---------------------------------------------------------------------------
  function automatic logic [BlockAw-1:0] reg_off(input int unsigned i);
    return BlockAw'(i * 4);
  endfunction

  function automatic string reg_name(input int unsigned i);
    case (i)
      0:       return "ALERT_TEST";
      1:       return "WKUP_CTRL";
      2:       return "WKUP_THOLD_HI";
      3:       return "WKUP_THOLD_LO";
      4:       return "WKUP_COUNT_HI";
      5:       return "WKUP_COUNT_LO";
      6:       return "WDOG_REGWEN";
      7:       return "WDOG_CTRL";
      8:       return "WDOG_BARK_THOLD";
      9:       return "WDOG_BITE_THOLD";
      10:      return "WDOG_COUNT";
      11:      return "INTR_STATE";
      12:      return "INTR_TEST";
      13:      return "WKUP_CAUSE";
      default: return "?";
    endcase
  endfunction

  // Read/write bits checked by the generic CSR tests. The two enable bits are
  // excluded so no timer runs during them; they are checked separately.
  function automatic logic [31:0] rw_mask(input int unsigned i);
    case (i)
      1:                    return 32'h0000_1FFE;  // WKUP_CTRL.prescaler
      2, 3, 4, 5, 8, 9, 10: return 32'hFFFF_FFFF;
      7:                    return 32'h0000_0002;  // WDOG_CTRL.pause_in_sleep
      default:              return 32'h0;
    endcase
  endfunction

  function automatic logic [31:0] en_bit(input int unsigned i);
    return (i == 1 || i == 7) ? 32'h1 : 32'h0;
  endfunction

  function automatic logic [31:0] reg_resval(input int unsigned i);
    return (i == 6) ? 32'h1 : 32'h0;  // only WDOG_REGWEN resets to 1
  endfunction

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  typedef enum {SigBark, SigRstReq, SigWkup} sig_e;

  function automatic logic sig_val(input sig_e s);
    case (s)
      SigBark:   return intr_bark;
      SigRstReq: return rst_req;
      SigWkup:   return intr_wkup;
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

  task automatic aon_cycles(input int unsigned n);
    repeat (n) @(posedge clk_aon);
  endtask

  // Both domains and the alert receiver reset together (as the SoC must do).
  task automatic apply_reset();
    rst_n     = 1'b0;
    rst_aon_n = 1'b0;
    repeat (4) @(posedge clk);
    repeat (4) @(posedge clk_aon);
    @(negedge clk);
    rst_n     = 1'b1;
    rst_aon_n = 1'b1;
    repeat (4) @(posedge clk_aon);
    repeat (30) @(posedge clk);  // alert receiver in-band init handshake
  endtask

  task automatic check_reset_values(input string tag);
    for (int unsigned i = 0; i < NumRegs; i++) begin
      check_rd(reg_off(i), reg_resval(i), $sformatf("%s: %s reset value", tag, reg_name(i)));
    end
    check(intr_bark === 1'b0 && nmi_bark === 1'b0 && intr_wkup === 1'b0 &&
          wkup_req === 1'b0 && rst_req === 1'b0, $sformatf("%s: all outputs idle", tag));
  endtask

  // ---------------------------------------------------------------------------
  // Reusable sequences (used by directed tests and by G1 stress)
  // ---------------------------------------------------------------------------

  // Watchdog with optional pets. Bark fires on count bark+1, bite on count bite+1.
  // Requires pet_period + 20 < bark and bite >= bark + 5.
  task automatic wdog_bark_bite_seq(input int unsigned bark, input int unsigned bite,
                                    input int unsigned n_pets, input int unsigned pet_period);
    int unsigned w, t_bark, t_bite;
    apply_reset();
    csr_wr(OffBark,      bark);
    csr_wr(OffBite,      bite);
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCtrl,  32'h1);
    for (int unsigned i = 0; i < n_pets; i++) begin
      aon_cycles(pet_period);
      csr_wr(OffWdogCount, 32'h0);
    end
    if (n_pets > 0) begin
      check(intr_bark === 1'b0 && rst_req === 1'b0,
            $sformatf("%0d pets every %0d cycles hold off bark (%0d) and bite (%0d)",
                      n_pets, pet_period, bark, bite));
    end
    wait_high(SigBark, bark + 1 + Slack, w);
    t_bark = w;
    check(intr_bark === 1'b1 && t_bark >= bark && t_bark <= bark + 1 + Slack,
          $sformatf("bark after %0d clk_aon cycles (threshold %0d, window %0d..%0d)",
                    t_bark, bark, bark, bark + 1 + Slack));
    check(rst_req === 1'b0 || bite <= t_bark, "no bite before its threshold");
    wait_high(SigRstReq, bite + 1 + Slack, w);
    t_bite = t_bark + w;
    check(rst_req === 1'b1 && t_bite >= bite && t_bite <= bite + 1 + Slack,
          $sformatf("bite after %0d clk_aon cycles (threshold %0d, window %0d..%0d)",
                    t_bite, bite, bite, bite + 1 + Slack));
    apply_reset();
  endtask

  // Wakeup timer: interrupt when the count reaches ticks, i.e. on tick ticks+1,
  // which is (ticks+1)*(prescaler+1) clk_aon cycles after enable.
  task automatic wkup_thold_seq(input int unsigned prescaler, input int unsigned ticks);
    int unsigned w, exp_t;
    logic [31:0] rd;
    apply_reset();
    exp_t = (ticks + 1) * (prescaler + 1);
    csr_wr(OffWkupTholdHi, 32'h0);
    csr_wr(OffWkupTholdLo, ticks);
    csr_wr(OffWkupCtrl, (prescaler << 1) | 1);
    wait_high(SigWkup, exp_t + Slack, w);
    check(intr_wkup === 1'b1 && w + 1 >= exp_t && w <= exp_t + Slack,
          $sformatf("prescaler %0d, threshold %0d: wakeup interrupt after %0d clk_aon cycles (expected %0d..%0d)",
                    prescaler, ticks, w, exp_t - 1, exp_t + Slack));
    check(intr_bark === 1'b0 && rst_req === 1'b0, "wakeup does not touch the watchdog outputs");
    csr_rd(OffIntrState, rd);
    check(rd === 32'h1, $sformatf("INTR_STATE = 0x%0h (expected 0x1, wkup_timer_expired)", rd));
    aon_cycles(5);
    check(wkup_req === 1'b1, "wkup_req_o set by the wakeup timer");
    // Still enabled with the count at/above the threshold: with prescaler > 0 the
    // event repeats on every prescaled tick, so a W1C clear is undone at the next
    // tick (programmer's guide, Interrupt Handling).
    if (prescaler > 0) begin
      csr_wr(OffIntrState, 32'h1);
      aon_cycles(prescaler + 1 + Slack);
      csr_rd(OffIntrState, rd);
      check(rd[0] === 1'b1,
            $sformatf("prescaler %0d, timer still enabled: interrupt re-triggers on the next tick after W1C",
                      prescaler));
    end
    // Programmer's guide sequence: disable the timer, then clear the interrupt
    csr_wr(OffWkupCtrl, prescaler << 1);
    aon_cycles(10);
    csr_wr(OffIntrState, 32'h1);
    repeat (3) @(posedge clk);
    check(intr_wkup === 1'b0, "INTR_STATE W1C clears the wakeup interrupt once the timer is disabled");
    aon_cycles(2 * (prescaler + 1) + Slack);
    check(intr_wkup === 1'b0, "no re-trigger while the wakeup timer is disabled");
    apply_reset();
  endtask

  task automatic intr_test_seq(input logic [1:0] val);
    csr_wr(OffIntrState, 32'h3);
    csr_wr(OffIntrTest, 32'(val));
    repeat (3) @(posedge clk);
    check(intr_wkup === val[0] && intr_bark === val[1] && nmi_bark === val[1],
          $sformatf("INTR_TEST = %02b drives the interrupt pins", val));
    check_rd(OffIntrState, 32'(val), $sformatf("INTR_TEST = %02b sets INTR_STATE", val));
    check(wkup_req === 1'b0, $sformatf("INTR_TEST = %02b does not set wkup_req_o", val));
    if (val[0]) begin
      csr_wr(OffIntrState, 32'h1);
      repeat (3) @(posedge clk);
      check(intr_wkup === 1'b0 && intr_bark === val[1], "W1C bit 0 clears only wkup_timer_expired");
    end
    if (val[1]) begin
      csr_wr(OffIntrState, 32'h2);
      repeat (3) @(posedge clk);
      check(intr_bark === 1'b0 && nmi_bark === 1'b0, "W1C bit 1 clears only wdog_timer_bark");
    end
    check_rd(OffIntrState, 32'h0, "INTR_STATE empty after the clears");
  endtask

  // Lower BARK then BITE below the running count: both must fire promptly.
  task automatic wdog_jump_seq(input int unsigned run, input int unsigned new_bark,
                               input int unsigned new_bite);
    int unsigned w;
    apply_reset();
    csr_wr(OffBark,      32'hFFFF_FFFF);
    csr_wr(OffBite,      32'hFFFF_FFFF);
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCtrl,  32'h1);
    aon_cycles(run);
    check(intr_bark === 1'b0 && rst_req === 1'b0, "no bark/bite with thresholds at maximum");
    csr_wr(OffBark, new_bark);
    wait_high(SigBark, Slack, w);
    check(intr_bark === 1'b1,
          $sformatf("jump: WDOG_BARK_THOLD lowered to %0d under count ~%0d -> bark after %0d cycles",
                    new_bark, run, w));
    csr_wr(OffBite, new_bite);
    wait_high(SigRstReq, Slack, w);
    check(rst_req === 1'b1,
          $sformatf("jump: WDOG_BITE_THOLD lowered to %0d under count ~%0d -> bite after %0d cycles",
                    new_bite, run, w));
    apply_reset();
  endtask

  // Lower WKUP_THOLD (LO first, then HI) below the running count (prescaler 0).
  task automatic wkup_jump_seq(input int unsigned run, input int unsigned new_thold);
    int unsigned w;
    apply_reset();
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl,    32'h1);
    aon_cycles(run);
    csr_wr(OffWkupTholdLo, new_thold);
    aon_cycles(Slack);
    check(intr_wkup === 1'b0, "WKUP_THOLD_HI still maximum: no wakeup yet");
    csr_wr(OffWkupTholdHi, 32'h0);
    wait_high(SigWkup, Slack, w);
    check(intr_wkup === 1'b1,
          $sformatf("jump: WKUP_THOLD lowered to %0d under count ~%0d -> wakeup after %0d cycles",
                    new_thold, run, w));
    apply_reset();
  endtask

  // ---------------------------------------------------------------------------
  // A. Registers
  // ---------------------------------------------------------------------------
  task automatic test_csr_hw_reset();
    begin_test("A1 csr_hw_reset");
    check_reset_values("power-on");
    // Random values into every writable register. ALERT_TEST is left out: it
    // sends an alert and is covered by C1.
    for (int unsigned i = 1; i < NumRegs; i++) csr_wr(reg_off(i), $urandom());
    apply_reset();
    check_reset_values("after random writes + reset");
    end_test();
  endtask

  task automatic test_csr_rw();
    logic [31:0] v;
    begin_test("A2 csr_rw");
    apply_reset();
    for (int unsigned i = 0; i < NumRegs; i++) begin
      if (rw_mask(i) != 32'h0) begin
        v = $urandom() & ~en_bit(i);
        csr_wr(reg_off(i), v);
        check_rd(reg_off(i), v & rw_mask(i), $sformatf("%s write 0x%08h", reg_name(i), v));
      end
    end
    // Enable bits, with thresholds at maximum so nothing fires
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCountHi, 32'h0);
    csr_wr(OffWkupCountLo, 32'h0);
    csr_wr(OffBark,        32'hFFFF_FFFF);
    csr_wr(OffBite,        32'hFFFF_FFFF);
    csr_wr(OffWdogCount,   32'h0);
    csr_wr(OffWkupCtrl, 32'h1);
    check_rd(OffWkupCtrl, 32'h1, "WKUP_CTRL.enable = 1");
    csr_wr(OffWkupCtrl, 32'h0);
    check_rd(OffWkupCtrl, 32'h0, "WKUP_CTRL.enable = 0");
    csr_wr(OffWdogCtrl, 32'h1);
    check_rd(OffWdogCtrl, 32'h1, "WDOG_CTRL.enable = 1");
    csr_wr(OffWdogCtrl, 32'h0);
    check_rd(OffWdogCtrl, 32'h0, "WDOG_CTRL.enable = 0");
    // Access policies of the other registers
    csr_wr(OffRegwen, 32'hFFFF_FFFF);
    check_rd(OffRegwen, 32'h1, "WDOG_REGWEN rw0c: writing 1 keeps it 1");
    csr_wr(OffWkupCause, 32'hFFFF_FFFF);
    check_rd(OffWkupCause, 32'h0, "WKUP_CAUSE rw0c: software cannot set it");
    csr_wr(OffIntrState, 32'hFFFF_FFFF);
    check_rd(OffIntrState, 32'h0, "INTR_STATE rw1c: software cannot set it");
    csr_wr(OffIntrTest, 32'h0);
    check_rd(OffIntrTest, 32'h0, "INTR_TEST is write-only (reads 0)");
    check_rd(OffAlertTest, 32'h0, "ALERT_TEST is write-only (reads 0)");
    apply_reset();
    end_test();
  endtask

  task automatic test_csr_bit_bash();
    logic [31:0] v, eb;
    begin_test("A3 csr_bit_bash");
    apply_reset();
    for (int unsigned i = 0; i < NumRegs; i++) begin
      if (rw_mask(i) != 32'h0) begin
        eb = en_bit(i);
        for (int unsigned b = 0; b < 32; b++) begin
          if (eb[b]) continue;
          v = 32'h1 << b;
          csr_wr(reg_off(i), v);
          check_rd(reg_off(i), v & rw_mask(i), $sformatf("%s walking 1, bit %0d", reg_name(i), b));
          v = ~(32'h1 << b) & ~eb;
          csr_wr(reg_off(i), v);
          check_rd(reg_off(i), v & rw_mask(i), $sformatf("%s walking 0, bit %0d", reg_name(i), b));
        end
      end
    end
    apply_reset();
    end_test();
  endtask

  task automatic test_csr_aliasing();
    logic [31:0] exp_val [NumRegs];
    logic [31:0] v;
    begin_test("A4 csr_aliasing");
    apply_reset();
    for (int unsigned i = 0; i < NumRegs; i++) exp_val[i] = reg_resval(i);
    for (int unsigned i = 0; i < NumRegs; i++) begin
      if (rw_mask(i) != 32'h0) begin
        v = $urandom() & ~en_bit(i);
        csr_wr(reg_off(i), v);
        exp_val[i] = v & rw_mask(i);
        for (int unsigned j = 0; j < NumRegs; j++) begin
          check_rd(reg_off(j), exp_val[j],
                   $sformatf("after writing %s, %s", reg_name(i), reg_name(j)));
        end
      end
    end
    apply_reset();
    end_test();
  endtask

  task automatic test_regwen();
    begin_test("A5 regwen + lockable registers");
    apply_reset();
    csr_wr(OffBark, 32'h1111_1111);
    check_rd(OffBark, 32'h1111_1111, "unlocked: WDOG_BARK_THOLD takes a new value");
    csr_wr(OffBite, 32'h2222_2222);
    check_rd(OffBite, 32'h2222_2222, "unlocked: WDOG_BITE_THOLD takes a new value");
    csr_wr(OffWdogCtrl, 32'h2);
    check_rd(OffWdogCtrl, 32'h2, "unlocked: WDOG_CTRL takes a new value");
    csr_wr(OffRegwen, 32'h0);
    check_rd(OffRegwen, 32'h0, "WDOG_REGWEN cleared by writing 0");
    csr_wr(OffBark, 32'h3333_3333);
    check_rd(OffBark, 32'h1111_1111, "locked: WDOG_BARK_THOLD write ignored");
    csr_wr(OffBite, 32'h4444_4444);
    check_rd(OffBite, 32'h2222_2222, "locked: WDOG_BITE_THOLD write ignored");
    csr_wr(OffWdogCtrl, 32'h1);
    check_rd(OffWdogCtrl, 32'h2, "locked: WDOG_CTRL write ignored");
    csr_wr(OffWdogCount, 32'h0000_0055);
    check_rd(OffWdogCount, 32'h0000_0055, "locked: WDOG_COUNT is not lockable");
    csr_wr(OffWkupCtrl, 32'h0000_1578);
    check_rd(OffWkupCtrl, 32'h0000_1578, "locked: wakeup registers are not lockable");
    csr_wr(OffRegwen, 32'h1);
    check_rd(OffRegwen, 32'h0, "WDOG_REGWEN cannot be set back to 1 by software");
    apply_reset();
    check_rd(OffRegwen, 32'h1, "reset clears the lock");
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // B. TL-UL device
  // ---------------------------------------------------------------------------
  task automatic test_tl_oob();
    logic [31:0] rd;
    logic        err;
    begin_test("B1 tl_d_oob_addr_access");
    apply_reset();
    csr_wr(OffBark, 32'h1234_5678);
    tl_raw(Get, 32'h0000_0038, 32'h0, 4'hF, 2'd2, MuFalse, rd, err);
    check(err === 1'b1, "read of unmapped offset 0x38 returns d_error");
    tl_raw(Get, 32'h0000_003C, 32'h0, 4'hF, 2'd2, MuFalse, rd, err);
    check(err === 1'b1, "read of unmapped offset 0x3C returns d_error");
    tl_raw(PutFullData, 32'h0000_0038, 32'hFFFF_FFFF, 4'hF, 2'd2, MuFalse, rd, err);
    check(err === 1'b1, "write to unmapped offset 0x38 returns d_error");
    tl_raw(PutFullData, 32'h0000_003C, 32'hFFFF_FFFF, 4'hF, 2'd2, MuFalse, rd, err);
    check(err === 1'b1, "write to unmapped offset 0x3C returns d_error");
    check_rd(OffBark, 32'h1234_5678, "unmapped writes had no side effect");
    apply_reset();
    end_test();
  endtask

  task automatic illegal(input tl_a_op_e op, input logic [31:0] addr, input logic [3:0] mask,
                         input logic [1:0] size, input prim_mubi_pkg::mubi4_t instr,
                         input string what);
    logic [31:0] rd;
    logic        err;
    tl_raw(op, addr, 32'hFFFF_0000, mask, size, instr, rd, err);
    check(err === 1'b1, $sformatf("%s -> d_error", what));
  endtask

  task automatic test_tl_illegal();
    logic [31:0] a;
    begin_test("B2 tl_d_illegal_access");
    apply_reset();
    a = 32'(OffBark);
    csr_wr(OffBark, 32'h5555_0000);
    illegal(tl_a_op_e'(3'h2), a,     4'hF,    2'd2, MuFalse, "opcode 3'h2 (ArithmeticData)");
    illegal(tl_a_op_e'(3'h3), a,     4'hF,    2'd2, MuFalse, "opcode 3'h3 (LogicalData)");
    illegal(tl_a_op_e'(3'h5), a,     4'hF,    2'd2, MuFalse, "opcode 3'h5 (Intent)");
    illegal(tl_a_op_e'(3'h6), a,     4'hF,    2'd2, MuFalse, "opcode 3'h6");
    illegal(tl_a_op_e'(3'h7), a,     4'hF,    2'd2, MuFalse, "opcode 3'h7");
    illegal(PutFullData,      a,     4'b0111, 2'd2, MuFalse, "PutFullData with mask 0111");
    illegal(PutFullData,      a,     4'b1110, 2'd2, MuFalse, "PutFullData with mask 1110");
    illegal(PutPartialData,   a,     4'b0010, 2'd0, MuFalse, "size 0 at byte 0 with mask 0010");
    illegal(PutPartialData,   a + 1, 4'b0001, 2'd0, MuFalse, "size 0 at byte 1 with mask 0001");
    illegal(PutFullData,      a + 2, 4'hF,    2'd2, MuFalse, "size 2 at address +2 (misaligned)");
    illegal(PutPartialData,   a + 1, 4'b0110, 2'd1, MuFalse, "size 1 at address +1 (misaligned)");
    illegal(PutFullData,      a,     4'hF,    2'd3, MuFalse, "write with a_size = 3");
    illegal(PutFullData,      a,     4'hF,    2'd2, MuTrue,  "write with instr_type = MuBi4True");
    illegal(PutFullData,      a,     4'hF,    2'd2, prim_mubi_pkg::mubi4_t'(4'h0),
            "write with invalid instr_type 4'h0");
    illegal(Get,              a,     4'hF,    2'd2, MuTrue,  "instruction fetch (instr_type = MuBi4True)");
    illegal(Get,              a,     4'hF,    2'd2, prim_mubi_pkg::mubi4_t'(4'h0),
            "read with invalid instr_type 4'h0");
    illegal(Get,              a,     4'hF,    2'd3, MuFalse, "read with a_size = 3");
    check_rd(OffBark, 32'h5555_0000, "no illegal write changed WDOG_BARK_THOLD");
    check(dut.alerts[0] === 1'b0, "illegal requests raise no integrity fault");
    apply_reset();
    end_test();
  endtask

  task automatic test_tl_partial();
    logic [31:0] rd, v, cur;
    logic        err;
    logic [3:0]  permit, bad;
    begin_test("B3 tl_d_partial_access");
    apply_reset();
    for (int unsigned i = 0; i < NumRegs; i++) begin
      if (rw_mask(i) != 32'h0) begin
        permit = AON_TIMER_PERMIT[i];
        cur    = 32'h5A5A_5A5A & ~en_bit(i);
        csr_wr(reg_off(i), cur);
        cur    = cur & rw_mask(i);

        // Byte read at +1 returns the whole register
        tl_raw(Get, 32'(reg_off(i)) + 1, 32'h0, 4'b0010, 2'd0, MuFalse, rd, err);
        check(err === 1'b0 && rd === cur,
              $sformatf("%s: byte read at +1 returns the full word (0x%08h)", reg_name(i), rd));

        // Byte enables equal to AON_TIMER_PERMIT are accepted
        v = 32'hA5C3_96E1 & ~en_bit(i);
        tl_raw(PutPartialData, 32'(reg_off(i)), v, permit, 2'd2, MuFalse, rd, err);
        check(err === 1'b0, $sformatf("%s: partial write with mask %04b (= PERMIT) accepted",
                                      reg_name(i), permit));
        cur = v & rw_mask(i);
        check_rd(reg_off(i), cur, $sformatf("%s: value after mask-%04b write", reg_name(i), permit));

        // Smallest aligned access covering the register (byte or half-word registers)
        if (permit == 4'b0001 || permit == 4'b0011) begin
          v = ~cur & rw_mask(i);
          tl_raw(PutPartialData, 32'(reg_off(i)), v, permit,
                 (permit == 4'b0001) ? 2'd0 : 2'd1, MuFalse, rd, err);
          check(err === 1'b0, $sformatf("%s: %s write accepted", reg_name(i),
                                        (permit == 4'b0001) ? "byte" : "half-word"));
          cur = v;
          check_rd(reg_off(i), cur, $sformatf("%s: value after the %s write", reg_name(i),
                                              (permit == 4'b0001) ? "byte" : "half-word"));
        end

        // Byte enables missing part of the register are rejected
        bad = (permit == 4'hF) ? 4'b0111 : ((permit == 4'b0011) ? 4'b0001 : 4'b0010);
        tl_raw(PutPartialData, 32'(reg_off(i)), 32'hFFFF_FFFF & ~en_bit(i), bad, 2'd2, MuFalse,
               rd, err);
        check(err === 1'b1, $sformatf("%s: mask %04b (misses PERMIT %04b) rejected",
                                      reg_name(i), bad, permit));
        check_rd(reg_off(i), cur, $sformatf("%s: unchanged after the rejected write", reg_name(i)));

        // Sub-word write at a non-word-aligned address is rejected
        tl_raw(PutPartialData, 32'(reg_off(i)) + 1, 32'hFFFF_FFFF & ~en_bit(i), 4'b0010, 2'd0,
               MuFalse, rd, err);
        check(err === 1'b1, $sformatf("%s: byte write at +1 (not word aligned) rejected",
                                      reg_name(i)));
        check_rd(reg_off(i), cur, $sformatf("%s: unchanged after the unaligned write",
                                            reg_name(i)));
      end
    end
    apply_reset();
    end_test();
  endtask

  task automatic test_tl_outstanding();
    logic [31:0] d0;
    int unsigned bad_cycles;
    begin_test("B4 tl_d_outstanding_access");
    apply_reset();
    csr_wr(OffBark, 32'hAAAA_0001);
    csr_wr(OffBite, 32'hBBBB_0002);
    aon_cycles(50);  // let both CDC transfers finish

    // Request A: read WDOG_BARK_THOLD with d_ready held low
    @(negedge clk);
    tl_h2d_raw           = TL_H2D_DEFAULT;
    tl_h2d_raw.a_valid   = 1'b1;
    tl_h2d_raw.a_opcode  = Get;
    tl_h2d_raw.a_size    = 2'd2;
    tl_h2d_raw.a_mask    = 4'hF;
    tl_h2d_raw.a_address = 32'(OffBark);
    tl_h2d_raw.d_ready   = 1'b0;
    #1ns;
    check(tl_d2h.a_ready === 1'b1, "idle device accepts request A");
    @(posedge clk);

    // Request B presented right away, response A not consumed
    @(negedge clk);
    tl_h2d_raw.a_address = 32'(OffBite);
    #1ns;
    check(tl_d2h.d_valid === 1'b1 && tl_d2h.d_data === 32'hAAAA_0001,
          "response A (WDOG_BARK_THOLD) valid");
    check(tl_d2h.a_ready === 1'b0, "request B stalled while response A is outstanding");
    d0         = tl_d2h.d_data;
    bad_cycles = 0;
    repeat (5) begin
      @(negedge clk);
      #1ns;
      if (tl_d2h.d_valid !== 1'b1 || tl_d2h.d_data !== d0 || tl_d2h.a_ready !== 1'b0) begin
        bad_cycles++;
      end
    end
    check(bad_cycles == 0, "d_valid/d_data held and a_ready low for 5 cycles with d_ready = 0");

    // Consume response A; request B must go next
    tl_h2d_raw.d_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    #1ns;
    check(tl_d2h.a_ready === 1'b1, "request B accepted once response A is consumed");
    @(posedge clk);
    @(negedge clk);
    tl_h2d_raw.a_valid = 1'b0;
    #1ns;
    check(tl_d2h.d_valid === 1'b1 && tl_d2h.d_data === 32'hBBBB_0002 && tl_d2h.d_error === 1'b0,
          "response B returns WDOG_BITE_THOLD");
    @(posedge clk);
    tl_h2d_raw = TL_H2D_DEFAULT;
    apply_reset();
    end_test();
  endtask

  // One corrupted transaction: expect d_error, no register update, and a fatal
  // alert that keeps firing until rst_ni.
  task automatic intg_case(input inj_e mode, input int unsigned bit_idx, input bit is_write,
                           input string what);
    logic [31:0] rd;
    logic        err;
    int unsigned a0;
    apply_reset();
    csr_wr(OffBark,      32'h0000_1111);
    csr_wr(OffWdogCount, 32'h0000_2222);
    aon_cycles(20);
    alert_expected = 1'b1;
    a0             = alert_pulses;
    inj_mode       = mode;
    inj_bit        = bit_idx;
    if (is_write) tl_raw(PutFullData, 32'(OffBark), 32'hDEAD_0000, 4'hF, 2'd2, MuFalse, rd, err);
    else          tl_raw(Get,         32'(OffBark), 32'h0,         4'hF, 2'd2, MuFalse, rd, err);
    inj_mode       = InjNone;
    check(err === 1'b1, $sformatf("%s: d_error", what));
    check(dut.alerts[0] === 1'b1, $sformatf("%s: integrity fault latched", what));
    repeat (400) @(posedge clk);
    check(alert_pulses - a0 >= 2,
          $sformatf("%s: fatal alert keeps firing (%0d alerts in 400 cycles)", what,
                    alert_pulses - a0));
    check_rd(OffBark,      32'h0000_1111, $sformatf("%s: WDOG_BARK_THOLD not written", what));
    check_rd(OffWdogCount, 32'h0000_2222, $sformatf("%s: WDOG_COUNT not written", what));
    apply_reset();
    check(dut.alerts[0] === 1'b0, $sformatf("%s: rst_ni clears the fault", what));
    a0 = alert_pulses;
    repeat (200) @(posedge clk);
    check(alert_pulses == a0, $sformatf("%s: no alerts after reset", what));
    alert_expected = 1'b0;
  endtask

  task automatic test_tl_intg_err();
    int unsigned a0;
    begin_test("B5 tl_intg_err (sec_cm_bus_integrity)");
    intg_case(InjCmdIntg,  0,  1'b1, "write, cmd_intg bit 0 flipped");
    intg_case(InjCmdIntg,  6,  1'b1, "write, cmd_intg bit 6 flipped");
    intg_case(InjDataIntg, 3,  1'b1, "write, data_intg bit 3 flipped");
    intg_case(InjAddr,     3,  1'b1, "write, address bit 3 flipped (0x20 -> 0x28)");
    intg_case(InjAddr,     12, 1'b1, "write, address bit 12 flipped (decoder ignores it)");
    intg_case(InjMask,     0,  1'b1, "write, a_mask bit 0 flipped");
    intg_case(InjData,     0,  1'b1, "write, a_data bit 0 flipped");
    intg_case(InjData,     31, 1'b1, "write, a_data bit 31 flipped");
    intg_case(InjCmdIntg,  2,  1'b0, "read, cmd_intg bit 2 flipped");

    // Fault in the register write-enable one-hot checker
    apply_reset();
    alert_expected = 1'b1;
    a0             = alert_pulses;
    force dut.u_reg.u_prim_reg_we_check.oh_buf = 14'h3;
    repeat (2) @(posedge clk);
    release dut.u_reg.u_prim_reg_we_check.oh_buf;
    check(dut.alerts[0] === 1'b1, "reg-we one-hot fault latched");
    repeat (400) @(posedge clk);
    check(alert_pulses - a0 >= 2,
          $sformatf("reg-we one-hot fault: fatal alert keeps firing (%0d alerts)", alert_pulses - a0));
    apply_reset();
    check(dut.alerts[0] === 1'b0, "reg-we one-hot fault cleared by rst_ni");
    alert_expected = 1'b0;
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // C / D. Alerts and interrupts
  // ---------------------------------------------------------------------------
  task automatic test_alert_test();
    int unsigned a0;
    begin_test("C1 alert_test");
    apply_reset();
    alert_expected = 1'b1;
    a0             = alert_pulses;
    csr_wr(OffAlertTest, 32'h1);
    repeat (300) @(posedge clk);
    check(alert_pulses - a0 == 1,
          $sformatf("ALERT_TEST sends exactly one alert (%0d)", alert_pulses - a0));
    check(dut.alerts[0] === 1'b0, "a test alert does not latch the fatal fault");
    csr_wr(OffAlertTest, 32'h0);
    repeat (300) @(posedge clk);
    check(alert_pulses - a0 == 1, "writing 0 to ALERT_TEST sends nothing");
    alert_expected = 1'b0;
    apply_reset();
    end_test();
  endtask

  task automatic test_intr_test();
    begin_test("D1 intr_test");
    apply_reset();
    intr_test_seq(2'b01);
    intr_test_seq(2'b10);
    intr_test_seq(2'b11);
    apply_reset();
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // E. Watchdog
  // ---------------------------------------------------------------------------
  task automatic test_wdog_count();
    logic [31:0] c1, c2, c3, c4;
    begin_test("E1 watchdog count / enable / disable");
    apply_reset();
    csr_wr(OffBark,      32'hFFFF_FFF0);
    csr_wr(OffBite,      32'hFFFF_FFFF);
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCtrl,  32'h1);
    aon_cycles(100);
    csr_rd(OffWdogCount, c1);
    check(c1 >= 70 && c1 <= 110,
          $sformatf("WDOG_COUNT = %0d after 100 clk_aon cycles (expected 70..110)", c1));
    aon_cycles(50);
    csr_rd(OffWdogCount, c2);
    check(c2 > c1 && (c2 - c1) >= 35 && (c2 - c1) <= 65,
          $sformatf("WDOG_COUNT advanced by %0d in 50 clk_aon cycles (expected 35..65)", c2 - c1));
    csr_wr(OffWdogCtrl, 32'h0);
    aon_cycles(20);
    csr_rd(OffWdogCount, c3);
    aon_cycles(30);
    csr_rd(OffWdogCount, c4);
    check(c4 === c3, $sformatf("WDOG_CTRL.enable = 0 stops the count (%0d -> %0d)", c3, c4));
    apply_reset();
    end_test();
  endtask

  task automatic test_wdog_bark_bite_detail();
    logic [31:0] rd;
    int unsigned w;
    begin_test("E2 bark / bite detail");
    apply_reset();
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffBite,      32'd1000);
    csr_wr(OffBark,      32'd40);
    csr_wr(OffIntrState, 32'h3);
    check(intr_bark === 1'b0, "no bark before enable");
    csr_wr(OffWdogCtrl, 32'h1);
    wait_high(SigBark, 41 + Slack, w);
    check(intr_bark === 1'b1 && w >= 40 && w <= 41 + Slack,
          $sformatf("bark after %0d clk_aon cycles (threshold 40, fires on count 41)", w));
    check(nmi_bark === 1'b1, "nmi_wdog_timer_bark_o follows the bark");
    check(rst_req === 1'b0, "no bite at bark");
    csr_rd(OffIntrState, rd);
    check(rd === 32'h2, $sformatf("INTR_STATE = 0x%0h (expected 0x2, wdog_timer_bark)", rd));
    aon_cycles(5);
    check(wkup_req === 1'b1, "wkup_req_o set by the bark");
    csr_wr(OffIntrState, 32'h2);
    repeat (3) @(posedge clk);
    check(intr_bark === 1'b0 && nmi_bark === 1'b0, "INTR_STATE W1C clears the bark interrupt");
    aon_cycles(20);
    check(intr_bark === 1'b0, "bark is edge-triggered: no re-assert while the count stays above it");
    csr_wr(OffWdogCount, 32'h0);
    wait_high(SigBark, 41 + Slack, w);
    check(intr_bark === 1'b1, $sformatf("bark re-fires after a pet (%0d cycles)", w));
    csr_wr(OffWdogCtrl, 32'h0);
    aon_cycles(10);
    csr_wr(OffIntrState, 32'h3);
    csr_wr(OffWkupCause, 32'h0);
    aon_cycles(10);
    check(intr_bark === 1'b0 && wkup_req === 1'b0,
          "bark interrupt and wkup_req_o clear once the watchdog is stopped");

    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffBark,      32'd20);
    csr_wr(OffBite,      32'd60);
    csr_wr(OffIntrState, 32'h3);
    csr_wr(OffWdogCtrl,  32'h1);
    wait_high(SigRstReq, 61 + Slack, w);
    check(rst_req === 1'b1 && w >= 60 && w <= 61 + Slack,
          $sformatf("bite after %0d clk_aon cycles (threshold 60, fires on count 61)", w));
    check(intr_bark === 1'b1, "bark fired before the bite");
    csr_wr(OffWdogCtrl,  32'h0);
    csr_wr(OffWdogCount, 32'h0);
    aon_cycles(20);
    check(rst_req === 1'b1, "aon_timer_rst_req_o is sticky: disable + pet do not clear it");
    apply_reset();
    check(rst_req === 1'b0, "aon_timer_rst_req_o clears on rst_aon_ni");
    end_test();
  endtask

  task automatic test_wdog_jump();
    begin_test("E3 watchdog jump (thresholds lowered under the count)");
    wdog_jump_seq(100, 50, 60);
    wdog_jump_seq(150, 0, 10);
    end_test();
  endtask

  task automatic test_wdog_edges();
    logic [31:0] c;
    int unsigned w;
    begin_test("E4 threshold 0 / 2^32 wrap");
    apply_reset();
    csr_wr(OffBite,      32'hFFFF_FFFF);
    csr_wr(OffBark,      32'h0);
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCtrl,  32'h1);
    wait_high(SigBark, Slack, w);
    check(intr_bark === 1'b1,
          $sformatf("WDOG_BARK_THOLD = 0 barks on the first count (%0d cycles)", w));
    apply_reset();

    csr_wr(OffBark,      32'hFFFF_FFFF);
    csr_wr(OffBite,      32'hFFFF_FFFF);
    csr_wr(OffWdogCount, 32'hFFFF_FFF0);
    csr_wr(OffWdogCtrl,  32'h1);
    wait_high(SigRstReq, 16 + Slack, w);
    check(rst_req === 1'b1,
          $sformatf("count 0xFFFF_FFFF meets BITE = 0xFFFF_FFFF (bite after %0d cycles)", w));
    aon_cycles(5);
    check(intr_bark === 1'b1, "count 0xFFFF_FFFF meets BARK = 0xFFFF_FFFF");
    aon_cycles(20);
    csr_rd(OffWdogCount, c);
    check(c < 64, $sformatf("WDOG_COUNT wraps from 0xFFFF_FFFF to 0 (now %0d)", c));
    apply_reset();
    end_test();
  endtask

  task automatic test_wdog_pet();
    begin_test("E5 petting");
    wdog_bark_bite_seq(100, 200, 10, 40);
    wdog_bark_bite_seq(60, 65, 3, 30);
    end_test();
  endtask

  task automatic test_lock_running();
    logic [31:0] rd;
    int unsigned w;
    begin_test("E6 lock while running");
    apply_reset();
    csr_wr(OffBark,      32'd150);
    csr_wr(OffBite,      32'd1000);
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCtrl,  32'h1);
    csr_wr(OffRegwen,    32'h0);
    csr_wr(OffWdogCtrl,  32'h0);
    check_rd(OffWdogCtrl, 32'h1, "locked: the watchdog cannot be disabled");
    csr_wr(OffBark, 32'hFFFF_FFFF);
    check_rd(OffBark, 32'd150, "locked: WDOG_BARK_THOLD cannot be raised");
    aon_cycles(50);
    csr_wr(OffWdogCount, 32'h0);
    aon_cycles(5);
    csr_rd(OffWdogCount, rd);
    check(rd < 20, $sformatf("locked: petting still works (WDOG_COUNT = %0d after the pet)", rd));
    wait_high(SigBark, 151 + Slack, w);
    check(intr_bark === 1'b1, $sformatf("locked watchdog still barks (%0d cycles)", w));
    apply_reset();
    end_test();
  endtask

  task automatic test_pause_in_sleep();
    logic [31:0] c1, c2, c3, c4, c5, w1, w2;
    begin_test("E7 pause_in_sleep / sleep_mode_i");
    apply_reset();
    csr_wr(OffBark,        32'hFFFF_FFFF);
    csr_wr(OffBite,        32'hFFFF_FFFF);
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl,    32'h1);
    csr_wr(OffWdogCtrl,    32'h3);  // enable + pause_in_sleep
    sleep_mode = 1'b1;
    aon_cycles(20);
    csr_rd(OffWdogCount,   c1);
    csr_rd(OffWkupCountLo, w1);
    aon_cycles(40);
    csr_rd(OffWdogCount,   c2);
    csr_rd(OffWkupCountLo, w2);
    check(c2 === c1, $sformatf("pause_in_sleep = 1, sleep_mode_i = 1: WDOG_COUNT paused (%0d -> %0d)",
                               c1, c2));
    check(w2 > w1, $sformatf("wakeup timer keeps counting in sleep (%0d -> %0d)", w1, w2));
    sleep_mode = 1'b0;
    aon_cycles(40);
    csr_rd(OffWdogCount, c3);
    check(c3 > c2, $sformatf("watchdog resumes when sleep_mode_i drops (%0d -> %0d)", c2, c3));
    csr_wr(OffWdogCtrl, 32'h1);     // pause_in_sleep = 0
    sleep_mode = 1'b1;
    aon_cycles(10);
    csr_rd(OffWdogCount, c4);
    aon_cycles(40);
    csr_rd(OffWdogCount, c5);
    check(c5 > c4, $sformatf("pause_in_sleep = 0: watchdog counts in sleep (%0d -> %0d)", c4, c5));
    sleep_mode = 1'b0;
    apply_reset();
    end_test();
  endtask

  task automatic test_lc_escalate();
    logic [31:0] c1, c2, c3, c4, c5, w1, w2;
    int unsigned w;
    begin_test("E8 lc_escalate_en_i");
    apply_reset();
    csr_wr(OffBark,        32'hFFFF_FFFF);
    csr_wr(OffBite,        32'hFFFF_FFFF);
    csr_wr(OffWdogCount,   32'h0);
    csr_wr(OffWdogCtrl,    32'h1);
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl,    32'h1);
    aon_cycles(50);
    lc_esc = lc_ctrl_pkg::On;
    aon_cycles(20);
    csr_rd(OffWdogCount,   c1);
    csr_rd(OffWkupCountLo, w1);
    aon_cycles(40);
    csr_rd(OffWdogCount,   c2);
    csr_rd(OffWkupCountLo, w2);
    check(c1 === c2 && w1 === w2,
          $sformatf("lc_escalate_en_i = On freezes both timers (wdog %0d -> %0d, wkup %0d -> %0d)",
                    c1, c2, w1, w2));
    csr_wr(OffBark,        32'd5);
    csr_wr(OffWkupTholdHi, 32'h0);
    csr_wr(OffWkupTholdLo, 32'd5);
    aon_cycles(40);
    check(intr_bark === 1'b0 && rst_req === 1'b0 && intr_wkup === 1'b0,
          "no bark, bite or wakeup while escalated, even with thresholds under the count");
    lc_esc = lc_ctrl_pkg::lc_tx_t'(4'b0000);
    aon_cycles(20);
    csr_rd(OffWdogCount, c3);
    aon_cycles(40);
    csr_rd(OffWdogCount, c4);
    check(c3 === c4 && c3 === c2,
          $sformatf("invalid value 4'b0000 also freezes the timers (strict Off check, %0d -> %0d)",
                    c3, c4));
    check(intr_bark === 1'b0 && intr_wkup === 1'b0, "still no bark or wakeup with 4'b0000");
    lc_esc = lc_ctrl_pkg::Off;
    wait_high(SigBark, Slack, w);
    check(intr_bark === 1'b1,
          $sformatf("bark %0d cycles after lc_escalate_en_i returns to Off", w));
    wait_high(SigWkup, Slack, w);
    check(intr_wkup === 1'b1,
          $sformatf("wakeup %0d cycles after lc_escalate_en_i returns to Off", w));
    csr_rd(OffWdogCount, c5);
    check(c5 > c4, $sformatf("watchdog count resumes (%0d -> %0d)", c4, c5));
    apply_reset();
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // F. Wakeup timer
  // ---------------------------------------------------------------------------
  task automatic wkup_rate(input int unsigned prescaler, input int unsigned ticks);
    logic [31:0] lo, hi;
    apply_reset();
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl, (prescaler << 1) | 1);
    aon_cycles(ticks * (prescaler + 1));
    csr_wr(OffWkupCtrl, prescaler << 1);
    aon_cycles(10);
    csr_rd(OffWkupCountLo, lo);
    csr_rd(OffWkupCountHi, hi);
    check(hi === 32'h0 && lo + 4 >= ticks && lo <= ticks + 4,
          $sformatf("prescaler %0d: WKUP_COUNT = %0d after %0d x %0d clk_aon cycles (expected %0d +/- 4)",
                    prescaler, lo, ticks, prescaler + 1, ticks));
  endtask

  task automatic test_wkup_rate();
    begin_test("F1 wakeup prescaler rate");
    wkup_rate(0, 40);
    wkup_rate(1, 40);
    wkup_rate(7, 40);
    wkup_thold_seq(12'hFFF, 1);  // maximum prescaler: interrupt after 2 x 4096 cycles
    apply_reset();
    end_test();
  endtask

  task automatic test_wkup_carry();
    logic [31:0] lo, hi;
    begin_test("F2 wakeup 64-bit carry");
    apply_reset();
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCountHi, 32'h0);
    csr_wr(OffWkupCountLo, 32'hFFFF_FFF0);
    csr_wr(OffWkupCtrl,    32'h1);
    aon_cycles(40);
    csr_wr(OffWkupCtrl,    32'h0);
    aon_cycles(10);
    csr_rd(OffWkupCountHi, hi);
    csr_rd(OffWkupCountLo, lo);
    check(hi === 32'h1 && lo >= 32'h10 && lo <= 32'h20,
          $sformatf("WKUP_COUNT carried into HI: 0x%08h_%08h (expected 0x00000001_000000[10..20])",
                    hi, lo));
    apply_reset();
    end_test();
  endtask

  task automatic test_wkup_thold();
    logic [31:0] rd;
    int unsigned w;
    begin_test("F3 wakeup threshold / WKUP_CAUSE");
    wkup_thold_seq(0, 40);
    wkup_thold_seq(3, 10);

    // 64-bit threshold across the HI/LO boundary: 0x0_FFFF_FFF0 -> 0x1_0000_0010
    apply_reset();
    csr_wr(OffWkupCountHi, 32'h0);
    csr_wr(OffWkupCountLo, 32'hFFFF_FFF0);
    csr_wr(OffWkupTholdHi, 32'h1);
    csr_wr(OffWkupTholdLo, 32'h10);
    csr_wr(OffWkupCtrl,    32'h1);
    wait_high(SigWkup, 33 + Slack, w);
    check(intr_wkup === 1'b1 && w >= 32 && w <= 33 + Slack,
          $sformatf("threshold across HI/LO: wakeup after %0d cycles (expected 32..%0d)", w, 33 + Slack));
    check_rd(OffIntrState, 32'h1, "INTR_STATE.wkup_timer_expired set");
    aon_cycles(5);
    check(wkup_req === 1'b1, "wkup_req_o set");
    csr_wr(OffIntrState, 32'h1);
    repeat (3) @(posedge clk);
    check(intr_wkup === 1'b0, "INTR_STATE W1C clears the wakeup interrupt");
    aon_cycles(20);
    check(intr_wkup === 1'b0,
          "wakeup interrupt is edge-triggered: no re-assert while the count stays above it");
    csr_wr(OffWkupCause, 32'h0);
    aon_cycles(10);
    check(wkup_req === 1'b1,
          "WKUP_CAUSE write 0 is overridden while the timer runs above its threshold");
    csr_wr(OffWkupCtrl, 32'h0);
    aon_cycles(10);
    csr_wr(OffWkupCause, 32'h0);
    aon_cycles(10);
    check(wkup_req === 1'b0, "WKUP_CAUSE clears once the wakeup timer is stopped");
    csr_rd(OffWkupCountHi, rd);
    check(rd === 32'h1, "WKUP_COUNT_HI = 1 after the carry");
    apply_reset();
    end_test();
  endtask

  task automatic test_wkup_prescaler_change();
    logic [31:0] lo;
    begin_test("F4 prescaler change while running");
    // Raise the prescaler: 20 ticks at /2, then 20 ticks at /4
    apply_reset();
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl, (1 << 1) | 1);
    aon_cycles(40);
    csr_wr(OffWkupCtrl, (3 << 1) | 1);
    aon_cycles(80);
    csr_wr(OffWkupCtrl, 3 << 1);
    aon_cycles(10);
    csr_rd(OffWkupCountLo, lo);
    check(lo + 4 >= 40 && lo <= 44,
          $sformatf("prescaler 1 -> 3 while running: WKUP_COUNT = %0d (expected 40 +/- 4)", lo));

    // Lower the prescaler under the running prescale count: the next tick waits
    // for the 12-bit prescale counter to wrap (tick needs count == prescaler).
    apply_reset();
    csr_wr(OffWkupTholdHi, 32'hFFFF_FFFF);
    csr_wr(OffWkupTholdLo, 32'hFFFF_FFFF);
    csr_wr(OffWkupCtrl, (12'hFFF << 1) | 1);
    aon_cycles(200);
    csr_wr(OffWkupCtrl, (12'h010 << 1) | 1);
    aon_cycles(3500);
    csr_rd(OffWkupCountLo, lo);
    check(lo === 32'h0,
          $sformatf("prescaler 0xFFF -> 0x10 at prescale count ~200: no tick for 3500 cycles (count %0d)", lo));
    aon_cycles(700);
    csr_rd(OffWkupCountLo, lo);
    check(lo >= 32'h1,
          $sformatf("ticks resume after the prescale counter wraps (count %0d at ~4200 cycles)", lo));
    apply_reset();
    end_test();
  endtask

  task automatic test_wkup_jump();
    begin_test("F5 wakeup jump (threshold lowered under the count)");
    wkup_jump_seq(100, 50);
    wkup_jump_seq(150, 0);
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // H. CDC back-pressure
  // ---------------------------------------------------------------------------
  task automatic test_cdc_backpressure();
    logic [31:0] rd;
    int unsigned stall_rd, stall_wr;
    begin_test("H1 CDC back-pressure");
    apply_reset();
    csr_wr(OffBark, 32'h1);
    csr_rd(OffBark, rd);  // same register straight after the write
    stall_rd = last_stall;
    csr_wr(OffWdogCount, 32'h0);
    csr_wr(OffWdogCount, 32'h0);  // back-to-back pets
    stall_wr = last_stall;
    $display("     a_ready low: read-after-write %0d, write-after-write %0d clk_i cycles",
             stall_rd, stall_wr);
    check(stall_rd > 0 && stall_wr > 0,
          "back-to-back access to a CDC register is back-pressured (a_ready low)");
    check(stall_rd < 20 * AonDiv + 20 && stall_wr < 20 * AonDiv + 20,
          $sformatf("CDC back-pressure bounded (< %0d clk_i cycles)", 20 * AonDiv + 20));
    apply_reset();
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // G. Stress
  // ---------------------------------------------------------------------------
  task automatic test_stress();
    int unsigned sel, bark, bite, npets, period, p, ticks, run;
    begin_test($sformatf("G1 stress_all (%0d iterations)", StressIters));
    for (int unsigned it = 0; it < StressIters; it++) begin
      sel = $urandom_range(4, 0);
      case (sel)
        0: begin
          bark   = $urandom_range(150, 30);
          bite   = bark + $urandom_range(150, 5);
          npets  = $urandom_range(4, 0);
          period = $urandom_range(bark - 20, 5);
          $display("     iter %0d: bark/bite  bark=%0d bite=%0d pets=%0d period=%0d",
                   it, bark, bite, npets, period);
          wdog_bark_bite_seq(bark, bite, npets, period);
        end
        1: begin
          p     = $urandom_range(7, 0);
          ticks = $urandom_range(40, 1);
          $display("     iter %0d: wakeup     prescaler=%0d threshold=%0d", it, p, ticks);
          wkup_thold_seq(p, ticks);
        end
        2: begin
          p = $urandom_range(3, 1);
          $display("     iter %0d: intr_test  value=%02b", it, p[1:0]);
          intr_test_seq(p[1:0]);
        end
        3: begin
          run  = $urandom_range(200, 60);
          bark = $urandom_range(run - 20, 0);
          bite = $urandom_range(run - 20, 0);
          $display("     iter %0d: wdog jump  run=%0d bark=%0d bite=%0d", it, run, bark, bite);
          wdog_jump_seq(run, bark, bite);
        end
        default: begin
          run   = $urandom_range(200, 60);
          ticks = $urandom_range(run - 20, 0);
          $display("     iter %0d: wkup jump  run=%0d threshold=%0d", it, run, ticks);
          wkup_jump_seq(run, ticks);
        end
      endcase
    end
    end_test();
  endtask

  task automatic test_rand_reset();
    int unsigned bark;
    begin_test("G2 stress_all_with_rand_reset");
    for (int unsigned it = 0; it < 5; it++) begin
      apply_reset();
      bark = $urandom_range(400, 50);
      csr_wr(OffBark,        bark);
      csr_wr(OffBite,        bark + $urandom_range(400, 10));
      csr_wr(OffWdogCount,   32'h0);
      csr_wr(OffWdogCtrl,    32'h1);
      csr_wr(OffWkupTholdHi, 32'h0);
      csr_wr(OffWkupTholdLo, $urandom_range(100, 10));
      csr_wr(OffWkupCtrl,    ($urandom_range(3, 0) << 1) | 1);
      if ($urandom_range(1, 0) == 1) csr_wr(OffRegwen, 32'h0);
      aon_cycles($urandom_range(300, 10));
      apply_reset();
      check_reset_values($sformatf("random reset %0d", it));
    end
    end_test();
  endtask

  // ---------------------------------------------------------------------------
  // Global timeout
  // ---------------------------------------------------------------------------
  initial begin
    #(AonPeriod * 400_000 + ClkPeriod * 400_000);
    $display("[%0t] TEST FAILED: global timeout in %s", $time, cur_test);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  initial begin
    n_checks          = 0;
    n_errors          = 0;
    alert_expected    = 1'b0;
    alert_pulses      = 0;
    unexpected_alerts = 0;
    integ_fail_pulses = 0;
    nmi_mismatch      = 0;
    rst_req_drops     = 0;
    tl_h2d_raw        = TL_H2D_DEFAULT;
    inj_mode          = InjNone;
    inj_bit           = 0;
    lc_esc            = lc_ctrl_pkg::Off;
    sleep_mode        = 1'b0;
    rst_n             = 1'b0;
    rst_aon_n         = 1'b0;

    $display("==== tb_watchdog_full: aon_timer, WDT_AON_DIV = %0d, clk_aon_i %s, %0d stress iterations ====",
             AonDiv, AonAsync ? "asynchronous" : "synchronous", StressIters);
    apply_reset();

    test_csr_hw_reset();
    test_csr_rw();
    test_csr_bit_bash();
    test_csr_aliasing();
    test_regwen();
    test_tl_oob();
    test_tl_illegal();
    test_tl_partial();
    test_tl_outstanding();
    test_tl_intg_err();
    test_alert_test();
    test_intr_test();
    test_wdog_count();
    test_wdog_bark_bite_detail();
    test_wdog_jump();
    test_wdog_edges();
    test_wdog_pet();
    test_lock_running();
    test_pause_in_sleep();
    test_lc_escalate();
    test_wkup_rate();
    test_wkup_carry();
    test_wkup_thold();
    test_wkup_prescaler_change();
    test_wkup_jump();
    test_cdc_backpressure();
    test_stress();
    test_rand_reset();

    begin_test("whole-run monitors");
    check(unexpected_alerts == 0,
          $sformatf("no alert or integrity fault outside the alert tests (%0d)", unexpected_alerts));
    check(integ_fail_pulses == 0,
          $sformatf("alert receiver never saw a signal-integrity failure (%0d)", integ_fail_pulses));
    check(nmi_mismatch == 0,
          $sformatf("nmi_wdog_timer_bark_o always equal to intr_wdog_timer_bark_o (%0d)", nmi_mismatch));
    check(rst_req_drops == 0,
          $sformatf("aon_timer_rst_req_o never dropped while rst_aon_ni was high (%0d)", rst_req_drops));
    end_test();

    $display("");
    $display("==== tb_watchdog_full summary (WDT_AON_DIV = %0d, clk_aon_i %s) ====",
             AonDiv, AonAsync ? "asynchronous" : "synchronous");
    foreach (results[i]) $display("  %s", results[i]);
    $display("==== %0d checks, %0d errors ====", n_checks, n_errors);
    if (n_errors == 0) $display("TEST PASSED");
    else               $display("TEST FAILED");
    $finish;
  end

endmodule
