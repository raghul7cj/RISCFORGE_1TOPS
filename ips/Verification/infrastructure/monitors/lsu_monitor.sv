// =============================================================================
// RISCFORGE 1TOPS — LSU Memory Access Monitor (lsu_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef LSU_MONITOR_SV
`define LSU_MONITOR_SV

module lsu_monitor import tb_pkg::*; #(
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,
  input logic        lsu_req,
  input logic        lsu_we,
  input logic [31:0] lsu_addr,
  input logic [31:0] lsu_wdata,
  input logic [3:0]  lsu_be,
  input logic [31:0] lsu_rdata,
  input logic        lsu_stall,
  input logic        lsu_err,
  input logic [31:0] pc_m = 32'b0,
  input logic [4:0]  lsunit_m = 5'b0,
  input logic        valid_m = 1'b1
);

  lsu_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;
  longint unsigned total_reads;
  longint unsigned total_writes;

  initial begin
    head_ptr     = 0;
    cycle_cnt    = 0;
    total_reads  = 0;
    total_writes = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr     <= 0;
      cycle_cnt    <= 0;
      total_reads  <= 0;
      total_writes <= 0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;
      // Capture completed LSU requests
      if (lsu_req && !lsu_stall && !freeze) begin
        ring_buffer[head_ptr].timestamp    <= cycle_cnt;
        ring_buffer[head_ptr].rel_cycle    <= cycle_cnt;
        ring_buffer[head_ptr].seq          <= total_reads + total_writes;
        ring_buffer[head_ptr].pc           <= pc_m;
        ring_buffer[head_ptr].lsunit       <= lsunit_m;
        ring_buffer[head_ptr].op           <= rf_lsu_op_e'(lsunit_m[2:0]);
        ring_buffer[head_ptr].is_load      <= !lsu_we;
        ring_buffer[head_ptr].is_store     <= lsu_we;
        ring_buffer[head_ptr].addr         <= lsu_addr;
        ring_buffer[head_ptr].wdata        <= lsu_wdata;
        ring_buffer[head_ptr].rdata        <= lsu_rdata;
        ring_buffer[head_ptr].be           <= lsu_be;
        ring_buffer[head_ptr].we           <= lsu_we;
        ring_buffer[head_ptr].is_mmio      <= is_mmio_addr(lsu_addr);
        ring_buffer[head_ptr].err          <= lsu_err;
        ring_buffer[head_ptr].region       <= decode_region(lsu_addr);
        ring_buffer[head_ptr].apb_slot     <= get_expected_apb_slot(lsu_addr);

        head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
        if (lsu_we) total_writes <= total_writes + 1;
        else        total_reads  <= total_reads + 1;
      end
    end
  end

  function automatic void dump_recent_lsu(int count = 10);
    $display("=== Last %0d LSU Memory Transactions ===", count);
    for (int i = count; i > 0; i--) begin
      int idx = (head_ptr - i + RING_BUFFER_DEPTH) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].timestamp != 0) begin
        $display("  [%0t] PC=0x%08X %s Addr=0x%08X %s=0x%08X BE=0x%X %s Slot=%0d",
                 ring_buffer[idx].timestamp,
                 ring_buffer[idx].pc,
                 ring_buffer[idx].we ? "WR" : "RD",
                 ring_buffer[idx].addr,
                 ring_buffer[idx].we ? "WData" : "RData",
                 ring_buffer[idx].we ? ring_buffer[idx].wdata : ring_buffer[idx].rdata,
                 ring_buffer[idx].be,
                 region_name(ring_buffer[idx].region),
                 ring_buffer[idx].apb_slot);
      end
    end
  endfunction

endmodule

`endif // LSU_MONITOR_SV
