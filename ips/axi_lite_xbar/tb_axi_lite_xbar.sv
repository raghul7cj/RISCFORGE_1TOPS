// =============================================================================
// AXI4-Lite Crossbar — Comprehensive Testbench
// DUT: axi_lite_xbar (PULP Platform / ETH Zurich)
//
// System Topology:
//   Slave Port 0 = RISC-V Core   (runtime master)
//   Slave Port 1 = Bootloader    (boot-time master)
//   Master Port 0 = Instruction DRAM (512 x 32-bit)
//   Master Port 1 = Data DRAM       (512 x 32-bit)
//   Master Port 2 = APB Bridge      (peripheral space)
//
// Test Cases:
//   TC01-TC06  Basic single-master writes & reads to each target
//   TC07-TC10  Address decoding & decode errors
//   TC11-TC14  Cross-target routing & boot handoff
//   TC15-TC20  Multi-master arbitration & contention
//   TC21-TC24  Outstanding transactions & backpressure
//   TC25-TC27  Edge cases (reset, AW-before-W, slow slave)
// =============================================================================

`timescale 1ns/1ps

module tb_axi_lite_xbar;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int unsigned ADDR_WIDTH  = 32;
  localparam int unsigned DATA_WIDTH  = 32;
  localparam int unsigned CLK_PERIOD  = 10;

  localparam int unsigned NO_SLV_PORTS = 2;  // RISC-V + Bootloader
  localparam int unsigned NO_MST_PORTS = 3;  // IDRAM + DDRAM + APB
  localparam int unsigned NO_RULES     = 3;

  localparam int unsigned MAX_MST_TRANS = 4;
  localparam int unsigned MAX_SLV_TRANS = 4;

  // MstIdxWidth: from xbar top — $clog2(NoMstPorts) clamped to min 1
  localparam int unsigned MST_IDX_W = (NO_MST_PORTS > 1) ? $clog2(NO_MST_PORTS) : 1;

  // =========================================================================
  // Type Definitions (must match the PULP AXI_LITE_TYPEDEF macros exactly)
  // =========================================================================
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

  // Request struct: master → xbar slave port
  typedef struct packed {
    aw_chan_t aw;
    logic     aw_valid;
    w_chan_t  w;
    logic     w_valid;
    logic     b_ready;
    ar_chan_t ar;
    logic     ar_valid;
    logic     r_ready;
  } axi_req_t;

  // Response struct: xbar slave port → master
  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    b_chan_t b;
    logic    b_valid;
    logic    ar_ready;
    r_chan_t r;
    logic    r_valid;
  } axi_resp_t;

  // Address decode rule — using 32-bit address variant
  typedef struct packed {
    int unsigned idx;
    addr_t       start_addr;
    addr_t       end_addr;
  } rule_t;

  // =========================================================================
  // Xbar Configuration
  // =========================================================================
  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         NO_SLV_PORTS,
    NoMstPorts:         NO_MST_PORTS,
    MaxMstTrans:        MAX_MST_TRANS,
    MaxSlvTrans:        MAX_SLV_TRANS,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::NO_LATENCY,
    PipelineStages:     0,             // not used in axi_lite_xbar
    AxiIdWidthSlvPorts: 0,             // not used in AXI-Lite
    AxiIdUsedSlvPorts:  0,             // not used in AXI-Lite
    UniqueIds:          0,             // not used in AXI-Lite
    AxiAddrWidth:       ADDR_WIDTH,
    AxiDataWidth:       DATA_WIDTH,
    NoAddrRules:        NO_RULES
  };

  // =========================================================================
  // Signals
  // =========================================================================
  logic clk, rst_n;

  // Slave ports: from masters into the xbar
  axi_req_t  [NO_SLV_PORTS-1:0] slv_req;
  axi_resp_t [NO_SLV_PORTS-1:0] slv_resp;

  // Master ports: from xbar to slaves
  axi_req_t  [NO_MST_PORTS-1:0] mst_req;
  axi_resp_t [NO_MST_PORTS-1:0] mst_resp;

  // Address map
  rule_t [NO_RULES-1:0] addr_map;

  // Default master port controls
  logic  [NO_SLV_PORTS-1:0]                en_default_mst;
  logic  [NO_SLV_PORTS-1:0][MST_IDX_W-1:0] default_mst;

  // =========================================================================
  // Pass / Fail
  // =========================================================================
  int pass_cnt = 0;
  int fail_cnt = 0;

  // =========================================================================
  // Address Map Configuration
  //   IDRAM:  0x0000_0000 – 0x0000_0800  (512 words × 4 bytes = 2KB)
  //   DDRAM:  0x0001_0000 – 0x0001_0800  (512 words × 4 bytes = 2KB)
  //   APB:    0x4000_0000 – 0x5000_0000  (256MB peripheral space)
  // =========================================================================
  assign addr_map[0] = '{ idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 32'h0000_0800 };
  assign addr_map[1] = '{ idx: 32'd1, start_addr: 32'h0001_0000, end_addr: 32'h0001_0800 };
  assign addr_map[2] = '{ idx: 32'd2, start_addr: 32'h4000_0000, end_addr: 32'h5000_0000 };

  assign en_default_mst = '0;
  assign default_mst    = '0;

  // =========================================================================
  // AXI-Lite Slave Memory Models (one per master port)
  //
  // Each slave is a simple memory-backed AXI-Lite responder:
  //   - Accepts AW+W with configurable latency (stall cycles)
  //   - Writes data into a local memory array
  //   - Returns B with RESP_OKAY
  //   - Accepts AR, returns R with data from memory
  //   - Supports error injection via inject_slverr
  // =========================================================================
  // IDRAM + DDRAM: 512 × 32-bit each.  APB model: 256 words.
  localparam int unsigned DRAM_DEPTH = 512;
  localparam int unsigned APB_DEPTH  = 256;

  // Per-slave configurable stall and error injection
  int  slv_stall_cycles [NO_MST_PORTS];
  logic slv_inject_err  [NO_MST_PORTS];

  initial begin
    for (int i = 0; i < NO_MST_PORTS; i++) begin
      slv_stall_cycles[i] = 0;
      slv_inject_err[i]   = 0;
    end
  end

  // --- Generate slave responders ---
  generate
    for (genvar s = 0; s < NO_MST_PORTS; s++) begin : gen_slv_mem

      localparam int unsigned DEPTH = (s < 2) ? DRAM_DEPTH : APB_DEPTH;
      localparam int unsigned AW    = $clog2(DEPTH); // word-address bits

      logic [31:0] mem [DEPTH];

      // Internal state
      logic        aw_pending_q,  w_pending_q;
      addr_t       aw_addr_q;
      data_t       w_data_q;
      strb_t       w_strb_q;
      logic        b_pending_q;
      axi_pkg::resp_t b_resp_q;

      logic        ar_pending_q;
      addr_t       ar_addr_q;
      logic        r_pending_q;
      data_t       r_data_q;
      axi_pkg::resp_t r_resp_q;

      int          aw_stall_cnt, ar_stall_cnt;

      // Initialize memory to known pattern
      initial begin
        for (int i = 0; i < DEPTH; i++)
          mem[i] = 32'h0;
      end

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          aw_pending_q <= 1'b0;
          w_pending_q  <= 1'b0;
          b_pending_q  <= 1'b0;
          ar_pending_q <= 1'b0;
          r_pending_q  <= 1'b0;
          aw_stall_cnt <= 0;
          ar_stall_cnt <= 0;
          aw_addr_q    <= '0;
          w_data_q     <= '0;
          w_strb_q     <= '0;
          b_resp_q     <= axi_pkg::RESP_OKAY;
          ar_addr_q    <= '0;
          r_data_q     <= '0;
          r_resp_q     <= axi_pkg::RESP_OKAY;
        end else begin

          // ---- Write Path ----

          // Accept AW (when not already holding one, and stall is done)
          if (!aw_pending_q && !b_pending_q && mst_req[s].aw_valid) begin
            if (aw_stall_cnt < slv_stall_cycles[s]) begin
              aw_stall_cnt <= aw_stall_cnt + 1;
            end else begin
              aw_addr_q    <= mst_req[s].aw.addr;
              aw_pending_q <= 1'b1;
              aw_stall_cnt <= 0;
            end
          end

          // Accept W (when not already holding one)
          if (!w_pending_q && !b_pending_q && mst_req[s].w_valid) begin
            w_data_q    <= mst_req[s].w.data;
            w_strb_q    <= mst_req[s].w.strb;
            w_pending_q <= 1'b1;
          end

          // Complete write when we have both AW and W
          if (aw_pending_q && w_pending_q && !b_pending_q) begin
            // Byte-lane write
            for (int b = 0; b < DATA_WIDTH/8; b++) begin
              if (w_strb_q[b])
                mem[aw_addr_q[AW+1:2]][b*8 +: 8] <= w_data_q[b*8 +: 8];
            end
            aw_pending_q <= 1'b0;
            w_pending_q  <= 1'b0;
            b_pending_q  <= 1'b1;
            b_resp_q     <= slv_inject_err[s] ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
          end

          // B handshake complete
          if (b_pending_q && mst_req[s].b_ready) begin
            b_pending_q <= 1'b0;
          end

          // ---- Read Path ----

          // Accept AR
          if (!ar_pending_q && !r_pending_q && mst_req[s].ar_valid) begin
            if (ar_stall_cnt < slv_stall_cycles[s]) begin
              ar_stall_cnt <= ar_stall_cnt + 1;
            end else begin
              ar_addr_q    <= mst_req[s].ar.addr;
              ar_pending_q <= 1'b1;
              ar_stall_cnt <= 0;
            end
          end

          // Generate R response (1-cycle latency after AR acceptance)
          if (ar_pending_q && !r_pending_q) begin
            r_data_q     <= mem[ar_addr_q[AW+1:2]];
            r_resp_q     <= slv_inject_err[s] ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
            r_pending_q  <= 1'b1;
            ar_pending_q <= 1'b0;
          end

          // R handshake complete
          if (r_pending_q && mst_req[s].r_ready) begin
            r_pending_q <= 1'b0;
          end

        end
      end

      // --- Drive response signals ---
      assign mst_resp[s].aw_ready = !aw_pending_q && !b_pending_q &&
                                    (aw_stall_cnt >= slv_stall_cycles[s]);
      assign mst_resp[s].w_ready  = !w_pending_q && !b_pending_q;
      assign mst_resp[s].b_valid  = b_pending_q;
      assign mst_resp[s].b.resp   = b_resp_q;
      assign mst_resp[s].ar_ready = !ar_pending_q && !r_pending_q &&
                                    (ar_stall_cnt >= slv_stall_cycles[s]);
      assign mst_resp[s].r_valid  = r_pending_q;
      assign mst_resp[s].r.data   = r_data_q;
      assign mst_resp[s].r.resp   = r_resp_q;

    end
  endgenerate

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  axi_lite_xbar #(
    .Cfg        ( XbarCfg   ),
    .aw_chan_t  ( aw_chan_t  ),
    .w_chan_t   ( w_chan_t   ),
    .b_chan_t   ( b_chan_t   ),
    .ar_chan_t  ( ar_chan_t  ),
    .r_chan_t   ( r_chan_t   ),
    .axi_req_t  ( axi_req_t  ),
    .axi_resp_t ( axi_resp_t ),
    .rule_t     ( rule_t     )
  ) dut (
    .clk_i                ( clk            ),
    .rst_ni               ( rst_n          ),
    .test_i               ( 1'b0           ),
    .slv_ports_req_i      ( slv_req        ),
    .slv_ports_resp_o     ( slv_resp       ),
    .mst_ports_req_o      ( mst_req        ),
    .mst_ports_resp_i     ( mst_resp       ),
    .addr_map_i           ( addr_map       ),
    .en_default_mst_port_i( en_default_mst ),
    .default_mst_port_i   ( default_mst    )
  );

  // =========================================================================
  // Clock Generation
  // =========================================================================
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // =========================================================================
  // AXI-Lite Master BFM Tasks
  // =========================================================================

  // Idle a specific slave port
  task automatic axi_idle(input int port);
    slv_req[port].aw_valid = 1'b0;
    slv_req[port].aw.addr  = '0;
    slv_req[port].aw.prot  = '0;
    slv_req[port].w_valid  = 1'b0;
    slv_req[port].w.data   = '0;
    slv_req[port].w.strb   = '0;
    slv_req[port].b_ready  = 1'b1;
    slv_req[port].ar_valid = 1'b0;
    slv_req[port].ar.addr  = '0;
    slv_req[port].ar.prot  = '0;
    slv_req[port].r_ready  = 1'b1;
  endtask

  // AXI-Lite Write: drive AW+W on `port`, wait for B
  task automatic axi_write(
    input  int    port,
    input  addr_t addr,
    input  data_t data,
    input  strb_t strb,
    output axi_pkg::resp_t resp
  );
    // Drive AW + W at negedge
    @(negedge clk);
    slv_req[port].aw.addr  = addr;
    slv_req[port].aw.prot  = '0;
    slv_req[port].aw_valid = 1'b1;
    slv_req[port].w.data   = data;
    slv_req[port].w.strb   = strb;
    slv_req[port].w_valid  = 1'b1;
    slv_req[port].b_ready  = 1'b1;

    // Wait for AW+W handshake
    forever begin
      @(posedge clk); #1;
      if (slv_resp[port].aw_ready && slv_resp[port].w_ready) break;
    end

    // Deassert valids
    @(negedge clk);
    slv_req[port].aw_valid = 1'b0;
    slv_req[port].w_valid  = 1'b0;

    // Wait for B response
    forever begin
      @(posedge clk); #1;
      if (slv_resp[port].b_valid) break;
    end
    resp = slv_resp[port].b.resp;
    @(negedge clk);
  endtask

  // AXI-Lite Read: drive AR on `port`, wait for R
  task automatic axi_read(
    input  int    port,
    input  addr_t addr,
    output data_t data,
    output axi_pkg::resp_t resp
  );
    @(negedge clk);
    slv_req[port].ar.addr  = addr;
    slv_req[port].ar.prot  = '0;
    slv_req[port].ar_valid = 1'b1;
    slv_req[port].r_ready  = 1'b1;

    // Wait for AR handshake
    forever begin
      @(posedge clk); #1;
      if (slv_resp[port].ar_ready) break;
    end

    @(negedge clk);
    slv_req[port].ar_valid = 1'b0;

    // Wait for R response
    forever begin
      @(posedge clk); #1;
      if (slv_resp[port].r_valid) break;
    end
    data = slv_resp[port].r.data;
    resp = slv_resp[port].r.resp;
    @(negedge clk);
  endtask

  // =========================================================================
  // Checkers
  // =========================================================================
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

  // =========================================================================
  // Main Test Sequence
  // =========================================================================
  data_t          rd_data;
  axi_pkg::resp_t resp;

  initial begin

    // Initialize both master ports to idle
    for (int i = 0; i < NO_SLV_PORTS; i++) axi_idle(i);

    // Reset sequence
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    $display("\n");
    $display("============================================================");
    $display("  AXI4-Lite Crossbar — Verification Testbench");
    $display("============================================================");
    $display("  Config: %0d slave ports, %0d master ports", NO_SLV_PORTS, NO_MST_PORTS);
    $display("  Address Map:");
    $display("    IDRAM (mst 0): 0x0000_0000 – 0x0000_07FF  (512x32)");
    $display("    DDRAM (mst 1): 0x0001_0000 – 0x0001_07FF  (512x32)");
    $display("    APB   (mst 2): 0x4000_0000 – 0x4FFF_FFFF");
    $display("============================================================\n");

    // ================================================================
    // TC01: RISC-V write → IDRAM
    // ================================================================
    $display("========== TC01: RISC-V Write → IDRAM ==========");
    axi_write(0, 32'h0000_0000, 32'hDEAD_BEEF, 4'hF, resp);
    check_resp("TC01: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(0, 32'h0000_0000, rd_data, resp);
    check("TC01: Readback", rd_data, 32'hDEAD_BEEF);
    check_resp("TC01: Read resp", resp, axi_pkg::RESP_OKAY);

    // ================================================================
    // TC02: RISC-V write → DDRAM
    // ================================================================
    $display("\n========== TC02: RISC-V Write → DDRAM ==========");
    axi_write(0, 32'h0001_0000, 32'hCAFE_BABE, 4'hF, resp);
    check_resp("TC02: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(0, 32'h0001_0000, rd_data, resp);
    check("TC02: Readback", rd_data, 32'hCAFE_BABE);

    // ================================================================
    // TC03: RISC-V write → APB space
    // ================================================================
    $display("\n========== TC03: RISC-V Write → APB ==========");
    axi_write(0, 32'h4000_0000, 32'h1234_5678, 4'hF, resp);
    check_resp("TC03: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(0, 32'h4000_0000, rd_data, resp);
    check("TC03: Readback", rd_data, 32'h1234_5678);

    // ================================================================
    // TC04: Bootloader write → IDRAM (load instructions)
    // ================================================================
    $display("\n========== TC04: Bootloader Write → IDRAM ==========");
    axi_write(1, 32'h0000_0010, 32'h0000_0013, 4'hF, resp);  // NOP instruction
    check_resp("TC04: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(1, 32'h0000_0010, rd_data, resp);
    check("TC04: Readback", rd_data, 32'h0000_0013);

    // ================================================================
    // TC05: Bootloader write → DDRAM (initialize data)
    // ================================================================
    $display("\n========== TC05: Bootloader Write → DDRAM ==========");
    axi_write(1, 32'h0001_0010, 32'hBAAD_F00D, 4'hF, resp);
    check_resp("TC05: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(1, 32'h0001_0010, rd_data, resp);
    check("TC05: Readback", rd_data, 32'hBAAD_F00D);

    // ================================================================
    // TC06: Bootloader write → APB (configure peripheral)
    // ================================================================
    $display("\n========== TC06: Bootloader Write → APB ==========");
    axi_write(1, 32'h4000_0010, 32'hA5A5_5A5A, 4'hF, resp);
    check_resp("TC06: Write resp", resp, axi_pkg::RESP_OKAY);

    axi_read(1, 32'h4000_0010, rd_data, resp);
    check("TC06: Readback", rd_data, 32'hA5A5_5A5A);

    // ================================================================
    // TC07: Decode error — unmapped write
    // ================================================================
    $display("\n========== TC07: Decode Error (unmapped write) ==========");
    axi_write(0, 32'h8000_0000, 32'hBAD0_0BAD, 4'hF, resp);
    check_resp("TC07: Write decode error", resp, axi_pkg::RESP_DECERR);

    // ================================================================
    // TC08: Decode error — unmapped read
    // ================================================================
    $display("\n========== TC08: Decode Error (unmapped read) ==========");
    axi_read(0, 32'h8000_0000, rd_data, resp);
    check_resp("TC08: Read decode error", resp, axi_pkg::RESP_DECERR);

    // ================================================================
    // TC09: Boundary — IDRAM end address (exclusive, should DECERR)
    // ================================================================
    $display("\n========== TC09: IDRAM End Boundary ==========");
    // Last valid word: 0x0000_07FC (word 511)
    axi_write(0, 32'h0000_07FC, 32'hLAST_WORD, 4'hF, resp);
    check_resp("TC09: Last valid IDRAM word", resp, axi_pkg::RESP_OKAY);

    // At end_addr (0x0000_0800) — should be decode error
    axi_write(0, 32'h0000_0800, 32'hOUT_BOUND, 4'hF, resp);
    check_resp("TC09: At end_addr (DECERR)", resp, axi_pkg::RESP_DECERR);

    // ================================================================
    // TC10: Boundary — gap between IDRAM and DDRAM
    // ================================================================
    $display("\n========== TC10: Gap Address (DECERR) ==========");
    axi_write(0, 32'h0000_8000, 32'h0000_0000, 4'hF, resp);
    check_resp("TC10: Gap address DECERR", resp, axi_pkg::RESP_DECERR);

    // ================================================================
    // TC11: Boot handoff — Bootloader loads IDRAM, RISC-V reads it
    // ================================================================
    $display("\n========== TC11: Boot → RISC-V Handoff ==========");
    // Bootloader writes instruction sequence
    axi_write(1, 32'h0000_0100, 32'h0000_0013, 4'hF, resp); // NOP
    axi_write(1, 32'h0000_0104, 32'h0000_0013, 4'hF, resp); // NOP
    axi_write(1, 32'h0000_0108, 32'h0010_0093, 4'hF, resp); // ADDI x1, x0, 1
    axi_write(1, 32'h0000_010C, 32'h0020_0113, 4'hF, resp); // ADDI x2, x0, 2

    // Bootloader goes idle
    axi_idle(1);
    repeat (2) @(posedge clk);

    // RISC-V reads back instructions
    axi_read(0, 32'h0000_0100, rd_data, resp);
    check("TC11: Instr[0]", rd_data, 32'h0000_0013);
    axi_read(0, 32'h0000_0104, rd_data, resp);
    check("TC11: Instr[1]", rd_data, 32'h0000_0013);
    axi_read(0, 32'h0000_0108, rd_data, resp);
    check("TC11: Instr[2]", rd_data, 32'h0010_0093);
    axi_read(0, 32'h0000_010C, rd_data, resp);
    check("TC11: Instr[3]", rd_data, 32'h0020_0113);

    // ================================================================
    // TC12: Both ports access different targets (no contention)
    // ================================================================
    $display("\n========== TC12: Different Targets, No Contention ==========");
    // Note: since these are sequential in this TB we test the routing,
    // not true simultaneity. See TC15-TC20 for fork-join contention tests.
    axi_write(0, 32'h0000_0200, 32'hAAAA_AAAA, 4'hF, resp); // RISC-V → IDRAM
    check_resp("TC12: Port0 → IDRAM", resp, axi_pkg::RESP_OKAY);

    axi_write(1, 32'h0001_0200, 32'hBBBB_BBBB, 4'hF, resp); // Boot → DDRAM
    check_resp("TC12: Port1 → DDRAM", resp, axi_pkg::RESP_OKAY);

    // Verify both writes landed
    axi_read(0, 32'h0000_0200, rd_data, resp);
    check("TC12: IDRAM data", rd_data, 32'hAAAA_AAAA);
    axi_read(0, 32'h0001_0200, rd_data, resp);
    check("TC12: DDRAM data", rd_data, 32'hBBBB_BBBB);

    // ================================================================
    // TC13: Sequential burst — 8 writes + 8 reads to IDRAM
    // ================================================================
    $display("\n========== TC13: Sequential Burst 8W+8R (IDRAM) ==========");
    begin
      logic [31:0] burst_data [8];
      for (int i = 0; i < 8; i++) begin
        burst_data[i] = 32'hA000_0000 + i;
        axi_write(0, 32'h0000_0300 + (i*4), burst_data[i], 4'hF, resp);
      end
      for (int i = 0; i < 8; i++) begin
        axi_read(0, 32'h0000_0300 + (i*4), rd_data, resp);
        check($sformatf("TC13: Burst[%0d]", i), rd_data, burst_data[i]);
      end
    end

    // ================================================================
    // TC14: Sequential burst — DDRAM
    // ================================================================
    $display("\n========== TC14: Sequential Burst 8W+8R (DDRAM) ==========");
    begin
      logic [31:0] burst_data [8];
      for (int i = 0; i < 8; i++) begin
        burst_data[i] = 32'hD000_0000 + i;
        axi_write(0, 32'h0001_0300 + (i*4), burst_data[i], 4'hF, resp);
      end
      for (int i = 0; i < 8; i++) begin
        axi_read(0, 32'h0001_0300 + (i*4), rd_data, resp);
        check($sformatf("TC14: Burst[%0d]", i), rd_data, burst_data[i]);
      end
    end

    // ================================================================
    // TC15: Simultaneous write — both ports to same target (DDRAM)
    // ================================================================
    $display("\n========== TC15: Simultaneous Write to DDRAM ==========");
    begin
      axi_pkg::resp_t resp0, resp1;

      // Drive both AW+W simultaneously at negedge
      @(negedge clk);
      // Port 0 writes to addr 0x0001_0400
      slv_req[0].aw.addr  = 32'h0001_0400;
      slv_req[0].aw_valid = 1'b1;
      slv_req[0].w.data   = 32'hAAAA_1111;
      slv_req[0].w.strb   = 4'hF;
      slv_req[0].w_valid  = 1'b1;
      slv_req[0].b_ready  = 1'b1;

      // Port 1 writes to addr 0x0001_0404
      slv_req[1].aw.addr  = 32'h0001_0404;
      slv_req[1].aw_valid = 1'b1;
      slv_req[1].w.data   = 32'hBBBB_2222;
      slv_req[1].w.strb   = 4'hF;
      slv_req[1].w_valid  = 1'b1;
      slv_req[1].b_ready  = 1'b1;

      // Wait for both to complete (fork-join)
      fork
        begin : port0_wr
          forever begin
            @(posedge clk); #1;
            if (slv_resp[0].aw_ready && slv_resp[0].w_ready) break;
          end
          @(negedge clk);
          slv_req[0].aw_valid = 1'b0;
          slv_req[0].w_valid  = 1'b0;
          forever begin
            @(posedge clk); #1;
            if (slv_resp[0].b_valid) break;
          end
          resp0 = slv_resp[0].b.resp;
        end
        begin : port1_wr
          forever begin
            @(posedge clk); #1;
            if (slv_resp[1].aw_ready && slv_resp[1].w_ready) break;
          end
          @(negedge clk);
          slv_req[1].aw_valid = 1'b0;
          slv_req[1].w_valid  = 1'b0;
          forever begin
            @(posedge clk); #1;
            if (slv_resp[1].b_valid) break;
          end
          resp1 = slv_resp[1].b.resp;
        end
      join

      @(negedge clk);
      check_resp("TC15: Port 0 write resp", resp0, axi_pkg::RESP_OKAY);
      check_resp("TC15: Port 1 write resp", resp1, axi_pkg::RESP_OKAY);

      // Verify both writes landed
      axi_read(0, 32'h0001_0400, rd_data, resp);
      check("TC15: Port0 write landed", rd_data, 32'hAAAA_1111);
      axi_read(0, 32'h0001_0404, rd_data, resp);
      check("TC15: Port1 write landed", rd_data, 32'hBBBB_2222);
    end

    // ================================================================
    // TC16: Simultaneous read — both ports from same target (IDRAM)
    // ================================================================
    $display("\n========== TC16: Simultaneous Read from IDRAM ==========");
    begin
      data_t          rd0, rd1;
      axi_pkg::resp_t rresp0, rresp1;

      // Pre-load a value
      axi_write(0, 32'h0000_0500, 32'hFACE_FACE, 4'hF, resp);

      @(negedge clk);
      slv_req[0].ar.addr  = 32'h0000_0500;
      slv_req[0].ar_valid = 1'b1;
      slv_req[0].r_ready  = 1'b1;

      slv_req[1].ar.addr  = 32'h0000_0500;
      slv_req[1].ar_valid = 1'b1;
      slv_req[1].r_ready  = 1'b1;

      fork
        begin : port0_rd
          forever begin @(posedge clk); #1; if (slv_resp[0].ar_ready) break; end
          @(negedge clk); slv_req[0].ar_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[0].r_valid) break; end
          rd0    = slv_resp[0].r.data;
          rresp0 = slv_resp[0].r.resp;
        end
        begin : port1_rd
          forever begin @(posedge clk); #1; if (slv_resp[1].ar_ready) break; end
          @(negedge clk); slv_req[1].ar_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[1].r_valid) break; end
          rd1    = slv_resp[1].r.data;
          rresp1 = slv_resp[1].r.resp;
        end
      join

      @(negedge clk);
      check("TC16: Port0 read data", rd0, 32'hFACE_FACE);
      check("TC16: Port1 read data", rd1, 32'hFACE_FACE);
      check_resp("TC16: Port0 read resp", rresp0, axi_pkg::RESP_OKAY);
      check_resp("TC16: Port1 read resp", rresp1, axi_pkg::RESP_OKAY);
    end

    // ================================================================
    // TC17: Port 0 write + Port 1 read to same target simultaneously
    // ================================================================
    $display("\n========== TC17: Port0 Write + Port1 Read (same target) ==========");
    begin
      axi_pkg::resp_t wr_resp, rd_resp;
      data_t          rd_val;

      // Pre-write a known value to DDRAM
      axi_write(0, 32'h0001_0500, 32'h1111_1111, 4'hF, resp);

      @(negedge clk);
      // Port 0: write new value
      slv_req[0].aw.addr  = 32'h0001_0504;
      slv_req[0].aw_valid = 1'b1;
      slv_req[0].w.data   = 32'h2222_2222;
      slv_req[0].w.strb   = 4'hF;
      slv_req[0].w_valid  = 1'b1;
      slv_req[0].b_ready  = 1'b1;

      // Port 1: read old value
      slv_req[1].ar.addr  = 32'h0001_0500;
      slv_req[1].ar_valid = 1'b1;
      slv_req[1].r_ready  = 1'b1;

      fork
        begin // Write path
          forever begin @(posedge clk); #1;
            if (slv_resp[0].aw_ready && slv_resp[0].w_ready) break; end
          @(negedge clk);
          slv_req[0].aw_valid = 1'b0;
          slv_req[0].w_valid  = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[0].b_valid) break; end
          wr_resp = slv_resp[0].b.resp;
        end
        begin // Read path
          forever begin @(posedge clk); #1; if (slv_resp[1].ar_ready) break; end
          @(negedge clk);
          slv_req[1].ar_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[1].r_valid) break; end
          rd_val  = slv_resp[1].r.data;
          rd_resp = slv_resp[1].r.resp;
        end
      join

      @(negedge clk);
      check_resp("TC17: Write resp", wr_resp, axi_pkg::RESP_OKAY);
      check_resp("TC17: Read resp", rd_resp, axi_pkg::RESP_OKAY);
      check("TC17: Read data (pre-write)", rd_val, 32'h1111_1111);

      // Verify the write also landed
      axi_read(0, 32'h0001_0504, rd_data, resp);
      check("TC17: Write landed", rd_data, 32'h2222_2222);
    end

    // ================================================================
    // TC18: Different targets simultaneously (no mux contention)
    // ================================================================
    $display("\n========== TC18: Port0→IDRAM + Port1→DDRAM (no contention) ==========");
    begin
      axi_pkg::resp_t resp0, resp1;

      @(negedge clk);
      slv_req[0].aw.addr  = 32'h0000_0600;
      slv_req[0].aw_valid = 1'b1;
      slv_req[0].w.data   = 32'hDDDD_0000;
      slv_req[0].w.strb   = 4'hF;
      slv_req[0].w_valid  = 1'b1;
      slv_req[0].b_ready  = 1'b1;

      slv_req[1].aw.addr  = 32'h0001_0600;
      slv_req[1].aw_valid = 1'b1;
      slv_req[1].w.data   = 32'hEEEE_0000;
      slv_req[1].w.strb   = 4'hF;
      slv_req[1].w_valid  = 1'b1;
      slv_req[1].b_ready  = 1'b1;

      fork
        begin
          forever begin @(posedge clk); #1;
            if (slv_resp[0].aw_ready && slv_resp[0].w_ready) break; end
          @(negedge clk); slv_req[0].aw_valid = 1'b0; slv_req[0].w_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[0].b_valid) break; end
          resp0 = slv_resp[0].b.resp;
        end
        begin
          forever begin @(posedge clk); #1;
            if (slv_resp[1].aw_ready && slv_resp[1].w_ready) break; end
          @(negedge clk); slv_req[1].aw_valid = 1'b0; slv_req[1].w_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[1].b_valid) break; end
          resp1 = slv_resp[1].b.resp;
        end
      join

      @(negedge clk);
      check_resp("TC18: Port0 resp", resp0, axi_pkg::RESP_OKAY);
      check_resp("TC18: Port1 resp", resp1, axi_pkg::RESP_OKAY);

      axi_read(0, 32'h0000_0600, rd_data, resp);
      check("TC18: IDRAM data", rd_data, 32'hDDDD_0000);
      axi_read(0, 32'h0001_0600, rd_data, resp);
      check("TC18: DDRAM data", rd_data, 32'hEEEE_0000);
    end

    // ================================================================
    // TC19: Both write to same address (last-writer wins)
    // ================================================================
    $display("\n========== TC19: Both Write Same Address ==========");
    begin
      axi_pkg::resp_t resp0, resp1;

      @(negedge clk);
      slv_req[0].aw.addr  = 32'h0001_0700;
      slv_req[0].aw_valid = 1'b1;
      slv_req[0].w.data   = 32'h0000_AAAA;
      slv_req[0].w.strb   = 4'hF;
      slv_req[0].w_valid  = 1'b1;
      slv_req[0].b_ready  = 1'b1;

      slv_req[1].aw.addr  = 32'h0001_0700;
      slv_req[1].aw_valid = 1'b1;
      slv_req[1].w.data   = 32'h0000_BBBB;
      slv_req[1].w.strb   = 4'hF;
      slv_req[1].w_valid  = 1'b1;
      slv_req[1].b_ready  = 1'b1;

      fork
        begin
          forever begin @(posedge clk); #1;
            if (slv_resp[0].aw_ready && slv_resp[0].w_ready) break; end
          @(negedge clk); slv_req[0].aw_valid = 1'b0; slv_req[0].w_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[0].b_valid) break; end
          resp0 = slv_resp[0].b.resp;
        end
        begin
          forever begin @(posedge clk); #1;
            if (slv_resp[1].aw_ready && slv_resp[1].w_ready) break; end
          @(negedge clk); slv_req[1].aw_valid = 1'b0; slv_req[1].w_valid = 1'b0;
          forever begin @(posedge clk); #1; if (slv_resp[1].b_valid) break; end
          resp1 = slv_resp[1].b.resp;
        end
      join

      @(negedge clk);
      check_resp("TC19: Port0 resp", resp0, axi_pkg::RESP_OKAY);
      check_resp("TC19: Port1 resp", resp1, axi_pkg::RESP_OKAY);

      // Read back — we don't know which won, but data must be one of the two
      axi_read(0, 32'h0001_0700, rd_data, resp);
      if (rd_data === 32'h0000_AAAA || rd_data === 32'h0000_BBBB) begin
        $display("  [PASS] TC19: Data = 0x%08X (valid, one of the writers won)", rd_data);
        pass_cnt++;
      end else begin
        $display("  [FAIL] TC19: Data = 0x%08X (corrupted! neither writer's value)", rd_data);
        fail_cnt++;
      end
    end

    // ================================================================
    // TC20: Interleaved writes — both ports to all 3 targets
    // ================================================================
    $display("\n========== TC20: Interleaved Writes to All Targets ==========");
    begin
      // Port 0: IDRAM, DDRAM, APB
      axi_write(0, 32'h0000_0700, 32'hA0_IDRAM0, 4'hF, resp);
      axi_write(1, 32'h0001_0700, 32'hB1_DDRAM0, 4'hF, resp);
      axi_write(0, 32'h0001_0704, 32'hA0_DDRAM1, 4'hF, resp);
      axi_write(1, 32'h0000_0704, 32'hB1_IDRAM1, 4'hF, resp);
      axi_write(0, 32'h4000_0100, 32'hA0_APB_00, 4'hF, resp);
      axi_write(1, 32'h4000_0104, 32'hB1_APB_01, 4'hF, resp);

      // Read back all
      axi_read(0, 32'h0000_0700, rd_data, resp);
      check("TC20: P0→IDRAM", rd_data, 32'hA0_IDRAM0);
      axi_read(0, 32'h0001_0700, rd_data, resp);
      check("TC20: P1→DDRAM", rd_data, 32'hB1_DDRAM0);
      axi_read(0, 32'h0001_0704, rd_data, resp);
      check("TC20: P0→DDRAM", rd_data, 32'hA0_DDRAM1);
      axi_read(0, 32'h0000_0704, rd_data, resp);
      check("TC20: P1→IDRAM", rd_data, 32'hB1_IDRAM1);
      axi_read(0, 32'h4000_0100, rd_data, resp);
      check("TC20: P0→APB", rd_data, 32'hA0_APB_00);
      axi_read(0, 32'h4000_0104, rd_data, resp);
      check("TC20: P1→APB", rd_data, 32'hB1_APB_01);
    end

    // ================================================================
    // TC21: Slave error injection
    // ================================================================
    $display("\n========== TC21: Slave Error Injection (IDRAM) ==========");
    slv_inject_err[0] = 1;
    axi_write(0, 32'h0000_0000, 32'hEE_EE_EE_EE, 4'hF, resp);
    check_resp("TC21: Write SLVERR", resp, axi_pkg::RESP_SLVERR);

    axi_read(0, 32'h0000_0000, rd_data, resp);
    check_resp("TC21: Read SLVERR", resp, axi_pkg::RESP_SLVERR);
    slv_inject_err[0] = 0;

    // ================================================================
    // TC22: Slow slave (stall cycles)
    // ================================================================
    $display("\n========== TC22: Slow Slave (DDRAM, 3-cycle stall) ==========");
    slv_stall_cycles[1] = 3;
    axi_write(0, 32'h0001_07F0, 32'hSLOW_BEEF, 4'hF, resp);
    check_resp("TC22: Stalled write", resp, axi_pkg::RESP_OKAY);

    axi_read(0, 32'h0001_07F0, rd_data, resp);
    check("TC22: Stalled readback", rd_data, 32'hSLOW_BEEF);
    slv_stall_cycles[1] = 0;

    // ================================================================
    // TC23: Back-to-back R-W-R pipeline
    // ================================================================
    $display("\n========== TC23: Back-to-back R-W-R ==========");
    axi_write(0, 32'h0000_0080, 32'hAAAA_BBBB, 4'hF, resp);
    axi_read(0, 32'h0000_0080, rd_data, resp);
    check("TC23: First read", rd_data, 32'hAAAA_BBBB);

    axi_write(0, 32'h0000_0080, 32'hCCCC_DDDD, 4'hF, resp);
    axi_read(0, 32'h0000_0080, rd_data, resp);
    check("TC23: Updated read", rd_data, 32'hCCCC_DDDD);

    // ================================================================
    // TC24: Decode error from bootloader port
    // ================================================================
    $display("\n========== TC24: Decode Error from Bootloader ==========");
    axi_write(1, 32'hFFFF_0000, 32'h0, 4'hF, resp);
    check_resp("TC24: Boot decode err write", resp, axi_pkg::RESP_DECERR);

    axi_read(1, 32'hFFFF_0000, rd_data, resp);
    check_resp("TC24: Boot decode err read", resp, axi_pkg::RESP_DECERR);

    // ================================================================
    // TC25: Reset mid-transaction recovery
    // ================================================================
    $display("\n========== TC25: Reset Mid-Transaction ==========");
    begin
      // Start a write
      @(negedge clk);
      slv_req[0].aw.addr  = 32'h0000_00A0;
      slv_req[0].aw_valid = 1'b1;
      slv_req[0].w.data   = 32'hDEAD_C0DE;
      slv_req[0].w.strb   = 4'hF;
      slv_req[0].w_valid  = 1'b1;

      repeat (2) @(posedge clk);

      // Assert reset
      rst_n = 1'b0;
      for (int i = 0; i < NO_SLV_PORTS; i++) axi_idle(i);
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);

      $display("  [INFO] Reset released, verifying recovery...");

      // Normal transaction after reset
      axi_write(0, 32'h0000_00B0, 32'hAF7E_E5E7, 4'hF, resp);
      check_resp("TC25: Post-reset write", resp, axi_pkg::RESP_OKAY);

      axi_read(0, 32'h0000_00B0, rd_data, resp);
      check("TC25: Post-reset readback", rd_data, 32'hAF7E_E5E7);
    end

    // ================================================================
    // TC26: Write all 512 IDRAM words, read back
    // ================================================================
    $display("\n========== TC26: Full IDRAM Write + Read (512 words) ==========");
    begin
      int errs = 0;
      for (int i = 0; i < 512; i++) begin
        axi_write(0, i*4, i, 4'hF, resp);
      end
      $display("  [INFO] 512 writes complete");

      for (int i = 0; i < 512; i++) begin
        axi_read(0, i*4, rd_data, resp);
        if (rd_data !== i) errs++;
      end
      if (errs == 0) begin
        $display("  [PASS] TC26: All 512 IDRAM words verified");
        pass_cnt++;
      end else begin
        $display("  [FAIL] TC26: %0d IDRAM words mismatched", errs);
        fail_cnt++;
      end
    end

    // ================================================================
    // TC27: Full DDRAM Write + Read (512 words)
    // ================================================================
    $display("\n========== TC27: Full DDRAM Write + Read (512 words) ==========");
    begin
      int errs = 0;
      for (int i = 0; i < 512; i++) begin
        axi_write(0, 32'h0001_0000 + i*4, 32'hD000_0000 + i, 4'hF, resp);
      end
      $display("  [INFO] 512 writes complete");

      for (int i = 0; i < 512; i++) begin
        axi_read(0, 32'h0001_0000 + i*4, rd_data, resp);
        if (rd_data !== (32'hD000_0000 + i)) errs++;
      end
      if (errs == 0) begin
        $display("  [PASS] TC27: All 512 DDRAM words verified");
        pass_cnt++;
      end else begin
        $display("  [FAIL] TC27: %0d DDRAM words mismatched", errs);
        fail_cnt++;
      end
    end

    // ================================================================
    // Summary
    // ================================================================
    $display("\n============================================================");
    $display("  RESULTS:  PASSED = %0d  /  FAILED = %0d", pass_cnt, fail_cnt);
    $display("============================================================");
    if (fail_cnt == 0)
      $display("  *** ALL TESTS PASSED ***");
    else
      $display("  *** %0d TEST(S) FAILED ***", fail_cnt);
    $display("============================================================\n");

    #500;
    $finish;
  end

  // =========================================================================
  // Global Watchdog
  // =========================================================================
  initial begin
    #50_000_000;
    $display("[ERROR] Global watchdog timeout at %0t!", $time);
    $finish;
  end

  // =========================================================================
  // Waveform Dump
  // =========================================================================
  initial begin
    $dumpfile("tb_axi_lite_xbar.vcd");
    $dumpvars(0, tb_axi_lite_xbar);
  end

endmodule
