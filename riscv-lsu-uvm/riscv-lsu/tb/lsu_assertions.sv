// =============================================================================
// lsu_assertions.sv — SystemVerilog Assertions (SVA) for RV32I Load/Store Unit
// Verifies protocol invariants, control decoding, and bus handshakes.
// =============================================================================
module lsu_assertions (
  input logic        clk,
  input logic        rst_n,

  // Core Pipeline Interface
  input logic [31:0] core_addr,
  input logic [31:0] core_wdata,
  input logic [4:0]  lsunit,
  input logic [31:0] core_rdata,
  input logic        core_stall,
  input logic        core_err,

  // Memory Bridge Interface
  input logic        mem_req,
  input logic        mem_we,
  input logic [31:0] mem_addr,
  input logic [31:0] mem_wdata,
  input logic [3:0]  mem_be,
  input logic [31:0] mem_rdata,
  input logic        mem_stall,
  input logic        mem_err
);

  // ── A1: mem_req must strictly follow lsunit[4] (enable) ────────────────────
  property p_mem_req_decode;
    @(posedge clk) disable iff (!rst_n)
    mem_req === lsunit[4];
  endproperty
  assert property (p_mem_req_decode)
    else `uvm_error("ASSERT", "A1: mem_req does not match lsunit[4]")

  // ── A2: mem_we must strictly follow (lsunit[4] & lsunit[3]) ───────────────
  property p_mem_we_decode;
    @(posedge clk) disable iff (!rst_n)
    mem_we === (lsunit[4] & lsunit[3]);
  endproperty
  assert property (p_mem_we_decode)
    else `uvm_error("ASSERT", "A2: mem_we does not match (lsunit[4] & lsunit[3])")

  // ── A3: mem_addr must pass through core_addr exactly ──────────────────────
  property p_mem_addr_passthrough;
    @(posedge clk) disable iff (!rst_n)
    mem_req |-> (mem_addr === core_addr);
  endproperty
  assert property (p_mem_addr_passthrough)
    else `uvm_error("ASSERT", "A3: mem_addr does not match core_addr")

  // ── A4: core_stall must be the exact logical AND of mem_req and mem_stall ─
  property p_core_stall_gating;
    @(posedge clk) disable iff (!rst_n)
    core_stall === (mem_req & mem_stall);
  endproperty
  assert property (p_core_stall_gating)
    else `uvm_error("ASSERT", "A4: core_stall != (mem_req & mem_stall)")

  // ── A5: core_err must pass through mem_err directly ────────────────────────
  property p_core_err_passthrough;
    @(posedge clk) disable iff (!rst_n)
    core_err === mem_err;
  endproperty
  assert property (p_core_err_passthrough)
    else `uvm_error("ASSERT", "A5: core_err != mem_err")

  // ── A6: When disabled (lsunit[4]==0), no mem request and zero byte enables ─
  property p_idle_quiescent;
    @(posedge clk) disable iff (!rst_n)
    !lsunit[4] |-> (!mem_req && !mem_we && (mem_be == 4'b0000) && (core_rdata == 32'd0));
  endproperty
  assert property (p_idle_quiescent)
    else `uvm_error("ASSERT", "A6: Spurious activity or non-zero output during idle/NOP")

  // ── A7: Store byte enables must be legal non-zero masks ─────────────────────
  property p_store_be_legal;
    @(posedge clk) disable iff (!rst_n)
    mem_we |-> mem_be inside {4'b0001, 4'b0010, 4'b0100, 4'b1000, 4'b0011, 4'b1100, 4'b1111};
  endproperty
  assert property (p_store_be_legal)
    else `uvm_error("ASSERT", $sformatf("A7: Illegal store byte enable mask %04b", mem_be))

  // ── A8: Non-store operations must assert zero write enables ────────────────
  property p_load_be_zero;
    @(posedge clk) disable iff (!rst_n)
    !mem_we |-> (mem_be == 4'b0000);
  endproperty
  assert property (p_load_be_zero)
    else `uvm_error("ASSERT", "A8: mem_be asserted during non-store cycle")

endmodule
