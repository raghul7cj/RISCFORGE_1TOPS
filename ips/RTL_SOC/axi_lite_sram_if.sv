// =============================================================================
// RISCFORGE 1TOPS — AXI-Lite to SRAM Interface Bridge
// =============================================================================
// Converts AXI4-Lite transactions into simple req/gnt SRAM operations.
// Connects to the low-priority port of sram_mux.
//
// Privilege-Gated Write Mode (PRIV_WRITE_ONLY = 1):
//   When enabled, AXI write transactions with awprot[0] = 0 (unprivileged)
//   are accepted on the bus but rejected — SRAM is NOT written, and the
//   B-channel response returns SLVERR (2'b10). Read transactions are
//   never privilege-gated. This mechanism ensures that only privileged
//   masters (e.g. the bootloader) can write to the target SRAM.
//
// Runtime Lockout (reject_i = 1):
//   Rejects BOTH reads and writes for as long as it is asserted, using the
//   same mechanism: the SRAM is never accessed (sram_req_o stays LOW) and the
//   transaction terminates with SLVERR on the B or R channel.
//
//   The ISRAM instance drives this from boot_done_o so the instruction memory
//   becomes core-private once the bootloader finishes. That is what keeps the
//   two sram_mux ports from ever being active at the same time: the core is
//   held in reset while the bootloader writes, and the AXI port is locked out
//   once the core runs. Without it, a runtime AXI access would wait forever
//   for a grant it can never win (the fetch port requests every cycle) and
//   deadlock the crossbar.
//
// Type Parameters:
//   axi_req_t  — AXI-Lite request struct
//   axi_resp_t — AXI-Lite response struct
// =============================================================================

module axi_lite_sram_if #(
  parameter int unsigned AXI_ADDR_WIDTH  = 32,
  parameter int unsigned AXI_DATA_WIDTH  = 32,
  parameter int unsigned SRAM_NUM_WORDS  = 1024,
  parameter bit          PRIV_WRITE_ONLY = 1'b0,  // 1 = reject unprivileged writes
  parameter type         axi_req_t       = logic,
  parameter type         axi_resp_t      = logic,
  localparam int unsigned SRAM_ADDR_WIDTH = $clog2(SRAM_NUM_WORDS),
  localparam int unsigned STRB_WIDTH      = AXI_DATA_WIDTH / 8,
  localparam int unsigned BYTE_OFFSET     = $clog2(AXI_DATA_WIDTH / 8)
)(
  input  logic      clk_i,
  input  logic      rst_ni,
  input  logic      soft_rst_ni,   // SRAM WE clamp during soft reset
  input  logic      reject_i,      // 1 = reject all traffic (reads AND writes)
                                   //     with SLVERR; SRAM is never accessed
  input  axi_req_t  axi_req_i,
  output axi_resp_t axi_resp_o,
  output logic                        sram_req_o,
  input  logic                        sram_gnt_i,
  output logic                        sram_we_o,     // clamped by soft_rst_ni
  output logic [SRAM_ADDR_WIDTH-1:0]  sram_addr_o,
  output logic [AXI_DATA_WIDTH-1:0]   sram_wdata_o,
  output logic [STRB_WIDTH-1:0]       sram_be_o,
  input  logic [AXI_DATA_WIDTH-1:0]   sram_rdata_i,
  input  logic                        sram_rvalid_i
);

  // Internal WE signal — clamped at the output
  logic sram_we_int;
  assign sram_we_o = sram_we_int & soft_rst_ni;

  // Reject flag — latched with the address. Set by the runtime lockout
  // (reject_i, reads and writes) or the privilege gate (writes only).
  logic reject_q;

  typedef enum logic [2:0] {
    S_IDLE, S_WRITE_WAIT_W, S_WRITE_WAIT_AW,
    S_READ_REQ, S_READ_RESP, S_WRITE_REQ, S_WRITE_RESP
  } state_e;

  state_e state_q, state_d;

  logic [SRAM_ADDR_WIDTH-1:0] addr_q;
  logic [AXI_DATA_WIDTH-1:0]  wdata_q;
  logic [STRB_WIDTH-1:0]      wstrb_q;
  logic [AXI_DATA_WIDTH-1:0]  rdata_q;
  logic                       rdata_valid_q;

  wire [SRAM_ADDR_WIDTH-1:0] aw_word_addr = axi_req_i.aw.addr[BYTE_OFFSET +: SRAM_ADDR_WIDTH];
  wire [SRAM_ADDR_WIDTH-1:0] ar_word_addr = axi_req_i.ar.addr[BYTE_OFFSET +: SRAM_ADDR_WIDTH];

  // ---- Combinational: next state + outputs ----
  always_comb begin
    state_d      = state_q;
    axi_resp_o   = '0;
    sram_req_o   = 1'b0;
    sram_we_int  = 1'b0;
    sram_addr_o  = addr_q;
    sram_wdata_o = wdata_q;
    sram_be_o    = wstrb_q;

    case (state_q)
      S_IDLE: begin
        if (axi_req_i.ar_valid) begin
          axi_resp_o.ar_ready = 1'b1;
          state_d = S_READ_REQ;
        end else if (axi_req_i.aw_valid && axi_req_i.w_valid) begin
          axi_resp_o.aw_ready = 1'b1;
          axi_resp_o.w_ready  = 1'b1;
          state_d = S_WRITE_REQ;
        end else if (axi_req_i.aw_valid) begin
          axi_resp_o.aw_ready = 1'b1;
          state_d = S_WRITE_WAIT_W;
        end else if (axi_req_i.w_valid) begin
          axi_resp_o.w_ready = 1'b1;
          state_d = S_WRITE_WAIT_AW;
        end
      end

      S_WRITE_WAIT_W: begin
        if (axi_req_i.w_valid) begin
          axi_resp_o.w_ready = 1'b1;
          state_d = S_WRITE_REQ;
        end
      end

      S_WRITE_WAIT_AW: begin
        if (axi_req_i.aw_valid) begin
          axi_resp_o.aw_ready = 1'b1;
          state_d = S_WRITE_REQ;
        end
      end

      S_READ_REQ: begin
        if (reject_q) begin
          // Runtime lockout — skip SRAM access, respond with error.
          // sram_req_o stays LOW, so no grant is ever awaited.
          state_d = S_READ_RESP;
        end else begin
          sram_req_o  = 1'b1;
          sram_we_int = 1'b0;
          sram_addr_o = addr_q;
          if (sram_gnt_i) state_d = S_READ_RESP;
        end
      end

      S_READ_RESP: begin
        if (reject_q) begin
          axi_resp_o.r_valid = 1'b1;
          axi_resp_o.r.resp  = 2'b10;  // SLVERR — read rejected
          if (axi_req_i.r_ready) state_d = S_IDLE;
        end else if (rdata_valid_q || sram_rvalid_i) begin
          axi_resp_o.r_valid = 1'b1;
          axi_resp_o.r.data  = rdata_valid_q ? rdata_q : sram_rdata_i;
          if (axi_req_i.r_ready) state_d = S_IDLE;
        end
      end

      S_WRITE_REQ: begin
        if (reject_q) begin
          // Privilege violation or runtime lockout — skip SRAM, respond error
          state_d = S_WRITE_RESP;
        end else begin
          sram_req_o   = 1'b1;
          sram_we_int  = 1'b1;
          sram_addr_o  = addr_q;
          sram_wdata_o = wdata_q;
          sram_be_o    = wstrb_q;
          if (sram_gnt_i) state_d = S_WRITE_RESP;
        end
      end

      S_WRITE_RESP: begin
        axi_resp_o.b_valid = 1'b1;
        if (reject_q)
          axi_resp_o.b.resp = 2'b10;  // SLVERR — write rejected
        if (axi_req_i.b_ready) state_d = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

  // ---- Sequential: state + data registers ----
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      addr_q         <= '0;
      wdata_q        <= '0;
      wstrb_q        <= '0;
      rdata_q        <= '0;
      rdata_valid_q  <= 1'b0;
      reject_q       <= 1'b0;
    end else begin
      state_q <= state_d;

      // Address latch — reject_i applies to reads and writes alike; the
      // privilege gate additionally applies to writes.
      if (state_q == S_IDLE && axi_req_i.ar_valid) begin
        addr_q   <= ar_word_addr;
        reject_q <= reject_i;
      end else if (state_q == S_IDLE && !axi_req_i.ar_valid && axi_req_i.aw_valid) begin
        addr_q   <= aw_word_addr;
        reject_q <= reject_i || (PRIV_WRITE_ONLY && !axi_req_i.aw.prot[0]);
      end else if (state_q == S_WRITE_WAIT_AW && axi_req_i.aw_valid) begin
        addr_q   <= aw_word_addr;
        reject_q <= reject_i || (PRIV_WRITE_ONLY && !axi_req_i.aw.prot[0]);
      end

      // Write-data latch

      if (state_q == S_IDLE && !axi_req_i.ar_valid &&
          axi_req_i.aw_valid && axi_req_i.w_valid) begin
        wdata_q <= axi_req_i.w.data;
        wstrb_q <= axi_req_i.w.strb;
      end else if (state_q == S_IDLE && !axi_req_i.ar_valid &&
                   !axi_req_i.aw_valid && axi_req_i.w_valid) begin
        wdata_q <= axi_req_i.w.data;
        wstrb_q <= axi_req_i.w.strb;
      end else if (state_q == S_WRITE_WAIT_W && axi_req_i.w_valid) begin
        wdata_q <= axi_req_i.w.data;
        wstrb_q <= axi_req_i.w.strb;
      end

      // Read-data latch (capture if R-channel back-pressures)
      if (state_q == S_READ_RESP && sram_rvalid_i && !rdata_valid_q) begin
        rdata_q       <= sram_rdata_i;
        rdata_valid_q <= 1'b1;
      end

      // Clear read-data latch on return to IDLE
      if (state_d == S_IDLE && state_q != S_IDLE)
        rdata_valid_q <= 1'b0;
    end
  end

endmodule
