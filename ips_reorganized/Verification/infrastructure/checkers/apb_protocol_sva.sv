// =============================================================================
// RISCFORGE 1TOPS — APB Protocol Assertions (apb_protocol_sva.sv)
// =============================================================================

`timescale 1ns/1ps

module apb_protocol_sva #(
  parameter int unsigned NUM_SLOTS = 6
)(
  input logic                 clk,
  input logic                 rst_n,
  input logic [31:0]          paddr,
  input logic [NUM_SLOTS-1:0] psel,
  input logic                 penable,
  input logic                 pwrite,
  input logic [31:0]          pwdata,
  input logic [NUM_SLOTS-1:0] pready,
  input logic [31:0]          prdata [0:NUM_SLOTS-1],
  input logic [NUM_SLOTS-1:0] pslverr
);

  // 1. One-hot PSEL: At most one peripheral select active
  property p_psel_onehot;
    @(posedge clk) disable iff (!rst_n)
    $onehot0(psel);
  endproperty
  assert_psel_onehot: assert property (p_psel_onehot)
    else $error("[SVA-APB-01] Multiple PSEL bits asserted simultaneously");

  // 2. Setup to Access Phase Transition: PSEL without PENABLE must be followed by PSEL with PENABLE
  genvar i;
  generate
    for (i = 0; i < NUM_SLOTS; i++) begin : gen_apb_slot_sva
      property p_setup_to_access;
        @(posedge clk) disable iff (!rst_n)
        (psel[i] && !penable) |=> (psel[i] && penable);
      endproperty
      assert_setup_to_access: assert property (p_setup_to_access)
        else $error("[SVA-APB-02] APB setup phase on slot %0d not followed by access phase", i);
    end
  endgenerate

  // 3. Control Stability: PADDR and PWRITE must not change between setup and access
  property p_apb_control_stable;
    @(posedge clk) disable iff (!rst_n)
    (|psel && !penable) |=> $stable(paddr) && $stable(pwrite) && $stable(pwdata);
  endproperty
  assert_apb_control_stable: assert property (p_apb_control_stable)
    else $error("[SVA-APB-03] APB control/data changed between setup and access phase");

endmodule
