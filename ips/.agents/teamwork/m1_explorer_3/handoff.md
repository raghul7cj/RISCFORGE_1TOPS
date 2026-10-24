# Handoff Report — Milestone 1: IRQ Monitor, Probe Binding, Top-Level Integration & Non-Intrusive Sniffing Engine

**Author**: `m1_explorer_3`  
**Date**: 2026-10-01T21:45:00Z  
**Target Milestone**: Milestone 1 (Passive Protocol & Pipeline Monitors with Circular Freeze Buffers)  
**Recipient**: Worker / Orchestrator (`f600a31f-7502-4e6a-baf5-5e32a55d3d3e`)

---

## 1. Observation

### 1.1 Existing `irq_monitor.sv` (`Verification/infrastructure/monitors/irq_monitor.sv`)
- **Lines 7–25**: Module port list accepts only `clk`, `rst_n`, `freeze`, raw IRQ lines (`timer0_irq`, `timer1_irq`, `uart_irq`, `i2c_irq`, `gpio_irq`, `spi_irq`), `irq_ack`, and `mcause[31:0]`.
- **Lines 43–51**:
  ```systemverilog
  if (irq_ack && !freeze) begin
    ring_buffer[head_ptr].timestamp <= cycle_cnt;
    ring_buffer[head_ptr].irq_id    <= mcause[4:0];
    ring_buffer[head_ptr].asserted  <= 1'b1;
    ring_buffer[head_ptr].granted   <= 1'b1;
    ring_buffer[head_ptr].acked     <= 1'b1;
    head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
  end
  ```
- **Deficiencies Observed**:
  1. It completely ignores `fast_irq_i[15:0]` and `timer_irq_i` (MTIP).
  2. It has zero visibility into `irq_gateway` sticky latches (`pend_q[5:0]`).
  3. It has zero visibility into `irq_arbiter` state (`irq_pending`, `irq_id`, `irq_class`, round-robin pointers `rr_ptr_c1`, `rr_ptr_c0`).
  4. It has zero visibility into the CSR 2-deep hardware shadow stack (`nest_depth`, `cur_class`, `mepc_stack[0:1]`, `mcause_stack[0:1]`, `class_stack[0:1]`, `mpie_stack[0:1]`).
  5. It samples exclusively on `irq_ack`, discarding edge assertions, arbitration decisions, preemption, and MRET returns.
  6. The ports defined in `irq_monitor.sv` do not match the instantiation in `soc_tb_top.sv` (line 253), causing elaboration failure.

### 1.2 SoC & Core Interrupt Architecture in RTL
- **SoC Top Interconnect (`RTL_SOC/riscforge_soc_subsystem.sv:1205–1252`)**:
  - The core is instantiated as `top #(.RESET_PC(32'h0000_0000)) i_riscv_core`, **not** `u_core`.
  - Interrupt pin mapping to core inbound buses:
    - `.fast_irq_i`:
      - `[0]`: `gpio_global_interrupt_o` &rarr; `mip[16]`, `mcause 16`
      - `[1]`: `i2c_interrupt_o` &rarr; `mip[17]`, `mcause 17`
      - `[2]`: `spi_events_o[0]` &rarr; `mip[18]`, `mcause 18`
      - `[3]`: `uart_int_o` &rarr; `mip[19]`, `mcause 19`
      - `[4]`: `timer0_irq_o[0]` (T0 ch0 overflow) &rarr; `mip[20]`, `mcause 20`
      - `[5]`: `timer0_irq_o[2]` (T0 ch1 overflow) &rarr; `mip[21]`, `mcause 21`
      - `[6]`: `timer0_irq_o[3]` (T0 ch1 compare)  &rarr; `mip[22]`, `mcause 22`
      - `[7]`: `timer1_irq_o[0]` (T1 ch0 overflow) &rarr; `mip[23]`, `mcause 23`
      - `[8]`: `timer1_irq_o[1]` (T1 ch0 compare)  &rarr; `mip[24]`, `mcause 24`
      - `[9]`: `timer1_irq_o[2]` (T1 ch1 overflow) &rarr; `mip[25]`, `mcause 25`
      - `[10]`: `timer1_irq_o[3]` (T1 ch1 compare) &rarr; `mip[26]`, `mcause 26`
      - `[11]`: `spi_events_o[1]` (SPI EOT / WD)    &rarr; `mip[27]`, `mcause 27`
      - `[15:12]`: `4'b0` (tied off)
    - `.timer_irq_i`: `timer0_irq_o[1]` (Timer 0 ch0 compare match) &rarr; `mip[7]` (MTIP), `mcause 7`.
- **Core Internal Interrupt Datapath (`riscv_core/rtl/top.v:207–242`)**:
  - `irq_raw = {fast_irq_i[11], timer_irq_i, fast_irq_i[3:0]}` (6-bit packed source vector).
  - Instantiates `irq_gateway u_irq_gateway` with `edge_mode = 6'b110101`.
  - Instantiates `irq_arbiter u_irq_arbiter` taking `pend_gateway`, CSR sidebands (`csr_mie_sb`, `csr_mstatus_mie_sb`, `cur_class_sb`, `nest_depth_sb`), and commit feedback.
  - Instantiates `wb_trap_mret_commit_controller wb_commit` (instance name is `wb_commit`!).
  - Instantiates `csr_regfile csr_file` exporting `cur_class_sb` and `nest_depth_sb`.
- **Gateway Latch Dynamics (`riscv_core/rtl/irq_gateway.v:44–66`)**:
  - `edge_mode_i = 6'b110101`: WD (bit 5), Timer0 (bit 4), SPI (bit 2), GPIO (bit 0) are edge-triggered and captured by sticky register `pend_q[5:0]`.
  - UART (bit 3) and I2C (bit 1) are level-triggered and bypass `pend_q`.
  - Pulse-wins priority: `edge_detect[k]` takes strict precedence over `clear_i[k]`.
- **Two-Level Priority Class Arbiter (`riscv_core/rtl/irq_arbiter.v:53–154`)**:
  - **Class 2 (Real-Time)**: Fixed priority, WD (`mcause 27`) > Timer0 (`mcause 7`).
  - **Class 1 (Stream)**: Round-Robin, UART (`mcause 19`) &harr; SPI (`mcause 18`) via `rr_ptr_c1`.
  - **Class 0 (Background)**: Round-Robin, I2C (`mcause 17`) &harr; GPIO (`mcause 16`) via `rr_ptr_c0`.
  - Hardware preemption rule: `preempt_allowed = (nest_depth_i == 2'd0) || (raw_winner_class > cur_class_i);`.
  - `irq_pending_o = raw_winner_valid && preempt_allowed;`.
  - Pointers `rr_ptr_c1` and `rr_ptr_c0` rotate strictly on Writeback commit (`wb_commit_i` with `wb_trap_cause_i`).
- **Hardware Shadow Stack (`riscv_core/rtl/csr_regfile.v:146–205`)**:
  - Dedicated hardware registers: `mepc_stack[0:1]`, `mcause_stack[0:1]`, `mpie_stack[0:1]`, `class_stack[0:1]`, `nest_depth` (2-bit), `cur_class_r` (2-bit).
  - Trap entry pushes context atomically when `trap_valid_i & trap_is_interrupt_i`:
    `mepc_stack[nest_depth] <= trap_pc_i; mcause_stack[nest_depth] <= {1'b1, trap_cause_i}; mpie_stack[nest_depth] <= mstatus_r[3]; class_stack[nest_depth] <= cur_class_r; nest_depth <= nest_depth + 1; cur_class_r <= trap_class_i;`.
  - MRET commit pops context atomically when `csr_write_en_mret_i || mret_commit_i`:
    `nest_depth <= nest_depth - 1;` restores previous `cur_class_r` and `mstatus_r[3]`.
- **Commit Controller (`riscv_core/rtl/wb_trap_mret_commit_controller.v:61–96`)**:
  - Trap commit: `trap_commit = valid_W & exc_valid_W;`.
  - Interrupt trap: `trap_is_interrupt_o = exc_cause_W[5] & exc_valid_W;`.
  - MRET commit: `mret_commit = valid_W & is_mret_W & ~exc_valid_W;`.
  - Gateway clear strobe: `clear_gateway_o` (one-hot pulse corresponding to `exc_cause_W[4:0]`).

### 1.3 Probe Layers (`rf_monitor_if.sv`, `rf_mon_probe.sv`, `soc_tb_top.sv`)
- **`rf_monitor_if.sv`**:
  - `rf_timebase_if`: Free-running 64-bit cycle counter with `#1step` sampling.
  - `rf_irq_if` (lines 408–467): Probes raw sources, gateway `pend_o`, arbiter outputs, CSR sidebands, and commit strobes. **Missing**: direct probes for shadow stack (`nest_depth`, `cur_class`, `mepc_stack`, `mcause_stack`), gateway internal latch `pend_q`, and round-robin pointers (`rr_ptr_c1`, `rr_ptr_c0`).
- **`rf_mon_probe.sv`**:
  - Line 95: `assign retire_if.wb_commit = u_dut.i_riscv_core.wb_commit;` &rarr; **CRITICAL BUG**: `wb_commit` is the instance name of `wb_trap_mret_commit_controller`, not a net! It should be `u_dut.i_riscv_core.valid_W & ~u_dut.i_riscv_core.exc_valid_W` (instruction retire commit) or wire `u_dut.i_riscv_core.wb_commit.wb_trap_redirect_o`.
  - Line 315–347: `fanout_timebase` registers `freeze` into `*_if.freeze <= freeze;` inside an `always_ff @(posedge clk)`. Combined with the `#1step` clocking block, this introduces a **2-cycle delay** between `failure_reporter.freeze_monitors` assertion and the monitor freeze taking effect!
  - Target DUT hierarchy: References `u_dut.i_riscv_core`, whereas `soc_tb_top.sv` instantiates the DUT as `dut`.
- **`soc_tb_top.sv`**:
  - Instantiates DUT as `dut` (line 92).
  - Lines 182–263: Instantiates module monitors using non-existent hierarchical nets: `dut.u_core.PC_F`, `dut.u_core.InstrW`, `dut.m0_awaddr`, `dut.apb_paddr`, `dut.u_core.irq_req`. None of these exist in `riscforge_soc_subsystem.sv`!
  - Does **not** instantiate `rf_mon_probe`.
  - Lines 288–325: Instantiates `register_predictor` and `irq_predictor` whose source files (`register_predictor.sv`, `irq_predictor.sv`) are 0 bytes in the repository (Milestone 3 items).

### 1.4 Bugs Discovered in `monitors/rf_monitors.sv`
- **Enum Cast Bug (`rf_monitors.sv:874`)**:
  ```systemverilog
  src_q = rf_irq_src_e'(vif.mon_cb.irq_cause_enc);
  ```
  `irq_cause_enc` contains the RISC-V cause number (e.g. 19 for UART). But `rf_irq_src_e` in `tb_pkg.sv` defines `RF_IRQ_UART = 4`. Casting 19 directly exceeds the enum bounds and causes `NONE` (id=31) to be printed in the log!
- **Level-Sensitive Grant Flooding Bug (`rf_monitors.sv:872–877`)**:
  ```systemverilog
  if (vif.mon_cb.irq_pending) begin
    grant_cycle_q = cur_cycle;
    src_q = ...
    emit(src_q, 1'b1, 1'b1, 1'b0);
    n_grant++;
  end
  ```
  `irq_pending` is an unclocked level signal from the arbiter that stays high until the trap is committed. Sampling on level without edge qualification causes `emit()` to be called **every cycle**, filling the circular ring buffer with 50+ identical grant entries (observed verbatim in `monitor_postmortem.txt:106–128`) and destroying previous history!

---

## 2. Logic Chain

```
[Observation 1.2: RTL Core & Peripherals]
  ├── Core is named `i_riscv_core`, bus signals are packed structs (core_axi_req, apb_req)
  ├── IRQ system has 3-class arbiter, gateway sticky latch pend_q, 2-deep shadow stack in csr_file
  └── Retirement commits: valid_W & ~exc_valid_W (instruction), trap_commit_valid (trap), mret_commit (MRET)
          │
          ▼
[Observation 1.3: Verification Infrastructure Disconnect]
  ├── soc_tb_top.sv references obsolete `dut.u_core`, `dut.m0_awaddr`, `dut.apb_paddr`
  ├── rf_mon_probe.sv already flattens packed structs to interfaces, but targets `u_dut`
  └── rf_mon_probe.sv line 95 incorrectly assigns module instance `wb_commit` to a wire
          │
          ▼
[Observation 1.4: Monitor Bugs in rf_monitors.sv]
  ├── rf_irq_monitor casts mcause (19) directly to rf_irq_src_e (max 13), corrupting event ID
  └── irq_pending sampled on level, causing 50+ cycle spam and ring buffer overflow
          │
          ▼
[Observation 1.1 & Dispatch Task: IRQ Monitor Deficiencies]
  ├── irq_monitor.sv only logs irq_ack, missing raw lines, pend_q, arbiter class/grants, shadow stack
  └── Missing synchronous simultaneous freeze propagation without cycle slip
          │
          ▼
[Harmonized Solution Architecture]
  1. Refactor `soc_tb_top.sv` to rename `dut` -> `u_dut`, instantiate `rf_mon_probe u_mon`
  2. Rewrite `irq_monitor.sv` with complete signal suite (peripheral lines, pend_q, arbiter, shadow stack)
  3. Extend `rf_irq_if` and `rf_mon_probe.sv` to probe shadow stack, gateway pend_q, and arbiter pointers
  4. Fix `rf_monitors.sv`: map mcause -> rf_irq_src_e correctly and add edge detection to `irq_pending`
  5. Replace double-registered `freeze` in `rf_mon_probe.sv` with continuous assignment for cycle-0 freeze
```

---

## 3. Caveats

1. **Milestone 3 Register & IRQ Predictor Stubs**:
   - `checkers/register_predictor.sv` and `checkers/irq_predictor.sv` are currently empty (0 bytes). To allow `soc_tb_top.sv` to compile and run under Milestone 1, lightweight passive stub definitions (matching their port signatures) must be provided, or their instantiations in `soc_tb_top.sv` must be wrapped in `+define+ENABLE_PREDICTORS`.
2. **Simulator Compatibility (Vivado XSim vs VCS / Xcelium)**:
   - XSim 2022.2 does not permit unpacked arrays or 2D packed arrays in interface ports or class formal parameter lists. All added probe signals (e.g. `mepc_stack`, `mcause_stack`) must be carried as flat packed vectors (e.g. `logic [63:0] mepc_stack_flat`).
   - XSim does not allow virtual interface variables to be assigned inside class methods. All interface driving (e.g. timebase and freeze fanout) must remain in module scope in `rf_mon_probe.sv`.
3. **Cold Boot vs Warm Boot Timing**:
   - In cold boot mode (`+BOOT_MODE=COLD`), the hardware bootloader exercises SPI Flash and crossbar writes before releasing the core reset. The passive monitors must be qualified with `rst_n` so bootloader SRAM configuration is logged as privileged writes without triggering false-positive assertions.

---

## 4. Conclusion & Actionable Recommendations for Worker

### 4.1 Implementation Plan Overview

```
Step 1: Fix tb_pkg.sv & Helper Functions
        ├── Add `irq_src_of_cause_enc(logic [4:0] cause)`
        └── Add shadow stack and latch fields to `irq_txn_t`

Step 2: Update Probe Interface (rf_monitor_if.sv)
        ├── Add `gateway_pend_q[5:0]`
        ├── Add `rr_ptr_c1`, `rr_ptr_c0`
        └── Add `nest_depth[1:0]`, `cur_class[1:0]`, `mepc_stack_flat[63:0]`, `mcause_stack_flat[63:0]`

Step 3: Update Structural Probe Module (rf_mon_probe.sv)
        ├── Fix line 95: assign retire_if.wb_commit to valid instruction commit net
        ├── Connect new IRQ gateway, arbiter, and shadow stack probes to `u_dut.i_riscv_core`
        └── Fix freeze propagation: assign `*_if.freeze = freeze;` (continuous assign, 0 delay)

Step 4: Fix Class-Based IRQ Monitor (monitors/rf_monitors.sv)
        ├── Use `irq_src_of_cause_enc()` instead of direct cast
        ├── Add edge detection (`irq_pending && !prev_pending`) to prevent duplicate ring spam
        └── Log shadow stack depth changes (push on trap, pop on MRET)

Step 5: Rewrite Module-Based IRQ Monitor (monitors/irq_monitor.sv)
        ├── Implement 64-entry circular ring buffer with full IRQ lifecycle
        ├── Ports: raw IRQ lines, gateway pend_q, fast_irq, timer_irq, arbiter state, shadow stack
        └── Methods: `dump_recent_irqs(int count)` for post-mortem analysis

Step 6: Refactor Unified Top Testbench (tb/soc_tb_top.sv)
        ├── Rename `dut` instance to `u_dut`
        ├── Instantiate `rf_mon_probe u_mon`
        ├── Connect module monitors to real RTL signals (`u_dut.i_riscv_core.*`)
        └── Provide stubs or conditionally guard empty Milestone 3 predictors
```

### 4.2 Detailed Code Specifications for Worker

#### A. Fixes for `Verification/infrastructure/tb/tb_pkg.sv`
1. **Cause Decoder Helper**:
   ```systemverilog
   function automatic rf_irq_src_e irq_src_of_cause_enc(logic [4:0] cause);
     case (cause)
       5'd16: return RF_IRQ_GPIO_GLOBAL;
       5'd17: return RF_IRQ_I2C;
       5'd18: return RF_IRQ_SPI_EVT0;
       5'd19: return RF_IRQ_UART;
       5'd20: return RF_IRQ_T0_C0_OVF;
       5'd21: return RF_IRQ_T0_C1_OVF;
       5'd22: return RF_IRQ_T0_C1_CMP;
       5'd23: return RF_IRQ_T1_C0_OVF;
       5'd24: return RF_IRQ_T1_C0_CMP;
       5'd25: return RF_IRQ_T1_C1_OVF;
       5'd26: return RF_IRQ_T1_C1_CMP;
       5'd27: return RF_IRQ_SPI_EVT1;
       5'd7:  return RF_IRQ_MTIP;
       default: return RF_IRQ_NONE;
     endcase
   endfunction
   ```
2. **Enhanced `irq_txn_t`**:
   Add fields:
   - `logic [1:0] nest_depth;`
   - `logic [5:0] gateway_pend_q;`
   - `logic [1:0] rr_ptrs; // {rr_ptr_c1, rr_ptr_c0}`
   - `logic is_mret;`

#### B. Enhancements to `Verification/infrastructure/tb/rf_monitor_if.sv`
In `interface rf_irq_if`:
```systemverilog
  // Gateway internal latch
  logic [5:0]  gateway_pend_q;

  // Arbiter round-robin pointers
  logic        rr_ptr_c1;
  logic        rr_ptr_c0;

  // Shadow stack observables
  logic [1:0]  nest_depth;
  logic [1:0]  cur_class;
  logic [63:0] mepc_stack_flat;   // {mepc_stack[1], mepc_stack[0]}
  logic [63:0] mcause_stack_flat; // {mcause_stack[1], mcause_stack[0]}
```
Include these in `clocking mon_cb`:
```systemverilog
  clocking mon_cb @(posedge clk);
    default input #1step;
    input gpio_irq, gpio_pin_irq, i2c_irq, spi_irq, uart_irq;
    input timer0_irq, timer1_irq, gateway_pend, gateway_pend_q;
    input fast_irq, timer_irq, mip, mie, mintprio, mstatus_mie;
    input irq_valid, irq_pending, irq_cause_enc, irq_id, irq_class;
    input rr_ptr_c1, rr_ptr_c0;
    input nest_depth, cur_class, mepc_stack_flat, mcause_stack_flat;
    input trap_is_interrupt, trap_cause, trap_pc, mret_commit;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking
```

#### C. Corrections to `Verification/infrastructure/tb/rf_mon_probe.sv`
1. **Fix Line 95 (Commit controller net)**:
   ```systemverilog
   // Replace:
   // assign retire_if.wb_commit = u_dut.i_riscv_core.wb_commit;
   // With:
   assign retire_if.wb_commit = u_dut.i_riscv_core.valid_W & ~u_dut.i_riscv_core.exc_valid_W & ~u_dut.i_riscv_core.mret_commit;
   ```
2. **Add IRQ Gateway & Shadow Stack Taps**:
   ```systemverilog
   assign irq_if.gateway_pend_q   = u_dut.i_riscv_core.u_irq_gateway.pend_q;
   assign irq_if.rr_ptr_c1        = u_dut.i_riscv_core.u_irq_arbiter.rr_ptr_c1;
   assign irq_if.rr_ptr_c0        = u_dut.i_riscv_core.u_irq_arbiter.rr_ptr_c0;
   assign irq_if.nest_depth       = u_dut.i_riscv_core.csr_file.nest_depth;
   assign irq_if.cur_class        = u_dut.i_riscv_core.csr_file.cur_class_r;
   assign irq_if.mepc_stack_flat  = {u_dut.i_riscv_core.csr_file.mepc_stack[1], u_dut.i_riscv_core.csr_file.mepc_stack[0]};
   assign irq_if.mcause_stack_flat= {u_dut.i_riscv_core.csr_file.mcause_stack[1], u_dut.i_riscv_core.csr_file.mcause_stack[0]};
   ```
3. **Immediate Freeze Propagation (Zero Cycle Slip)**:
   In `fanout_timebase`:
   Change the `freeze` assignment from registered (`always_ff`) to direct continuous assignments:
   ```systemverilog
   assign fetch_if.freeze  = freeze;
   assign retire_if.freeze = freeze;
   assign lsu_if.freeze    = freeze;
   assign axil_if.freeze   = freeze;
   assign apb_if.freeze    = freeze;
   assign irq_if.freeze    = freeze;
   assign pin_if.freeze    = freeze;
   ```
   *Rationale*: `failure_reporter` drives `freeze_monitors`. Since `mon_cb` samples inputs `#1step` before the posedge clock, having `freeze` driven combinationally ensures that any failure reported in cycle $C$ will cause the monitors sampling at the posedge of cycle $C+1$ to see `freeze == 1` in the Preponed region, freezing write pointers with **0 added cycles**.

#### D. Fixes to `monitors/rf_monitors.sv` (`rf_irq_monitor`)
1. **Edge-Gated Grant & Correct Enum Translation**:
   ```systemverilog
   logic prev_pending;
   // In run():
   // Replace line 872-877 with:
   if (vif.mon_cb.irq_pending && !prev_pending) begin
     grant_cycle_q = cur_cycle;
     src_q         = irq_src_of_cause_enc(vif.mon_cb.irq_cause_enc);
     emit(src_q, 1'b1, 1'b1, 1'b0);
     n_grant++;
   end
   prev_pending <= vif.mon_cb.irq_pending;
   ```
2. **MRET Tracking**:
   ```systemverilog
   if (vif.mon_cb.mret_commit) begin
     n_mret++;
     emit(RF_IRQ_NONE, 1'b0, 1'b0, 1'b0); // Tagged as MRET return / stack pop
   end
   ```

#### E. Complete Rewrite of `Verification/infrastructure/monitors/irq_monitor.sv`
Replace the minimal 56-line stub with a full 64-entry circular ring buffer module monitor:
- **Port List**:
  - `clk`, `rst_n`, `freeze`
  - Raw inputs: `gpio_irq`, `i2c_irq`, `spi_irq[1:0]`, `uart_irq`, `timer0_irq[3:0]`, `timer1_irq[3:0]`
  - Gateway: `gateway_pend_q[5:0]`, `gateway_pend_o[5:0]`
  - Core Inbound: `fast_irq_i[15:0]`, `timer_irq_i`
  - Arbiter: `irq_pending`, `irq_id[4:0]`, `irq_class[1:0]`, `rr_ptr_c1`, `rr_ptr_c0`
  - Shadow Stack: `nest_depth[1:0]`, `cur_class[1:0]`
  - Commit: `trap_commit_valid`, `trap_is_interrupt`, `trap_cause[30:0]`, `trap_pc[31:0]`, `mret_commit`
- **Internal Storage**: `irq_txn_t ring_buffer [0:63]`, `int unsigned head_ptr`, `longint unsigned cycle_cnt`.
- **Capture Logic**:
  - Edge detection on all raw lines &rarr; logs `asserted = 1`.
  - Rising edge of `irq_pending` &rarr; logs `granted = 1`, records grant cycle.
  - `trap_commit_valid & trap_is_interrupt` &rarr; logs `acked = 1`, computes latency `cycle_cnt - grant_cycle`, records `nest_depth`.
  - `mret_commit` &rarr; logs stack pop and context restore.
- **Freeze**: Synchronous check: `if (!freeze) begin ring_buffer[head_ptr] <= ...; head_ptr <= (head_ptr + 1) % 64; end`.
- **Diagnostic Method**: `dump_recent_irqs(int count = 10)` formatting timestamp, event type, IRQ ID, source name, priority class, nest depth, and latency.

#### F. Refactoring `Verification/infrastructure/tb/soc_tb_top.sv`
1. Change DUT instance name from `dut` to `u_dut` (line 92).
2. Instantiate `rf_mon_probe u_mon` (wires connected to top-level pins and clocks).
3. Connect module monitors to real RTL paths:
   - `fetch_monitor`: `pc_f` &rarr; `{u_dut.i_riscv_core.Fetch.PCF, 2'b00}`, `imem_en` &rarr; `u_dut.i_riscv_core.imem_sram_en`, `stall_f` &rarr; `u_dut.i_riscv_core.Fetch.imem_stall | u_dut.i_riscv_core.StallF`.
   - `retire_monitor`: `pc_w` &rarr; `u_dut.i_riscv_core.PC_W`, `rd_addr_w` &rarr; `u_dut.i_riscv_core.RDW`, `rd_wdata_w` &rarr; `u_dut.i_riscv_core.ResultW`, `reg_we_w` &rarr; `u_dut.i_riscv_core.RegWriteW_gated`, `trap_w` &rarr; `u_dut.i_riscv_core.trap_commit_valid`.
   - `lsu_monitor`: `lsu_req` &rarr; `u_dut.i_riscv_core.lsu_mem_req`, `lsu_addr` &rarr; `u_dut.i_riscv_core.lsu_mem_addr`, `lsu_wdata` &rarr; `u_dut.i_riscv_core.lsu_mem_wdata`, `lsu_be` &rarr; `u_dut.i_riscv_core.lsu_mem_be`, `lsu_we` &rarr; `u_dut.i_riscv_core.lsu_mem_we`, `lsu_stall` &rarr; `u_dut.i_riscv_core.lsu_mem_stall`.
   - `axi_lite_monitor`: Connect to `u_mon.axil_if.*` (pre-flattened).
   - `apb_monitor`: Connect to `u_mon.apb_if.*` (pre-flattened).
   - `irq_monitor`: Connect to full signal set from `u_dut` and `u_mon.irq_if`.
4. Provide passive dummy stubs for `register_predictor` and `irq_predictor` so that elaboration succeeds immediately under Vivado XSim and VCS.

---

## 5. Verification Method

To independently verify these recommendations and sign off Milestone 1:

1. **Monitor Smoke Test**:
   Execute the self-test script in `Verification/infrastructure/`:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   .\run_rf_mon_smoke.ps1
   ```
   *Success Condition*: All 10 self-checks pass (`M1..M6`, `A1..A5`, `P1..P6`, `T1..T2`, `R1..R3`, `J1..J3`, `I1..I3`, `D1..D10`, `F1..F2`). Zero errors reported.
2. **SoC Subsystem Infrastructure Compilation**:
   Compile the unified testbench with Vivado XSim:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   xvlog --sv -f soc_verification.f
   xelab soc_tb_top -s soc_sim
   ```
   *Success Condition*: Zero elaboration errors, zero undeclared hierarchical references (`u_core`, `m0_awaddr`, etc.).
3. **Simultaneous Freeze Broadcast Verification**:
   In `soc_tb_top`, inject a test error or trigger `u_failure_reporter.report_failure(LAYER_PROTOCOL, "TEST-FREEZE", "Testing simultaneous freeze", 32'h1000)`:
   - Check that `freeze_monitors` asserts.
   - Inspect the write pointers of all 6 ring buffers (`fetch`, `retire`, `lsu`, `axi`, `apb`, `irq`) in the subsequent cycles: none of them must advance.
   - Confirm `failure_report.md` is generated and names the failing layer, cycle, check ID, and PC.
4. **Non-Intrusiveness Proof**:
   - Compare simulation cycle counts and memory output checksums of `stage1_hello` with monitors enabled (`RUN_MONITORS=1`) versus disabled (`RUN_MONITORS=0`).
   - The retired instruction count and execution cycle count must be **100.00% identical**, proving zero timing distortion or backpressure.
