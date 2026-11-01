// =============================================================================
// RISCFORGE 1TOPS — Core Retire Monitor / RVFI Tracker (retire_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef RETIRE_MONITOR_SV
`define RETIRE_MONITOR_SV

module retire_monitor import tb_pkg::*; #(
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,
  input logic        valid_w,
  input logic        exc_valid_w = 1'b0,
  input logic [31:0] pc_w,
  input logic [31:0] instr_w = 32'b0,
  input logic [4:0]  rd_addr_w,
  input logic [31:0] rd_wdata_w,
  input logic        reg_we_w,
  input logic        trap_w,
  input logic        trap_is_interrupt = 1'b0,
  input logic [30:0] trap_cause = 31'b0,
  input logic        is_mret_w = 1'b0,
  input logic        csr_we_w = 1'b0,
  input logic [11:0] csr_addr_w = 12'b0,
  input logic [31:0] csr_wdata_w = 32'b0
);

  retire_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;
  longint unsigned total_retired_instr;
  longint unsigned total_retired; // Alias for backward compatibility
  longint unsigned total_traps;

  // True architectural commit in RISCFORGE pipeline:
  // Normal instruction commits when valid_W is high and no exception/trap occurs.
  wire retire_fire = valid_w && ~exc_valid_w;
  wire trap_fire   = trap_w;

  initial begin
    head_ptr            = 0;
    cycle_cnt           = 0;
    total_retired_instr = 0;
    total_retired       = 0;
    total_traps         = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr            <= 0;
      cycle_cnt           <= 0;
      total_retired_instr <= 0;
      total_retired       <= 0;
      total_traps         <= 0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;

      // Architectural instruction commit or trap commit
      if ((retire_fire || trap_fire) && !freeze) begin
        logic [31:0] resolved_instr;
        // Resolve instruction word: use port if non-zero, else shadow PC map
        resolved_instr = (instr_w != 32'h0000_0000) ? instr_w : shadow_lookup_instr(pc_w);

        ring_buffer[head_ptr].timestamp    <= cycle_cnt;
        ring_buffer[head_ptr].rel_cycle    <= cycle_cnt;
        ring_buffer[head_ptr].seq          <= total_retired_instr + total_traps;
        ring_buffer[head_ptr].pc           <= pc_w;
        ring_buffer[head_ptr].instr        <= resolved_instr;
        ring_buffer[head_ptr].rd_addr      <= rd_addr_w;
        ring_buffer[head_ptr].rd_wdata     <= rd_wdata_w;
        ring_buffer[head_ptr].reg_we       <= reg_we_w;
        ring_buffer[head_ptr].trap         <= trap_w;
        ring_buffer[head_ptr].irq_ack      <= trap_is_interrupt;
        ring_buffer[head_ptr].is_mret      <= is_mret_w;
        ring_buffer[head_ptr].csr_we       <= csr_we_w;
        ring_buffer[head_ptr].csr_addr     <= csr_addr_w;
        ring_buffer[head_ptr].csr_wdata    <= csr_wdata_w;
        ring_buffer[head_ptr].exc_cause    <= trap_cause[5:0];
        ring_buffer[head_ptr].cause        <= trap_cause;
        ring_buffer[head_ptr].irq_src      <= trap_is_interrupt ? irq_src_of_cause_enc(trap_cause[4:0]) : RF_IRQ_NONE;
        ring_buffer[head_ptr].irq_class    <= trap_is_interrupt ? irq_class(irq_src_of_cause_enc(trap_cause[4:0])) : 2'b0;

        head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;

        if (retire_fire) begin
          total_retired_instr <= total_retired_instr + 1;
          total_retired       <= total_retired + 1;
        end
        if (trap_fire) begin
          total_traps <= total_traps + 1;
        end
      end
    end
  end

  function automatic void dump_recent_retires(int count = 10);
    $display("=== Last %0d Retired Instructions ===", count);
    for (int i = count; i > 0; i--) begin
      int idx = (head_ptr - i + RING_BUFFER_DEPTH) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].timestamp != 0) begin
        $display("  [%0t] PC=0x%08X Instr=0x%08X %s%s%s (rd=x%0d, val=0x%08X)",
                 ring_buffer[idx].timestamp,
                 ring_buffer[idx].pc,
                 ring_buffer[idx].instr,
                 ring_buffer[idx].trap        ? "[TRAP] " : "       ",
                 ring_buffer[idx].irq_ack     ? "[IRQ] "  : "",
                 ring_buffer[idx].is_mret     ? "[MRET]"  : "",
                 ring_buffer[idx].rd_addr,
                 ring_buffer[idx].rd_wdata);
      end
    end
  endfunction

endmodule

`endif // RETIRE_MONITOR_SV
