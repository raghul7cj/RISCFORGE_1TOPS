// =============================================================================
// RISCFORGE 1TOPS — Interrupt Lifecycle Monitor (irq_monitor.sv)
// =============================================================================

`timescale 1ns/1ps

`ifndef IRQ_MONITOR_SV
`define IRQ_MONITOR_SV

module irq_monitor import tb_pkg::*; #(
  parameter int unsigned RING_BUFFER_DEPTH = 64
)(
  input logic        clk,
  input logic        rst_n,
  input logic        freeze,

  // Raw Peripheral IRQ Sources
  input logic        gpio_irq,
  input logic        i2c_irq,
  input logic [1:0]  spi_irq,
  input logic        uart_irq,
  input logic [3:0]  timer0_irq,
  input logic [3:0]  timer1_irq,

  // Gateway Observable Taps
  input logic [5:0]  gateway_pend_q,
  input logic [5:0]  gateway_pend_o,

  // Core Inbound
  input logic [15:0] fast_irq_i,
  input logic        timer_irq_i,

  // Arbiter Observables
  input logic        irq_pending,
  input logic [4:0]  irq_id,
  input logic [1:0]  irq_class,
  input logic        rr_ptr_c1,
  input logic        rr_ptr_c0,

  // Shadow Stack Observables
  input logic [1:0]  nest_depth,
  input logic [1:0]  cur_class,

  // Architectural Commit Strobes
  input logic        trap_commit_valid,
  input logic        trap_is_interrupt,
  input logic [30:0] trap_commit_cause,
  input logic [31:0] trap_commit_pc,
  input logic        mret_commit
);

  irq_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];
  int unsigned head_ptr;
  longint unsigned cycle_cnt;

  // Lifecycle counters
  longint unsigned total_irq_asserts;
  longint unsigned total_irq_grants;
  longint unsigned total_irq_acks;
  longint unsigned total_irq_mrets;

  // Edge detection history registers
  logic prev_gpio;
  logic prev_i2c;
  logic [1:0] prev_spi;
  logic prev_uart;
  logic [3:0] prev_t0;
  logic [3:0] prev_t1;
  logic prev_pending;
  longint unsigned grant_cycle;
  int unsigned irq_head_next;
  int unsigned irq_events_this_cycle;
  int unsigned irq_asserts_this_cycle;
  int unsigned irq_grants_this_cycle;
  int unsigned irq_acks_this_cycle;
  int unsigned irq_mrets_this_cycle;

  initial begin
    head_ptr           = 0;
    cycle_cnt          = 0;
    total_irq_asserts  = 0;
    total_irq_grants   = 0;
    total_irq_acks     = 0;
    total_irq_mrets    = 0;
    prev_gpio          = 1'b0;
    prev_i2c           = 1'b0;
    prev_spi           = 2'b0;
    prev_uart          = 1'b0;
    prev_t0            = 4'b0;
    prev_t1            = 4'b0;
    prev_pending       = 1'b0;
    grant_cycle        = 0;
    irq_head_next      = 0;
    irq_events_this_cycle = 0;
    irq_asserts_this_cycle = 0;
    irq_grants_this_cycle = 0;
    irq_acks_this_cycle = 0;
    irq_mrets_this_cycle = 0;
  end

  task automatic push_event(
    input logic [4:0]  id,
    input rf_irq_src_e src,
    input logic        asserted,
    input logic        granted,
    input logic        acked,
    input logic        is_mret_event
  );
    if (!freeze) begin
      ring_buffer[irq_head_next].timestamp      <= cycle_cnt;
      ring_buffer[irq_head_next].rel_cycle      <= cycle_cnt;
      ring_buffer[irq_head_next].seq            <= total_irq_asserts + total_irq_grants + total_irq_acks + total_irq_mrets + irq_events_this_cycle;
      ring_buffer[irq_head_next].irq_id         <= id;
      ring_buffer[irq_head_next].src            <= src;
      ring_buffer[irq_head_next].asserted       <= asserted;
      ring_buffer[irq_head_next].granted        <= granted;
      ring_buffer[irq_head_next].acked          <= acked;
      ring_buffer[irq_head_next].is_interrupt   <= acked;
      ring_buffer[irq_head_next].cause          <= trap_commit_cause;
      ring_buffer[irq_head_next].mip            <= {fast_irq_i, 8'b0, timer_irq_i, 7'b0};
      ring_buffer[irq_head_next].mie            <= '0;
      ring_buffer[irq_head_next].mie_bit        <= 1'b1;
      ring_buffer[irq_head_next].mstatus_mie    <= 1'b1;
      ring_buffer[irq_head_next].irq_class      <= (src != RF_IRQ_NONE) ? tb_pkg::irq_class(src) : 2'b0;
      ring_buffer[irq_head_next].latency_cycles <= (acked && grant_cycle != 0) ? (cycle_cnt - grant_cycle) : 32'd0;
      ring_buffer[irq_head_next].nest_depth     <= nest_depth;
      ring_buffer[irq_head_next].gateway_pend_q <= gateway_pend_q;
      ring_buffer[irq_head_next].rr_ptrs        <= {rr_ptr_c1, rr_ptr_c0};
      ring_buffer[irq_head_next].is_mret        <= is_mret_event;

      irq_head_next = (irq_head_next + 1) % RING_BUFFER_DEPTH;
      irq_events_this_cycle++;
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_ptr           <= 0;
      cycle_cnt          <= 0;
      total_irq_asserts  <= 0;
      total_irq_grants   <= 0;
      total_irq_acks     <= 0;
      total_irq_mrets    <= 0;
      prev_gpio          <= 1'b0;
      prev_i2c           <= 1'b0;
      prev_spi           <= 2'b0;
      prev_uart          <= 1'b0;
      prev_t0            <= 4'b0;
      prev_t1            <= 4'b0;
      prev_pending       <= 1'b0;
      grant_cycle        <= 0;
      irq_head_next      <= 0;
      irq_events_this_cycle <= 0;
      irq_asserts_this_cycle <= 0;
      irq_grants_this_cycle <= 0;
      irq_acks_this_cycle <= 0;
      irq_mrets_this_cycle <= 0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;
      irq_head_next = head_ptr;
      irq_events_this_cycle = 0;
      irq_asserts_this_cycle = 0;
      irq_grants_this_cycle = 0;
      irq_acks_this_cycle = 0;
      irq_mrets_this_cycle = 0;

      // 1. Edge-triggered interrupt line assertions
      if (gpio_irq && !prev_gpio) begin
        push_event(5'd16, RF_IRQ_GPIO_GLOBAL, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (i2c_irq && !prev_i2c) begin
        push_event(5'd17, RF_IRQ_I2C, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (spi_irq[0] && !prev_spi[0]) begin
        push_event(5'd18, RF_IRQ_SPI_EVT0, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (spi_irq[1] && !prev_spi[1]) begin
        push_event(5'd27, RF_IRQ_SPI_EVT1, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (uart_irq && !prev_uart) begin
        push_event(5'd19, RF_IRQ_UART, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer0_irq[0] && !prev_t0[0]) begin
        push_event(5'd20, RF_IRQ_T0_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer0_irq[1] && !prev_t0[1]) begin
        push_event(5'd7, RF_IRQ_MTIP, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer0_irq[2] && !prev_t0[2]) begin
        push_event(5'd21, RF_IRQ_T0_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer0_irq[3] && !prev_t0[3]) begin
        push_event(5'd22, RF_IRQ_T0_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer1_irq[0] && !prev_t1[0]) begin
        push_event(5'd23, RF_IRQ_T1_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer1_irq[1] && !prev_t1[1]) begin
        push_event(5'd24, RF_IRQ_T1_C0_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer1_irq[2] && !prev_t1[2]) begin
        push_event(5'd25, RF_IRQ_T1_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end
      if (timer1_irq[3] && !prev_t1[3]) begin
        push_event(5'd26, RF_IRQ_T1_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
        irq_asserts_this_cycle++;
      end

      // 2. Arbiter Grant (Edge-gated on irq_pending to prevent ring buffer flooding)
      if (irq_pending && !prev_pending) begin
        grant_cycle <= cycle_cnt;
        push_event(irq_id, irq_src_of_cause_enc(irq_id), 1'b1, 1'b1, 1'b0, 1'b0);
        irq_grants_this_cycle++;
      end

      // 3. Commit Acknowledgement (Trap Commit for Interrupt)
      if (trap_commit_valid && trap_is_interrupt) begin
        push_event(trap_commit_cause[4:0], irq_src_of_cause_enc(trap_commit_cause[4:0]), 1'b1, 1'b1, 1'b1, 1'b0);
        irq_acks_this_cycle++;
      end

      // 4. MRET Commit (Stack pop and context restore)
      if (mret_commit) begin
        push_event(5'd0, RF_IRQ_NONE, 1'b0, 1'b0, 1'b0, 1'b1);
        irq_mrets_this_cycle++;
      end

      head_ptr          <= irq_head_next;
      total_irq_asserts <= total_irq_asserts + irq_asserts_this_cycle;
      total_irq_grants  <= total_irq_grants  + irq_grants_this_cycle;
      total_irq_acks    <= total_irq_acks    + irq_acks_this_cycle;
      total_irq_mrets   <= total_irq_mrets   + irq_mrets_this_cycle;

      // Update history
      prev_gpio    <= gpio_irq;
      prev_i2c     <= i2c_irq;
      prev_spi     <= spi_irq;
      prev_uart    <= uart_irq;
      prev_t0      <= timer0_irq;
      prev_t1      <= timer1_irq;
      prev_pending <= irq_pending;
    end
  end

  function automatic void dump_recent_irqs(int count = 10);
    $display("=== Last %0d Interrupt Lifecycle Events ===", count);
    for (int i = count; i > 0; i--) begin
      int idx = (head_ptr - i + RING_BUFFER_DEPTH) % RING_BUFFER_DEPTH;
      if (ring_buffer[idx].timestamp != 0) begin
        $display("  [%0t] ID=%0d %-14s Assert=%b Grant=%b Ack=%b Depth=%0d Class=%s Latency=%0d%s",
                 ring_buffer[idx].timestamp,
                 ring_buffer[idx].irq_id,
                 irq_src_name(ring_buffer[idx].src),
                 ring_buffer[idx].asserted,
                 ring_buffer[idx].granted,
                 ring_buffer[idx].acked,
                 ring_buffer[idx].nest_depth,
                 irq_class_name(ring_buffer[idx].irq_class),
                 ring_buffer[idx].latency_cycles,
                 ring_buffer[idx].is_mret ? " [MRET]" : "");
      end
    end
  endfunction

endmodule

`endif // IRQ_MONITOR_SV
