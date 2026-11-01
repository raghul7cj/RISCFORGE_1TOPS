// =============================================================================
// apb_timeout_monitor — bounds the ACCESS phase of one APB slave
// =============================================================================
// Placed between axi_lite_to_apb and one APB slave. The request path is NOT
// routed through this module: apb_req stays wired straight from the bridge to
// the slave, and only the response struct going back to the bridge is muxed.
//
// Why the request side is untouched: the SPI master pops its RX FIFO with
// "spi_data_rx_ready = rxfifo_rd_access & PREADY" using its OWN PREADY
// (spi_master_apb_if.sv:236). Driving PREADY into the slave on a timeout would
// pop and discard a received word. Answering only the bridge leaves the slave
// seeing an access that was abandoned before it completed, so nothing is lost.
//
// Behaviour:
//   - transparent while the slave answers within TimeoutCycles
//   - counter runs while PSEL & PENABLE & !PREADY, clears otherwise
//   - on expiry the bridge is answered with PREADY=1, PSLVERR=1, TimeoutData.
//     axi_lite_to_apb turns PSLVERR into RESP_SLVERR (axi_lite_to_apb.sv:345),
//     which hybrid_mem_interface turns into a load/store access fault in the
//     core (memory_cycle.v:135-136), with mtval = the faulting address.
//   - "real PREADY wins": the override is qualified with !pready_from_slave, so
//     a slave completing on the same cycle the counter matures is passed through
//   - after a timeout the slot is blocked: further accesses are answered at once
//     instead of re-running the counter. The block clears when the slave shows
//     PREADY high while deselected, which for the SPI master happens one cycle
//     after the abort, so it only persists for a slave stuck low permanently.
// =============================================================================

module apb_timeout_monitor #(
  parameter type         apb_req_t     = logic,
  parameter type         apb_resp_t    = logic,
  parameter int unsigned TimeoutCycles = 16,
  parameter logic [31:0] TimeoutData   = 32'hDEAD_BEEF
) (
  input  logic      clk_i,
  input  logic      rst_ni,

  input  apb_req_t  apb_req_i,       // observed only (PSEL / PENABLE)
  input  apb_resp_t apb_resp_slv_i,  // response from the slave
  output apb_resp_t apb_resp_mst_o,  // response presented to the bridge

  output logic      timeout_pulse_o,  // one cycle per aborted access
  output logic      timeout_sticky_o  // set on the first abort, clears on reset
);

  localparam int unsigned CntWidth = (TimeoutCycles < 2) ? 1 : $clog2(TimeoutCycles);

  logic                access;
  logic                waiting;
  logic                expired;
  logic                fire;
  logic [CntWidth-1:0] cnt_q;
  logic                blocked_q;

  // ACCESS phase of an APB transfer, with the slave not yet ready
  assign access  = apb_req_i.psel & apb_req_i.penable;
  assign waiting = access & ~apb_resp_slv_i.pready;

  assign expired = (cnt_q == CntWidth'(TimeoutCycles - 1));

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q <= '0;
    end else if (!waiting) begin
      cnt_q <= '0;
    end else if (!expired) begin
      cnt_q <= cnt_q + 1'b1;
    end
  end

  // Qualified with `waiting`, so a slave that completes on the maturing cycle
  // keeps ownership of the response and no data is dropped.
  assign fire = waiting & (expired | blocked_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      blocked_q <= 1'b0;
    end else if (fire) begin
      blocked_q <= 1'b1;
    end else if (!apb_req_i.psel && apb_resp_slv_i.pready) begin
      blocked_q <= 1'b0;
    end
  end

  always_comb begin
    apb_resp_mst_o = apb_resp_slv_i;
    if (fire) begin
      apb_resp_mst_o.pready  = 1'b1;
      apb_resp_mst_o.pslverr = 1'b1;
      apb_resp_mst_o.prdata  = TimeoutData;
    end
  end

  assign timeout_pulse_o = fire;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)   timeout_sticky_o <= 1'b0;
    else if (fire) timeout_sticky_o <= 1'b1;
  end

endmodule
