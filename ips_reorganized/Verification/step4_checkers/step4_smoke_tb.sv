// =============================================================================
//  step4_smoke_tb.sv : Step 4 self-proof testbench
// =============================================================================
//  The integration guide makes the Step 4 proof explicit:
//
//    "each injected fault is named by the correct check ID in the report, and
//     every assertion has a cover that is hit."
//
//  This bench is that proof.  It is not a SoC test: it is a checker test.
//
//  WHAT IT DOES
//    Phase 1  Clean traffic.  A real axi_lite_to_apb is driven through reads,
//             writes, sub-word writes, an unmapped read and a zero-strobe write.
//             ZERO findings are allowed.  This is the important half of the
//             proof: it shows the path scoreboard's prediction of what the
//             bridge does -- read with a rule -> one APB transfer, write with
//             |strb -> one APB transfer, write with strb==0 -> none and OKAY,
//             read with no rule -> none and DECERR -- matches the actual RTL
//             rather than matching a wish.  A scoreboard that fires on golden
//             RTL is worse than no scoreboard.
//
//    Phase 2  Fault matrix.  One injection per case, then the ID of the first
//             check to fire is compared against the ID that case is supposed to
//             produce.  Both directions matter: the right check must fire, and
//             no other check may get there first.
//
//  THE REAL BRIDGE, NOT A STUB
//  axi_lite_to_apb is compiled in from the SoC source tree.  A stub would prove
//  only that the scoreboard agrees with itself.
// =============================================================================

`include "step4_cfg.svh"

module step4_smoke_tb;

  import step4_pkg::*;
  import step4_fault_inject_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;   // 100 MHz, 10 ns period

  //  Bus types come from step4_bus_pkg, which mirrors
  //  riscforge_soc_subsystem.sv:335-413 field for field.  At package scope
  //  rather than module scope because xsim will not connect an
  //  unpacked-array port whose parameter type is a module-local typedef.
  import step4_bus_pkg::*;
// ---------------------------------------------------------------------------
  // The DUT under test: an AXI4-Lite to APB4 bridge
  //
  //  WHY A MODEL AND NOT axi_lite_to_apb ITSELF
  //  axi_lite_to_apb declares its APB ports as unpacked arrays of a parameter
  //  type (axi_lite_to_apb.sv:69-70).  xsim refuses to elaborate that port
  //  connection -- "cannot assign a packed type to an unpacked type" -- whatever
  //  the declaring scope.  Xcelium and VCS handle it, which is why the SoC
  //  testbenches run there (see tb_gpio_apb_directed.f).  So the self-proof,
  //  which has to run in the xsim inner loop, uses the model below, and the
  //  checkers are additionally bound to the real bridge in the SoC regression.
  //
  //  Every arm of the model carries the line of axi_lite_to_apb.sv it
  //  reproduces, so the model can be diffed against the RTL rather than
  //  trusted.  It is a model of the DECISION LOGIC only: it does not attempt to
  //  reproduce the spill-register timing, which the AXI assertions check
  //  independently.
  // ---------------------------------------------------------------------------
  localparam int N = NUM_APB_SLAVES;

  axi_req_t   m_axi_req;
  axi_resp_t  m_axi_resp;

  logic [N-1:0]        br_psel, br_penable, br_pwrite;
  logic [N-1:0]        br_pready, br_pslverr;
  logic [N-1:0][31:0]  br_paddr, br_pwdata, br_prdata;
  logic [N-1:0][3:0]   br_pstrb;

  rule_t [N-1:0] apb_addr_map;
  for (genvar g = 0; g < N; g++) begin : g_map
    assign apb_addr_map[g] = '{idx: g, start_addr: SLOT_BASE[g], end_addr: SLOT_END[g]};
  end

  step4_apb_bridge_model u_br (
    .clk (clk), .rst_n (rst_n),
    .axi_req_i  (m_axi_req),
    .axi_resp_o (m_axi_resp),
    .apb_addr_map (apb_addr_map),
    .apb_psel_o (br_psel), .apb_penable_o (br_penable), .apb_pwrite_o (br_pwrite),
    .apb_paddr_o (br_paddr), .apb_pwdata_o (br_pwdata), .apb_pstrb_o (br_pstrb),
    .apb_pready_i (br_pready), .apb_prdata_i (br_prdata), .apb_pslverr_i (br_pslverr)
  );

  // ---------------------------------------------------------------------------
  // Six APB slaves: zero wait state, byte strobes honoured, never an error.
  // ---------------------------------------------------------------------------
for (genvar g = 0; g < N; g++) begin : g_slave
    step4_apb_slave #(.SLOT(g)) u_slave (
      .clk       (clk),
      .rst_n     (rst_n),
      .paddr_i   (br_paddr[g]),
      .pprot_i   (3'b000),
      .psel_i    (br_psel[g]),
      .penable_i (br_penable[g]),
      .pwrite_i  (br_pwrite[g]),
      .pwdata_i  (br_pwdata[g]),
      .pstrb_i   (br_pstrb[g]),
      .prdata_o  (br_prdata[g]),
      .pready_o  (br_pready[g]),
      .pslverr_o (br_pslverr[g])
    );
  end

  // ---------------------------------------------------------------------------
  // The "core LSU" stub.  Mirrors hybrid_mem_interface: the access is presented
  // on the mem_* port, held while the transaction is in flight, and mem_req is
  // only asserted for addresses inside the MMIO window.
  // ---------------------------------------------------------------------------
  logic        lsu_req = 1'b0, lsu_we = 1'b0, lsu_stall = 1'b0;
  logic [31:0] lsu_addr = '0, lsu_wdata = '0;
  logic [3:0]  lsu_be = 4'hF;

  wire lsu_to_axi = lsu_req && !lsu_stall;

  // ---------------------------------------------------------------------------
  // Reporter + injectors
  // ---------------------------------------------------------------------------
  step4_hub    hub (.clk(clk), .rst_n(rst_n));
  step4_reporter u_rep (.clk(clk), .rst_n(rst_n), .hub(hub));

  step4_fault_inject_cfg_t fi_cfg = '0;

  //  Flattened APB payload for the injector.
  logic [5:0]        s_psel, s_penable, s_pwrite, s_pready, s_pslverr;
  logic [5:0][31:0]  s_paddr, s_pwdata, s_prdata;
  logic [5:0][3:0]   s_pstrb;
  //  The bridge model presents flat vectors, so no flattening is needed here.
  //  Against the real SoC the same checkers get these from flatten_apb_req() and
  //  flatten_apb_rsp() in step4_bus_pkg.
  assign s_psel    = br_psel;
  assign s_penable = br_penable;
  assign s_pwrite  = br_pwrite;
  assign s_pready  = br_pready;
  assign s_pslverr = br_pslverr;
  assign s_paddr   = br_paddr;
  assign s_pwdata  = br_pwdata;
  assign s_prdata  = br_prdata;
  assign s_pstrb   = br_pstrb;

  //  Injected view: what the checkers observe.
  logic [5:0]        f_psel, f_penable, f_pwrite, f_pready, f_pslverr;
  logic [5:0][31:0]  f_paddr, f_pwdata, f_prdata;
  logic [5:0][3:0]   f_pstrb;
  logic [31:0]       f_lsu_addr, f_lsu_wdata, f_aw_addr, f_w_data, f_ar_addr, f_r_data;
  logic [3:0]        f_lsu_be, f_w_strb;
  logic [1:0]        f_b_resp, f_r_resp;

  step4_fault_inject u_fi (
    .clk (clk), .rst_n (rst_n), .cfg (fi_cfg),
    .i_lsu_req (lsu_req), .i_lsu_we (lsu_we), .i_lsu_stall (lsu_stall),
    .i_aw_valid (m_axi_req.aw_valid), .i_aw_ready (m_axi_resp.aw_ready),
    .i_w_valid  (m_axi_req.w_valid),  .i_w_ready  (m_axi_resp.w_ready),
    .i_ar_valid (m_axi_req.ar_valid), .i_ar_ready (m_axi_resp.ar_ready),
    .i_b_valid  (m_axi_resp.b_valid), .i_b_ready  (m_axi_req.b_ready),
    .i_r_valid  (m_axi_resp.r_valid), .i_r_ready  (m_axi_req.r_ready),
    .i_psel (s_psel), .i_penable (s_penable), .i_pwrite (s_pwrite),
    .i_pready (s_pready),
    .i_lsu_addr (lsu_addr), .i_lsu_wdata (lsu_wdata), .i_lsu_be (lsu_be),
    .i_aw_addr (m_axi_req.aw.addr), .i_w_data (m_axi_req.w.data),
    .i_w_strb (m_axi_req.w.strb), .i_ar_addr (m_axi_req.ar.addr),
    .i_b_resp (m_axi_resp.b.resp), .i_r_resp (m_axi_resp.r.resp),
    .i_r_data (m_axi_resp.r.data),
    .i_paddr (s_paddr), .i_pwdata (s_pwdata), .i_prdata (s_prdata),
    .i_pstrb (s_pstrb), .i_pslverr (s_pslverr),
    .o_lsu_addr (f_lsu_addr), .o_lsu_wdata (f_lsu_wdata), .o_lsu_be (f_lsu_be),
    .o_aw_addr (f_aw_addr), .o_w_data (f_w_data), .o_w_strb (f_w_strb),
    .o_ar_addr (f_ar_addr), .o_b_resp (f_b_resp), .o_r_resp (f_r_resp),
    .o_r_data (f_r_data),
    .o_paddr (f_paddr), .o_pwdata (f_pwdata), .o_prdata (f_prdata),
    .o_pstrb (f_pstrb), .o_pslverr (f_pslverr), .o_psel (f_psel), .o_penable (f_penable), .o_pready (f_pready)
  );

  // ---------------------------------------------------------------------------
  // The checkers, fed the injected view
  // ---------------------------------------------------------------------------
  step4_axi_sva #(.PORT_NAME("bridge-axi")) u_axi_sva (
    .clk (clk), .rst_n (rst_n),
    .aw_addr (f_aw_addr), .aw_prot (m_axi_req.aw.prot),
    .aw_valid (m_axi_req.aw_valid), .aw_ready (m_axi_resp.aw_ready),
    .w_data (f_w_data), .w_strb (f_w_strb),
    .w_valid (m_axi_req.w_valid), .w_ready (m_axi_resp.w_ready),
    .b_resp (f_b_resp), .b_valid (m_axi_resp.b_valid), .b_ready (m_axi_req.b_ready),
    .ar_addr (f_ar_addr), .ar_prot (m_axi_req.ar.prot),
    .ar_valid (m_axi_req.ar_valid), .ar_ready (m_axi_resp.ar_ready),
    .r_data (f_r_data), .r_resp (f_r_resp),
    .r_valid (m_axi_resp.r_valid), .r_ready (m_axi_req.r_ready),
    .hub (hub)
  );

  step4_apb_sva u_apb_sva (
    .clk (clk), .rst_n (rst_n),
    //  PSEL comes from the injected view (f_psel == s_psel except during a
    //  FI_WAIT stall, which holds the access phase in the checker view so the
    //  completion bound can expire). Everything else unchanged.
    .psel (f_psel), .penable (f_penable), .pwrite (s_pwrite),
    .pready (f_pready), .pslverr (f_pslverr),
    .paddr (f_paddr), .pwdata (f_pwdata), .pstrb (f_pstrb), .prdata (f_prdata),
    .tmo_pulse (6'b0),
    .hub (hub)
  );

  step4_path_scoreboard u_sb (
    .clk (clk), .rst_n (rst_n),
    .lsu_req (lsu_req), .lsu_addr (f_lsu_addr), .lsu_we (lsu_we),
    .lsu_wdata (f_lsu_wdata), .lsu_be (f_lsu_be), .lsu_stall (lsu_stall),
    .aw_addr (f_aw_addr), .aw_valid (m_axi_req.aw_valid), .aw_ready (m_axi_resp.aw_ready),
    .w_data (f_w_data), .w_strb (f_w_strb),
    .w_valid (m_axi_req.w_valid), .w_ready (m_axi_resp.w_ready),
    .ar_addr (f_ar_addr), .ar_valid (m_axi_req.ar_valid), .ar_ready (m_axi_resp.ar_ready),
    .b_valid (m_axi_resp.b_valid), .b_ready (m_axi_req.b_ready), .b_resp (f_b_resp),
    .r_valid (m_axi_resp.r_valid), .r_ready (m_axi_req.r_ready), .r_resp (f_r_resp),
    .r_data (f_r_data), .axi_tmo_pulse (1'b0),
    .boot_aw_addr (32'h0), .boot_aw_valid (1'b0), .boot_aw_ready (1'b0),
    .boot_ar_addr (32'h0), .boot_ar_valid (1'b0), .boot_ar_ready (1'b0),
    .apb_psel (s_psel), .apb_penable (f_penable), .apb_pwrite (s_pwrite),
    .apb_pready (f_pready), .apb_pslverr (f_pslverr),
    .apb_paddr (f_paddr), .apb_pwdata (f_pwdata), .apb_prdata (f_prdata),
    .apb_pstrb (f_pstrb), .apb_tmo_pulse (6'b0),
    .hub (hub)
  );

  // ---------------------------------------------------------------------------
  // AXI-Lite master BFM
  // ---------------------------------------------------------------------------
  task automatic axi_reset_idle();
    m_axi_req = '0;
    @(negedge clk);
    repeat (3) @(posedge clk);
    @(negedge clk);
  endtask

  //  ---------------------------------------------------------------------------
  //  AXI-Lite master BFM.
  //
  //  DRIVE ON THE NEGEDGE, SAMPLE ON THE POSEDGE.  Driving and checking in the
  //  same clocking region is a race: the BFM would clear VALID in the same delta
  //  cycle the slave sampled it, so the handshake would appear to complete one
  //  cycle early and the slave would never see the request at all.  With the
  //  split, VALID is up for a full cycle before READY is looked at.
  //
  //  LAUNCH CYCLE WITH lsu_stall LOW.  The scoreboard taps the core MMIO access
  //  at lsu_req && in-range && !lsu_stall, which is exactly the cycle the real
  //  hybrid_mem_interface asserts axi_req_active (hybrid_mem_interface.sv:75)
  //  and only then raises mem_stall.  A BFM that holds lsu_stall high from the
  //  first cycle makes that tap never fire, and the whole path check silently
  //  does nothing while every other checker still looks healthy.  It did exactly
  //  that once; the reporter's vacuity check is what caught it, which is the
  //  argument for having that check at all.
  // ---------------------------------------------------------------------------
  task automatic do_write(input logic [31:0] addr, input logic [31:0] data,
                          input logic [3:0] strb);
    int guard = 0;
    bit aw_done = 0, w_done = 0, b_done = 0;

    //  Present on the LSU port exactly as the core would, then hold it until the
    //  transaction retires -- which is what core_lsu_stall does.
    @(negedge clk);
    lsu_req    = 1'b1;
    lsu_we     = 1'b1;
    lsu_addr   = addr;
    lsu_wdata  = data;
    lsu_be     = strb;
     lsu_stall  = 1'b0;   // launch cycle -- see the note below

    m_axi_req.aw_valid = 1'b1;
    m_axi_req.aw.addr  = addr;
    m_axi_req.w_valid  = 1'b1;
    m_axi_req.w.data   = data;
    m_axi_req.w.strb   = strb;
    m_axi_req.b_ready  = 1'b1;
    //  Hold the core exactly one launch cycle, then stall it -- but without
    //  consuming a cycle in THIS thread: the handshake loop below must sample
    //  the very first posedge after the drive, otherwise a handshake that
    //  completes immediately is missed and the lingering VALID re-latches in
    //  the bridge spill registers as a phantom second transfer (ghost APB
    //  access, stranded ghost response wedging resp_v and every later read,
    //  plus a spurious AXIL-1006 on clean traffic). The forked thread sets the
    //  stall while this thread proceeds straight to sampling.
    fork
      begin @(negedge clk); lsu_stall = 1'b1; end
    join_none


    while (!b_done && guard < 400) begin
      @(posedge clk);
      guard++;
      //  Sample BOTH handshakes first, then drop VALID once, at a single
      //  negedge.  Sequential per-channel negedge waits let one channel's
      //  VALID linger a full cycle after the other, which re-latches (see the
      //  note above).  One shared drop keeps this BFM a legal AXI master.
      if (!aw_done && m_axi_req.aw_valid && m_axi_resp.aw_ready) begin aw_done = 1; end
      if (!w_done  && m_axi_req.w_valid  && m_axi_resp.w_ready)  begin w_done  = 1; end
      if (aw_done && m_axi_req.aw_valid || w_done && m_axi_req.w_valid) begin
        @(negedge clk);
        if (aw_done) m_axi_req.aw_valid = 1'b0;
        if (w_done)  m_axi_req.w_valid  = 1'b0;
      end
      //  One extra edge after the response appears.  Exiting the loop on the
      //  LEVEL of b_valid and dropping b_ready at the next negedge leaves the
      //  slave one edge short of ever seeing the handshake: BVALID goes high
      //  after an edge, the master drops READY before the following edge, and
      //  the response is stranded with READY low for ever.  The bridge then
      //  stops accepting the next request and the run wedges with no message.
      if (m_axi_resp.b_valid)              begin b_done  = 1; @(posedge clk); end
    end

    //  Never leave VALID asserted behind, whatever happened above: a stranded
    //  aw_valid with w_ready low wedges the bus for the rest of the run and
    //  every later symptom is a consequence.
    @(negedge clk);
    m_axi_req.aw_valid = 1'b0;
    m_axi_req.w_valid  = 1'b0;
    m_axi_req.b_ready  = 1'b0;
    lsu_req  = 1'b0;
    lsu_we   = 1'b0;
    lsu_stall = 1'b0;
    repeat (2) @(posedge clk);
  endtask

  task automatic do_read(input logic [31:0] addr, output logic [31:0] rdata);
    int guard = 0;
    bit ar_done = 0, r_done = 0;

    @(negedge clk);
    lsu_req    = 1'b1;
    lsu_we     = 1'b0;
    lsu_addr   = addr;
     lsu_stall  = 1'b0;   // launch cycle -- see the note below

    m_axi_req.ar_valid = 1'b1;
    m_axi_req.ar.addr  = addr;
    m_axi_req.r_ready  = 1'b1;
    //  Same launch-cycle treatment as the write path: the handshake loop must
    //  sample the first posedge after the drive, or a lingering ARVALID
    //  re-latches as a phantom second read. See the note in do_write.
    fork
      begin @(negedge clk); lsu_stall = 1'b1; end
    join_none


    while (!r_done && guard < 400) begin
      @(posedge clk);
      guard++;
      //  Drop ARVALID at the first negedge after its handshake is observed.
      //  Waiting longer lets the lingering VALID re-latch (see do_write).
      if (!ar_done && m_axi_req.ar_valid && m_axi_resp.ar_ready) begin
        ar_done = 1;
        @(negedge clk);
        m_axi_req.ar_valid = 1'b0;
      end
      //  Same one-extra-edge rule as the write path; see the note there.
      if (m_axi_resp.r_valid)              begin r_done  = 1; rdata = m_axi_resp.r.data; @(posedge clk); end
    end

    @(negedge clk);
    m_axi_req.ar_valid = 1'b0;
    m_axi_req.r_ready  = 1'b0;
    lsu_req   = 1'b0;
    lsu_stall = 1'b0;
    repeat (2) @(posedge clk);
  endtask
  // ---------------------------------------------------------------------------
  // Phase 1 -- clean traffic.  Zero findings is the pass criterion.
  // ---------------------------------------------------------------------------
  //  ---------------------------------------------------------------------------
  //  Retire-window stub.
  //
  //  In the SoC the retire window is filled by the RVFI-style retire monitor
  //  from Step 6.  It does not exist yet, and the reporter's disassembly is one
  //  of the things Step 4 is required to deliver, so it gets exercised here with
  //  a short hand-written instruction sequence.  The encodings are chosen to
  //  cover the cases a reader will actually hit when triaging an MMIO bug:
  //  a load, a store, and the compressed-looking pseudo-instruction that shows up
  //  in hand-written assembly tests.
  //
  //  Replace with the real retire port once Step 6 lands; nothing else changes,
  //  because the reporter only ever reads hub.ret_pc / hub.ret_in.
  // ---------------------------------------------------------------------------
  //  Minimal instruction encoders.  Building the retire window from named
  //  fields instead of hand-typed hex removes a whole class of silent error:
  //  a mistyped word in the retire window makes the failure report disassemble
  //  to something plausible and wrong, which is worse than showing nothing.
  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                        input logic [2:0] f3, input logic [4:0] rd,
                                        input logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_r(input logic [6:0] funct7, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [4:0] rd, input logic [6:0] op);
    return {funct7, rs2, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction

  function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [6:0] op);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
  endfunction

  function automatic logic [31:0] enc_u(input logic [19:0] imm, input logic [4:0] rd,
                                        input logic [6:0] op);
    return {imm, rd, op};
  endfunction

  task automatic seed_retire_window();
    localparam logic [6:0] OP_LUI = 7'b0110111, OP_ADDI = 7'b0010011,
                         OP_LW  = 7'b0000011, OP_SW  = 7'b0100011,
                         OP_BLT = 7'b1100011, OP_SYS = 7'b1110011;
    hub.ret_pc[0] = 32'h0001_0000;
    hub.ret_in[0] = enc_u(20'h40000, 5'd5, OP_LUI);        // lui   x5, 0x40000
    hub.ret_pc[1] = 32'h0001_0004;
    hub.ret_in[1] = enc_i(12'd768, 5'd0, 3'b000, 5'd6, OP_ADDI);    // addi x6, x0, 768
    hub.ret_pc[2] = 32'h0001_0008;
    hub.ret_in[2] = enc_s(12'h040, 5'd6, 5'd5, 3'b010, OP_SW);     // sw    x6, 0x40(x5)
    hub.ret_pc[3] = 32'h0001_000c;
    hub.ret_in[3] = enc_i(12'h040, 5'd5, 3'b010, 5'd7, OP_LW);     // lw    x7, 0x40(x5)
    hub.ret_pc[4] = 32'h0001_0010;
    hub.ret_in[4] = enc_i(12'd520, 5'd0, 3'b000, 5'd4, OP_ADDI);   // addi  x4, x0, 520
    hub.ret_pc[5] = 32'h0001_0014;
    hub.ret_in[5] = enc_s(12'h000, 5'd4, 5'd5, 3'b010, OP_SW);     // sw    x4, 0(x5)
    hub.ret_pc[6] = 32'h0001_0018;
    hub.ret_in[6] = enc_i(12'h302, 5'd0, 3'b000, 5'd0, OP_SYS);    // mret
    hub.ret_pc[7] = 32'h0001_001c;
    hub.ret_in[7] = enc_b(13'd8, 5'd5, 5'd0, 3'b100, OP_BLT);     // blt   x0, x5, +8
    hub.wp_ret  = 8;
    hub.cnt_ret = 8;
  endtask
  int unsigned phase1_findings = 0;
  bit           phase1_traffic_ok = 0;
  int unsigned fi_pass = 0, fi_fail = 0;
  logic [31:0] rd;

  task automatic phase1_clean();
    u_rep.arm_run("phase1-clean");
    for (int s = 0; s < N; s++) begin
      logic [31:0] base;
      base = SLOT_BASE[s] + 32'h20;
      do_write(base, 32'hA5A5_1234, 4'hF);
      do_read (base, rd);
      if (rd !== 32'hA5A5_1234)
        $display("[STEP4] PHASE1 DATA MISMATCH slot %0d: read 0x%08h", s, rd);
    end
    //  Sub-word write: byte lane 2 only.
    do_write(SLOT_BASE[3] + 32'h40, 32'h0000_FF00, 4'b0100);
    do_read (SLOT_BASE[3] + 32'h40, rd);
    //  Unmapped read inside the APB window: no rule matches -> DECERR.
    do_read (32'h4000_6000, rd);
    //  Write with every strobe clear: no APB transfer, RESP_OKAY.
    do_write(SLOT_BASE[0] + 32'h60, 32'hDEAD_BEEF, 4'h0);
    //  GPIO alias hole: 0x4000_3800 is past the 2 KB rule -> DECERR.
    do_read (32'h4000_3800, rd);
    phase1_findings = hub.n_find;

    //  The pass rule's vacuity clause, applied to the self-proof itself.  Zero
    //  findings is only meaningful if the checkers actually saw the traffic: a
    //  scoreboard wired to the wrong tap reports nothing, forever, happily.
    phase1_traffic_ok = (hub.stats.lsu_reqs    > 0) &&
                        (hub.stats.axi_wrs     > 0) &&
                        (hub.stats.axi_rds     > 0) &&
                        (u_sb.apb_xfer_count() > 0);
    if (!phase1_traffic_ok)
      $display("[STEP4] PHASE 1 *** VACUOUS *** lsu=%0d awr=%0d ard=%0d apb=%0d -- the checkers saw nothing",
               hub.stats.lsu_reqs, hub.stats.axi_wrs, hub.stats.axi_rds, u_sb.apb_xfer_count());
    else
      $display("[STEP4] PHASE 1 traffic: lsu=%0d awr=%0d ard=%0d apb=%0d",
               hub.stats.lsu_reqs, hub.stats.axi_wrs, hub.stats.axi_rds, u_sb.apb_xfer_count());
  endtask

  // ---------------------------------------------------------------------------
  // Phase 2 -- fault injection matrix
  // ---------------------------------------------------------------------------

  //  ---------------------------------------------------------------------------
  //  One injection case.
  //
  //  `op` picks the stimulus the fault needs: a strobe or write-data fault needs
  //  a write, a read-data or timeout fault needs a read, a response-corruption
  //  case needs a read of the unmapped hole.
  //
  //  The injection window is deliberately generous (n_times is a CYCLE count,
  //  not a transfer count) so it is still open when the APB access phase
  //  happens, which is a fixed few cycles after the request.
  //
  //  Two timing rules keep the matrix deterministic:
  //  1. The window opens at hub.cyc + 2, BEFORE the BFM's first handshake.
  //     AXI-hop checks (PATH_STRB/WADATA/NO_LOSS on the AXI tap) sample the
  //     handshake cycle itself; opening the window any later lets a fast
  //     handshake slip through uncorrupted and the case ends with no finding.
  //     Opening early is safe: between transactions the bus is idle and every
  //     checker samples on events (handshake / access / response), so forced
  //     payload with no event is never observed.
  //  2. The post-transaction wait covers wait_c plus the stall bound.  The
  //     wait-state case needs APB_COMPLETE, which fires STALL_BOUND (64)
  //     cycles after an unanswered access -- long after the BFM (which sees
  //     the real, fast fabric) has retired the transaction.  Reading blame
  //     after 10 cycles would catch only the early PATH finding and miss the
  //     PROTO reassignment the precedence rule requires.
  // ---------------------------------------------------------------------------

  task automatic run_case(input string name, input fi_kind_t kind,
                          input string expect_id, input logic [3:0] strb_v,
                          input logic [1:0] resp_v, input logic [31:0] data_v,
                          input int unsigned wait_c, input int unsigned slot,
                          input bit is_write, input logic [31:0] addr_v);
    string got;
    u_rep.arm_run(name);
    seed_retire_window();   // arm_run() clears the window; put the history back
    fi_cfg = '0;
    fi_cfg.armed       = 1'b1;
    fi_cfg.kind        = kind;
    fi_cfg.slot_mask   = 6'b0;
    fi_cfg.slot_mask[slot] = 1'b1;
    fi_cfg.at_cycle    = hub.cyc + 2;
    fi_cfg.n_times     = 400;          // cycles, not transfers
    fi_cfg.strb_value  = strb_v;
    fi_cfg.resp_value  = resp_v;
    fi_cfg.data_value  = data_v;
    fi_cfg.wait_cycles = wait_c;
    repeat (4) @(posedge clk);

    if (is_write) do_write(addr_v, 32'h1122_3344, 4'hF);
    else          do_read (addr_v, rd);
    //  See rule 2 above: wait out any bound the expected check needs.
    repeat (30 + wait_c) @(posedge clk);

    // Blame-aware attribution: first_id() returns findings[0] in arrival order,
    // but the reporter reassigns blame to the lowest (most fundamental) layer,
    // so L_PROTO (1) outranks L_PATH (2) when both fire on one fault.
    // Comparing against blame_id() enforces that precedence here. arm_run()
    // does not clear the sticky blame registers, so a case with zero findings
    // must not read a previous case's blame: report "<none>" instead.
    got = (hub.n_find > 0) ? u_rep.blame_id() : "<none>";
    if (got == expect_id) begin
      fi_pass++;
      $display("[STEP4] FI %-22s -> %-12s OK", name, got);
    end
    else begin
      fi_fail++;
      $display("[STEP4] FI %-22s -> got '%-12s' expected '%-12s'  *** FAIL ***",
               name, got, expect_id);
    end
    fi_cfg.armed = 1'b0;
    repeat (4) @(posedge clk);
  endtask
  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  initial begin : main
    $display("\n=========================================================");
    $display("  RISCFORGE Step 4 -- checker self-proof");
    $display("=========================================================");
    u_rep.init("step4_selfproof");
    seed_retire_window();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    axi_reset_idle();

    // ---- Phase 1 ----
    $display("\n-- PHASE 1 : clean traffic, zero findings expected --");
    phase1_clean();
    if (phase1_findings == 0 && phase1_traffic_ok)
      $display("[STEP4] PHASE 1 PASS : %0d findings on clean traffic", phase1_findings);
    else begin
      $display("[STEP4] PHASE 1 *** FAIL *** : %0d findings on clean traffic",
               phase1_findings);
      u_rep.emit_one_page("PHASE 1 CLEAN-TRAFFIC VIOLATION");
    end

    // ---- Phase 2 ----
    $display("\n-- PHASE 2 : fault injection matrix --");
    //  Each row: injector, hop broken, and the check ID that MUST be named.
    //  run_case(name, kind, expect_id, strb, resp, xor-mask, wait, slot, is_write, addr)
    run_case("strobe/apb",       FI_STROBE,     PATH_STRB,   4'b1100, 2'b00, 32'h0,          0,   3, 1'b1, SLOT_BASE[3] + 32'h80);
    run_case("strobe/axi",       FI_STROBE_AXI, PATH_STRB,   4'b0011, 2'b00, 32'h0,          0,   3, 1'b1, SLOT_BASE[3] + 32'h84);
    run_case("wait-state",       FI_WAIT,       APB_COMPLETE,4'hF,    2'b00, 32'h0,          200, 1, 1'b1, SLOT_BASE[1] + 32'h80);
    run_case("parity-trigger",   FI_SLVERR,     PATH_RESP,    4'hF,    2'b00, 32'h0,          0,   2, 1'b1, SLOT_BASE[2] + 32'h80);
    run_case("timeout-trigger",  FI_TIMEOUT,    PATH_RDATA,   4'hF,    2'b00, 32'h1,          0,   5, 1'b0, SLOT_BASE[5] + 32'h80);
    run_case("paddr-corruptor",  FI_PADDR,      PATH_ADDR,    4'hF,    2'b00, 32'h0000_0100, 0,   0, 1'b1, SLOT_BASE[0] + 32'h80);
    run_case("axi-addr",         FI_AXI_ADDR,   PATH_NO_LOSS, 4'hF,    2'b00, 32'h0000_1000, 0,   1, 1'b0, SLOT_BASE[1] + 32'h80);
    run_case("pwrite-data/apb",  FI_WDATA,      PATH_WDATA,   4'hF,    2'b00, 32'hFFFF_FFFF, 0,   4, 1'b1, SLOT_BASE[4] + 32'h80);
    run_case("pwrite-data/axi",  FI_AXI_WDATA,  PATH_WDATA,   4'hF,    2'b00, 32'hFFFF_FFFF, 0,   0, 1'b1, SLOT_BASE[0] + 32'h80);
    run_case("pread-data/apb",   FI_RDATA,      PATH_RDATA,   4'hF,    2'b00, 32'hFFFF_FFFF, 0,   0, 1'b0, SLOT_BASE[0] + 32'h80);
    run_case("resp/unmapped",    FI_RESP,       PATH_HOLE,    4'hF,    RESP_OKAY, 32'h0,     0,   1, 1'b0, 32'h4000_6000);
    // ---- Verdict ----
    $display("\n=========================================================");
    $display("  STEP 4 SELF-PROOF : phase1_findings=%0d  fi_pass=%0d  fi_fail=%0d",
             phase1_findings, fi_pass, fi_fail);
    if (phase1_findings == 0 && phase1_traffic_ok && fi_fail == 0)
      $display("  RESULT : PASS  -- every injected fault was named by the right check");
    else
      $display("  RESULT : FAIL");
    $display("=========================================================\n");
    $finish;
  end

  //  Watchdog: a self-proof that hangs is a failed self-proof.
  initial begin : watchdog
    #2_000_000;
    $display("[STEP4] *** WATCHDOG *** self-proof did not finish");
    $finish;
  end

endmodule : step4_smoke_tb


// =============================================================================
//  step4_apb_bridge_model
//
//  A behavioural model of axi_lite_to_apb.sv, used only by the Step 4 self-proof
//  because xsim cannot elaborate that module's unpacked-array ports (see the
//  note in step4_smoke_tb).  Every decision below cites the RTL line it copies,
//  so a reviewer diffs this against the bridge rather than trusting it.
//
//  Reproduced, in order of appearance in the RTL:
//    :299  apb_dec_valid && ((write && |strb) || !write)  gates APB generation
//    :302-312  Setup phase drives psel=1, penable=0, PADDR word aligned (:305)
//    :305  aligned_addr(addr, $clog2(DataWidth/8))  -> PADDR[1:0] == 0
//    :311  PSTRB taken straight from the AXI W channel (:126)
//    :315-325  no APB request: answer the AXI side immediately
//    :318-320  write: ~(|strb) ? RESP_OKAY : RESP_DECERR
//    :321-324  read : RESP_DECERR
//    :330-340  Access phase drives psel=1, penable=1
//    :341      transfer completes on PREADY
//    :345-348  write: PSLVERR ? RESP_SLVERR : RESP_OKAY
//    :349-354  read : PRDATA returned, PSLVERR ? RESP_SLVERR : RESP_OKAY
//    :355      back to Setup
//
//  NOT reproduced: the spill-register timing.  The AXI assertions check
//  handshaking and stability independently, and a model that invented its own
//  handshake timing would prove nothing about the real bridge.
// =============================================================================
module step4_apb_bridge_model (
  input  logic clk,
  input  logic rst_n,
  input  step4_bus_pkg::axi_req_t   axi_req_i,
  output step4_bus_pkg::axi_resp_t  axi_resp_o,
  input  step4_bus_pkg::rule_t [step4_pkg::NUM_APB_SLAVES-1:0] apb_addr_map,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0]        apb_psel_o,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0]        apb_penable_o,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0]        apb_pwrite_o,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  apb_paddr_o,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  apb_pwdata_o,
  output logic [step4_pkg::NUM_APB_SLAVES-1:0][3:0]   apb_pstrb_o,
  input  logic [step4_pkg::NUM_APB_SLAVES-1:0]        apb_pready_i,
  input  logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  apb_prdata_i,
  input  logic [step4_pkg::NUM_APB_SLAVES-1:0]        apb_pslverr_i
);
  import step4_pkg::*;

  localparam int N = NUM_APB_SLAVES;

  //  Request latches: the equivalent of the bridge's spill registers.
  logic        aw_q_v = 0;
  logic [31:0] aw_q_addr = '0;
  logic [2:0]  aw_q_prot = '0;
  logic        w_q_v = 0;
  logic [31:0] w_q_data = '0;
  logic [3:0]  w_q_strb = '0;
  logic        ar_q_v = 0;
  logic [31:0] ar_q_addr = '0;
  logic [2:0]  ar_q_prot = '0;

  //  A single transaction is in the bridge or none, so a write response and a
  //  read response can never be live at the same time.  That is the property
  //  step4_path_scoreboard relies on when it uses one record instead of a queue.
  logic        in_access = 0;
  logic        tx_write  = 0;
  logic [31:0] tx_addr   = '0;
  logic [31:0] tx_data   = '0;
  logic [3:0]  tx_strb   = '0;
  int unsigned tx_slot   = 0;
  logic        resp_v    = 0;
  logic [1:0]  resp_code = RESP_OKAY;
  logic [31:0] resp_data = '0;

  assign axi_resp_o.aw_ready = !aw_q_v;
  assign axi_resp_o.w_ready  = !w_q_v;
  assign axi_resp_o.ar_ready = !ar_q_v;
  assign axi_resp_o.b_valid  = resp_v && tx_write;
  assign axi_resp_o.r_valid  = resp_v && !tx_write;
  assign axi_resp_o.b        = '{resp: resp_code};
  assign axi_resp_o.r        = '{data: resp_data, resp: resp_code};

  //  addr_decode: start inclusive, end exclusive (addr_decode.sv:53-54).
  function automatic bit dec_valid(input logic [31:0] a, output int unsigned slot);
    for (int unsigned i = 0; i < N; i++)
      if ((a >= apb_addr_map[i].start_addr) && (a < apb_addr_map[i].end_addr)) begin
        slot = i;
        return 1'b1;
      end
    slot = 0;
    return 1'b0;
  endfunction

  function automatic logic [31:0] align4(input logic [31:0] a);
    return {a[31:2], 2'b00};                       // :305
  endfunction

  always_comb begin
    apb_psel_o    = '0;
    apb_penable_o = '0;
    apb_pwrite_o  = '0;
    apb_paddr_o   = '0;
    apb_pwdata_o  = '0;
    apb_pstrb_o   = '0;
    if (in_access) begin
      apb_psel_o[tx_slot]    = 1'b1;               // :302 / :330
      apb_penable_o[tx_slot] = 1'b1;               // :313 Access phase
      apb_pwrite_o[tx_slot]  = tx_write;
      apb_paddr_o[tx_slot]   = align4(tx_addr);
      apb_pwdata_o[tx_slot]  = tx_data;
      apb_pstrb_o[tx_slot]   = tx_strb;            // :311 / :339
    end
  end

  wire aw_hs = axi_req_i.aw_valid && axi_resp_o.aw_ready;
  wire w_hs  = axi_req_i.w_valid  && axi_resp_o.w_ready;
  wire ar_hs = axi_req_i.ar_valid && axi_resp_o.ar_ready;
  wire resp_hs = resp_v && (tx_write ? axi_req_i.b_ready : axi_req_i.r_ready);

  //  Setup phase: PSEL=1, PENABLE=0, for exactly one cycle.
  logic setup_q = 0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_q_v <= 0; w_q_v <= 0; ar_q_v <= 0;
      in_access <= 0; setup_q <= 0; resp_v <= 0;
      tx_write <= 0; tx_slot <= 0;
    end
    else begin
      //  ---- latch requests ----
      if (aw_hs) begin aw_q_v <= 1'b1; aw_q_addr <= axi_req_i.aw.addr;
                         aw_q_prot <= axi_req_i.aw.prot; end
      if (w_hs)  begin w_q_v  <= 1'b1; w_q_data  <= axi_req_i.w.data;
                         w_q_strb  <= axi_req_i.w.strb; end
      if (ar_hs) begin ar_q_v <= 1'b1; ar_q_addr <= axi_req_i.ar.addr;
                         ar_q_prot <= axi_req_i.ar.prot; end

      if (resp_hs) resp_v <= 1'b0;

      //  ---- Setup: decide whether an APB transfer happens at all ----
      //  Reproduces the arm at axi_lite_to_apb.sv:298-325.  The (aw_q_v || ar_q_v)
      //  guard matters: without it the model would answer a DECERR on an idle
      //  bus, because with nothing latched the decode of address 0 fails and
      //  the 'no APB transfer' arm looks identical to an unmapped read.
      if (!setup_q && !in_access && !resp_v && ((aw_q_v && w_q_v) || ar_q_v)) begin
        //  A WRITE needs BOTH halves latched.  The real bridge keys the decision on apb_req_valid, which is the AND of the write-path spill registers (axi_lite_to_apb.sv:298).  Keying it on AW alone would answer the transfer before W had arrived, drop the W latch on the floor, and leave WREADY stuck low for the rest of the run -- a hang with no explanation.
        automatic bit wr  = aw_q_v && w_q_v;
        automatic bit dv  = dec_valid(wr ? aw_q_addr : ar_q_addr, tx_slot);
        automatic logic [3:0] sb = w_q_strb;
        //  :299
        automatic bit gen = dv && ((wr && (|sb)) || (!wr));
        if (dv) begin
          tx_write = wr;
          tx_addr  = wr ? aw_q_addr : ar_q_addr;
          tx_data  = w_q_data;
          tx_strb  = sb;
        end
        if (gen) begin
          aw_q_v <= 0; w_q_v <= 0; ar_q_v <= 0;
          setup_q   <= 1'b1;
          in_access <= 1'b0;
        end
        else begin
          aw_q_v <= 0; w_q_v <= 0; ar_q_v <= 0;
          setup_q <= 0;
          if (wr) resp_code = (~(|sb)) ? RESP_OKAY : RESP_DECERR;   // :319
          else     resp_code = RESP_DECERR;                         // :322
          resp_v    <= 1'b1;
          tx_write  <= wr;
          tx_slot   <= NUM_APB_SLAVES;   // no APB transfer was generated
        end
      end
      //  Setup -> Access
      else if (setup_q && !in_access) begin
        setup_q   <= 0;
        in_access <= 1'b1;
      end
      //  Access: complete on PREADY  (:341-357)
      else if (in_access) begin
        if (apb_pready_i[tx_slot]) begin
          in_access <= 0;
          resp_v    <= 1'b1;
          if (tx_write) begin
            resp_code = apb_pslverr_i[tx_slot] ? RESP_SLVERR : RESP_OKAY;  // :346-347
          end
          else begin
            resp_code = apb_pslverr_i[tx_slot] ? RESP_SLVERR : RESP_OKAY;  // :351-352
            resp_data = apb_prdata_i[tx_slot];                             // :350
          end
        end
      end
    end
  end
endmodule : step4_apb_bridge_model


// =============================================================================
//  APB slave model: zero wait state, byte strobes honoured, never an error.
//  Matches gpio_apb_wrap's behaviour, which also ties PREADY high.
// =============================================================================
module step4_apb_slave #(
  parameter int SLOT = 0
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [31:0] paddr_i, pwrite_i, pwdata_i,
  input  logic [2:0]  pprot_i,
  input  logic        psel_i, penable_i,
  input  logic [3:0]  pstrb_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o
);
  import step4_pkg::*;


  logic [31:0] regs [0:255];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < 256; i++) regs[i] <= 32'h0;
    end
    else if (psel_i && penable_i && pwrite_i) begin
      for (int b = 0; b < 4; b++)
        if (pstrb_i[b]) regs[paddr_i[9:2]][b*8 +: 8] <= pwdata_i[b*8 +: 8];
    end
  end

//  Driven straight to the scalar ports: no struct, so this module stays
  //  independent of the typedefs local to step4_smoke_tb.
  assign prdata_o  = regs[paddr_i[9:2]];
  assign pready_o  = 1'b1;      // zero wait state, like gpio_apb_wrap
  assign pslverr_o = 1'b0;      // this model never raises an error
endmodule : step4_apb_slave