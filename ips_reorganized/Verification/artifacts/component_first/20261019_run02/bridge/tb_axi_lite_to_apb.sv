// =============================================================================
// AXI4-Lite to APB4 Bridge — Comprehensive Testbench
// DUT: axi_lite_to_apb (ETH Zurich / PULP Platform)
//
// Dependencies: axi_pkg.sv, cf_math_pkg.sv (compiled via axil2apb_file.f)
//
// Test Cases:
//   TC1  – Single APB write + readback
//   TC2  – Single APB read
//   TC3  – Decode error (address outside map)
//   TC4  – Simultaneous AW+W+AR (write priority via round-robin)
//   TC5  – APB slave error (pslverr)
//   TC6  – Write with zero strobe (special: RESP_OKAY, no APB txn)
//   TC7  – Sequential burst of 8 writes then 8 reads
//   TC8  – APB slave stall (pready delayed N cycles)
//   TC9  – Back-to-back read-write-read pipeline
//   TC10 – Reset mid-transaction recovery
// =============================================================================

`timescale 1ns/1ps

module tb_axi_lite_to_apb;

  // -------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH    = 32;
  localparam int unsigned DATA_WIDTH    = 32;
  localparam int unsigned NO_APB_SLAVES = 2;
  localparam int unsigned NO_RULES      = 2;
  localparam int unsigned CLK_PERIOD    = 10;
  localparam int unsigned AXI_TIMEOUT_CYC = 500;

  localparam int unsigned SEL_IDX_W = (NO_APB_SLAVES > 1) ? $clog2(NO_APB_SLAVES) : 1;

  // -------------------------------------------------------------------
  // Type definitions
  // -------------------------------------------------------------------
  typedef logic [ADDR_WIDTH-1:0]   addr_t;
  typedef logic [DATA_WIDTH-1:0]   data_t;
  typedef logic [DATA_WIDTH/8-1:0] strb_t;

  // AXI-Lite channel structs
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

  typedef struct packed {
    aw_chan_t aw;
    logic     aw_valid;
    w_chan_t  w;
    logic     w_valid;
    logic     b_ready;
    ar_chan_t ar;
    logic     ar_valid;
    logic     r_ready;
  } axi_lite_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    b_chan_t b;
    logic    b_valid;
    logic    ar_ready;
    r_chan_t r;
    logic    r_valid;
  } axi_lite_resp_t;

  // APB structs
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

  // Address decoder rule
  typedef struct packed {
    logic [SEL_IDX_W-1:0] idx;
    addr_t                start_addr;
    addr_t                end_addr;
  } rule_t;

  // -------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------
  logic                          clk, rst_n;
  axi_lite_req_t                 axi_req;
  axi_lite_resp_t                axi_resp;
  apb_req_t  [NO_APB_SLAVES-1:0] apb_req;
  apb_resp_t [NO_APB_SLAVES-1:0] apb_resp;
  rule_t     [NO_RULES-1:0]      addr_map;

  // -------------------------------------------------------------------
  // Pass / Fail counters
  // -------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // -------------------------------------------------------------------
  // Address Map: Slave0 = 0x1000_0000 .. 0x1000_0FFF
  //              Slave1 = 0x2000_0000 .. 0x2000_0FFF
  // -------------------------------------------------------------------
  assign addr_map[0] = '{ idx: 1'b0, start_addr: 32'h1000_0000, end_addr: 32'h1000_1000 };
  assign addr_map[1] = '{ idx: 1'b1, start_addr: 32'h2000_0000, end_addr: 32'h2000_1000 };

  // -------------------------------------------------------------------
  // Simple APB slave memory model (per slave)
  // -------------------------------------------------------------------
  logic [31:0] apb_mem [2][256]; // 256 words per slave
  int apb_stall_cycles [2];     // configurable stall per slave

  initial begin
    apb_stall_cycles[0] = 0;
    apb_stall_cycles[1] = 0;
  end

  // APB slave error injection
  logic apb_inject_slverr [2];
  initial begin
    apb_inject_slverr[0] = 0;
    apb_inject_slverr[1] = 0;
  end

  // APB slave responder — one generate block per slave so the index is
  // a constant genvar (avoids force/release with variable index).
  //
  // Uses always_ff with NBA assignments so that pready is stable at the
  // posedge, eliminating the race condition that existed when using
  // blocking assignments inside an initial/forever block.
  generate
    for (genvar s = 0; s < NO_APB_SLAVES; s++) begin : gen_apb_slave

      logic        slv_pready;
      logic [31:0] slv_prdata;
      logic        slv_pslverr;
      int          stall_cnt;

      assign apb_resp[s].pready  = slv_pready;
      assign apb_resp[s].prdata  = slv_prdata;
      assign apb_resp[s].pslverr = slv_pslverr;

      // Registered APB slave model using NBA (<=) assignments.
      // pready asserts one cycle after psel && penable is seen,
      // which is valid APB protocol (adds one wait state).
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          slv_pready  <= 1'b0;
          slv_prdata  <= '0;
          slv_pslverr <= 1'b0;
          stall_cnt   <= 0;
        end else begin
          // Default: deassert after one cycle of response
          if (slv_pready) begin
            slv_pready  <= 1'b0;
            slv_pslverr <= 1'b0;
            slv_prdata  <= '0;
          end else if (apb_req[s].psel && apb_req[s].penable) begin
            // Handle stall cycles
            if (apb_stall_cycles[s] > 0 && stall_cnt < apb_stall_cycles[s]) begin
              slv_pready <= 1'b0;
              stall_cnt  <= stall_cnt + 1;
            end else begin
              // Respond
              slv_pready  <= 1'b1;
              slv_pslverr <= apb_inject_slverr[s];
              stall_cnt   <= 0;
              if (apb_req[s].pwrite) begin
                slv_prdata <= '0;
              end else begin
                slv_prdata <= apb_mem[s][(apb_req[s].paddr[9:2])];
              end
            end
          end
        end
      end

      // Memory write: capture data on the same cycle the always_ff decides to
      // assert pready (i.e., when psel+penable+pwrite are active, stall is
      // done, and pready hasn't been asserted yet — meaning it WILL be next cycle).
      always @(posedge clk) begin
        if (rst_n && apb_req[s].psel && apb_req[s].penable && apb_req[s].pwrite) begin
          if (apb_stall_cycles[s] == 0 || stall_cnt >= apb_stall_cycles[s]) begin
            if (!slv_pready) begin
              apb_mem[s][(apb_req[s].paddr[9:2])] = apb_req[s].pwdata;
            end
          end
        end
      end

    end
  endgenerate

  // -------------------------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------------------------
  axi_lite_to_apb #(
    .NoApbSlaves      ( NO_APB_SLAVES    ),
    .NoRules          ( NO_RULES         ),
    .AddrWidth        ( ADDR_WIDTH       ),
    .DataWidth        ( DATA_WIDTH       ),
    .PipelineRequest  ( 1'b0             ),
    .PipelineResponse ( 1'b0             ),
    .axi_lite_req_t   ( axi_lite_req_t   ),
    .axi_lite_resp_t  ( axi_lite_resp_t  ),
    .apb_req_t        ( apb_req_t        ),
    .apb_resp_t       ( apb_resp_t       ),
    .rule_t           ( rule_t           )
  ) dut (
    .clk_i          ( clk      ),
    .rst_ni         ( rst_n    ),
    .axi_lite_req_i ( axi_req  ),
    .axi_lite_resp_o( axi_resp ),
    .apb_req_o      ( apb_req  ),
    .apb_resp_i     ( apb_resp ),
    .addr_map_i     ( addr_map )
  );

  // -------------------------------------------------------------------
  // Clock generation
  // -------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -------------------------------------------------------------------
  // AXI-Lite Master BFM Tasks
  // -------------------------------------------------------------------
  task automatic axi_idle();
    axi_req.aw_valid = 1'b0;
    axi_req.aw.addr  = '0;
    axi_req.aw.prot  = '0;
    axi_req.w_valid  = 1'b0;
    axi_req.w.data   = '0;
    axi_req.w.strb   = '0;
    axi_req.b_ready  = 1'b1;
    axi_req.ar_valid = 1'b0;
    axi_req.ar.addr  = '0;
    axi_req.ar.prot  = '0;
    axi_req.r_ready  = 1'b1;
  endtask

  // AXI-Lite Write (AW+W presented simultaneously, wait for B)
  // Drive at negedge so signals are stable before DUT's posedge sampling
  task automatic axi_write(
    input addr_t addr,
    input data_t data,
    input strb_t strb = 4'hF,
    output axi_pkg::resp_t resp
  );
    int cycles;
    // Drive AW + W at negedge (stable before next posedge)
    @(negedge clk);
    axi_req.aw.addr  = addr;
    axi_req.aw.prot  = '0;
    axi_req.aw_valid = 1'b1;
    axi_req.w.data   = data;
    axi_req.w.strb   = strb;
    axi_req.w_valid  = 1'b1;
    // Hold BREADY low until the testbench has sampled the response. A decode
    // error can complete immediately and otherwise be consumed before the
    // BFM reaches its response wait.
    axi_req.b_ready  = 1'b0;
    $display("  [DBG] WR: valid driven at %0t, addr=0x%08X", $time, addr);

    // This bridge presents AWREADY and WREADY together after it has accepted
    // the combined write request. Sample on the active edge, before NBA
    // updates; keep both VALID signals asserted through that handshake.
    cycles  = 0;
    forever begin
      @(posedge clk);
      if (axi_resp.aw_ready && axi_resp.w_ready) break;
      cycles++;
      if (cycles >= AXI_TIMEOUT_CYC)
        $fatal(1, "AXI write handshake timeout: addr=%08h", addr);
    end
    @(negedge clk);
    axi_req.aw_valid = 1'b0;
    axi_req.w_valid  = 1'b0;
    $display("  [DBG] WR: valid deasserted at %0t, waiting for b_valid", $time);

    // BVALID is also sampled on the active edge, before any update.
    cycles = 0;
    forever begin
      @(posedge clk);
      $display("  [DBG] WR: @posedge %0t b_valid=%b b_resp=%2b | raw_resp=0x%0h",
               $time, axi_resp.b_valid, axi_resp.b.resp, axi_resp);
      $display("  [DBG] WR:   APB[0] psel=%b pen=%b prdy=%b | APB[1] psel=%b pen=%b prdy=%b",
               apb_req[0].psel, apb_req[0].penable, apb_resp[0].pready,
               apb_req[1].psel, apb_req[1].penable, apb_resp[1].pready);
      if (axi_resp.b_valid) break;
      cycles++;
      if (cycles >= AXI_TIMEOUT_CYC)
        $fatal(1, "AXI B response timeout: addr=%08h", addr);
    end
    resp = axi_resp.b.resp;
    @(negedge clk);
    axi_req.b_ready = 1'b1;
    @(posedge clk); // consume the held response
    @(negedge clk);
    $display("  [DBG] WR: done at %0t, resp=%2b", $time, resp);
  endtask

  // AXI-Lite Read
  task automatic axi_read(
    input  addr_t addr,
    output data_t data,
    output axi_pkg::resp_t resp
  );
    int cycles;
    // Drive AR at negedge
    @(negedge clk);
    axi_req.ar.addr  = addr;
    axi_req.ar.prot  = '0;
    axi_req.ar_valid = 1'b1;
    // Hold RREADY low so even an immediate decode-error response is sampled.
    axi_req.r_ready  = 1'b0;
    $display("  [DBG] RD: valid driven at %0t, addr=0x%08X", $time, addr);

    // AXI handshakes are sampled on the active edge, before NBA updates.
    cycles = 0;
    forever begin
      @(posedge clk);
      $display("  [DBG] RD: @posedge %0t ar_ready=%b r_valid=%b",
               $time, axi_resp.ar_ready, axi_resp.r_valid);
      if (axi_resp.ar_ready) break;
      cycles++;
      if (cycles >= AXI_TIMEOUT_CYC)
        $fatal(1, "AXI AR handshake timeout: addr=%08h", addr);
    end

    // Deassert at negedge
    @(negedge clk);
    axi_req.ar_valid = 1'b0;
    $display("  [DBG] RD: ar deasserted at %0t, waiting for r_valid", $time);

    // Wait for RVALID, sampling on each active edge.
    cycles = 0;
    forever begin
      @(posedge clk);
      $display("  [DBG] RD: @posedge %0t r_valid=%b r_data=0x%08X r_resp=%2b",
               $time, axi_resp.r_valid, axi_resp.r.data, axi_resp.r.resp);
      if (axi_resp.r_valid) break;
      cycles++;
      if (cycles >= AXI_TIMEOUT_CYC)
        $fatal(1, "AXI R response timeout: addr=%08h", addr);
    end
    data = axi_resp.r.data;
    resp = axi_resp.r.resp;
    @(negedge clk);
    axi_req.r_ready = 1'b1;
    @(posedge clk); // consume the held response
    @(negedge clk);
    $display("  [DBG] RD: done at %0t", $time);
  endtask

  // -------------------------------------------------------------------
  // Checker
  // -------------------------------------------------------------------
  task automatic check(
    input string       msg,
    input logic [31:0] got,
    input logic [31:0] exp
  );
    if (got === exp) begin
      $display("  [PASS] %s  got=0x%08X  exp=0x%08X", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s  got=0x%08X  exp=0x%08X", msg, got, exp);
      fail_cnt++;
    end
  endtask

  task automatic check_resp(
    input string          msg,
    input axi_pkg::resp_t got,
    input axi_pkg::resp_t exp
  );
    if (got === exp) begin
      $display("  [PASS] %s  resp=%2b (expected %2b)", msg, got, exp);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s  resp=%2b (expected %2b)", msg, got, exp);
      fail_cnt++;
    end
  endtask

  // -------------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------------
  data_t          rd_data;
  axi_pkg::resp_t resp;

  initial begin
    axi_idle();
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    // APB slave responders start automatically via generate initial blocks
    $display("\n");
    $display("============================================================");
    $display("  AXI4-Lite to APB4 Bridge — Verification Testbench");
    $display("============================================================");
    $display("  Address Map:");
    $display("    Slave0: 0x1000_0000 – 0x1000_0FFF");
    $display("    Slave1: 0x2000_0000 – 0x2000_0FFF");
    $display("============================================================\n");

    // ==================================================================
    // TC1: Single Write to Slave0 + Readback
    // ==================================================================
    $display("========== TC1: Single Write to Slave0 + Readback ==========");

    axi_write(32'h1000_0000, 32'hDEAD_BEEF, 4'hF, resp);
    check_resp("TC1: Write resp OKAY", resp, axi_pkg::RESP_OKAY);

    axi_read(32'h1000_0000, rd_data, resp);
    check("TC1: Read data matches", rd_data, 32'hDEAD_BEEF);
    check_resp("TC1: Read resp OKAY", resp, axi_pkg::RESP_OKAY);

    // ==================================================================
    // TC2: Single Read from Slave1
    // ==================================================================
    $display("\n========== TC2: Write+Read Slave1 ==========");

    axi_write(32'h2000_0010, 32'hCAFE_BABE, 4'hF, resp);
    check_resp("TC2: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(32'h2000_0010, rd_data, resp);
    check("TC2: Read Slave1", rd_data, 32'hCAFE_BABE);

    // ==================================================================
    // TC3: Decode Error (unmapped address)
    //   Bridge returns RESP_DECERR when address is outside all rules
    // ==================================================================
    $display("\n========== TC3: Decode Error (Unmapped Address) ==========");

    axi_write(32'h3000_0000, 32'hBAD0_0BAD, 4'hF, resp);
    check_resp("TC3: Write decode error", resp, axi_pkg::RESP_DECERR);

    axi_read(32'h3000_0000, rd_data, resp);
    check_resp("TC3: Read decode error", resp, axi_pkg::RESP_DECERR);
    $display("  [NOTE] Read data on decode error: 0x%08X (bridge returns 0xDEA110C8)", rd_data);

    // ==================================================================
    // TC4: Simultaneous AW+W and AR (tests round-robin arbitration)
    //   Both write and read presented in same cycle; RR arbiter picks one
    // ==================================================================
    $display("\n========== TC4: Simultaneous Write + Read ==========");
    begin
      axi_pkg::resp_t wr_resp, rd_resp;
      data_t          rd_val;
      bit             wr_accepted, rd_accepted, wr_seen, rd_seen;
      int             cycles;

      // Pre-load a known value
      axi_write(32'h1000_0020, 32'h1111_1111, 4'hF, resp);

      // Present both channels simultaneously (drive at negedge)
      @(negedge clk);
      axi_req.aw.addr  = 32'h1000_0024;
      axi_req.aw_valid = 1'b1;
      axi_req.w.data   = 32'h2222_2222;
      axi_req.w.strb   = 4'hF;
      axi_req.w_valid  = 1'b1;
      axi_req.ar.addr  = 32'h1000_0020;
      axi_req.ar_valid = 1'b1;
      // Hold both response-ready signals low until the responses are sampled;
      // otherwise a fast response may handshake before this BFM observes it.
      axi_req.b_ready  = 1'b0;
      axi_req.r_ready  = 1'b0;

      // Present both requests together and preserve each VALID through its
      // active-edge handshake. The bridge serializes the two APB transfers.
      wr_accepted = 1'b0;
      rd_accepted = 1'b0;
      cycles = 0;
      while (!(wr_accepted && rd_accepted)) begin
        @(posedge clk);
        if (!wr_accepted && axi_resp.aw_ready && axi_resp.w_ready)
          wr_accepted = 1'b1;
        if (!rd_accepted && axi_resp.ar_ready)
          rd_accepted = 1'b1;
        cycles++;
        if (cycles >= AXI_TIMEOUT_CYC)
          $fatal(1, "TC4 simultaneous request handshake timeout");
        @(negedge clk);
        if (wr_accepted) begin
          axi_req.aw_valid = 1'b0;
          axi_req.w_valid  = 1'b0;
        end
        if (rd_accepted) axi_req.ar_valid = 1'b0;
      end

      cycles = 0;
      wr_seen = 1'b0;
      rd_seen = 1'b0;
      while (!(wr_seen && rd_seen)) begin
        @(posedge clk);
        if (!wr_seen && axi_resp.b_valid) begin
          wr_resp = axi_resp.b.resp;
          wr_seen = 1'b1;
        end
        if (!rd_seen && axi_resp.r_valid) begin
          rd_val  = axi_resp.r.data;
          rd_resp = axi_resp.r.resp;
          rd_seen = 1'b1;
        end
        cycles++;
        if (cycles >= AXI_TIMEOUT_CYC)
          $fatal(1, "TC4 simultaneous response timeout");
        @(negedge clk);
        axi_req.b_ready = wr_seen;
        axi_req.r_ready = rd_seen;
      end
      @(negedge clk);
      axi_req.b_ready = 1'b1;
      axi_req.r_ready = 1'b1;
      @(posedge clk);

      @(negedge clk);
      check_resp("TC4: Write resp", wr_resp, axi_pkg::RESP_OKAY);
      check_resp("TC4: Read resp", rd_resp, axi_pkg::RESP_OKAY);
      check("TC4: Read data", rd_val, 32'h1111_1111);

      // Verify the write actually landed
      axi_read(32'h1000_0024, rd_data, resp);
      check("TC4: Write landed", rd_data, 32'h2222_2222);
    end

    // ==================================================================
    // TC5: APB Slave Error (pslverr)
    //   Inject pslverr from slave — bridge translates to RESP_SLVERR
    // ==================================================================
    $display("\n========== TC5: APB Slave Error (pslverr) ==========");
    apb_inject_slverr[0] = 1;

    axi_write(32'h1000_0040, 32'hAAAA_AAAA, 4'hF, resp);
    check_resp("TC5: Write slverr", resp, axi_pkg::RESP_SLVERR);

    axi_read(32'h1000_0040, rd_data, resp);
    check_resp("TC5: Read slverr", resp, axi_pkg::RESP_SLVERR);

    apb_inject_slverr[0] = 0;

    // ==================================================================
    // TC6: Write with Zero Strobe
    //   Special case in this bridge: write with strb==0 does NOT
    //   generate an APB transaction, returns RESP_OKAY immediately.
    //   This is an important integration gotcha!
    // ==================================================================
    $display("\n========== TC6: Write with Zero Strobe ==========");
    $display("  [NOTE] Bridge treats strb==0 write as no-op (RESP_OKAY, no APB txn)");

    axi_write(32'h1000_0050, 32'hFFFF_FFFF, 4'h0, resp);
    check_resp("TC6: Zero-strobe write OKAY", resp, axi_pkg::RESP_OKAY);

    // ==================================================================
    // TC7: Sequential Burst — 8 Writes then 8 Reads
    // ==================================================================
    $display("\n========== TC7: Sequential Burst (8W + 8R) ==========");
    begin
      logic [31:0] burst_data [8];
      for (int i = 0; i < 8; i++) begin
        burst_data[i] = 32'hA000_0000 + i;
        axi_write(32'h2000_0000 + (i*4), burst_data[i], 4'hF, resp);
      end
      $display("  [INFO] 8 writes completed");

      for (int i = 0; i < 8; i++) begin
        axi_read(32'h2000_0000 + (i*4), rd_data, resp);
        check($sformatf("TC7: Burst[%0d]", i), rd_data, burst_data[i]);
      end
    end

    // ==================================================================
    // TC8: APB Slave Stall (pready delayed)
    //   Tests that bridge correctly waits in Access state
    // ==================================================================
    $display("\n========== TC8: APB Slave Stall (pready delayed) ==========");
    apb_stall_cycles[1] = 5;
    $display("  [INFO] Slave1 will stall pready by 5 cycles");

    axi_write(32'h2000_0100, 32'h57A1_BEEF, 4'hF, resp);
    check_resp("TC8: Stalled write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(32'h2000_0100, rd_data, resp);
    check("TC8: Stalled read data", rd_data, 32'h57A1_BEEF);

    apb_stall_cycles[1] = 0;

    // ==================================================================
    // TC9: Back-to-back Read-Write-Read pipeline
    // ==================================================================
    $display("\n========== TC9: Back-to-back R-W-R ==========");

    axi_write(32'h1000_0080, 32'h1234_5678, 4'hF, resp);
    axi_read(32'h1000_0080, rd_data, resp);
    check("TC9: First read", rd_data, 32'h1234_5678);

    axi_write(32'h1000_0080, 32'h8765_4321, 4'hF, resp);
    axi_read(32'h1000_0080, rd_data, resp);
    check("TC9: Updated read", rd_data, 32'h8765_4321);

    // ==================================================================
    // TC10: Reset Mid-Transaction Recovery
    //   Start a transaction, assert reset, verify clean recovery
    // ==================================================================
    $display("\n========== TC10: Reset Mid-Transaction ==========");
    begin
      // Start a write (drive at negedge)
      @(negedge clk);
      axi_req.aw.addr  = 32'h1000_00A0;
      axi_req.aw_valid = 1'b1;
      axi_req.w.data   = 32'hDEAD_C0DE;
      axi_req.w.strb   = 4'hF;
      axi_req.w_valid  = 1'b1;

      // Let it enter the pipeline
      repeat (2) @(posedge clk);

      // Assert reset
      rst_n = 1'b0;
      axi_idle();
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);

      $display("  [INFO] Reset released, attempting normal transaction...");

      // Verify bridge is functional after reset
      axi_write(32'h1000_00B0, 32'hAF7E_E5E7, 4'hF, resp);
      check_resp("TC10: Post-reset write", resp, axi_pkg::RESP_OKAY);

      axi_read(32'h1000_00B0, rd_data, resp);
      check("TC10: Post-reset read", rd_data, 32'hAF7E_E5E7);
    end

    // ==================================================================
    // Summary
    // ==================================================================
    $display("\n============================================================");
    $display("  RESULTS:  PASSED = %0d  /  FAILED = %0d", pass_cnt, fail_cnt);
    $display("============================================================");
    if (fail_cnt == 0)
      $display("  *** ALL TESTS PASSED ***");
    else
      $display("  *** %0d TEST(S) FAILED ***", fail_cnt);
    $display("============================================================\n");

    #200;
    $finish;
  end

  // -------------------------------------------------------------------
  // Global watchdog
  // -------------------------------------------------------------------
  initial begin
    #5_000_000;
    $display("[ERROR] Global watchdog timeout!");
    $finish;
  end

  // -------------------------------------------------------------------
  // Optional: waveform dump
  // -------------------------------------------------------------------
  initial begin
    $dumpfile("tb_axi_lite_to_apb.vcd");
    $dumpvars(0, tb_axi_lite_to_apb);
  end

endmodule
