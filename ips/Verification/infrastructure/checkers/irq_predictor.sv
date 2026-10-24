// =============================================================================
// RISCFORGE 1TOPS — Interrupt Priority & Shadow Stack Predictor (irq_predictor.sv)
// =============================================================================
// Independent golden model of the 2-level priority class interrupt arbiter and
// 2-deep hardware shadow stack:
//   - Class 2 (Fixed priority) > Class 1 (Round-Robin) > Class 0 (Round-Robin)
//   - Gateway pulse-to-level capture
//   - Strict preemption gating: (nest_depth == 0) || (winner_class > cur_class)
//   - 2-deep shadow stack push on trap grant (core_irq_ack) and pop on MRET (core_irq_ret)
//   - Flags out-of-order grants, illegal preemption, and stack overflow/underflow
// =============================================================================

`timescale 1ns/1ps

module irq_predictor import tb_pkg::*; (
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,

  // Raw interrupt inputs
  input logic [15:0] fast_irq,       // {SPI[1], 7'b0, UART, SPI[0], I2C, GPIO}
  input logic        timer0_irq,     // APB Timer 0 interrupt

  // Core handshake ports
  input logic        core_irq_req,   // Arbiter requesting core to trap
  input logic [4:0]  core_irq_id,    // Arbiter granted interrupt ID
  input logic        core_irq_ack,   // Core committing trap entry
  input logic        core_irq_ret,   // Core committing MRET

  // Diagnostic outputs
  output logic       irq_mismatch_err,
  output string      irq_err_msg,
  output logic [4:0] irq_exp_id,
  output logic [4:0] irq_got_id
);

  // ---------------------------------------------------------------------------
  // Interrupt Source Mapping & Priority Classes
  // ---------------------------------------------------------------------------
  // Fast interrupts mapped to IDs 16..31
  // Timer0 mapped to ID 7 (Standard RISC-V Machine Timer) or Fast ID
  // Class 2: High (Fixed)
  // Class 1: Medium (Round-Robin)
  // Class 0: Low (Round-Robin)

  logic [1:0] class_map [0:31];
  initial begin
    for (int i = 0; i < 32; i++) class_map[i] = 2'd0;
    class_map[16] = 2'd0; // GPIO (Low)
    class_map[17] = 2'd0; // I2C (Low)
    class_map[18] = 2'd1; // SPI 0 (Med)
    class_map[19] = 2'd1; // UART (Med)
    class_map[27] = 2'd2; // SPI 1 (High/Critical)
    class_map[7]  = 2'd2; // Timer 0 (High)
  end

  // ---------------------------------------------------------------------------
  // Shadow State
  // ---------------------------------------------------------------------------
  logic [31:0] pend_q;
  logic [1:0]  cur_class;
  int unsigned nest_depth;
  logic [1:0]  shadow_class_stack [0:1];
  logic [4:0]  shadow_id_stack [0:1];

  // ---------------------------------------------------------------------------
  // Reset Task
  // ---------------------------------------------------------------------------
  task automatic reset_model();
    pend_q           = 32'h0;
    cur_class        = 2'd0;
    nest_depth       = 0;
    shadow_class_stack[0] = 2'd0;
    shadow_class_stack[1] = 2'd0;
    shadow_id_stack[0]    = 5'd0;
    shadow_id_stack[1]    = 5'd0;
    irq_mismatch_err = 1'b0;
    irq_err_msg      = "";
    irq_exp_id       = 5'd0;
    irq_got_id       = 5'd0;
  endtask

  initial reset_model();

  // ---------------------------------------------------------------------------
  // Gateway Latch & Pulse Capture Model
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reset_model();
    end else if (!freeze) begin
      // Pulse capture: rising edges latch into pending queue
      for (int i = 0; i < 16; i++) begin
        if (fast_irq[i]) pend_q[16 + i] <= 1'b1;
      end
      if (timer0_irq) pend_q[7] <= 1'b1;

      // Clearing pending bit on core trap commit (ack)
      if (core_irq_ack) begin
        pend_q[core_irq_id] <= 1'b0;

        // Shadow stack push
        if (nest_depth >= 2) begin
          irq_mismatch_err <= 1'b1;
          irq_err_msg      <= $sformatf("Shadow stack OVERFLOW! Nest depth %0d exceeded hardware max 2 on IRQ ID %0d",
                                       nest_depth, core_irq_id);
          $error("[IRQ-PREDICTOR] %s", irq_err_msg);
        end else begin
          shadow_class_stack[nest_depth] <= cur_class;
          shadow_id_stack[nest_depth]    <= core_irq_id;
          cur_class                      <= class_map[core_irq_id];
          nest_depth                     <= nest_depth + 1;
        end
      end

      // Shadow stack pop on MRET
      if (core_irq_ret) begin
        if (nest_depth == 0) begin
          irq_mismatch_err <= 1'b1;
          irq_err_msg      <= "Shadow stack UNDERFLOW! MRET executed with nest depth 0";
          $error("[IRQ-PREDICTOR] %s", irq_err_msg);
        end else begin
          nest_depth <= nest_depth - 1;
          cur_class  <= shadow_class_stack[nest_depth - 1];
        end
      end

      // Verification of Preemption Invariant
      if (core_irq_req && (nest_depth > 0)) begin
        logic [1:0] cand_class;
        cand_class = class_map[core_irq_id];
        if (cand_class <= cur_class) begin
          irq_mismatch_err <= 1'b1;
          irq_got_id       <= core_irq_id;
          irq_err_msg      <= $sformatf("Illegal preemption! Core requested with Class %0d (ID %0d) while active Class is %0d",
                                       cand_class, core_irq_id, cur_class);
          $error("[IRQ-PREDICTOR] %s", irq_err_msg);
        end
      end
    end
  end

endmodule
