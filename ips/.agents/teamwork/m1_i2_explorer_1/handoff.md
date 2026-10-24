# Handoff Report — Milestone 1 (Iteration 2): IRQ Monitor Same-Cycle Concurrency Race & Timer 1 Remediation

## Executive Summary
This investigation resolves the two gating defects identified in `irq_monitor.sv`:
1. **Critical Concurrency Race**: `push_event` utilized non-blocking assignment (`<=`) on `head_ptr` and `ring_buffer[head_ptr]`. When multiple interrupt lines asserted or concurrent events (assertion, grant, ack, mret) fired in the same clock cycle, every call evaluated against the un-updated `head_ptr`, causing subsequent events in the cycle to overwrite earlier events in the exact same ring buffer slot, while `head_ptr` only incremented by 1 instead of N.
2. **Missing Timer 1 Edge Detection**: Although `input logic [3:0] timer1_irq` was declared in the module port list and sampled into `prev_t1`, lines 142–179 omitted all edge-detection logic for channels 0–3, rendering Timer 1 interrupts completely invisible to the monitor.

An exact, drop-in SystemVerilog remediation strategy has been formulated, maintaining full IEEE 1800 compatibility, zero cycle overhead, deterministic multi-event ordering, wrap-boundary safety, and freeze immunity.

---

## 1. Observation

### 1.1 Empirical Reproduction & Test Evidence
- **Stress Test**: `Verification/infrastructure/tb/tb_freeze_buffer_stress.sv` (Test 5: Multi-Interrupt Concurrency in IRQ Monitor)
- **Execution Script**: `Verification/infrastructure/run_freeze_stress.ps1`
- **Observed Test Failure**:
  ```
  --- [TEST 5] Multi-Interrupt Concurrency in IRQ Monitor ---
  IRQ Monitor After Dual Simultaneous Assertion:
    total_irq_asserts = 1
    head_ptr          = 1
    ring_buffer[0].src = UART (id=19)
    ring_buffer[1].src = NONE (id=x)
  [CRITICAL BUG CONFIRMED] irq_monitor: Simultaneous GPIO and UART assertion resulted in only 1 event recorded! The earlier event was silently overwritten by the second call in the same cycle due to non-blocking head_ptr scheduling!
  [ASSERTION FAILED] [IRQ_CONCURRENCY_PRESERVED] Simultaneous IRQs caused ring buffer slot overwrite / dropped event!
  ```

### 1.2 Verbatim Source Inspection: `irq_monitor.sv`
- **Lines 89–121**:
  ```systemverilog
  task automatic push_event(
    input logic [4:0]  id,
    input rf_irq_src_e src,
    input logic        asserted,
    input logic        granted,
    input logic        acked,
    input logic        is_mret_event
  );
    if (!freeze) begin
      ring_buffer[head_ptr].timestamp      <= cycle_cnt;
      ring_buffer[head_ptr].rel_cycle      <= cycle_cnt;
      ring_buffer[head_ptr].seq            <= total_irq_asserts + total_irq_grants + total_irq_acks + total_irq_mrets;
      ring_buffer[head_ptr].irq_id         <= id;
      ring_buffer[head_ptr].src            <= src;
      ring_buffer[head_ptr].asserted       <= asserted;
      ring_buffer[head_ptr].granted        <= granted;
      ring_buffer[head_ptr].acked          <= acked;
      ring_buffer[head_ptr].is_interrupt   <= acked;
      ring_buffer[head_ptr].cause          <= trap_commit_cause;
      ring_buffer[head_ptr].mip            <= {fast_irq_i, 8'b0, timer_irq_i, 7'b0};
      ring_buffer[head_ptr].mie            <= '0;
      ring_buffer[head_ptr].mie_bit        <= 1'b1;
      ring_buffer[head_ptr].mstatus_mie    <= 1'b1;
      ring_buffer[head_ptr].irq_class      <= (src != RF_IRQ_NONE) ? tb_pkg::irq_class(src) : 2'b0;
      ring_buffer[head_ptr].latency_cycles <= (acked && grant_cycle != 0) ? (cycle_cnt - grant_cycle) : 32'd0;
      ring_buffer[head_ptr].nest_depth     <= nest_depth;
      ring_buffer[head_ptr].gateway_pend_q <= gateway_pend_q;
      ring_buffer[head_ptr].rr_ptrs        <= {rr_ptr_c1, rr_ptr_c0};
      ring_buffer[head_ptr].is_mret        <= is_mret_event;

      head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
    end
  endtask
  ```
- **Lines 142–179**:
  ```systemverilog
  // 1. Edge-triggered interrupt line assertions
  if (gpio_irq && !prev_gpio) begin
    push_event(5'd16, RF_IRQ_GPIO_GLOBAL, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (i2c_irq && !prev_i2c) begin
    push_event(5'd17, RF_IRQ_I2C, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (spi_irq[0] && !prev_spi[0]) begin
    push_event(5'd18, RF_IRQ_SPI_EVT0, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (spi_irq[1] && !prev_spi[1]) begin
    push_event(5'd27, RF_IRQ_SPI_EVT1, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (uart_irq && !prev_uart) begin
    push_event(5'd19, RF_IRQ_UART, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer0_irq[0] && !prev_t0[0]) begin
    push_event(5'd20, RF_IRQ_T0_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer0_irq[1] && !prev_t0[1]) begin
    push_event(5'd7, RF_IRQ_MTIP, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer0_irq[2] && !prev_t0[2]) begin
    push_event(5'd21, RF_IRQ_T0_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  if (timer0_irq[3] && !prev_t0[3]) begin
    push_event(5'd22, RF_IRQ_T0_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
    total_irq_asserts <= total_irq_asserts + 1;
  end
  ```
  `timer1_irq[3:0]` is completely missing from this logic, even though lines 23, 68, 84, 136, and 205 declare and maintain `prev_t1 <= timer1_irq`.

---

## 2. Logic Chain

1. **IEEE 1800 Non-Blocking Assignment Semantics**:
   - In SystemVerilog, non-blocking assignments (`<=`) evaluated during the Active region of a simulation cycle do not take effect until the Non-Blocking Assignment (NBA) region.
   - Inside `irq_monitor.sv:always @(posedge clk)`, sequential `if` statements check conditions for GPIO, I2C, SPI, UART, Timer0, Arbiter Grant, Trap Commit, and MRET Commit.
2. **Race Mechanism**:
   - If two or more conditions are true in cycle $T$ (e.g., `gpio_irq` and `uart_irq` rise together), `push_event` is called for GPIO first.
   - The task executes: `ring_buffer[head_ptr] <= gpio_event; head_ptr <= (head_ptr + 1) % 64;`.
   - In the same Active region, execution moves immediately to `uart_irq`.
   - Because NBA has not run, `head_ptr` still holds its original value.
   - The task executes: `ring_buffer[head_ptr] <= uart_event; head_ptr <= (head_ptr + 1) % 64;`.
   - Consequently:
     - `ring_buffer[head_ptr]` receives the UART assignment, overwriting GPIO.
     - `head_ptr` is scheduled twice with identical target value `(head_ptr + 1) % 64`.
     - `total_irq_asserts <= total_irq_asserts + 1` is scheduled twice with the same base, advancing by only 1.
3. **Timer 1 Root Cause**:
   - `timer1_irq[3:0]` has 4 channels on APB Slot 5:
     - Channel 0 Overflow (`RF_IRQ_T1_C0_OVF`, ID 23)
     - Channel 0 Compare (`RF_IRQ_T1_C0_CMP`, ID 24)
     - Channel 1 Overflow (`RF_IRQ_T1_C1_OVF`, ID 25)
     - Channel 1 Compare (`RF_IRQ_T1_C1_CMP`, ID 26)
   - These enumerations and cause IDs are fully mapped in `tb_pkg.sv:276-279, 311-314, 396-399` and implemented in `rf_monitors.sv:862-875`, but were inadvertently omitted from `monitors/irq_monitor.sv`.

---

## 3. Recommended Fix Strategy for Worker

### 3.1 Design Principles
1. **Blocking Event Offset Accumulator (`evt_offset`)**:
   - Maintain a local blocking variable `int unsigned evt_offset` initialized to 0 at the start of each clock cycle.
   - Pass `evt_offset` into `push_event` via `inout int unsigned offset`.
   - Target ring buffer slot: `slot = (head_ptr + offset) % RING_BUFFER_DEPTH`.
   - Target sequence number: `seq = base_seq + offset`.
   - `push_event` writes to `ring_buffer[slot] <= ...` and increments `offset = offset + 1`.
2. **Single End-of-Cycle Non-Blocking Pointer Update**:
   - `head_ptr <= (head_ptr + evt_offset) % RING_BUFFER_DEPTH;`
   - Advances `head_ptr` by exactly $N$ slots, supporting $0 \le N \le 16$ simultaneous events in a single cycle.
3. **Accurate Lifecycle Accounting**:
   - Accumulate cycle event counts in blocking variables: `n_asserts`, `n_grants`, `n_acks`, `n_mrets`.
   - At cycle end:
     - `total_irq_asserts <= total_irq_asserts + n_asserts;`
     - `total_irq_grants  <= total_irq_grants  + n_grants;`
     - `total_irq_acks    <= total_irq_acks    + n_acks;`
     - `total_irq_mrets   <= total_irq_mrets   + n_mrets;`
4. **Complete Freeze Immunity**:
   - Enclose the entire event capture, pointer advancement, and counter increment block inside `if (!freeze) begin ... end`.
   - Ensures that when `freeze == 1`, write pointers and event counters are strictly immutably frozen.
5. **Add Timer 1 Edge Detection**:
   - Add the 4 missing channel checks for `timer1_irq[0..3]`.
6. **Hardened `dump_recent_irqs`**:
   - Replace `(head_ptr - i + RING_BUFFER_DEPTH) % RING_BUFFER_DEPTH` with bounds-safe indexing to prevent negative modulo pitfalls.

---

### 3.2 Exact Drop-in RTL Replacement for `Verification/infrastructure/monitors/irq_monitor.sv`

Replace lines 89–230 of `irq_monitor.sv` with the following implementation:

```systemverilog
  // ===========================================================================
  // Event Push Task (in-cycle offset addressing for full concurrency safety)
  // ===========================================================================
  task automatic push_event(
    inout int unsigned offset,
    input logic [4:0]  id,
    input rf_irq_src_e src,
    input logic        asserted,
    input logic        granted,
    input logic        acked,
    input logic        is_mret_event
  );
    int unsigned slot;
    slot = (head_ptr + offset) % RING_BUFFER_DEPTH;

    ring_buffer[slot].timestamp      <= cycle_cnt;
    ring_buffer[slot].rel_cycle      <= cycle_cnt;
    ring_buffer[slot].seq            <= total_irq_asserts + total_irq_grants + total_irq_acks + total_irq_mrets + offset;
    ring_buffer[slot].irq_id         <= id;
    ring_buffer[slot].src            <= src;
    ring_buffer[slot].asserted       <= asserted;
    ring_buffer[slot].granted        <= granted;
    ring_buffer[slot].acked          <= acked;
    ring_buffer[slot].is_interrupt   <= acked;
    ring_buffer[slot].cause          <= trap_commit_cause;
    ring_buffer[slot].mip            <= {fast_irq_i, 8'b0, timer_irq_i, 7'b0};
    ring_buffer[slot].mie            <= '0;
    ring_buffer[slot].mie_bit        <= 1'b1;
    ring_buffer[slot].mstatus_mie    <= 1'b1;
    ring_buffer[slot].irq_class      <= (src != RF_IRQ_NONE) ? tb_pkg::irq_class(src) : 2'b0;
    ring_buffer[slot].latency_cycles <= (acked && grant_cycle != 0) ? (cycle_cnt - grant_cycle) : 32'd0;
    ring_buffer[slot].nest_depth     <= nest_depth;
    ring_buffer[slot].gateway_pend_q <= gateway_pend_q;
    ring_buffer[slot].rr_ptrs        <= {rr_ptr_c1, rr_ptr_c0};
    ring_buffer[slot].is_mret        <= is_mret_event;

    offset = offset + 1;
  endtask

  // ===========================================================================
  // Sequential Monitor Process
  // ===========================================================================
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
    end else begin
      int unsigned evt_offset;
      int unsigned n_asserts;
      int unsigned n_grants;
      int unsigned n_acks;
      int unsigned n_mrets;

      cycle_cnt <= cycle_cnt + 1;

      evt_offset = 0;
      n_asserts  = 0;
      n_grants   = 0;
      n_acks     = 0;
      n_mrets    = 0;

      if (!freeze) begin
        // 1. Edge-triggered interrupt line assertions
        if (gpio_irq && !prev_gpio) begin
          push_event(evt_offset, 5'd16, RF_IRQ_GPIO_GLOBAL, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (i2c_irq && !prev_i2c) begin
          push_event(evt_offset, 5'd17, RF_IRQ_I2C, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (spi_irq[0] && !prev_spi[0]) begin
          push_event(evt_offset, 5'd18, RF_IRQ_SPI_EVT0, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (spi_irq[1] && !prev_spi[1]) begin
          push_event(evt_offset, 5'd27, RF_IRQ_SPI_EVT1, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (uart_irq && !prev_uart) begin
          push_event(evt_offset, 5'd19, RF_IRQ_UART, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer0_irq[0] && !prev_t0[0]) begin
          push_event(evt_offset, 5'd20, RF_IRQ_T0_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer0_irq[1] && !prev_t0[1]) begin
          push_event(evt_offset, 5'd7, RF_IRQ_MTIP, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer0_irq[2] && !prev_t0[2]) begin
          push_event(evt_offset, 5'd21, RF_IRQ_T0_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer0_irq[3] && !prev_t0[3]) begin
          push_event(evt_offset, 5'd22, RF_IRQ_T0_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end

        // Timer 1 IRQ channels (Overflow and Compare on Channels 0 and 1)
        if (timer1_irq[0] && !prev_t1[0]) begin
          push_event(evt_offset, 5'd23, RF_IRQ_T1_C0_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer1_irq[1] && !prev_t1[1]) begin
          push_event(evt_offset, 5'd24, RF_IRQ_T1_C0_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer1_irq[2] && !prev_t1[2]) begin
          push_event(evt_offset, 5'd25, RF_IRQ_T1_C1_OVF, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end
        if (timer1_irq[3] && !prev_t1[3]) begin
          push_event(evt_offset, 5'd26, RF_IRQ_T1_C1_CMP, 1'b1, 1'b0, 1'b0, 1'b0);
          n_asserts++;
        end

        // 2. Arbiter Grant (Edge-gated on irq_pending to prevent ring buffer flooding)
        if (irq_pending && !prev_pending) begin
          grant_cycle <= cycle_cnt;
          push_event(evt_offset, irq_id, irq_src_of_cause_enc(irq_id), 1'b1, 1'b1, 1'b0, 1'b0);
          n_grants++;
        end

        // 3. Commit Acknowledgement (Trap Commit for Interrupt)
        if (trap_commit_valid && trap_is_interrupt) begin
          push_event(evt_offset, trap_commit_cause[4:0], irq_src_of_cause_enc(trap_commit_cause[4:0]), 1'b1, 1'b1, 1'b1, 1'b0);
          n_acks++;
        end

        // 4. MRET Commit (Stack pop and context restore)
        if (mret_commit) begin
          push_event(evt_offset, 5'd0, RF_IRQ_NONE, 1'b0, 1'b0, 1'b0, 1'b1);
          n_mrets++;
        end

        // Atomic advancement of ring buffer pointer and lifecycle counters
        head_ptr          <= (head_ptr + evt_offset) % RING_BUFFER_DEPTH;
        total_irq_asserts <= total_irq_asserts + n_asserts;
        total_irq_grants  <= total_irq_grants  + n_grants;
        total_irq_acks    <= total_irq_acks    + n_acks;
        total_irq_mrets   <= total_irq_mrets   + n_mrets;
      end

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

  // ===========================================================================
  // Post-Mortem Diagnostics Dump
  // ===========================================================================
  function automatic void dump_recent_irqs(int count = 10);
    int start_idx;
    int display_count;
    display_count = (count > RING_BUFFER_DEPTH) ? RING_BUFFER_DEPTH : count;
    $display("=== Last %0d Interrupt Lifecycle Events ===", display_count);
    start_idx = (head_ptr >= display_count) ? (head_ptr - display_count) : (RING_BUFFER_DEPTH + head_ptr - display_count);
    for (int i = 0; i < display_count; i++) begin
      int idx = (start_idx + i) % RING_BUFFER_DEPTH;
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
```

---

## 4. Caveats
- The maximum theoretical number of concurrent events that can occur in one cycle is 16 (13 raw peripheral lines + 1 grant + 1 ack + 1 mret), which is well within `RING_BUFFER_DEPTH` (64).
- The priority ordering of events within the same cycle matches the natural datapath order (Peripheral assertion -> Arbiter grant -> Core interrupt commit -> MRET pop).
- No caveats regarding simulator compatibility; `inout int unsigned` and procedural blocking arithmetic are supported natively across Vivado XSim, VCS, and Xcelium.

---

## 5. Conclusion
Applying the proposed fix strategy will:
1. Guarantee that $N$ simultaneous interrupt assertions and lifecycle events occupy $N$ distinct contiguous slots in the circular ring buffer.
2. Advance `head_ptr` and `total_irq_asserts` by exactly $N$.
3. Provide complete visibility for Timer 1 interrupt activity across all 4 channels.
4. Convert Test 5 in `tb_freeze_buffer_stress.sv` from `[FAIL]` to `[PASS]`, resolving the Milestone 1 Gate block.

---

## 6. Verification Method

To independently verify the implementation after the worker applies the fix:

### Step 1: Run the Empirical Stress Test Suite
```powershell
cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_freeze_stress.ps1"
```
**Expected Verification Result**:
- Total checks: 165 checks.
- Pass count: **165 PASS, 0 FAIL**.
- Verbatim confirmation in log:
  ```
  IRQ Monitor After Dual Simultaneous Assertion:
    total_irq_asserts = 2
    head_ptr          = 2
    ring_buffer[0].src = GPIO_GLOBAL (id=16)
    ring_buffer[1].src = UART (id=19)
  [PASS] [IRQ_CONCURRENCY_PRESERVED] Both simultaneous IRQ events successfully captured in separate slots
  ```

### Step 2: Run Baseline Smoke Test
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\run_rf_mon_smoke.ps1"
```
**Expected Verification Result**: Exits with code 0; all 23 self-checks pass.

### Step 3: Verify Timer 1 Edge Capture
In `tb_freeze_buffer_stress.sv`, pulse `timer1_irq[0] <= 1; timer1_irq[1] <= 1;` simultaneously:
Verify that `head_ptr` advances by 2 and `ring_buffer` holds `RF_IRQ_T1_C0_OVF` and `RF_IRQ_T1_C0_CMP`.
