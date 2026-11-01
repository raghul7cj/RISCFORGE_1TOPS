// =============================================================================
// RISCFORGE 1TOPS — Core Fetch Monitor (fetch_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef FETCH_MONITOR_SV
`define FETCH_MONITOR_SV

module fetch_monitor import tb_pkg::*; #(
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,
  input logic [31:0] pc_f,
  input logic [31:0] instr_f,
  input logic        imem_en,
  input logic        stall_f,
  input logic [31:0] pc_next,
  input logic        exc_valid_f = 1'b0,
  input logic [5:0]  exc_cause_f = 6'b0,
  input logic [31:0] exc_tval_f  = 32'b0
);

  fetch_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;
  longint unsigned total_fetches;

  initial begin
    head_ptr      = 0;
    cycle_cnt     = 0;
    total_fetches = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr      <= 0;
      cycle_cnt     <= 0;
      total_fetches <= 0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;
      if (imem_en && !stall_f && !freeze) begin
        ring_buffer[head_ptr].timestamp    <= cycle_cnt;
        ring_buffer[head_ptr].rel_cycle    <= cycle_cnt;
        ring_buffer[head_ptr].seq          <= total_fetches;
        ring_buffer[head_ptr].pc           <= pc_f;
        ring_buffer[head_ptr].instr        <= instr_f;
        ring_buffer[head_ptr].valid        <= 1'b1;
        ring_buffer[head_ptr].stall        <= stall_f;
        ring_buffer[head_ptr].branch_taken <= (pc_next != 32'h0) && (pc_next != pc_f + 4);
        ring_buffer[head_ptr].pc_next      <= pc_next;
        ring_buffer[head_ptr].exc_valid    <= exc_valid_f;
        ring_buffer[head_ptr].exc_cause    <= exc_cause_f;
        ring_buffer[head_ptr].exc_tval     <= exc_tval_f;
        ring_buffer[head_ptr].region       <= decode_region(pc_f);

        // Populate shadow table so retire_monitor can disassemble without RTL modification
        shadow_record_fetch(pc_f, instr_f);

        head_ptr      <= (head_ptr + 1) % RING_BUFFER_DEPTH;
        total_fetches <= total_fetches + 1;
      end
    end
  end

  function automatic void dump_recent_fetches(int count = 10);
    $display("=== Recent %0d Instruction Fetches ===", count);
    for (int i = count; i > 0; i--) begin
      int idx = (head_ptr - i + RING_BUFFER_DEPTH) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].valid) begin
        $display("  [%0t] PC=0x%08X Instr=0x%08X %s %s",
                 ring_buffer[idx].timestamp,
                 ring_buffer[idx].pc,
                 ring_buffer[idx].instr,
                 ring_buffer[idx].branch_taken ? "[BRANCH]" : "        ",
                 region_name(ring_buffer[idx].region));
      end
    end
  endfunction

endmodule

`endif // FETCH_MONITOR_SV
