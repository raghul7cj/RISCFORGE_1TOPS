// =============================================================================
// RISCFORGE 1TOPS — APB 6-Slot Per-Peripheral Monitor (apb_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef APB_MONITOR_SV
`define APB_MONITOR_SV

module apb_monitor import tb_pkg::*; #(
  parameter int unsigned NUM_SLOTS         = 6,
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,

  // APB Interface
  input logic [NUM_SLOTS*32-1:0] paddr_flat,
  input logic [NUM_SLOTS-1:0]    psel,
  input logic [NUM_SLOTS-1:0]    penable,
  input logic [NUM_SLOTS-1:0]    pwrite,
  input logic [NUM_SLOTS*32-1:0] pwdata_flat,
  input logic [NUM_SLOTS*4-1:0]  pstrb_flat,
  input logic [NUM_SLOTS-1:0]    pready,
  input logic [NUM_SLOTS*32-1:0] prdata_flat,
  input logic [NUM_SLOTS-1:0]    pslverr
);

  apb_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;
  longint unsigned total_apb_trans;
  longint unsigned per_slot_trans [0:NUM_SLOTS-1];

  logic [31:0] ws_cnt [0:NUM_SLOTS-1];

  initial begin
    head_ptr        = 0;
    cycle_cnt       = 0;
    total_apb_trans = 0;
    for (int s = 0; s < NUM_SLOTS; s++) begin
      per_slot_trans[s] = 0;
      ws_cnt[s]         = 0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr        <= 0;
      cycle_cnt       <= 0;
      total_apb_trans <= 0;
      for (int s = 0; s < NUM_SLOTS; s++) begin
        per_slot_trans[s] <= 0;
        ws_cnt[s]         <= 0;
      end
    end else begin
      cycle_cnt <= cycle_cnt + 1;

      for (int s = 0; s < NUM_SLOTS; s++) begin
        if (psel[s] && penable[s] && !pready[s])
          ws_cnt[s] <= ws_cnt[s] + 1;
        else if (psel[s] && penable[s] && pready[s])
          ws_cnt[s] <= 0;
      end

      for (int i = 0; i < NUM_SLOTS; i++) begin
        // APB Access cycle completion: PSEL && PENABLE && PREADY
        if (psel[i] && penable[i] && pready[i] && !freeze) begin
          ring_buffer[head_ptr].timestamp    <= cycle_cnt;
          ring_buffer[head_ptr].rel_cycle    <= cycle_cnt;
          ring_buffer[head_ptr].seq          <= total_apb_trans;
          ring_buffer[head_ptr].slot         <= i;
          ring_buffer[head_ptr].paddr        <= paddr_flat[i*32 +: 32];
          ring_buffer[head_ptr].pwdata       <= pwdata_flat[i*32 +: 32];
          ring_buffer[head_ptr].prdata       <= prdata_flat[i*32 +: 32];
          ring_buffer[head_ptr].pstrb        <= pstrb_flat[i*4 +: 4];
          ring_buffer[head_ptr].pwrite       <= pwrite[i];
          ring_buffer[head_ptr].pready       <= 1'b1;
          ring_buffer[head_ptr].pslverr      <= pslverr[i];
          ring_buffer[head_ptr].wait_states  <= ws_cnt[i];
          ring_buffer[head_ptr].setup_cycle  <= (cycle_cnt >= ws_cnt[i] + 1) ? (cycle_cnt - ws_cnt[i] - 1) : 0;
          ring_buffer[head_ptr].access_cycle <= cycle_cnt;
          ring_buffer[head_ptr].addr_match   <= apb_slot_base(i);

          head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
          total_apb_trans <= total_apb_trans + 1;
          per_slot_trans[i] <= per_slot_trans[i] + 1;
        end
      end
    end
  end

  task automatic dump_recent_trans(input int num_entries = 10);
    int start_idx;
    $display("\n=======================================================");
    $display(" APB RECENT TRANSACTIONS DUMP (Total APB Transfers: %0d)", total_apb_trans);
    $display("=======================================================");
    $display(" [TIME]     SLOT  DIR  PADDR        PWDATA       PRDATA       PSLVERR");
    $display("---------------------------------------------------------------------");
    start_idx = (head_ptr >= num_entries) ? (head_ptr - num_entries) : (RING_BUFFER_DEPTH + head_ptr - num_entries);
    for (int i = 0; i < num_entries; i++) begin
      int idx = (start_idx + i) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].timestamp != 0) begin
        $display(" [%08t]  [%0d]   %s   0x%08h   0x%08h   0x%08h   %0b",
          ring_buffer[idx].timestamp,
          ring_buffer[idx].slot,
          ring_buffer[idx].pwrite ? "WR" : "RD",
          ring_buffer[idx].paddr,
          ring_buffer[idx].pwdata,
          ring_buffer[idx].prdata,
          ring_buffer[idx].pslverr
        );
      end
    end
    $display("=======================================================\n");
  endtask

endmodule

`endif // APB_MONITOR_SV
