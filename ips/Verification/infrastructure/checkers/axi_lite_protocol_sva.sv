// =============================================================================
// RISCFORGE 1TOPS — AXI4-Lite Protocol Assertions (axi_lite_protocol_sva.sv)
// =============================================================================

`timescale 1ns/1ps

module axi_lite_protocol_sva (
  input logic        clk,
  input logic        rst_n,

  // Write Address Channel
  input logic [31:0] awaddr,
  input logic [2:0]  awprot,
  input logic        awvalid,
  input logic        awready,

  // Write Data Channel
  input logic [31:0] wdata,
  input logic [3:0]  wstrb,
  input logic        wvalid,
  input logic        wready,

  // Write Response Channel
  input logic [1:0]  bresp,
  input logic        bvalid,
  input logic        bready,

  // Read Address Channel
  input logic [31:0] araddr,
  input logic [2:0]  arprot,
  input logic        arvalid,
  input logic        arready,

  // Read Data Channel
  input logic [31:0] rdata,
  input logic [1:0]  rresp,
  input logic        rvalid,
  input logic        rready
);

  // 1. AWVALID Stability: AWADDR must remain stable until AWREADY
  property p_awaddr_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> $stable(awaddr) && $stable(awprot) && awvalid;
  endproperty
  assert_awaddr_stable: assert property (p_awaddr_stable)
    else $error("[SVA-AXI-01] AWADDR/AWPROT not stable while AWVALID is high");

  // 2. WVALID Stability: WDATA and WSTRB must remain stable until WREADY
  property p_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> $stable(wdata) && $stable(wstrb) && wvalid;
  endproperty
  assert_wdata_stable: assert property (p_wdata_stable)
    else $error("[SVA-AXI-02] WDATA/WSTRB not stable while WVALID is high");

  // 3. ARVALID Stability: ARADDR must remain stable until ARREADY
  property p_araddr_stable;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && !arready) |=> $stable(araddr) && $stable(arprot) && arvalid;
  endproperty
  assert_araddr_stable: assert property (p_araddr_stable)
    else $error("[SVA-AXI-03] ARADDR/ARPROT not stable while ARVALID is high");

  // 4. BVALID Handshake: BVALID must remain high until BREADY
  property p_bvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> bvalid && $stable(bresp);
  endproperty
  assert_bvalid_stable: assert property (p_bvalid_stable)
    else $error("[SVA-AXI-04] BVALID/BRESP dropped before BREADY");

  // 5. RVALID Handshake: RVALID must remain high until RREADY
  property p_rvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (rvalid && !rready) |=> rvalid && $stable(rdata) && $stable(rresp);
  endproperty
  assert_rvalid_stable: assert property (p_rvalid_stable)
    else $error("[SVA-AXI-05] RVALID/RDATA dropped before RREADY");

endmodule
