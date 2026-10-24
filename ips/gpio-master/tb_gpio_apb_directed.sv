// =============================================================================
// Testbench: tb_gpio_apb_directed
// DUT      : gpio_apb_wrap  (PULP GPIO, 32 pins, reggen register file behind
//            apb_to_reg) — the same wrapper instantiated at APB[3]
//            (0x4000_3000) of riscforge_soc_subsystem.
//
// Methodology:
//   * Directed + constrained-random stimulus, self-checking, non-UVM.
//   * Expected values are computed inline by each test (no reference model).
//   * APB BFM drives on posedge+1ns and samples PRDATA/PSLVERR inside the
//     ACCESS phase. apb_to_reg is feedthrough, so PREADY is high in the first
//     ACCESS cycle and the write commits on the edge that ends it.
//   * Every task starts and ends aligned to posedge+1ns, so the cycle counts
//     used by the latency checks are exact.
//   * Sticky monitors latch single-cycle interrupt pulses.
//   * Concurrent SVA check the APB response and X on every DUT output.
//   * Checks are reported as [PASS] / [FAIL]. Behaviour that is legal for this
//     RTL but most likely wrong for the SoC is reported as [BUG?] and counted
//     separately, so it does not hide real failures.
//
// Input path timing (gpio_input_stage_no_clk_gates, 2-flop synchroniser):
//   gpio_in changes between two clock edges; call the next edges A, B, C, D.
//     after A : sync flop 1 holds the new value
//     after B : sync flop 2 holds it   -> r_edge/f_edge high for one cycle
//     after C : serial_q = gpio_in_sync_o = GPIO_IN -> edge status latched,
//                                                     level interrupt asserts
//     after D : level status latched
//
// Coverage (22 test-cases):
//   TC01 Reset values of all outputs and all 19 registers (INFO = 0x820)
//   TC02 RW registers: walking-1/0 + random round-trip, reserved bits, crosstalk
//   TC03 Read-only (INFO, GPIO_IN) and write-only (SET/CLEAR/TOGGLE) semantics
//   TC04 Unmapped offsets: PSLVERR on read/write, no register corruption
//   TC05 Address aliasing inside the 4 KB SoC window              [BUG? check]
//   TC06 Back-to-back APB transfers (PSEL held, no idle cycle)
//   TC07 Pin modes: INPUT / PUSH_PULL / OPEN_DRAIN0 / OPEN_DRAIN1 (tx_en, out)
//   TC08 SET / CLEAR / TOGGLE per pin, zero writes, multi-bit, commit edge
//   TC09 Random MODE/OUT/SET/CLEAR/TOGGLE sequence (200 operations)
//   TC10 Input latency: gpio_in -> gpio_in_sync_o / GPIO_IN in exactly 3 edges
//   TC11 GPIO_EN: disabled pins hold the last sampled value, per-pin enable
//   TC12 Fast input sampling: new random vector every clock cycle
//   TC13 Edge interrupts: rise / fall / both, 1-cycle pulse, sticky, glitch
//   TC14 Level interrupts: high / low, re-latch while level present
//   TC15 W1C semantics of the status registers and aggregated INTRPT_STATUS
//   TC16 CFG.glbl_intrpt_mode / CFG.pin_lvl_intrpt_mode independence
//   TC17 Interrupt masking (no stray interrupt, only enabled pin reports)
//   TC18 Status clear on the same edge as a new edge event       [BUG? check]
//   TC19 Interrupts from a pin with GPIO_EN = 0                  [BUG? check]
//   TC20 Asynchronous reset in the middle of an APB transfer
//   TC21 Random mixed I/O (outputs and inputs together, 300 operations)
//   TC22 Sub-word writes (PSTRB != 4'hF) rejected with PSLVERR, no side effects
//
// Plusargs:
//   +SEED=<n>   seed for all $urandom calls (default 1)
//
// Compile / run (Xcelium, from rtl/gpio-master on the CentOS tree):
//   xrun -f tb_gpio_apb_directed.f
// =============================================================================

`timescale 1ns/1ps

`include "apb/typedef.svh"

module tb_gpio_apb_directed;

  import gpio_reg_pkg::*;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int          CLK_PERIOD   = 10;           // 100 MHz
  localparam int          TIMEOUT_CYC  = 1000;         // per APB transfer
  localparam longint      GLOBAL_WD_NS = 50_000_000;   // 50 ms watchdog
  localparam int          NPINS        = GPIOCount;
  localparam logic [31:0] GPIO_BASE    = 32'h4000_3000; // SoC APB[3] base

  // Register offsets (12-bit: the SoC decodes a 4 KB window to the GPIO)
  localparam logic [11:0] R_INFO        = 12'(GPIO_INFO_OFFSET);
  localparam logic [11:0] R_CFG         = 12'(GPIO_CFG_OFFSET);
  localparam logic [11:0] R_MODE0       = 12'(GPIO_GPIO_MODE_0_OFFSET);
  localparam logic [11:0] R_MODE1       = 12'(GPIO_GPIO_MODE_1_OFFSET);
  localparam logic [11:0] R_EN          = 12'(GPIO_GPIO_EN_OFFSET);
  localparam logic [11:0] R_IN          = 12'(GPIO_GPIO_IN_OFFSET);
  localparam logic [11:0] R_OUT         = 12'(GPIO_GPIO_OUT_OFFSET);
  localparam logic [11:0] R_SET         = 12'(GPIO_GPIO_SET_OFFSET);
  localparam logic [11:0] R_CLEAR       = 12'(GPIO_GPIO_CLEAR_OFFSET);
  localparam logic [11:0] R_TOGGLE      = 12'(GPIO_GPIO_TOGGLE_OFFSET);
  localparam logic [11:0] R_RISE_EN     = 12'(GPIO_INTRPT_RISE_EN_OFFSET);
  localparam logic [11:0] R_FALL_EN     = 12'(GPIO_INTRPT_FALL_EN_OFFSET);
  localparam logic [11:0] R_HIGH_EN     = 12'(GPIO_INTRPT_LVL_HIGH_EN_OFFSET);
  localparam logic [11:0] R_LOW_EN      = 12'(GPIO_INTRPT_LVL_LOW_EN_OFFSET);
  localparam logic [11:0] R_STATUS      = 12'(GPIO_INTRPT_STATUS_OFFSET);
  localparam logic [11:0] R_RISE_STATUS = 12'(GPIO_INTRPT_RISE_STATUS_OFFSET);
  localparam logic [11:0] R_FALL_STATUS = 12'(GPIO_INTRPT_FALL_STATUS_OFFSET);
  localparam logic [11:0] R_HIGH_STATUS = 12'(GPIO_INTRPT_LVL_HIGH_STATUS_OFFSET);
  localparam logic [11:0] R_LOW_STATUS  = 12'(GPIO_INTRPT_LVL_LOW_STATUS_OFFSET);

  localparam logic [11:0] ALL_OFF [19] = '{
    R_INFO, R_CFG, R_MODE0, R_MODE1, R_EN, R_IN, R_OUT, R_SET, R_CLEAR,
    R_TOGGLE, R_RISE_EN, R_FALL_EN, R_HIGH_EN, R_LOW_EN, R_STATUS,
    R_RISE_STATUS, R_FALL_STATUS, R_HIGH_STATUS, R_LOW_STATUS
  };

  // Software read/write registers and their implemented-bit masks
  localparam logic [11:0] RW_OFF  [9] = '{
    R_CFG, R_MODE0, R_MODE1, R_EN, R_OUT,
    R_RISE_EN, R_FALL_EN, R_HIGH_EN, R_LOW_EN
  };
  localparam logic [31:0] RW_MASK [9] = '{
    32'h0000_0003, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF,
    32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF
  };

  // INFO = {version[19:10] = 2, gpio_cnt[9:0] = 32}
  localparam logic [31:0] INFO_EXP = {12'h000, 10'd2, 10'(GPIOCount)};

  // GPIO_MODE encodings
  localparam logic [1:0] M_INPUT = 2'b00;
  localparam logic [1:0] M_PUSH  = 2'b01;
  localparam logic [1:0] M_OD0   = 2'b10;
  localparam logic [1:0] M_OD1   = 2'b11;

  // ---------------------------------------------------------------------------
  // APB structs (same macros the SoC uses for apb_req_t / apb_resp_t)
  // ---------------------------------------------------------------------------
  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;
  `APB_TYPEDEF_REQ_T(apb_req_t, addr_t, data_t, strb_t)
  `APB_TYPEDEF_RESP_T(apb_resp_t, data_t)

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic        clk;
  logic        rst_n   = 1'b0;
  logic        psel    = 1'b0;
  logic        penable = 1'b0;
  logic        pwrite  = 1'b0;
  logic [31:0] paddr   = '0;
  logic [31:0] pwdata  = '0;
  logic [3:0]  pstrb   = 4'hF;
  logic [31:0] prdata;
  logic        pready, pslverr;

  apb_req_t    apb_req;
  apb_resp_t   apb_rsp;

  logic [NPINS-1:0] gpio_in = '0;
  logic [NPINS-1:0] gpio_out;
  logic [NPINS-1:0] gpio_tx_en;
  logic [NPINS-1:0] gpio_in_sync;
  logic [NPINS-1:0] pin_irq;
  logic             glb_irq;

  assign apb_req = '{paddr:   paddr,
                     pprot:   3'b000,
                     psel:    psel,
                     penable: penable,
                     pwrite:  pwrite,
                     pwdata:  pwdata,
                     pstrb:   pstrb};
  assign prdata  = apb_rsp.prdata;
  assign pready  = apb_rsp.pready;
  assign pslverr = apb_rsp.pslverr;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  gpio_apb_wrap #(
    .ADDR_WIDTH ( 32         ),
    .DATA_WIDTH ( 32         ),
    .apb_req_t  ( apb_req_t  ),
    .apb_rsp_t  ( apb_resp_t )
  ) dut (
    .clk_i                  ( clk          ),
    .rst_ni                 ( rst_n        ),
    .gpio_in                ( gpio_in      ),
    .gpio_out               ( gpio_out     ),
    .gpio_tx_en_o           ( gpio_tx_en   ),
    .gpio_in_sync_o         ( gpio_in_sync ),
    .global_interrupt_o     ( glb_irq      ),
    .pin_level_interrupts_o ( pin_irq      ),
    .apb_req_i              ( apb_req      ),
    .apb_rsp_o              ( apb_rsp      )
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Pass/fail counters and check helpers
  // ---------------------------------------------------------------------------
  int pass_cnt = 0, fail_cnt = 0, bug_cnt = 0;

  task automatic check(input string msg, input logic got, input logic exp);
    if (got === exp) begin
      $display("  [PASS] %s (got=%0b exp=%0b)", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s (got=%0b exp=%0b) @%0t", msg, got, exp, $time);
      fail_cnt++;
    end
  endtask

  task automatic check_val(input string msg,
                           input logic [31:0] got, input logic [31:0] exp,
                           input logic [31:0] mask = 32'hFFFF_FFFF);
    if ((got & mask) === (exp & mask)) begin
      $display("  [PASS] %s got=0x%08X exp=0x%08X", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s got=0x%08X exp=0x%08X mask=0x%08X @%0t",
               msg, got, exp, mask, $time);
      fail_cnt++;
    end
  endtask

  // Aggregated check for loops: one result line for many comparisons
  task automatic check_cnt(input string msg, input int errs);
    if (errs == 0) begin
      $display("  [PASS] %s (0 mismatches)", msg);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s (%0d mismatches)", msg, errs);
      fail_cnt++;
    end
  endtask

  // Suspected RTL issue: ok=1 means the behaviour is as a user would expect
  task automatic check_bug(input string msg, input bit ok, input string detail);
    if (ok) begin
      $display("  [PASS] %s", msg);
      pass_cnt++;
    end else begin
      $display("  [BUG?] %s -- %s", msg, detail);
      bug_cnt++;
    end
  endtask

  task automatic tc_banner(input string name);
    $display("");
    $display("---------------------------------------------------------------");
    $display(" %s", name);
    $display("---------------------------------------------------------------");
  endtask

  function automatic string reg_name(input logic [11:0] off);
    case (off)
      R_INFO:        return "INFO";
      R_CFG:         return "CFG";
      R_MODE0:       return "GPIO_MODE_0";
      R_MODE1:       return "GPIO_MODE_1";
      R_EN:          return "GPIO_EN";
      R_IN:          return "GPIO_IN";
      R_OUT:         return "GPIO_OUT";
      R_SET:         return "GPIO_SET";
      R_CLEAR:       return "GPIO_CLEAR";
      R_TOGGLE:      return "GPIO_TOGGLE";
      R_RISE_EN:     return "INTRPT_RISE_EN";
      R_FALL_EN:     return "INTRPT_FALL_EN";
      R_HIGH_EN:     return "INTRPT_LVL_HIGH_EN";
      R_LOW_EN:      return "INTRPT_LVL_LOW_EN";
      R_STATUS:      return "INTRPT_STATUS";
      R_RISE_STATUS: return "INTRPT_RISE_STATUS";
      R_FALL_STATUS: return "INTRPT_FALL_STATUS";
      R_HIGH_STATUS: return "INTRPT_LVL_HIGH_STATUS";
      R_LOW_STATUS:  return "INTRPT_LVL_LOW_STATUS";
      default:       return $sformatf("UNMAPPED@0x%03h", off);
    endcase
  endfunction

  function automatic string mode_name(input logic [1:0] m);
    case (m)
      M_INPUT: return "INPUT";
      M_PUSH:  return "PUSH_PULL";
      M_OD0:   return "OPEN_DRAIN0";
      default: return "OPEN_DRAIN1";
    endcase
  endfunction

  // Expected gpio_tx_en_o for a full MODE_1:MODE_0 image and GPIO_OUT value
  function automatic logic [31:0] exp_tx_vec(input logic [63:0] modes,
                                             input logic [31:0] out);
    logic [31:0] v;
    for (int i = 0; i < NPINS; i++) begin
      case (modes[2*i +: 2])
        M_INPUT: v[i] = 1'b0;
        M_PUSH:  v[i] = 1'b1;
        M_OD0:   v[i] = out[i];
        default: v[i] = ~out[i];
      endcase
    end
    return v;
  endfunction

  function automatic logic [63:0] all_modes(input logic [1:0] m);
    return {32{m}};
  endfunction

  // ---------------------------------------------------------------------------
  // Timing helper: advance n edges, stay aligned to posedge+1ns
  // ---------------------------------------------------------------------------
  task automatic cyc(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  // ---------------------------------------------------------------------------
  // Interrupt monitors — latch pulses so tests can check "ever seen" and
  // measure how long global_interrupt_o stays high without a break.
  // ---------------------------------------------------------------------------
  logic             mon_clr = 1'b0;
  logic             glb_seen;
  logic [NPINS-1:0] pin_seen;
  int unsigned      glb_run, glb_run_max;

  always_ff @(posedge clk) begin
    if (mon_clr) begin
      glb_seen    <= 1'b0;
      pin_seen    <= '0;
      glb_run     <= 0;
      glb_run_max <= 0;
    end else begin
      if (glb_irq === 1'b1) glb_seen <= 1'b1;
      pin_seen <= pin_seen | pin_irq;
      glb_run  <= (glb_irq === 1'b1) ? glb_run + 1 : 0;
      if ((glb_irq === 1'b1) && (glb_run + 1 > glb_run_max))
        glb_run_max <= glb_run + 1;
    end
  end

  task automatic mon_reset();
    mon_clr = 1'b1;
    cyc(1);
    mon_clr = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // APB BFM
  //
  // Must be called at posedge+1ns and returns at posedge+1ns.
  //   SETUP  : this call's first cycle
  //   ACCESS : next cycle; PRDATA/PSLVERR sampled here, one delta after
  //            PENABLE is driven so the combinational response has settled
  //   commit : the edge that ends ACCESS (register updates on this edge)
  // back2back=1 keeps PSEL high and skips the idle cycle, so the caller can
  // start the next SETUP immediately. The caller must drop PSEL afterwards.
  // strb is the write byte-enable (PSTRB); reads always drive PSTRB = 0, as
  // APB4 requires. Every existing caller uses the default full-word strobe.
  // ---------------------------------------------------------------------------
  task automatic apb_xfer(input  bit          wr,
                          input  logic [11:0] off,
                          input  logic [31:0] wdata,
                          output logic [31:0] rdata,
                          output logic        err,
                          input  bit          back2back = 1'b0,
                          input  logic [3:0]  strb      = 4'hF);
    int t;
    t       = 0;
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = wr;
    paddr   = GPIO_BASE + {20'h0, off};
    pwdata  = wr ? wdata : 32'h0;
    pstrb   = wr ? strb  : 4'h0;
    @(posedge clk); #1;                       // ACCESS phase
    penable = 1'b1;
    // PREADY/PSLVERR/PRDATA are combinational from psel & penable inside the
    // slave, so the drive above must be given a delta to propagate. Sampling
    // in the same time step returns the SETUP-phase values, which makes every
    // access look like it completed without an error.
    #1;
    while (pready !== 1'b1) begin
      @(posedge clk); #2;                     // same sampling point each cycle
      t++;
      if (t >= TIMEOUT_CYC) begin
        $display("  [FAIL] APB %s timeout @ offset 0x%03h",
                 wr ? "write" : "read", off);
        fail_cnt++;
        break;
      end
    end
    rdata = prdata;
    err   = pslverr;
    @(posedge clk); #1;                       // this edge commits the transfer
    penable = 1'b0;
    if (!back2back) begin
      psel   = 1'b0;
      pwrite = 1'b0;
      cyc(1);                                 // one idle cycle
    end
  endtask

  task automatic reg_write(input logic [11:0] off, input logic [31:0] data);
    logic [31:0] rd;
    logic        err;
    apb_xfer(1'b1, off, data, rd, err);
    if (err !== 1'b0) begin
      $display("  [FAIL] unexpected PSLVERR on write %s <= 0x%08X",
               reg_name(off), data);
      fail_cnt++;
    end
  endtask

  task automatic reg_read(input logic [11:0] off, output logic [31:0] data);
    logic err;
    apb_xfer(1'b0, off, 32'h0, data, err);
    if (err !== 1'b0) begin
      $display("  [FAIL] unexpected PSLVERR on read %s", reg_name(off));
      fail_cnt++;
    end
  endtask

  task automatic reg_expect(input string msg, input logic [11:0] off,
                            input logic [31:0] exp,
                            input logic [31:0] mask = 32'hFFFF_FFFF);
    logic [31:0] rd;
    reg_read(off, rd);
    check_val($sformatf("%s: %s", reg_name(off), msg), rd, exp, mask);
  endtask

  task automatic set_modes(input logic [63:0] modes);
    reg_write(R_MODE0, modes[31:0]);
    reg_write(R_MODE1, modes[63:32]);
  endtask

  task automatic clear_all_status();
    reg_write(R_STATUS, 32'hFFFF_FFFF);       // aggregated clear of all 4 types
  endtask

  // ---------------------------------------------------------------------------
  // Reset: drives the bus idle and all pins low, ends aligned to posedge+1ns
  // ---------------------------------------------------------------------------
  task automatic dut_reset();
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = '0;
    pwdata  = '0;
    pstrb   = 4'h0;
    gpio_in = '0;
    mon_clr = 1'b0;
    rst_n   = 1'b0;
    repeat (4) @(posedge clk);
    #1 rst_n = 1'b1;
    cyc(2);
  endtask

  // ---------------------------------------------------------------------------
  // SVA — APB response and output sanity
  // ---------------------------------------------------------------------------
  // PSLVERR is only meaningful (and only driven) during the ACCESS phase
  a_slverr_in_access: assert property (@(posedge clk) disable iff (!rst_n)
      pslverr |-> (psel && penable))
    else begin
      $display("  [FAIL] SVA: PSLVERR outside ACCESS phase @%0t", $time);
      fail_cnt++;
    end

  // Feedthrough apb_to_reg + reggen top: zero wait states
  a_pready_in_access: assert property (@(posedge clk) disable iff (!rst_n)
      (psel && penable) |-> (pready === 1'b1))
    else begin
      $display("  [FAIL] SVA: PREADY low in ACCESS phase @%0t", $time);
      fail_cnt++;
    end

  a_prdata_known: assert property (@(posedge clk) disable iff (!rst_n)
      (psel && penable && !pwrite) |-> !$isunknown(prdata))
    else begin
      $display("  [FAIL] SVA: PRDATA is X during read ACCESS @%0t", $time);
      fail_cnt++;
    end

  a_outputs_known: assert property (@(posedge clk) disable iff (!rst_n)
      !$isunknown({gpio_out, gpio_tx_en, gpio_in_sync, pin_irq, glb_irq,
                   pready, pslverr}))
    else begin
      $display("  [FAIL] SVA: X on a DUT output @%0t", $time);
      fail_cnt++;
    end

  // ===========================================================================
  // TC01 — Reset values
  // ===========================================================================
  task automatic tc01_reset_values();
    logic [31:0] rd;
    tc_banner("TC01 Reset values of outputs and registers");
    dut_reset();

    check_val("gpio_out after reset",       gpio_out,     32'h0);
    check_val("gpio_tx_en_o after reset",   gpio_tx_en,   32'h0);
    check_val("gpio_in_sync_o after reset", gpio_in_sync, 32'h0);
    check_val("pin_level_interrupts_o after reset", pin_irq, 32'h0);
    check("global_interrupt_o after reset", glb_irq, 1'b0);

    reg_expect("version=2, gpio_cnt=32", R_INFO, INFO_EXP);
    foreach (ALL_OFF[i]) begin
      if (ALL_OFF[i] != R_INFO) reg_expect("reset value", ALL_OFF[i], 32'h0);
    end
  endtask

  // ===========================================================================
  // TC02 — Software read/write registers
  // ===========================================================================
  task automatic tc02_rw_registers();
    logic [31:0] pat [$];
    logic [31:0] rd;
    logic [31:0] vals [9];
    int          errs;
    tc_banner("TC02 RW register round-trip (walking-1, walking-0, random)");
    dut_reset();

    foreach (RW_OFF[r]) begin
      pat = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hAAAA_AAAA, 32'h5555_5555};
      for (int b = 0; b < 32; b++) pat.push_back(32'h1 << b);
      for (int b = 0; b < 32; b++) pat.push_back(~(32'h1 << b));
      repeat (8) pat.push_back($urandom);

      errs = 0;
      foreach (pat[i]) begin
        reg_write(RW_OFF[r], pat[i]);
        reg_read (RW_OFF[r], rd);
        // implemented bits must match, reserved bits must read 0
        if (((rd & RW_MASK[r]) !== (pat[i] & RW_MASK[r])) ||
            ((rd & ~RW_MASK[r]) !== 32'h0)) begin
          if (errs < 3)
            $display("    %s: wrote 0x%08X read 0x%08X (mask 0x%08X)",
                     reg_name(RW_OFF[r]), pat[i], rd, RW_MASK[r]);
          errs++;
        end
      end
      check_cnt($sformatf("%s: %0d patterns round-trip", reg_name(RW_OFF[r]),
                          pat.size()), errs);
      pat.delete();
    end

    // Crosstalk: distinct values in every RW register at once
    dut_reset();
    foreach (RW_OFF[r]) begin
      vals[r] = $urandom & RW_MASK[r];
      reg_write(RW_OFF[r], vals[r]);
    end
    errs = 0;
    foreach (RW_OFF[r]) begin
      reg_read(RW_OFF[r], rd);
      if (rd !== vals[r]) begin
        $display("    %s: expected 0x%08X read 0x%08X",
                 reg_name(RW_OFF[r]), vals[r], rd);
        errs++;
      end
    end
    check_cnt("all 9 RW registers hold distinct values simultaneously", errs);
  endtask

  // ===========================================================================
  // TC03 — Read-only and write-only registers
  // ===========================================================================
  task automatic tc03_ro_wo_registers();
    logic [31:0] rd;
    logic        err;
    localparam logic [31:0] IN_PAT = 32'hA5C3_0F96;
    tc_banner("TC03 Read-only (INFO, GPIO_IN) and write-only (SET/CLEAR/TOGGLE)");
    dut_reset();

    // INFO is read-only: the write must be dropped silently
    apb_xfer(1'b1, R_INFO, 32'hFFFF_FFFF, rd, err);
    $display("  [INFO] write to INFO returned pslverr=%0b", err);
    reg_expect("unchanged after write of 0xFFFFFFFF", R_INFO, INFO_EXP);

    // GPIO_IN mirrors the pins and ignores writes
    reg_write(R_EN, 32'hFFFF_FFFF);
    gpio_in = IN_PAT;
    cyc(4);
    reg_expect("mirrors gpio_in", R_IN, IN_PAT);
    apb_xfer(1'b1, R_IN, 32'h0, rd, err);
    $display("  [INFO] write to GPIO_IN returned pslverr=%0b", err);
    reg_expect("unchanged after write of 0", R_IN, IN_PAT);

    // SET/CLEAR/TOGGLE are write-only: read as 0, and reading has no effect
    set_modes(all_modes(M_PUSH));
    reg_write(R_OUT, 32'h1234_5678);
    reg_expect("write-only, reads 0", R_SET,    32'h0);
    reg_expect("write-only, reads 0", R_CLEAR,  32'h0);
    reg_expect("write-only, reads 0", R_TOGGLE, 32'h0);
    check_val("gpio_out unaffected by SET/CLEAR/TOGGLE reads",
              gpio_out, 32'h1234_5678);
    reg_expect("unaffected by SET/CLEAR/TOGGLE reads", R_OUT, 32'h1234_5678);

    gpio_in = '0;
    cyc(4);
  endtask

  // ===========================================================================
  // TC04 — Unmapped offsets
  // ===========================================================================
  task automatic tc04_unmapped();
    logic [11:0] offs [11];
    logic [31:0] rd;
    logic        err;
    int          rd_errs, wr_errs;
    tc_banner("TC04 Unmapped offsets return PSLVERR and change nothing");
    dut_reset();

    offs = '{12'h010, 12'h014, 12'h07C, 12'h084, 12'h0FC, 12'h104,
             12'h184, 12'h204, 12'h57C, 12'h784, 12'h7FC};

    rd_errs = 0;
    wr_errs = 0;
    foreach (offs[i]) begin
      apb_xfer(1'b0, offs[i], 32'h0, rd, err);
      if (err !== 1'b1) begin
        $display("    read 0x%03h: pslverr=%0b (expected 1), rdata=0x%08X",
                 offs[i], err, rd);
        rd_errs++;
      end
      apb_xfer(1'b1, offs[i], 32'hFFFF_FFFF, rd, err);
      if (err !== 1'b1) begin
        $display("    write 0x%03h: pslverr=%0b (expected 1)", offs[i], err);
        wr_errs++;
      end
    end
    check_cnt($sformatf("%0d unmapped reads flagged with PSLVERR", $size(offs)),
              rd_errs);
    check_cnt($sformatf("%0d unmapped writes flagged with PSLVERR", $size(offs)),
              wr_errs);

    // Nothing may have been corrupted by the erroring writes
    check_val("gpio_out still 0", gpio_out, 32'h0);
    rd_errs = 0;
    foreach (ALL_OFF[i]) begin
      reg_read(ALL_OFF[i], rd);
      if (rd !== ((ALL_OFF[i] == R_INFO) ? INFO_EXP : 32'h0)) begin
        $display("    %s corrupted: 0x%08X", reg_name(ALL_OFF[i]), rd);
        rd_errs++;
      end
    end
    check_cnt("all registers still at reset values after unmapped writes",
              rd_errs);
  endtask

  // ===========================================================================
  // TC05 — Address aliasing inside the 4 KB SoC window          [BUG? check]
  //
  // gpio_reg_top truncates the address to BlockAw = 11 bits, but the SoC
  // decodes a full 4 KB window (0x4000_3000-0x4000_3FFF) to this slave, so
  // offsets 0x800-0xFFF fold back onto 0x000-0x7FF instead of erroring.
  // ===========================================================================
  task automatic tc05_address_aliasing();
    logic [31:0] rd;
    logic        err;
    tc_banner("TC05 Address aliasing above offset 0x7FF");
    dut_reset();

    apb_xfer(1'b0, 12'h800, 32'h0, rd, err);
    check_bug("read at +0x800 (above the register block) returns PSLVERR",
              err === 1'b1,
              $sformatf("pslverr=%0b rdata=0x%08X (INFO reads 0x%08X)",
                        err, rd, INFO_EXP));

    set_modes(all_modes(M_PUSH));
    reg_write(R_OUT, 32'h0);
    apb_xfer(1'b1, 12'h980, 32'hDEAD_BEEF, rd, err);
    psel = 1'b0; pwrite = 1'b0;
    cyc(2);
    check_bug("write at +0x980 does not reach GPIO_OUT (0x180)",
              (err === 1'b1) && (gpio_out === 32'h0),
              $sformatf("pslverr=%0b gpio_out=0x%08X", err, gpio_out));
  endtask

  // ===========================================================================
  // TC06 — Back-to-back APB transfers (PSEL held high, no idle cycle)
  // ===========================================================================
  task automatic tc06_back_to_back();
    logic [31:0] v0, v1, v2, r0, r1, r2;
    logic        e0, e1, e2;
    int          errs;
    tc_banner("TC06 Back-to-back APB transfers");
    dut_reset();

    v0 = $urandom;
    v1 = $urandom;
    v2 = $urandom;

    apb_xfer(1'b1, R_OUT,     v0, r0, e0, 1'b1);
    apb_xfer(1'b1, R_EN,      v1, r1, e1, 1'b1);
    apb_xfer(1'b1, R_RISE_EN, v2, r2, e2, 1'b1);
    apb_xfer(1'b0, R_OUT,     32'h0, r0, e0, 1'b1);
    apb_xfer(1'b0, R_EN,      32'h0, r1, e1, 1'b1);
    apb_xfer(1'b0, R_RISE_EN, 32'h0, r2, e2, 1'b0);

    errs = 0;
    if (r0 !== v0) begin $display("    GPIO_OUT 0x%08X != 0x%08X", r0, v0); errs++; end
    if (r1 !== v1) begin $display("    GPIO_EN 0x%08X != 0x%08X",  r1, v1); errs++; end
    if (r2 !== v2) begin $display("    INTRPT_RISE_EN 0x%08X != 0x%08X", r2, v2); errs++; end
    if ({e0, e1, e2} !== 3'b000) begin $display("    unexpected PSLVERR"); errs++; end
    check_cnt("3 writes + 3 reads with PSEL held high", errs);

    // Clear the interrupt enables this test left behind
    dut_reset();
  endtask

  // ===========================================================================
  // TC07 — Pin modes
  // ===========================================================================
  task automatic tc07_pin_modes();
    logic [63:0] modes;
    logic [31:0] outv;
    tc_banner("TC07 Pin modes: tx_en and gpio_out per GPIO_MODE");
    dut_reset();

    for (int m = 0; m < 4; m++) begin
      modes = all_modes(m[1:0]);
      set_modes(modes);
      for (int k = 0; k < 4; k++) begin
        case (k)
          0: outv = 32'h0000_0000;
          1: outv = 32'hFFFF_FFFF;
          2: outv = 32'hA5A5_5A5A;
          default: outv = $urandom;
        endcase
        reg_write(R_OUT, outv);
        check_val($sformatf("all pins %s, GPIO_OUT=0x%08X: gpio_out",
                            mode_name(m[1:0]), outv), gpio_out, outv);
        check_val($sformatf("all pins %s, GPIO_OUT=0x%08X: gpio_tx_en_o",
                            mode_name(m[1:0]), outv),
                  gpio_tx_en, exp_tx_vec(modes, outv));
      end
    end

    // Mixed per-pin modes: pin i gets mode i%4
    modes = {16{M_OD1, M_OD0, M_PUSH, M_INPUT}};
    set_modes(modes);
    reg_expect("readback", R_MODE0, modes[31:0]);
    reg_expect("readback", R_MODE1, modes[63:32]);
    for (int k = 0; k < 4; k++) begin
      outv = $urandom;
      reg_write(R_OUT, outv);
      check_val($sformatf("mixed modes, GPIO_OUT=0x%08X: gpio_out", outv),
                gpio_out, outv);
      check_val($sformatf("mixed modes, GPIO_OUT=0x%08X: gpio_tx_en_o", outv),
                gpio_tx_en, exp_tx_vec(modes, outv));
    end
  endtask

  // ===========================================================================
  // TC08 — SET / CLEAR / TOGGLE
  // ===========================================================================
  task automatic tc08_set_clear_toggle();
    logic [31:0] exp, mask, rd;
    logic        err;
    int          errs;
    tc_banner("TC08 GPIO_SET / GPIO_CLEAR / GPIO_TOGGLE");
    dut_reset();
    set_modes(all_modes(M_PUSH));

    exp = $urandom;
    reg_write(R_OUT, exp);

    // Per-pin: toggle, set, clear, toggle — only the addressed pin may move
    errs = 0;
    for (int p = 0; p < NPINS; p++) begin
      reg_write(R_TOGGLE, 32'h1 << p);
      exp ^= (32'h1 << p);
      if (gpio_out !== exp) begin
        if (errs < 3) $display("    TOGGLE pin %0d: 0x%08X != 0x%08X", p, gpio_out, exp);
        errs++;
      end
      reg_write(R_SET, 32'h1 << p);
      exp |= (32'h1 << p);
      if (gpio_out !== exp) begin
        if (errs < 3) $display("    SET pin %0d: 0x%08X != 0x%08X", p, gpio_out, exp);
        errs++;
      end
      reg_write(R_CLEAR, 32'h1 << p);
      exp &= ~(32'h1 << p);
      if (gpio_out !== exp) begin
        if (errs < 3) $display("    CLEAR pin %0d: 0x%08X != 0x%08X", p, gpio_out, exp);
        errs++;
      end
      reg_write(R_TOGGLE, 32'h1 << p);
      exp ^= (32'h1 << p);
      if (gpio_out !== exp) begin
        if (errs < 3) $display("    TOGGLE pin %0d: 0x%08X != 0x%08X", p, gpio_out, exp);
        errs++;
      end
    end
    check_cnt("TOGGLE/SET/CLEAR/TOGGLE walked over all 32 pins", errs);
    reg_expect("matches gpio_out after per-pin walk", R_OUT, exp);

    // Writing zero must be a no-op for all three registers
    reg_write(R_SET,    32'h0);
    reg_write(R_CLEAR,  32'h0);
    reg_write(R_TOGGLE, 32'h0);
    check_val("writing 0 to SET/CLEAR/TOGGLE leaves gpio_out alone",
              gpio_out, exp);

    // Multi-bit masks
    errs = 0;
    for (int i = 0; i < 20; i++) begin
      mask = $urandom;
      case (i % 3)
        0: begin reg_write(R_SET,    mask); exp |=  mask; end
        1: begin reg_write(R_CLEAR,  mask); exp &= ~mask; end
        2: begin reg_write(R_TOGGLE, mask); exp ^=  mask; end
      endcase
      if (gpio_out !== exp) begin
        if (errs < 3) $display("    multi-bit op %0d: 0x%08X != 0x%08X", i, gpio_out, exp);
        errs++;
      end
    end
    check_cnt("20 multi-bit SET/CLEAR/TOGGLE masks", errs);

    // Open-drain: tx_en must follow the bits SET/CLEAR change
    set_modes(all_modes(M_OD0));
    reg_write(R_OUT, 32'h0);
    reg_write(R_SET, 32'h0000_FFFF);
    check_val("OPEN_DRAIN0: SET drives tx_en on the set pins",
              gpio_tx_en, 32'h0000_FFFF);
    reg_write(R_CLEAR, 32'h0000_00FF);
    check_val("OPEN_DRAIN0: CLEAR releases tx_en on the cleared pins",
              gpio_tx_en, 32'h0000_FF00);

    // A SET takes effect on the edge that completes the ACCESS phase
    set_modes(all_modes(M_PUSH));
    reg_write(R_OUT, 32'h0);
    apb_xfer(1'b1, R_SET, 32'h0000_0001, rd, err, 1'b1);
    check_val("SET is visible on gpio_out immediately after the commit edge",
              gpio_out, 32'h0000_0001);
    psel = 1'b0; pwrite = 1'b0;
    cyc(1);
  endtask

  // ===========================================================================
  // TC09 — Random output activity
  // ===========================================================================
  task automatic tc09_random_outputs();
    logic [63:0] modes;
    logic [31:0] exp_out, v;
    int          errs;
    tc_banner("TC09 Random MODE / OUT / SET / CLEAR / TOGGLE sequence");
    dut_reset();

    modes   = '0;
    exp_out = '0;
    set_modes(modes);
    reg_write(R_OUT, exp_out);

    errs = 0;
    for (int i = 0; i < 200; i++) begin
      case ($urandom_range(0, 4))
        0: begin modes = {$urandom, $urandom}; set_modes(modes); end
        1: begin v = $urandom; reg_write(R_OUT,    v); exp_out  = v; end
        2: begin v = $urandom; reg_write(R_SET,    v); exp_out |= v; end
        3: begin v = $urandom; reg_write(R_CLEAR,  v); exp_out &= ~v; end
        4: begin v = $urandom; reg_write(R_TOGGLE, v); exp_out ^= v; end
      endcase
      if (gpio_out !== exp_out) begin
        if (errs < 3) $display("    op %0d: gpio_out 0x%08X != 0x%08X",
                               i, gpio_out, exp_out);
        errs++;
      end
      if (gpio_tx_en !== exp_tx_vec(modes, exp_out)) begin
        if (errs < 3) $display("    op %0d: gpio_tx_en_o 0x%08X != 0x%08X",
                               i, gpio_tx_en, exp_tx_vec(modes, exp_out));
        errs++;
      end
    end
    check_cnt("200 random output operations", errs);
    reg_expect("final value after random sequence", R_OUT, exp_out);
    reg_expect("final value after random sequence", R_MODE0, modes[31:0]);
    reg_expect("final value after random sequence", R_MODE1, modes[63:32]);
  endtask

  // ===========================================================================
  // TC10 — Input latency (3 edges from pin to GPIO_IN)
  // ===========================================================================
  task automatic tc10_input_latency();
    logic [31:0] v, prev;
    tc_banner("TC10 Input latency: gpio_in -> gpio_in_sync_o in 3 edges");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);

    prev = '0;
    for (int k = 0; k < 4; k++) begin
      case (k)
        0: v = 32'hFFFF_FFFF;
        1: v = 32'h0000_0000;
        2: v = 32'h5A5A_A5A5;
        default: v = $urandom;
      endcase
      gpio_in = v;
      cyc(1);
      check_val($sformatf("0x%08X: unchanged after 1 edge", v), gpio_in_sync, prev);
      cyc(1);
      check_val($sformatf("0x%08X: unchanged after 2 edges", v), gpio_in_sync, prev);
      cyc(1);
      check_val($sformatf("0x%08X: visible after 3 edges", v), gpio_in_sync, v);
      reg_expect($sformatf("reads 0x%08X", v), R_IN, v);
      prev = v;
    end
  endtask

  // ===========================================================================
  // TC11 — GPIO_EN gating of the input sampler
  // ===========================================================================
  task automatic tc11_input_enable();
    logic [31:0] rd;
    int          errs;
    tc_banner("TC11 GPIO_EN: disabled pins freeze their sampled value");
    dut_reset();

    reg_write(R_EN, 32'h0000_FFFF);
    gpio_in = 32'hFFFF_FFFF;
    cyc(5);
    check_val("only enabled pins sample the high input",
              gpio_in_sync, 32'h0000_FFFF);
    reg_expect("matches gpio_in_sync_o", R_IN, 32'h0000_FFFF);

    reg_write(R_EN, 32'hFFFF_FFFF);
    cyc(4);
    check_val("newly enabled pins pick the input up", gpio_in_sync, 32'hFFFF_FFFF);

    reg_write(R_EN, 32'h0000_FFFF);
    gpio_in = 32'h0000_0000;
    cyc(5);
    check_val("disabled pins hold their last sampled value",
              gpio_in_sync, 32'hFFFF_0000);
    reg_expect("holds the frozen value", R_IN, 32'hFFFF_0000);

    reg_write(R_EN, 32'hFFFF_FFFF);
    cyc(4);
    check_val("re-enabled pins resample the low input", gpio_in_sync, 32'h0000_0000);

    // Walk the enable over every pin
    errs = 0;
    for (int p = 0; p < NPINS; p++) begin
      reg_write(R_EN, 32'h1 << p);
      gpio_in = 32'hFFFF_FFFF;
      cyc(4);
      if (gpio_in_sync !== (32'h1 << p)) begin
        if (errs < 3) $display("    pin %0d enabled: sync 0x%08X != 0x%08X",
                               p, gpio_in_sync, 32'h1 << p);
        errs++;
      end
      gpio_in = 32'h0000_0000;
      cyc(4);
      if (gpio_in_sync !== 32'h0) begin
        if (errs < 3) $display("    pin %0d enabled: sync 0x%08X != 0", p, gpio_in_sync);
        errs++;
      end
    end
    check_cnt("enable walked over all 32 pins", errs);
  endtask

  // ===========================================================================
  // TC12 — Fast sampling: a new random vector every cycle
  // ===========================================================================
  task automatic tc12_fast_sampling();
    logic [31:0] v [128];
    int          errs;
    tc_banner("TC12 Fast input sampling (new vector every clock cycle)");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    gpio_in = '0;
    cyc(4);

    foreach (v[i]) v[i] = $urandom;

    errs = 0;
    for (int j = 0; j < 128; j++) begin
      // after edge j the synchroniser output must hold the vector applied
      // three edges earlier
      if (j >= 3 && gpio_in_sync !== v[j-3]) begin
        if (errs < 3) $display("    cycle %0d: sync 0x%08X != 0x%08X",
                               j, gpio_in_sync, v[j-3]);
        errs++;
      end
      gpio_in = v[j];
      cyc(1);
    end
    check_cnt("128 back-to-back input vectors sampled in order", errs);

    cyc(3);
    reg_expect("holds the last applied vector", R_IN, v[127]);
    gpio_in = '0;
    cyc(4);
  endtask

  // ===========================================================================
  // TC13 — Edge interrupts
  //
  // Preconditions for edge_timing(): GPIO_EN = all ones, CFG = 0 (both
  // interrupt outputs combinational), all status bits clear, only the edge
  // under test enabled, and the pin settled at the opposite level.
  // ===========================================================================
  task automatic edge_timing(input int p, input bit rise, input string label);
    gpio_in[p] = rise;
    cyc(1);                                     // after A
    check($sformatf("%s pin %0d: no interrupt after 1 edge", label, p),
          glb_irq, 1'b0);
    cyc(1);                                     // after B
    check($sformatf("%s pin %0d: interrupt asserted after 2 edges", label, p),
          glb_irq, 1'b1);
    check_val($sformatf("%s pin %0d: pin_level_interrupts_o", label, p),
              pin_irq, 32'h1 << p);
    cyc(1);                                     // after C
    check($sformatf("%s pin %0d: interrupt is a 1-cycle pulse (CFG=0)", label, p),
          glb_irq, 1'b0);
    check_val($sformatf("%s pin %0d: pin_level_interrupts_o back low", label, p),
              pin_irq, 32'h0);
  endtask

  task automatic tc13_edge_interrupts();
    int          pins [3];
    int          p;
    logic [31:0] rd;
    int          errs;
    tc_banner("TC13 Edge interrupts (rise / fall / both, pulse, sticky, glitch)");

    pins = '{0, NPINS-1, $urandom_range(1, NPINS-2)};

    foreach (pins[i]) begin
      p = pins[i];
      dut_reset();
      reg_write(R_EN, 32'hFFFF_FFFF);

      // --- rising edge ---
      reg_write(R_RISE_EN, 32'h1 << p);
      edge_timing(p, 1'b1, "RISE");
      reg_expect($sformatf("rising edge on pin %0d latched", p),
                 R_RISE_STATUS, 32'h1 << p);
      reg_expect("no falling-edge status", R_FALL_STATUS, 32'h0);
      reg_expect("aggregated status set", R_STATUS, 32'h1 << p);

      gpio_in[p] = 1'b0;                        // falling edge, not enabled
      cyc(5);
      reg_expect("falling edge ignored while INTRPT_FALL_EN=0",
                 R_FALL_STATUS, 32'h0);
      reg_expect("rise status is sticky", R_RISE_STATUS, 32'h1 << p);
      reg_write(R_RISE_STATUS, 32'h1 << p);
      reg_expect("cleared by W1C", R_RISE_STATUS, 32'h0);
      reg_expect("aggregated status cleared", R_STATUS, 32'h0);

      // --- falling edge ---
      reg_write(R_RISE_EN, 32'h0);
      gpio_in[p] = 1'b1;
      cyc(5);
      reg_write(R_FALL_EN, 32'h1 << p);
      edge_timing(p, 1'b0, "FALL");
      reg_expect($sformatf("falling edge on pin %0d latched", p),
                 R_FALL_STATUS, 32'h1 << p);
      reg_expect("no rising-edge status", R_RISE_STATUS, 32'h0);
      clear_all_status();

      // --- both edges ---
      reg_write(R_RISE_EN, 32'h1 << p);
      gpio_in[p] = 1'b1;
      cyc(5);
      gpio_in[p] = 1'b0;
      cyc(5);
      reg_expect("both-edge mode: rise latched", R_RISE_STATUS, 32'h1 << p);
      reg_expect("both-edge mode: fall latched", R_FALL_STATUS, 32'h1 << p);

      // --- sticky output mode (CFG = 3) ---
      reg_write(R_FALL_EN, 32'h0);
      clear_all_status();
      reg_write(R_CFG, 32'h3);
      gpio_in[p] = 1'b1;
      cyc(3);
      check($sformatf("CFG=3 pin %0d: interrupt asserted with the status bit", p),
            glb_irq, 1'b1);
      check_val("CFG=3: pin_level_interrupts_o follows the status bits",
                pin_irq, 32'h1 << p);
      cyc(10);
      check("CFG=3: interrupt stays asserted until the status is cleared",
            glb_irq, 1'b1);
      reg_write(R_RISE_STATUS, 32'h1 << p);
      check("CFG=3: interrupt drops when the status is cleared", glb_irq, 1'b0);
      reg_write(R_CFG, 32'h0);
      gpio_in[p] = 1'b0;
      cyc(5);
    end

    // --- every pin: rise and fall land on the right bit ---
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    errs = 0;
    for (int q = 0; q < NPINS; q++) begin
      reg_write(R_RISE_EN, 32'h1 << q);
      reg_write(R_FALL_EN, 32'h1 << q);
      gpio_in[q] = 1'b1;
      cyc(4);
      gpio_in[q] = 1'b0;
      cyc(4);
      reg_read(R_RISE_STATUS, rd);
      if (rd !== (32'h1 << q)) begin
        if (errs < 3) $display("    pin %0d rise status 0x%08X", q, rd);
        errs++;
      end
      reg_read(R_FALL_STATUS, rd);
      if (rd !== (32'h1 << q)) begin
        if (errs < 3) $display("    pin %0d fall status 0x%08X", q, rd);
        errs++;
      end
      reg_read(R_STATUS, rd);
      if (rd !== (32'h1 << q)) begin
        if (errs < 3) $display("    pin %0d aggregated status 0x%08X", q, rd);
        errs++;
      end
      reg_write(R_STATUS, 32'h1 << q);
      reg_read(R_STATUS, rd);
      if (rd !== 32'h0) begin
        if (errs < 3) $display("    pin %0d status not cleared: 0x%08X", q, rd);
        errs++;
      end
    end
    check_cnt("rise/fall interrupt walked over all 32 pins", errs);

    // --- a pulse narrower than one clock period must not be sampled ---
    dut_reset();
    reg_write(R_EN,       32'hFFFF_FFFF);
    reg_write(R_RISE_EN,  32'hFFFF_FFFF);
    reg_write(R_FALL_EN,  32'hFFFF_FFFF);
    mon_reset();
    #2 gpio_in = 32'hFFFF_FFFF;                 // glitch well inside one period
    #2 gpio_in = 32'h0000_0000;
    @(posedge clk); #1;                         // realign
    cyc(6);
    check("sub-cycle glitch raises no interrupt", glb_seen, 1'b0);
    reg_expect("no rise status from a glitch", R_RISE_STATUS, 32'h0);
    reg_expect("no fall status from a glitch", R_FALL_STATUS, 32'h0);
  endtask

  // ===========================================================================
  // TC14 — Level interrupts
  // ===========================================================================
  task automatic tc14_level_interrupts();
    int          pins [3];
    int          p;
    logic [31:0] rd;
    int          errs;
    tc_banner("TC14 Level interrupts (high / low, re-latch while asserted)");

    pins = '{0, NPINS-1, $urandom_range(1, NPINS-2)};

    foreach (pins[i]) begin
      p = pins[i];
      dut_reset();
      reg_write(R_EN, 32'hFFFF_FFFF);

      // --- level high ---
      reg_write(R_HIGH_EN, 32'h1 << p);
      cyc(3);
      check($sformatf("HIGH pin %0d: idle low, no interrupt", p), glb_irq, 1'b0);
      gpio_in[p] = 1'b1;
      cyc(2);
      check($sformatf("HIGH pin %0d: not asserted after 2 edges", p), glb_irq, 1'b0);
      cyc(1);
      check($sformatf("HIGH pin %0d: asserted after 3 edges", p), glb_irq, 1'b1);
      check_val("pin_level_interrupts_o", pin_irq, 32'h1 << p);
      cyc(10);
      check("level interrupt held while the input stays high", glb_irq, 1'b1);
      reg_expect("level-high status latched", R_HIGH_STATUS, 32'h1 << p);
      reg_write(R_HIGH_STATUS, 32'h1 << p);
      reg_expect("re-latches while the level is still present",
                 R_HIGH_STATUS, 32'h1 << p);
      gpio_in[p] = 1'b0;
      cyc(4);
      check("CFG=0: interrupt follows the level down", glb_irq, 1'b0);
      reg_expect("status stays set after the level goes away",
                 R_HIGH_STATUS, 32'h1 << p);
      reg_write(R_HIGH_STATUS, 32'h1 << p);
      reg_expect("clears once the level is gone", R_HIGH_STATUS, 32'h0);
      reg_write(R_HIGH_EN, 32'h0);

      // --- level low ---
      gpio_in[p] = 1'b1;
      cyc(5);
      clear_all_status();
      reg_write(R_LOW_EN, 32'h1 << p);
      cyc(3);
      check($sformatf("LOW pin %0d: input high, no interrupt", p), glb_irq, 1'b0);
      gpio_in[p] = 1'b0;
      cyc(2);
      check($sformatf("LOW pin %0d: not asserted after 2 edges", p), glb_irq, 1'b0);
      cyc(1);
      check($sformatf("LOW pin %0d: asserted after 3 edges", p), glb_irq, 1'b1);
      reg_expect("level-low status latched", R_LOW_STATUS, 32'h1 << p);
      reg_write(R_LOW_EN, 32'h0);
      clear_all_status();
    end

    // --- every pin ---
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    errs = 0;
    for (int q = 0; q < NPINS; q++) begin
      reg_write(R_HIGH_EN, 32'h1 << q);
      gpio_in[q] = 1'b1;
      cyc(5);
      reg_read(R_HIGH_STATUS, rd);
      if (rd !== (32'h1 << q)) begin
        if (errs < 3) $display("    pin %0d high status 0x%08X", q, rd);
        errs++;
      end
      reg_write(R_HIGH_EN, 32'h0);
      reg_write(R_LOW_EN,  32'h1 << q);
      cyc(3);
      reg_read(R_LOW_STATUS, rd);
      if (rd !== 32'h0) begin
        if (errs < 3) $display("    pin %0d low status set while input high: 0x%08X", q, rd);
        errs++;
      end
      gpio_in[q] = 1'b0;
      cyc(5);
      reg_read(R_LOW_STATUS, rd);
      if (rd !== (32'h1 << q)) begin
        if (errs < 3) $display("    pin %0d low status 0x%08X", q, rd);
        errs++;
      end
      reg_write(R_LOW_EN, 32'h0);
      clear_all_status();
    end
    check_cnt("level-high and level-low walked over all 32 pins", errs);
  endtask

  // ===========================================================================
  // TC15 — W1C semantics of the status registers
  // ===========================================================================
  task automatic tc15_w1c_semantics();
    localparam int P = 5;
    tc_banner("TC15 Status registers: write-1-to-clear semantics");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);

    // Latch rising edges on pins 3:0, then stop new ones
    reg_write(R_RISE_EN, 32'h0000_000F);
    gpio_in = 32'h0000_000F;
    cyc(5);
    reg_write(R_RISE_EN, 32'h0);
    reg_expect("pins 3:0 latched", R_RISE_STATUS, 32'h0000_000F);

    reg_write(R_RISE_STATUS, 32'h0000_0005);
    reg_expect("only the written bits clear", R_RISE_STATUS, 32'h0000_000A);
    reg_write(R_RISE_STATUS, 32'h0000_0000);
    reg_expect("writing 0 clears nothing", R_RISE_STATUS, 32'h0000_000A);
    reg_write(R_RISE_STATUS, 32'hFFFF_FFF0);
    reg_expect("1s on bits that are not pending are harmless",
               R_RISE_STATUS, 32'h0000_000A);
    reg_expect("aggregated view", R_STATUS, 32'h0000_000A);

    reg_write(R_STATUS, 32'h0000_0002);
    reg_expect("aggregated W1C clears the per-type bit", R_RISE_STATUS, 32'h0000_0008);
    reg_expect("aggregated view after clear", R_STATUS, 32'h0000_0008);

    // All four status types set on one pin, then cleared in one write
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    reg_write(R_RISE_EN, 32'h1 << P);
    reg_write(R_FALL_EN, 32'h1 << P);
    reg_write(R_HIGH_EN, 32'h1 << P);
    reg_write(R_LOW_EN,  32'h1 << P);
    gpio_in[P] = 1'b1;
    cyc(5);
    gpio_in[P] = 1'b0;
    cyc(5);
    reg_write(R_RISE_EN, 32'h0);
    reg_write(R_FALL_EN, 32'h0);
    reg_write(R_HIGH_EN, 32'h0);
    reg_write(R_LOW_EN,  32'h0);

    reg_expect($sformatf("pin %0d rise", P),  R_RISE_STATUS, 32'h1 << P);
    reg_expect($sformatf("pin %0d fall", P),  R_FALL_STATUS, 32'h1 << P);
    reg_expect($sformatf("pin %0d high", P),  R_HIGH_STATUS, 32'h1 << P);
    reg_expect($sformatf("pin %0d low", P),   R_LOW_STATUS,  32'h1 << P);
    reg_expect("aggregated", R_STATUS, 32'h1 << P);

    reg_write(R_STATUS, 32'h0);
    reg_expect("write of 0 leaves all four types set", R_STATUS, 32'h1 << P);
    reg_write(R_STATUS, ~(32'h1 << P));
    reg_expect("clearing other pins leaves this one set", R_STATUS, 32'h1 << P);

    reg_write(R_STATUS, 32'h1 << P);
    reg_expect("aggregated W1C cleared rise",  R_RISE_STATUS, 32'h0);
    reg_expect("aggregated W1C cleared fall",  R_FALL_STATUS, 32'h0);
    reg_expect("aggregated W1C cleared high",  R_HIGH_STATUS, 32'h0);
    reg_expect("aggregated W1C cleared low",   R_LOW_STATUS,  32'h0);
    check("global_interrupt_o low once every status is clear", glb_irq, 1'b0);
  endtask

  // ===========================================================================
  // TC16 — CFG.glbl_intrpt_mode and CFG.pin_lvl_intrpt_mode
  // ===========================================================================
  task automatic tc16_cfg_interrupt_modes();
    localparam int P = 2;
    tc_banner("TC16 CFG interrupt-mode bits are independent");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    reg_write(R_RISE_EN, 32'h1 << P);

    // CFG[0]=1: global sticky, per-pin combinational
    reg_write(R_CFG, 32'h1);
    reg_expect("glbl_intrpt_mode=1, pin_lvl_intrpt_mode=0", R_CFG, 32'h1);
    gpio_in[P] = 1'b1;
    cyc(2);
    check("CFG=1: pin output pulses with the edge", pin_irq[P], 1'b1);
    check("CFG=1: global output still low (status not latched yet)", glb_irq, 1'b0);
    cyc(1);
    check("CFG=1: pin output back low after the pulse", pin_irq[P], 1'b0);
    check("CFG=1: global output follows the latched status", glb_irq, 1'b1);
    cyc(8);
    check("CFG=1: global output stays asserted", glb_irq, 1'b1);
    reg_write(R_STATUS, 32'h1 << P);
    check("CFG=1: global output drops on status clear", glb_irq, 1'b0);

    // CFG[1]=1: global combinational, per-pin sticky
    gpio_in[P] = 1'b0;
    cyc(5);
    clear_all_status();
    reg_write(R_CFG, 32'h2);
    reg_expect("glbl_intrpt_mode=0, pin_lvl_intrpt_mode=1", R_CFG, 32'h2);
    gpio_in[P] = 1'b1;
    cyc(2);
    check("CFG=2: global output pulses with the edge", glb_irq, 1'b1);
    check("CFG=2: pin output still low", pin_irq[P], 1'b0);
    cyc(1);
    check("CFG=2: global output back low after the pulse", glb_irq, 1'b0);
    check("CFG=2: pin output follows the latched status", pin_irq[P], 1'b1);
    cyc(8);
    check("CFG=2: pin output stays asserted", pin_irq[P], 1'b1);
    reg_write(R_STATUS, 32'h1 << P);
    check("CFG=2: pin output drops on status clear", pin_irq[P], 1'b0);
    reg_write(R_CFG, 32'h0);
  endtask

  // ===========================================================================
  // TC17 — Interrupt masking
  // ===========================================================================
  task automatic tc17_masking();
    localparam int P = 3;
    logic [31:0] v, rd;
    tc_banner("TC17 Masked interrupts never fire");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    mon_reset();

    // Every enable is 0: heavy pin activity must produce nothing
    for (int i = 0; i < 40; i++) begin
      gpio_in = $urandom;
      cyc(2);
    end
    cyc(4);
    check("no interrupt with every enable at 0", glb_seen, 1'b0);
    check_val("no pin interrupt with every enable at 0", pin_seen, 32'h0);
    reg_expect("no status with every enable at 0", R_STATUS, 32'h0);

    // Only pin P enabled: only pin P may report
    gpio_in = '0;
    cyc(4);
    reg_write(R_RISE_EN, 32'h1 << P);
    reg_write(R_FALL_EN, 32'h1 << P);
    mon_reset();
    for (int i = 0; i < 40; i++) begin
      v    = $urandom;
      v[P] = i[0];                              // guarantee edges on pin P
      gpio_in = v;
      cyc(2);
    end
    cyc(4);
    check_val($sformatf("only pin %0d drives pin_level_interrupts_o", P),
              pin_seen & ~(32'h1 << P), 32'h0);
    check($sformatf("pin %0d did report", P), pin_seen[P], 1'b1);
    reg_read(R_RISE_STATUS, rd);
    check_val("rise status limited to the enabled pin", rd & ~(32'h1 << P), 32'h0);
    reg_read(R_FALL_STATUS, rd);
    check_val("fall status limited to the enabled pin", rd & ~(32'h1 << P), 32'h0);
    reg_read(R_HIGH_STATUS, rd);
    check_val("no level-high status while masked", rd, 32'h0);
    reg_read(R_LOW_STATUS, rd);
    check_val("no level-low status while masked", rd, 32'h0);

    gpio_in = '0;
    cyc(4);
  endtask

  // ===========================================================================
  // TC18 — Status clear coincident with a new edge             [BUG? check]
  //
  // prim_subreg_arb W1C computes wr_data = (de ? d : q) & ~wd, so a software
  // clear that commits on the same edge as a hardware set wins and the event
  // is dropped. With CFG=3 (sticky outputs) software then never sees the edge
  // at all. The control case below proves the stimulus alignment by clearing
  // one cycle earlier, where the edge must survive.
  // ===========================================================================
  task automatic tc18_clear_race();
    localparam int P = 0;
    logic [31:0] rd;
    logic        err;
    tc_banner("TC18 W1C clear on the same edge as a new edge event");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);
    reg_write(R_RISE_EN, 32'h1 << P);
    reg_write(R_CFG, 32'h3);                    // sticky outputs

    // Control: the clear commits on edge B, one cycle before the status is set
    gpio_in[P] = 1'b1;
    apb_xfer(1'b1, R_RISE_STATUS, 32'h1 << P, rd, err, 1'b1);
    psel = 1'b0; pwrite = 1'b0;
    cyc(3);
    reg_read(R_RISE_STATUS, rd);
    check_val("control: clear one cycle early, edge still latched",
              rd, 32'h1 << P);

    gpio_in[P] = 1'b0;
    cyc(5);
    clear_all_status();

    // Race A: the clear commits on edge C, the same edge that sets the status
    gpio_in[P] = 1'b1;
    cyc(1);
    apb_xfer(1'b1, R_RISE_STATUS, 32'h1 << P, rd, err, 1'b1);
    psel = 1'b0; pwrite = 1'b0;
    cyc(3);
    reg_read(R_RISE_STATUS, rd);
    check_bug("rising edge coincident with an INTRPT_RISE_STATUS W1C survives",
              rd[P] === 1'b1,
              $sformatf("INTRPT_RISE_STATUS=0x%08X, global_interrupt_o=%0b (CFG=3) -- the edge is lost",
                        rd, glb_irq));

    gpio_in[P] = 1'b0;
    cyc(5);
    clear_all_status();

    // Race B: same, through the aggregated INTRPT_STATUS register
    gpio_in[P] = 1'b1;
    cyc(1);
    apb_xfer(1'b1, R_STATUS, 32'h1 << P, rd, err, 1'b1);
    psel = 1'b0; pwrite = 1'b0;
    cyc(3);
    reg_read(R_RISE_STATUS, rd);
    check_bug("rising edge coincident with an INTRPT_STATUS W1C survives",
              rd[P] === 1'b1,
              $sformatf("INTRPT_RISE_STATUS=0x%08X, global_interrupt_o=%0b (CFG=3) -- the edge is lost",
                        rd, glb_irq));

    reg_write(R_CFG, 32'h0);
    gpio_in[P] = 1'b0;
    cyc(5);
  endtask

  // ===========================================================================
  // TC19 — Interrupts from a pin whose GPIO_EN is 0            [BUG? check]
  //
  // gpio_input_stage_no_clk_gates (the variant the SoC compiles) keeps the
  // 2-flop synchroniser running while en_i=0 but freezes serial_q, so
  // r_edge = serial & ~serial_q stays high for as long as the pin differs
  // from the frozen sample. The clock-gated variant does not behave this way.
  // ===========================================================================
  task automatic tc19_disabled_pin_interrupts();
    localparam int P = 7;
    logic [31:0] rd;
    int unsigned run_max;
    tc_banner("TC19 Interrupts from a disabled pin (GPIO_EN = 0)");
    dut_reset();

    reg_write(R_EN, ~(32'h1 << P));             // every pin except P enabled
    reg_write(R_RISE_EN, 32'h1 << P);
    mon_reset();
    gpio_in[P] = 1'b1;
    cyc(8);
    run_max = glb_run_max;

    reg_read(R_RISE_STATUS, rd);
    check_bug($sformatf("disabled pin %0d does not latch a rising-edge interrupt", P),
              rd[P] === 1'b0,
              $sformatf("INTRPT_RISE_STATUS=0x%08X although GPIO_EN[%0d]=0", rd, P));
    check_bug("edge interrupt output stays a pulse (CFG=0)",
              run_max <= 1,
              $sformatf("global_interrupt_o was high for %0d consecutive cycles",
                        run_max));
    if (rd[P] !== 1'b0 || run_max > 1) begin
      $display("    note: with en_i=0 the synchroniser keeps running while serial_q is");
      $display("          frozen; check that r_edge_o/f_edge_o in");
      $display("          gpio_input_stage_no_clk_gates.sv are qualified with en_i");
    end

    // A disabled pin reads back its frozen sample, so a level-low interrupt
    // fires even though the pin is high
    dut_reset();
    reg_write(R_EN, ~(32'h1 << P));
    gpio_in = 32'hFFFF_FFFF;
    cyc(5);
    reg_write(R_LOW_EN, 32'h1 << P);
    cyc(4);
    reg_read(R_LOW_STATUS, rd);
    check_bug($sformatf("disabled pin %0d with a high input raises no level-low interrupt", P),
              rd[P] === 1'b0,
              $sformatf("INTRPT_LVL_LOW_STATUS=0x%08X -- GPIO_IN[%0d] is frozen at its reset value 0",
                        rd, P));

    gpio_in = '0;
    cyc(4);
  endtask

  // ===========================================================================
  // TC20 — Asynchronous reset in the middle of an APB transfer
  // ===========================================================================
  task automatic tc20_reset_during_activity();
    logic [31:0] rd;
    int          errs;
    tc_banner("TC20 Asynchronous reset during an APB ACCESS phase");
    dut_reset();

    // Put the block in a thoroughly non-reset state
    set_modes({32'hFFFF_FFFF, 32'h5555_5555});
    reg_write(R_OUT,     32'hFFFF_FFFF);
    reg_write(R_EN,      32'hFFFF_FFFF);
    reg_write(R_CFG,     32'h3);
    reg_write(R_RISE_EN, 32'hFFFF_FFFF);
    reg_write(R_HIGH_EN, 32'h0000_00FF);
    gpio_in = 32'hFFFF_FFFF;
    cyc(5);
    check("sanity: interrupt asserted before reset", glb_irq, 1'b1);

    // Start a write and pull reset low inside the ACCESS phase
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b1;
    paddr   = GPIO_BASE + {20'h0, R_OUT};
    pwdata  = 32'h0;
    pstrb   = 4'hF;                             // full word, so the write guard lets it through
    @(posedge clk); #1;
    penable = 1'b1;
    #2 rst_n = 1'b0;
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    @(posedge clk); #1;

    check_val("gpio_out cleared asynchronously by reset", gpio_out, 32'h0);
    check_val("gpio_tx_en_o cleared by reset",            gpio_tx_en, 32'h0);
    check("global_interrupt_o cleared by reset",          glb_irq, 1'b0);

    cyc(2);
    rst_n = 1'b1;
    cyc(2);
    gpio_in = '0;
    cyc(4);

    errs = 0;
    foreach (ALL_OFF[i]) begin
      reg_read(ALL_OFF[i], rd);
      if (rd !== ((ALL_OFF[i] == R_INFO) ? INFO_EXP : 32'h0)) begin
        $display("    %s = 0x%08X after reset", reg_name(ALL_OFF[i]), rd);
        errs++;
      end
    end
    check_cnt("all 19 registers back at their reset values", errs);
  endtask

  // ===========================================================================
  // TC21 — Random mixed input/output activity
  // ===========================================================================
  task automatic tc21_random_mixed();
    logic [63:0] modes;
    logic [31:0] exp_out, exp_in, v, rd;
    int          errs;
    tc_banner("TC21 Random mixed input/output activity");
    dut_reset();
    reg_write(R_EN, 32'hFFFF_FFFF);

    modes   = '0;
    exp_out = '0;
    exp_in  = '0;
    set_modes(modes);
    reg_write(R_OUT, exp_out);

    errs = 0;
    for (int i = 0; i < 300; i++) begin
      case ($urandom_range(0, 6))
        0: begin modes = {$urandom, $urandom}; set_modes(modes); end
        1: begin v = $urandom; reg_write(R_OUT,    v); exp_out  = v; end
        2: begin v = $urandom; reg_write(R_SET,    v); exp_out |= v; end
        3: begin v = $urandom; reg_write(R_CLEAR,  v); exp_out &= ~v; end
        4: begin v = $urandom; reg_write(R_TOGGLE, v); exp_out ^= v; end
        5: begin exp_in = $urandom; gpio_in = exp_in; cyc(3); end
        6: begin
             reg_read(R_IN, rd);
             if (rd !== exp_in) begin
               if (errs < 3) $display("    op %0d: GPIO_IN 0x%08X != 0x%08X",
                                      i, rd, exp_in);
               errs++;
             end
           end
      endcase
      if (gpio_out !== exp_out) begin
        if (errs < 3) $display("    op %0d: gpio_out 0x%08X != 0x%08X",
                               i, gpio_out, exp_out);
        errs++;
      end
      if (gpio_tx_en !== exp_tx_vec(modes, exp_out)) begin
        if (errs < 3) $display("    op %0d: gpio_tx_en_o 0x%08X != 0x%08X",
                               i, gpio_tx_en, exp_tx_vec(modes, exp_out));
        errs++;
      end
      if (gpio_in_sync !== exp_in) begin
        if (errs < 3) $display("    op %0d: gpio_in_sync_o 0x%08X != 0x%08X",
                               i, gpio_in_sync, exp_in);
        errs++;
      end
    end
    check_cnt("300 random mixed operations", errs);
  endtask

  // ===========================================================================
  // TC22 — Sub-word write guard (gpio_apb_wrap)
  //
  // apb_to_reg discards PSTRB and gpio_reg_top writes all 32 bits of the bus
  // data, so gpio_apb_wrap blocks every write whose PSTRB is not all ones and
  // answers with PSLVERR itself. Checked on the three register kinds the guard
  // protects: plain RW (GPIO_OUT), write-only hwext (GPIO_SET) and W1C
  // (INTRPT_RISE_STATUS), plus recovery straight after a rejected write.
  // ===========================================================================
  task automatic tc22_sub_word_write_guard();
    localparam logic [31:0] OUT_INIT = 32'hA5A5_A5A5;
    logic [3:0]  strbs [8];
    logic [31:0] rd;
    logic        err, err_rejected;
    int          err_errs, val_errs;
    tc_banner("TC22 Sub-word writes are rejected with PSLVERR");
    dut_reset();
    set_modes(all_modes(M_PUSH));
    reg_write(R_OUT, OUT_INIT);

    // Every strobe pattern a byte or half-word store produces, plus the
    // three-byte and no-byte cases
    strbs = '{4'b0001, 4'b0010, 4'b0100, 4'b1000,
              4'b0011, 4'b1100, 4'b0111, 4'b0000};

    err_errs = 0;
    val_errs = 0;
    foreach (strbs[i]) begin
      apb_xfer(1'b1, R_OUT, ~OUT_INIT, rd, err, 1'b0, strbs[i]);
      if (err !== 1'b1) begin
        $display("    GPIO_OUT pstrb=%04b: pslverr=%0b (expected 1)", strbs[i], err);
        err_errs++;
      end
      if (gpio_out !== OUT_INIT) begin
        $display("    GPIO_OUT pstrb=%04b: gpio_out=0x%08X, register was modified",
                 strbs[i], gpio_out);
        val_errs++;
      end
    end
    check_cnt("GPIO_OUT: 8 partial-strobe writes return PSLVERR", err_errs);
    check_cnt("GPIO_OUT: 8 partial-strobe writes leave the pins unchanged", val_errs);
    reg_expect("unchanged after partial-strobe writes", R_OUT, OUT_INIT);

    // Write-only hwext register: a byte SET must not drive any pin
    apb_xfer(1'b1, R_SET, 32'hFFFF_FFFF, rd, err, 1'b0, 4'b0001);
    check("GPIO_SET byte write returns PSLVERR", err, 1'b1);
    check_val("GPIO_SET byte write drives no pin", gpio_out, OUT_INIT);

    // W1C status register: a byte write must not acknowledge pending bits
    reg_write(R_EN, 32'hFFFF_FFFF);
    reg_write(R_RISE_EN, 32'h0000_00FF);
    gpio_in = 32'h0000_00FF;
    cyc(5);
    reg_write(R_RISE_EN, 32'h0);
    reg_expect("pins 7:0 latched", R_RISE_STATUS, 32'h0000_00FF);
    apb_xfer(1'b1, R_RISE_STATUS, 32'h0000_00FF, rd, err, 1'b0, 4'b0001);
    check("INTRPT_RISE_STATUS byte write returns PSLVERR", err, 1'b1);
    reg_expect("pending bits not cleared by a byte write",
               R_RISE_STATUS, 32'h0000_00FF);

    // A full-word write straight after a rejected one, PSEL held high between
    // them: the guard must not stick
    apb_xfer(1'b1, R_OUT, 32'h0000_0000, rd, err_rejected, 1'b1, 4'b0011);
    apb_xfer(1'b1, R_OUT, 32'h1234_5678, rd, err, 1'b0, 4'hF);
    check("back-to-back: half-word write rejected", err_rejected, 1'b1);
    check("back-to-back: following full-word write accepted", err, 1'b0);
    check_val("back-to-back: full-word write takes effect", gpio_out, 32'h1234_5678);

    gpio_in = '0;
    cyc(4);
  endtask

  // ===========================================================================
  // Summary and main sequence
  // ===========================================================================
  task automatic print_summary();
    $display("");
    $display("===============================================================");
    $display(" TB SUMMARY: %0d PASSED / %0d FAILED / %0d SUSPECTED RTL ISSUES",
             pass_cnt, fail_cnt, bug_cnt);
    $display("===============================================================");
    if (fail_cnt == 0 && bug_cnt == 0)
      $display("*** ALL TESTS PASSED ***");
    else if (fail_cnt == 0)
      $display("*** NO FUNCTIONAL FAILURES - %0d [BUG?] ITEM(S) NEED REVIEW ***",
               bug_cnt);
    else
      $display("*** %0d CHECK(S) FAILED ***", fail_cnt);
    $display("");
  endtask

  // Global watchdog
  initial begin
    #(GLOBAL_WD_NS);
    $display("  [FAIL] global watchdog expired after %0d ns", GLOBAL_WD_NS);
    fail_cnt++;
    print_summary();
    $finish;
  end

  initial begin : main
    int unsigned seed;

    $display("");
    $display("===============================================================");
    $display(" tb_gpio_apb_directed - GPIO (gpio_apb_wrap), %0d pins", NPINS);
    $display("===============================================================");

    if (NPINS != 32)
      $fatal(1, "This testbench assumes gpio_reg_pkg::GPIOCount == 32 (is %0d)",
             NPINS);

    seed = 32'd1;
    void'($value$plusargs("SEED=%d", seed));
    process::self().srandom(seed);
    $display(" random seed = %0d (override with +SEED=<n>)", seed);

    dut_reset();

    tc01_reset_values();
    tc02_rw_registers();
    tc03_ro_wo_registers();
    tc04_unmapped();
    tc05_address_aliasing();
    tc06_back_to_back();
    tc07_pin_modes();
    tc08_set_clear_toggle();
    tc09_random_outputs();
    tc10_input_latency();
    tc11_input_enable();
    tc12_fast_sampling();
    tc13_edge_interrupts();
    tc14_level_interrupts();
    tc15_w1c_semantics();
    tc16_cfg_interrupt_modes();
    tc17_masking();
    tc18_clear_race();
    tc19_disabled_pin_interrupts();
    tc20_reset_during_activity();
    tc21_random_mixed();
    tc22_sub_word_write_guard();

    print_summary();
    $finish;
  end

endmodule
