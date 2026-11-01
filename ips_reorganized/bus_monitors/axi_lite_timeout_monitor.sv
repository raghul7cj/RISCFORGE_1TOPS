// =============================================================================
// axi_lite_timeout_monitor — bounds one AXI-Lite master port
// =============================================================================
// Sits between hybrid_mem_interface and the crossbar slave port. Transparent
// until a transaction outlives its threshold, then it answers the core with
// SLVERR and cleans up after the transaction that is still stuck downstream.
//
// Why the cleanup is needed: AXI forbids deasserting a VALID that has not been
// accepted, so the monitor cannot simply withdraw the request. On a timeout it
//   1. captures the outstanding AW / W / AR beats,
//   2. accepts them from the core and answers with SLVERR so the core retires
//      the access (hybrid_mem_interface then leaves AXI_WAIT_* and drops its
//      own valids),
//   3. keeps driving the captured beats downstream until the crossbar accepts,
//   4. holds b_ready / r_ready high to swallow and discard the late response,
//   5. answers any new core request with an immediate SLVERR while draining,
//      because forwarding it would collide with the orphan's late response.
//
// Thresholds are picked per region from the transaction address: the SRAM paths
// are fixed-latency (~4 cycles), so a small value catches a crossbar or wrapper
// deadlock quickly, while the APB region must stay above the largest APB slot
// timeout so that apb_timeout_monitor always fires first.
//
// The core turns the SLVERR into a precise load/store access fault, mcause 5/7
// with mtval = the address (memory_cycle.v:135-139).
// =============================================================================

module axi_lite_timeout_monitor #(
  parameter type         axi_req_t      = logic,
  parameter type         axi_resp_t     = logic,
  parameter int unsigned AddrWidth      = 32,
  parameter logic [31:0] ApbBase        = 32'h4000_0000,
  parameter logic [31:0] ApbEnd         = 32'h5000_0000,
  parameter int unsigned TimeoutApb     = 131072,  // must exceed the largest APB slot timeout
  parameter int unsigned TimeoutDefault = 64,      // SRAM and everything else
  parameter logic [31:0] TimeoutData    = 32'hDEAD_DEAD
) (
  input  logic      clk_i,
  input  logic      rst_ni,

  input  axi_req_t  slv_req_i,    // from the core
  output axi_resp_t slv_resp_o,   // to the core
  output axi_req_t  mst_req_o,    // to the crossbar
  input  axi_resp_t mst_resp_i,   // from the crossbar

  output logic      wr_timeout_pulse_o,
  output logic      rd_timeout_pulse_o,
  output logic      wr_timeout_sticky_o,
  output logic      rd_timeout_sticky_o
);

  localparam int unsigned CntWidth = $clog2(TimeoutApb);

  typedef enum logic [1:0] {StPass, StInject, StDrain} state_e;

  // ---------------------------------------------------------------------------
  // Region decode
  // ---------------------------------------------------------------------------
  function automatic logic addr_in_apb(input logic [AddrWidth-1:0] addr);
    return (addr >= ApbBase[AddrWidth-1:0]) && (addr < ApbEnd[AddrWidth-1:0]);
  endfunction

  // ---------------------------------------------------------------------------
  // Write path
  // ---------------------------------------------------------------------------
  state_e              wr_state_q;
  logic [CntWidth-1:0] wr_cnt_q;
  logic                wr_inflight_q, wr_apb_q;
  logic                aw_acc_q, w_acc_q;
  logic                aw_pend_q, w_pend_q, b_swallow_q, err_b_q;
  logic [$bits(slv_req_i.aw)-1:0] aw_beat_q;
  logic [$bits(slv_req_i.w)-1:0]  w_beat_q;

  logic [CntWidth-1:0] wr_thresh_m1;
  logic                wr_expired, wr_busy, wr_b_hs, wr_fire;

  assign wr_thresh_m1 = wr_apb_q ? CntWidth'(TimeoutApb - 1) : CntWidth'(TimeoutDefault - 1);
  assign wr_expired   = (wr_cnt_q >= wr_thresh_m1);
  assign wr_busy      = wr_inflight_q | slv_req_i.aw_valid;
  assign wr_b_hs      = mst_resp_i.b_valid & slv_req_i.b_ready;
  assign wr_fire      = (wr_state_q == StPass) & wr_busy & wr_expired & ~wr_b_hs;

  assign wr_timeout_pulse_o = wr_fire;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q          <= StPass;
      wr_cnt_q            <= '0;
      wr_inflight_q       <= 1'b0;
      wr_apb_q            <= 1'b0;
      aw_acc_q            <= 1'b0;
      w_acc_q             <= 1'b0;
      aw_pend_q           <= 1'b0;
      w_pend_q            <= 1'b0;
      b_swallow_q         <= 1'b0;
      err_b_q             <= 1'b0;
      aw_beat_q           <= '0;
      w_beat_q            <= '0;
      wr_timeout_sticky_o <= 1'b0;
    end else begin
      case (wr_state_q)
        StPass: begin
          // Track the single outstanding write and its region
          if (!wr_inflight_q && slv_req_i.aw_valid) begin
            wr_inflight_q <= 1'b1;
            wr_apb_q      <= addr_in_apb(slv_req_i.aw.addr);
          end
          if (slv_req_i.aw_valid && mst_resp_i.aw_ready) aw_acc_q <= 1'b1;
          if (slv_req_i.w_valid  && mst_resp_i.w_ready)  w_acc_q  <= 1'b1;

          if (wr_b_hs) begin
            wr_inflight_q <= 1'b0;
            aw_acc_q      <= 1'b0;
            w_acc_q       <= 1'b0;
            wr_cnt_q      <= '0;
          end else if (wr_busy) begin
            if (!wr_expired) wr_cnt_q <= wr_cnt_q + 1'b1;
          end else begin
            wr_cnt_q <= '0;
          end

          if (wr_fire) begin
            // "& ~*_ready" so a beat accepted downstream on this very cycle is
            // not captured and re-driven as a duplicate
            aw_pend_q           <= slv_req_i.aw_valid & ~aw_acc_q & ~mst_resp_i.aw_ready;
            aw_beat_q           <= slv_req_i.aw;
            w_pend_q            <= slv_req_i.w_valid & ~w_acc_q & ~mst_resp_i.w_ready;
            w_beat_q            <= slv_req_i.w;
            // a B will come back for any AW that is or will be delivered
            b_swallow_q         <= aw_acc_q | slv_req_i.aw_valid;
            wr_inflight_q       <= 1'b0;
            aw_acc_q            <= 1'b0;
            w_acc_q             <= 1'b0;
            wr_cnt_q            <= '0;
            wr_state_q          <= StInject;
            wr_timeout_sticky_o <= 1'b1;
          end
        end

        StInject: begin
          // drain downstream while the core takes the injected error response
          if (aw_pend_q   && mst_resp_i.aw_ready) aw_pend_q   <= 1'b0;
          if (w_pend_q    && mst_resp_i.w_ready)  w_pend_q    <= 1'b0;
          if (b_swallow_q && mst_resp_i.b_valid)  b_swallow_q <= 1'b0;
          if (slv_req_i.b_ready)                  wr_state_q  <= StDrain;
        end

        StDrain: begin
          if (aw_pend_q   && mst_resp_i.aw_ready) aw_pend_q   <= 1'b0;
          if (w_pend_q    && mst_resp_i.w_ready)  w_pend_q    <= 1'b0;
          if (b_swallow_q && mst_resp_i.b_valid)  b_swallow_q <= 1'b0;

          // new core writes are answered with an immediate error, never forwarded
          if (slv_req_i.aw_valid && slv_req_i.w_valid && !err_b_q) begin
            err_b_q <= 1'b1;
          end else if (err_b_q && slv_req_i.b_ready) begin
            err_b_q <= 1'b0;
          end

          if (!aw_pend_q && !w_pend_q && !b_swallow_q && !err_b_q &&
              !(slv_req_i.aw_valid && slv_req_i.w_valid)) begin
            wr_state_q <= StPass;
          end
        end

        default: wr_state_q <= StPass;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Read path
  // ---------------------------------------------------------------------------
  state_e              rd_state_q;
  logic [CntWidth-1:0] rd_cnt_q;
  logic                rd_inflight_q, rd_apb_q;
  logic                ar_pend_q, r_swallow_q, err_r_q;
  logic [$bits(slv_req_i.ar)-1:0] ar_beat_q;

  logic [CntWidth-1:0] rd_thresh_m1;
  logic                rd_expired, rd_busy, rd_r_hs, rd_fire;

  assign rd_thresh_m1 = rd_apb_q ? CntWidth'(TimeoutApb - 1) : CntWidth'(TimeoutDefault - 1);
  assign rd_expired   = (rd_cnt_q >= rd_thresh_m1);
  assign rd_busy      = rd_inflight_q | slv_req_i.ar_valid;
  assign rd_r_hs      = mst_resp_i.r_valid & slv_req_i.r_ready;
  assign rd_fire      = (rd_state_q == StPass) & rd_busy & rd_expired & ~rd_r_hs;

  assign rd_timeout_pulse_o = rd_fire;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q          <= StPass;
      rd_cnt_q            <= '0;
      rd_inflight_q       <= 1'b0;
      rd_apb_q            <= 1'b0;
      ar_pend_q           <= 1'b0;
      r_swallow_q         <= 1'b0;
      err_r_q             <= 1'b0;
      ar_beat_q           <= '0;
      rd_timeout_sticky_o <= 1'b0;
    end else begin
      case (rd_state_q)
        StPass: begin
          if (!rd_inflight_q && slv_req_i.ar_valid) begin
            rd_inflight_q <= 1'b1;
            rd_apb_q      <= addr_in_apb(slv_req_i.ar.addr);
          end

          if (rd_r_hs) begin
            rd_inflight_q <= 1'b0;
            rd_cnt_q      <= '0;
          end else if (rd_busy) begin
            if (!rd_expired) rd_cnt_q <= rd_cnt_q + 1'b1;
          end else begin
            rd_cnt_q <= '0;
          end

          if (rd_fire) begin
            ar_pend_q           <= slv_req_i.ar_valid & ~mst_resp_i.ar_ready;
            ar_beat_q           <= slv_req_i.ar;
            r_swallow_q         <= 1'b1;
            rd_inflight_q       <= 1'b0;
            rd_cnt_q            <= '0;
            rd_state_q          <= StInject;
            rd_timeout_sticky_o <= 1'b1;
          end
        end

        StInject: begin
          if (ar_pend_q   && mst_resp_i.ar_ready) ar_pend_q   <= 1'b0;
          if (r_swallow_q && mst_resp_i.r_valid)  r_swallow_q <= 1'b0;
          if (slv_req_i.r_ready)                  rd_state_q  <= StDrain;
        end

        StDrain: begin
          if (ar_pend_q   && mst_resp_i.ar_ready) ar_pend_q   <= 1'b0;
          if (r_swallow_q && mst_resp_i.r_valid)  r_swallow_q <= 1'b0;

          if (slv_req_i.ar_valid && !err_r_q) begin
            err_r_q <= 1'b1;
          end else if (err_r_q && slv_req_i.r_ready) begin
            err_r_q <= 1'b0;
          end

          if (!ar_pend_q && !r_swallow_q && !err_r_q && !slv_req_i.ar_valid) begin
            rd_state_q <= StPass;
          end
        end

        default: rd_state_q <= StPass;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Datapath: pass-through by default, overridden per channel group
  // ---------------------------------------------------------------------------
  always_comb begin
    mst_req_o  = slv_req_i;
    slv_resp_o = mst_resp_i;

    // ---- write channels ----
    case (wr_state_q)
      StInject: begin
        mst_req_o.aw_valid  = aw_pend_q;
        mst_req_o.aw        = aw_beat_q;
        mst_req_o.w_valid   = w_pend_q;
        mst_req_o.w         = w_beat_q;
        mst_req_o.b_ready   = 1'b1;          // swallow the orphan's response
        // accept the request from the core and answer it, so hybrid_mem_interface
        // leaves AXI_WAIT_ADDR / AXI_WAIT_DATA and asserts b_ready
        slv_resp_o.aw_ready = slv_req_i.aw_valid;
        slv_resp_o.w_ready  = slv_req_i.w_valid;
        slv_resp_o.b_valid  = 1'b1;
        slv_resp_o.b.resp   = axi_pkg::RESP_SLVERR;
      end
      StDrain: begin
        mst_req_o.aw_valid  = aw_pend_q;
        mst_req_o.aw        = aw_beat_q;
        mst_req_o.w_valid   = w_pend_q;
        mst_req_o.w         = w_beat_q;
        mst_req_o.b_ready   = 1'b1;
        slv_resp_o.aw_ready = slv_req_i.aw_valid & slv_req_i.w_valid & ~err_b_q;
        slv_resp_o.w_ready  = slv_req_i.aw_valid & slv_req_i.w_valid & ~err_b_q;
        slv_resp_o.b_valid  = err_b_q;
        slv_resp_o.b.resp   = axi_pkg::RESP_SLVERR;
      end
      default: ;  // StPass: transparent
    endcase

    // ---- read channels ----
    case (rd_state_q)
      StInject: begin
        mst_req_o.ar_valid  = ar_pend_q;
        mst_req_o.ar        = ar_beat_q;
        mst_req_o.r_ready   = 1'b1;          // swallow the orphan's response
        slv_resp_o.ar_ready = slv_req_i.ar_valid;
        slv_resp_o.r_valid  = 1'b1;
        slv_resp_o.r.data   = TimeoutData;
        slv_resp_o.r.resp   = axi_pkg::RESP_SLVERR;
      end
      StDrain: begin
        mst_req_o.ar_valid  = ar_pend_q;
        mst_req_o.ar        = ar_beat_q;
        mst_req_o.r_ready   = 1'b1;
        slv_resp_o.ar_ready = slv_req_i.ar_valid & ~err_r_q;
        slv_resp_o.r_valid  = err_r_q;
        slv_resp_o.r.data   = TimeoutData;
        slv_resp_o.r.resp   = axi_pkg::RESP_SLVERR;
      end
      default: ;  // StPass: transparent
    endcase
  end

endmodule
