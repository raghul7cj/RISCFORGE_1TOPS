# RISCFORGE 1TOPS — Boot Mechanism, Combinational Feedback & Latch Analysis

This document provides a detailed architectural audit of the **RISCFORGE 1TOPS SoC Subsystem Boot Mechanism**, analyzing the Bootloader FSM, APB/AXI interconnect multiplexers, reset sequencing, the **inferred latch on `warm_boot_q`**, and potential **combinational feedback paths**.

---

## 1. Boot Mechanism Architecture Overview

The boot subsystem coordinates initialization between external SPI Flash, internal SRAMs (ISRAM & DSRAM), the RV32IM processor core, and SoC bus interconnects:

```
                      +-------------------------------------------------------------+
                      |                 riscforge_soc_subsystem.sv                  |
                      |                                                             |
                      |  +-------------------------------------------------------+  |
                      |  | Bootloader Module (ips/bootloader/bootloader.sv)      |  |
                      |  |                                                       |  |
                      |  |   - Dual-Reset Controller (hard_rst_ni, soft_rst_ni)  |  |
                      |  |   - 16-State Master Boot FSM (S_RESET -> S_DONE)      |  |
                      |  |   - AXI-Lite Master Port (Crossbar SLV[1])            |  |
                      |  |   - APB Slave Port (Bridge Slot 4)                    |  |
                      |  |   - APB Master Port (to apb_spi_master)               |  |
                      |  |   - Output Resets: core_rst_n, periph_rst_n, spi_rst_n|  |
                      |  +-------------------------------------------------------+  |
                      |         |                 |                     |           |
                      |         | AXI-Lite        | APB Master          | Reset     |
                      |         v                 v                     v           |
                      |    [AXI Crossbar]   [apb_spi_master]     [Core & Peripherals|
                      |         |                 |                                 |
                      |         v                 v                                 |
                      |    [ISRAM/DSRAM]    (SPI Flash Pins)                        |
                      +-------------------------------------------------------------+
```

### Key Subsystem Components
1. **Bootloader Module (`bootloader.sv`)**: Manages the cold-boot SRAM zeroing loop, SPI Flash DMA extraction, and warm-boot fast bypass.
2. **BootROM Stub (`boot_rom.sv`)**: 16-word read-only memory holding the hardware reset trampoline (`lui sp, 0x28000; jal x0, 0x10000`).
3. **Instruction Fetch Demux (`instr_fetch_demux.sv`)**: Routes CPU fetch addresses (`0x0000_0000` &rarr; BootROM, `0x0001_0000` &rarr; ISRAM).
4. **SRAM Arbiters (`sram_mux.sv`)**: 2:1 priority arbiters granting Port 0 (Core Fetch / LSU) priority over Port 1 (AXI Bootloader writes).

---

## 2. Inferred Latch Analysis: `warm_boot_q` (`InferLatch` & `SYNTH_12608`)

### 2.1 The Issue in RTL Source Code
In [`ips/bootloader/bootloader.sv:447-493`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/bootloader/bootloader.sv#L447-L493), the sequential block is written as:

```systemverilog
// ips/bootloader/bootloader.sv:447
always_ff @(posedge clk_i or negedge hard_rst_ni or negedge soft_rst_ni) begin
  if (!hard_rst_ni) begin
    // ===== Cold Boot Reset =====
    state_q     <= S_RESET;
    warm_boot_q <= 1'b0;          // Cleared on hard reset
    // ... other resets ...
  end else if (!soft_rst_ni) begin
    // ===== Warm Boot Reset =====
    state_q     <= S_RESET;
    warm_boot_q <= 1'b1;          // Set on soft reset
    // ... other resets ...
  end else begin
    // ===== Normal Clocked Operation =====
    state_q <= state_d;
    
    // *** CRITICAL OMISSION ***
    // warm_boot_q is NOT assigned or updated anywhere in the clocked branch!
    // ...
  end
end
```

### 2.2 Root Cause & Hardware Mechanism
* **Why SpyGlass Flags `InferLatch`**:
  An `always_ff` block with two asynchronous resets (`hard_rst_ni` and `soft_rst_ni`) must define register behavior for the active clock edge (`posedge clk_i`).
  Because `warm_boot_q` has **no assignment** in the `else` (clocked) branch, standard synthesis tools cannot synthesize `warm_boot_q` as a standard D-type flip-flop with reset.
  Instead, the synthesis tool infers an **asynchronous set-reset latch (SR latch)** that holds its value based on the previous pulse of `hard_rst_ni` vs. `soft_rst_ni`.
* **Associated SpyGlass Messages**:
  * `[526] InferLatch Error: Latch inferred for signal 'warm_boot_q' in module 'bootloader' (Line 476)`
  * `[4FE] SYNTH_12608 Warning: The logic of the always block mismatches with the type of Always Block (which should be "always_latch") due to latch instance warm_boot_q_reg (Line 447)`

### 2.3 Synthesis & Timing Risks
1. **Static Timing Analysis (STA) Ambiguity**: Latches create transparent timing paths that complicate setup and hold time closure on asynchronous reset pins.
2. **Glitch Sensitivity**: Any glitch or bounce on `hard_rst_ni` or `soft_rst_ni` immediately flips `warm_boot_q` without clock synchronization.

### 2.4 Recommended RTL Fix
To make `warm_boot_q` a fully synchronous D-flip-flop with standard single reset:
```systemverilog
// Clean Solution: Single asynchronous master reset (sys_rst_n) and synchronous warm boot latching
always_ff @(posedge clk_i or negedge sys_rst_n) begin
  if (!sys_rst_n) begin
    state_q     <= S_RESET;
    warm_boot_q <= ~soft_rst_ni; // Sample reset pin state synchronously
  end else begin
    state_q     <= state_d;
    warm_boot_q <= warm_boot_q;  // Explicit register hold or clear after S_DONE
  end
end
```

---

## 3. APB Master / Slave Multiplexer Combinational Path Analysis

### 3.1 APB Passthrough Architecture
In [`bootloader.sv:375-397`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/bootloader/bootloader.sv#L375-L397), the bootloader implements a 2:1 APB mux to arbitrate access to `apb_spi_master`:

```systemverilog
always_comb begin
  if (boot_active) begin
    // ---- Boot mode: FSM drives APB master to SPI master ----
    apb_mst_req_o         = '0;
    apb_mst_req_o.paddr   = apb_boot_paddr;
    apb_mst_req_o.psel    = 1'b1;
    apb_mst_req_o.penable = apb_phase_q;
    apb_mst_req_o.pwrite  = apb_boot_pwrite;
    apb_mst_req_o.pwdata  = apb_boot_pwdata;
    apb_mst_req_o.pstrb   = '1;
    
    apb_slv_resp_o.pready  = 1'b1;
    apb_slv_resp_o.prdata  = '0;
    apb_slv_resp_o.pslverr = 1'b0;
  end else begin
    // ---- Runtime mode: transparent passthrough ----
    apb_mst_req_o  = apb_slv_req_i;   // Upstream bridge -> SPI master
    apb_slv_resp_o = apb_mst_resp_i;  // SPI master -> Upstream bridge
  end
end
```

### 3.2 Long Combinatorial Timing Chain (No Combinational Loop)
During runtime mode (`!boot_active`), requests and responses pass combinatorially through `bootloader.sv`:
1. Core LSU initiates MMIO read to SPI Master (`0x4000_4000`).
2. `hybrid_mem_interface.sv` issues AXI-Lite read request (`m_axi_req_o.ar_valid`).
3. `axi_lite_xbar.sv` routes transaction to Master Port 2 (`xbar_mst_req[2]`).
4. `axi_lite_to_apb.sv` translates AXI request to APB request (`apb_req[4]`).
5. `bootloader.sv` forwards `apb_req[4]` &rarr; `spi_apb_req` &rarr; `apb_spi_master.sv`.
6. `apb_spi_master.sv` asserts `spi_pready` only when FIFO data is ready.
7. `spi_pready` propagates back &rarr; `bootloader` &rarr; `axi_lite_to_apb` &rarr; AXI `r_valid` &rarr; `hybrid_mem_interface` &rarr; Core `lsu_mem_stall`.

> **Timing Assessment**: While this path spans 5 hierarchy levels, it is **strictly feed-forward (acyclic)** and does not form a combinational loop. SpyGlass verified this with **0 CombLoop violations** in `CombLoopReport_temp.rpt`.

---

## 4. AXI-Lite Handshake Overwrite Warning (`STARC05-2.2.3.3`)

### 4.1 The Issue in `bootloader.sv:500-507`
```systemverilog
// ips/bootloader/bootloader.sv:500
if (is_axi_write_state(state_q)) begin
  if (axi_req_o.aw_valid && axi_resp_i.aw_ready) aw_done_q <= 1'b1; // Line 501
  if (axi_req_o.w_valid  && axi_resp_i.w_ready)  w_done_q  <= 1'b1; // Line 502
  if (axi_resp_i.b_valid) begin                                      // Line 503
    aw_done_q <= 1'b0;                                               // Line 504 (OVERWRITE)
    w_done_q  <= 1'b0;                                               // Line 505 (OVERWRITE)
  end
end
```

### 4.2 Potential Race Condition
* If a slave AXI device responds with single-cycle zero-wait `b_valid = 1` on the exact same clock edge as `aw_ready = 1`, both lines 501 and 504 execute in parallel.
* Under IEEE 1800 SystemVerilog semantics, the last non-blocking assignment (`<= 1'b0`) in source order wins.
* **Why it works in simulation**: `axi_lite_sram_if.sv` requires at least 1 clock cycle to process writes and return `b_valid`, so simultaneous `aw_ready` and `b_valid` never occurs in practice.
* **Fix**: Use mutually exclusive priority nesting:
  ```systemverilog
  if (axi_resp_i.b_valid) begin
    aw_done_q <= 1'b0;
    w_done_q  <= 1'b0;
  end else begin
    if (axi_req_o.aw_valid && axi_resp_i.aw_ready) aw_done_q <= 1'b1;
    if (axi_req_o.w_valid  && axi_resp_i.w_ready)  w_done_q  <= 1'b1;
  end
  ```

---

## 5. Instruction Fetch Demux Reset Domain Crossing (`STARC05-1.3.1.3`)

### 5.1 The Issue in `instr_fetch_demux.sv` and `decode_cycle.v`
* **Root Cause**:
  * `core_rst_n` is generated internally by `bootloader.core_rst_q`.
  * `core_rst_n` acts as the asynchronous active-low reset for the entire CPU core (`top.v` &rarr; `decode_cycle.v`).
  * In `decode_cycle.v:242` and `fetch_cycle.v:295`, `core_rst_n` is also used as a combinational data condition to clear pipeline register values during stalls.
* **SpyGlass Message**:
  * `[527] STARC05-1.3.1.3 Warning: Asynchronous reset signal 'riscforge_soc_subsystem.i_bootloader.core_rst_q' used as non-reset/synchronous-reset at instance 'riscforge_soc_subsystem.i_riscv_core.Fetch.InstrF_reg_reg[0].D'`
* **Impact**: Asynchronous resets should be routed exclusively to flip-flop reset pins (`CLR`/`PRE`). Mixing reset nets into logic trees can introduce race conditions and glitches during reset transitions.

---

## 6. Summary Matrix of Boot Mechanism Audit Findings

| Component | Signal / Mechanism | Severity | Issue Classification | Production Recommendation |
|---|---|:---:|---|---|
| `bootloader.sv:476` | `warm_boot_q` | **ERROR** | `InferLatch` / `SYNTH_12608` | Assign `warm_boot_q` in clocked branch of `always_ff` or convert to single-reset D-FF. |
| `bootloader.sv:504` | `aw_done_q`, `w_done_q` | **WARNING** | `STARC05-2.2.3.3` | Use `if (b_valid) ... else` to prevent simultaneous assignment overwrite. |
| `bootloader.sv:375` | APB Passthrough Mux | **INFO** | Long combinational path | 0 combinational loops; meets timing for 100 MHz target. |
| `instr_fetch_demux.sv` | `core_rst_n` routing | **WARNING** | `STARC05-1.3.1.3` | Isolate asynchronous reset net from combinational data paths. |
| `boot_rom.sv:36` | `INIT_FILE` string | **ERROR** | `SYNTH_5260` | Replace SV `string` parameter with sized `reg [255:0]` or pre-synthesized ROM case table. |
| `sram_sp.sv:36` | 32 KB behavioral array | **ERROR** | `SYNTH_5273` / `W123` | Bind to Foundry compiled SRAM macro blackbox during physical ASIC synthesis. |

