// =============================================================================
// RISCFORGE 1TOPS — AXI4-Lite Protocol Monitor (axi_lite_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef AXI_LITE_MONITOR_SV
`define AXI_LITE_MONITOR_SV

module axi_lite_monitor import tb_pkg::*; #(
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,

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

  axi_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;

  logic [31:0] latched_awaddr;
  logic [2:0]  latched_awprot;
  logic [31:0] latched_wdata;
  logic [3:0]  latched_wstrb;
  logic [31:0] latched_araddr;
  logic [2:0]  latched_arprot;

  // Single-cycle handshake support: if address/data valid & ready in current cycle,
  // use port directly instead of registered value from previous cycle.
  wire [31:0] eff_awaddr = (awvalid && awready) ? awaddr : latched_awaddr;
  wire [2:0]  eff_awprot = (awvalid && awready) ? awprot : latched_awprot;
  wire [31:0] eff_wdata  = (wvalid  && wready)  ? wdata  : latched_wdata;
  wire [3:0]  eff_wstrb  = (wvalid  && wready)  ? wstrb  : latched_wstrb;
  wire [31:0] eff_araddr = (arvalid && arready) ? araddr : latched_araddr;
  wire [2:0]  eff_arprot = (arvalid && arready) ? arprot : latched_arprot;

  wire b_fire = bvalid && bready && !freeze;
  wire r_fire = rvalid && rready && !freeze;

  longint unsigned total_axi_writes;
  longint unsigned total_axi_reads;

  initial begin
    head_ptr         = 0;
    cycle_cnt        = 0;
    total_axi_writes = 0;
    total_axi_reads  = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr         <= 0;
      cycle_cnt        <= 0;
      total_axi_writes <= 0;
      total_axi_reads  <= 0;
      latched_awaddr   <= '0;
      latched_awprot   <= '0;
      latched_wdata    <= '0;
      latched_wstrb    <= '0;
      latched_araddr   <= '0;
      latched_arprot   <= '0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;

      if (awvalid && awready) begin
        latched_awaddr <= awaddr;
        latched_awprot <= awprot;
      end
      if (wvalid && wready) begin
        latched_wdata  <= wdata;
        latched_wstrb  <= wstrb;
      end
      if (arvalid && arready) begin
        latched_araddr <= araddr;
        latched_arprot <= arprot;
      end

      // Race-free write to ring buffer handling single or simultaneous B and R handshakes
      case ({b_fire, r_fire})
        2'b10: begin // Write only
          ring_buffer[head_ptr].timestamp <= cycle_cnt;
          ring_buffer[head_ptr].rel_cycle <= cycle_cnt;
          ring_buffer[head_ptr].seq       <= total_axi_writes + total_axi_reads;
          ring_buffer[head_ptr].addr      <= eff_awaddr;
          ring_buffer[head_ptr].data      <= eff_wdata;
          ring_buffer[head_ptr].strb      <= eff_wstrb;
          ring_buffer[head_ptr].resp      <= bresp;
          ring_buffer[head_ptr].is_write  <= 1'b1;
          ring_buffer[head_ptr].prot      <= eff_awprot;
          ring_buffer[head_ptr].b_hs      <= 1'b1;
          ring_buffer[head_ptr].is_mmio   <= is_mmio_addr(eff_awaddr);
          ring_buffer[head_ptr].apb_slot  <= get_expected_apb_slot(eff_awaddr);
          ring_buffer[head_ptr].decoded   <= (get_expected_apb_slot(eff_awaddr) != RF_APB_NONE);

          head_ptr         <= (head_ptr + 1) % RING_BUFFER_DEPTH;
          total_axi_writes <= total_axi_writes + 1;
        end

        2'b01: begin // Read only
          ring_buffer[head_ptr].timestamp <= cycle_cnt;
          ring_buffer[head_ptr].rel_cycle <= cycle_cnt;
          ring_buffer[head_ptr].seq       <= total_axi_writes + total_axi_reads;
          ring_buffer[head_ptr].addr      <= eff_araddr;
          ring_buffer[head_ptr].data      <= rdata;
          ring_buffer[head_ptr].strb      <= 4'hF;
          ring_buffer[head_ptr].resp      <= rresp;
          ring_buffer[head_ptr].is_write  <= 1'b0;
          ring_buffer[head_ptr].prot      <= eff_arprot;
          ring_buffer[head_ptr].is_mmio   <= is_mmio_addr(eff_araddr);
          ring_buffer[head_ptr].apb_slot  <= get_expected_apb_slot(eff_araddr);
          ring_buffer[head_ptr].decoded   <= (get_expected_apb_slot(eff_araddr) != RF_APB_NONE);

          head_ptr        <= (head_ptr + 1) % RING_BUFFER_DEPTH;
          total_axi_reads <= total_axi_reads + 1;
        end

        2'b11: begin // Simultaneous B and R handshakes in same cycle
          int next_idx;
          next_idx = (head_ptr + 1) % RING_BUFFER_DEPTH;

          // Slot 1: Write transaction
          ring_buffer[head_ptr].timestamp <= cycle_cnt;
          ring_buffer[head_ptr].rel_cycle <= cycle_cnt;
          ring_buffer[head_ptr].seq       <= total_axi_writes + total_axi_reads;
          ring_buffer[head_ptr].addr      <= eff_awaddr;
          ring_buffer[head_ptr].data      <= eff_wdata;
          ring_buffer[head_ptr].strb      <= eff_wstrb;
          ring_buffer[head_ptr].resp      <= bresp;
          ring_buffer[head_ptr].is_write  <= 1'b1;
          ring_buffer[head_ptr].prot      <= eff_awprot;
          ring_buffer[head_ptr].b_hs      <= 1'b1;
          ring_buffer[head_ptr].is_mmio   <= is_mmio_addr(eff_awaddr);
          ring_buffer[head_ptr].apb_slot  <= get_expected_apb_slot(eff_awaddr);
          ring_buffer[head_ptr].decoded   <= (get_expected_apb_slot(eff_awaddr) != RF_APB_NONE);

          // Slot 2: Read transaction
          ring_buffer[next_idx].timestamp <= cycle_cnt;
          ring_buffer[next_idx].rel_cycle <= cycle_cnt;
          ring_buffer[next_idx].seq       <= total_axi_writes + total_axi_reads + 1;
          ring_buffer[next_idx].addr      <= eff_araddr;
          ring_buffer[next_idx].data      <= rdata;
          ring_buffer[next_idx].strb      <= 4'hF;
          ring_buffer[next_idx].resp      <= rresp;
          ring_buffer[next_idx].is_write  <= 1'b0;
          ring_buffer[next_idx].prot      <= eff_arprot;
          ring_buffer[next_idx].is_mmio   <= is_mmio_addr(eff_araddr);
          ring_buffer[next_idx].apb_slot  <= get_expected_apb_slot(eff_araddr);
          ring_buffer[next_idx].decoded   <= (get_expected_apb_slot(eff_araddr) != RF_APB_NONE);

          head_ptr         <= (head_ptr + 2) % RING_BUFFER_DEPTH;
          total_axi_writes <= total_axi_writes + 1;
          total_axi_reads  <= total_axi_reads + 1;
        end

        default: ;
      endcase
    end
  end

  task automatic dump_recent_trans(input int num_entries = 10);
    int start_idx;
    $display("\n=======================================================");
    $display(" AXI4-LITE RECENT TRANSACTIONS DUMP (Total WR: %0d, RD: %0d)", total_axi_writes, total_axi_reads);
    $display("=======================================================");
    $display(" [TIME]     DIR   ADDR         DATA         STRB  RESP");
    $display("-------------------------------------------------------");
    start_idx = (head_ptr >= num_entries) ? (head_ptr - num_entries) : (RING_BUFFER_DEPTH + head_ptr - num_entries);
    for (int i = 0; i < num_entries; i++) begin
      int idx = (start_idx + i) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].timestamp != 0) begin
        $display(" [%08t]  %s   0x%08h   0x%08h   0x%1h     0x%1h",
          ring_buffer[idx].timestamp,
          ring_buffer[idx].is_write ? "WR " : "RD ",
          ring_buffer[idx].addr,
          ring_buffer[idx].data,
          ring_buffer[idx].strb,
          ring_buffer[idx].resp
        );
      end
    end
    $display("=======================================================\n");
  endtask

endmodule

`endif // AXI_LITE_MONITOR_SV
