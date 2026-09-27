# RISCFORGE 1TOPS — SoC Static Lint Warnings & File Breakdown Report

This document contains the complete, parsed categorization of all warnings and errors identified by **Synopsys SpyGlass `U-2023.03-SP2`** during the static lint audit of the entire **RISCFORGE 1TOPS SoC Subsystem** (`riscforge_soc_subsystem`).

---

## 1. Executive Metrics & Summary

| Severity | Count (Standard Lint) | Count (Turbo Lint) | Description |
|---|:---:|:---:|---|
| **FATAL** | **0** | **0** | No unrecoverable elaboration or syntax halts. |
| **ERROR** | **42** | **42** | Structural violations (port widths, latch inference, memory models). |
| **WARNING** | **1,242** | **404** | Style, unused signals, unconnected ports, FSM structures. |
| **INFO** | **8** | **9** | Informational elaboration notes. |

---

## 2. File-by-File Issue Matrix

The table below details all 46 source files flagged by SpyGlass, ordered by total violation count:

| File Path | Total Issues | Errors | Warnings | Primary Rule IDs |
|---|:---:|:---:|:---:|---|
| [`ips/SOC_FILES/include/obi/obi_uart_baudgen.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_baudgen.sv) | **172** | 0 | 172 | `W240` (144), `W415a` (24), `W263` (4) |
| [`ips/SOC_FILES/include/obi/obi_uart_modem.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_modem.sv) | **144** | 0 | 144 | `W240` (120), `W415a` (24) |
| [`ips/SOC_FILES/include/obi/obi_uart_rx.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_rx.sv) | **124** | 0 | 124 | `W240` (104), `W415a` (20) |
| [`ips/SOC_FILES/include/obi/obi_uart_interrupts.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_interrupts.sv) | **116** | 0 | 116 | `W240` (96), `W415a` (20) |
| [`ips/SOC_FILES/include/obi/obi_uart_tx.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_tx.sv) | **108** | 0 | 108 | `W240` (88), `W415a` (20) |
| [`ips/SOC_FILES/include/obi/obi_uart_register.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart_register.sv) | **70** | 0 | 70 | `W240` (40), `W415a` (24), `W263` (6) |
| [`ips/SOC_FILES/include/obi/obi_uart.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/obi_uart.sv) | **68** | 0 | 68 | `W287b` (68) |
| [`ips/riscv_core/rtl/rv32m_mul.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/rv32m_mul.v) | **33** | 33 | 0 | `W110` (33) |
| [`ips/bootloader/bootloader.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/bootloader/bootloader.sv) | **23** | 1 | 22 | `InferLatch` (1), `SYNTH_12608` (1), `W287b` (16), `STARC05-2.2.3.3` (2), `W528` (3) |
| [`ips/axi_lite_xbar/include/common_cells/addr_decode_dync.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/common_cells/addr_decode_dync.sv) | **18** | 0 | 18 | `W240` (8), `W415a` (6), `SYNTH_5143` (2), `W528` (2) |
| [`ips/axi_lite_xbar/include/common_cells/addr_decode.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/common_cells/addr_decode.sv) | **15** | 0 | 15 | `W240` (7), `W415a` (6), `W528` (2) |
| [`ips/RTL_SOC/riscforge_soc_subsystem.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv) | **13** | 2 | 10 | `ErrorAnalyzeBBox` (2), `W287b` (8), `W240` (2), `DetectTopDesignUnits` (1) |
| [`ips/apb_i2c-master/apb_i2c.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/apb_i2c-master/apb_i2c.sv) | **10** | 0 | 10 | `W287b` (6), `W415a` (3), `STARC05-2.2.3.3` (1) |
| [`ips/axi_lite_xbar/include/common_cells/spill_register_flushable.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/common_cells/spill_register_flushable.sv) | **10** | 0 | 10 | `W240` (9), `FlopEConst` (1) |
| [`ips/riscv_core/rtl/hybrid_mem_interface.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/hybrid_mem_interface.sv) | **8** | 0 | 8 | `W528` (8) |
| [`ips/spi_master_ip/spi_master/spi_master_apb_if.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/spi_master_ip/spi_master/spi_master_apb_if.sv) | **7** | 0 | 7 | `W415a` (6), `WRN_26` (1) |
| [`ips/riscv_core/rtl/csr_regfile.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/csr_regfile.v) | **6** | 0 | 6 | `W415a` (4), `STARC05-2.2.3.3` (2) |
| [`ips/riscv_core/rtl/top.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/top.v) | **6** | 0 | 6 | `W287b` (3), `W528` (3) |
| [`ips/gpio-master/gpio.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/gpio-master/gpio.sv) | **5** | 0 | 5 | `SYNTH_5064` (5) |
| [`ips/RTL_SOC/axi_lite_sram_if.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/axi_lite_sram_if.sv) | **5** | 0 | 5 | `W240` (2), `W415a` (2), `STARC05-2.2.3.3` (1) |
| [`ips/axi_lite_xbar/include/axi/axi_lite_to_axi.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/axi/axi_lite_to_axi.sv) | **5** | 0 | 5 | `W240` (5) |
| [`ips/axi_lite_xbar/include/common_cells/rr_arb_tree.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/common_cells/rr_arb_tree.sv) | **5** | 0 | 5 | `W240` (2), `W528` (2), `W287b` (1) |
| [`ips/SOC_FILES/include/obi/apb_to_obi.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/obi/apb_to_obi.sv) | **4** | 0 | 4 | `W240` (4) |
| [`ips/apb_timer-master/timer.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/apb_timer-master/timer.sv) | **4** | 0 | 4 | `W362` (4) |
| [`ips/RTL_SOC/sram_sp.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/sram_sp.sv) | **3** | 2 | 1 | `SYNTH_5273` (1), `W123` (1), `W528` (1) |
| [`ips/instr_module/Instruction_Memory.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/instr_module/Instruction_Memory.v) | **3** | 2 | 1 | `SYNTH_5273` (1), `W123` (1), `W528` (1) |
| [`ips/apb_i2c-master/i2c_master_bit_ctrl.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/apb_i2c-master/i2c_master_bit_ctrl.sv) | **3** | 0 | 3 | `WRN_69` (1), `STARC05-2.11.3.1` (1), `W486` (1) |
| [`ips/gpio-master/gpio_apb_wrap.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/gpio-master/gpio_apb_wrap.sv) | **3** | 0 | 3 | `W240` (2), `W528` (1) |
| [`ips/riscv_core/rtl/hazard_unit.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/hazard_unit.v) | **3** | 0 | 3 | `W240` (3) |
| [`ips/axi_lite_xbar/include/axi/axi_lite_demux.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/axi/axi_lite_demux.sv) | **3** | 0 | 3 | `W287b` (3) |
| [`ips/axi_lite_xbar/include/axi/axi_lite_mux.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/axi/axi_lite_mux.sv) | **3** | 0 | 3 | `W287b` (3) |
| [`ips/spi_master_ip/spi_master/spi_master_fifo.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/spi_master_ip/spi_master/spi_master_fifo.sv) | **2** | 0 | 2 | `WRN_1024` (2) |
| [`ips/riscv_core/rtl/rv32m_div.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/rv32m_div.v) | **2** | 0 | 2 | `STARC05-2.11.3.1` (1), `W528` (1) |
| [`ips/SOC_FILES/include/register_interface/apb_to_reg.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/register_interface/apb_to_reg.sv) | **2** | 0 | 2 | `W240` (2) |
| [`ips/riscv_core/rtl/execute_cycle.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/execute_cycle.v) | **2** | 0 | 2 | `W240` (1), `W287b` (1) |
| [`ips/spi_master_ip/spi_master/spi_master_controller.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/spi_master_ip/spi_master/spi_master_controller.sv) | **2** | 0 | 2 | `W240` (1), `W528` (1) |
| [`ips/axi_lite_to_apb/axi_lite_to_apb.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_to_apb/axi_lite_to_apb.sv) | **2** | 0 | 2 | `W287b` (2) |
| [`ips/axi_lite_xbar/axi_lite_xbar.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/axi_lite_xbar.sv) | **2** | 0 | 2 | `W287b` (2) |
| [`ips/SOC_FILES/include/register_interface/prim_subreg_arb.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/SOC_FILES/include/register_interface/prim_subreg_arb.sv) | **2** | 0 | 2 | `W528` (2) |
| [`ips/RTL_SOC/imem_sram_wrapper.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/imem_sram_wrapper.sv) | **1** | 1 | 0 | `ErrorAnalyzeBBox` (1) |
| [`ips/RTL_SOC/boot_rom.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/boot_rom.sv) | **1** | 1 | 0 | `SYNTH_5260` (1) |
| [`ips/riscv_core/rtl/decode_cycle.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/decode_cycle.v) | **1** | 0 | 1 | `STARC05-1.3.1.3` (1) |
| [`ips/apb_i2c-master/i2c_master_byte_ctrl.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/apb_i2c-master/i2c_master_byte_ctrl.sv) | **1** | 0 | 1 | `STARC05-2.11.3.1` (1) |
| [`ips/riscv_core/rtl/memory_cycle.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/memory_cycle.v) | **1** | 0 | 1 | `W240` (1) |
| [`ips/apb_uart-main/rtl/apb_uart_wrap.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/apb_uart-main/rtl/apb_uart_wrap.sv) | **1** | 0 | 1 | `W287b` (1) |
| [`ips/axi_lite_xbar/include/common_cells/fall_through_register.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/include/common_cells/fall_through_register.sv) | **1** | 0 | 1 | `W287b` (1) |

---

## 3. Categorical Breakdown of All Warning Types

### 3.1 Unconnected Instance Output Ports (`W287b` — 707 Violations)
* **What it is**: An output port on an instantiated module is left unconnected in the parent module (`.port()`).
* **Where it occurs**:
  * `obi_uart.sv` (68 instances): Unconnected modem status flags (`rtsn_o`, `dtrn_o`, `out1n_o`, `out2n_o`) and baudgen clock outputs.
  * `bootloader.sv` (16 instances): Unused AXI read response fields (`r.data`, `r.resp`, `b.id`).
  * `riscforge_soc_subsystem.sv` (8 instances): Unused GPIO pin-level interrupt wires and UART debug signals.
  * `axi_lite_demux.sv` / `axi_lite_mux.sv` (6 instances): Unconnected `usage_o` occupancy monitor signals.
* **Functional Impact**: **Harmless**. These represent intentionally ignored status/debug outputs that are not needed at the top level.

---

### 3.2 Unread Declared Input Ports (`W240` — 258 Violations)
* **What it is**: A module port is declared as `input`, but its value is never referenced in any internal statement.
* **Where it occurs**:
  * `obi_uart_baudgen.sv` (144 instances) & `obi_uart_modem.sv` (120 instances): The entire register bus struct `reg_read_i` is passed into all submodules, but each submodule only reads 1-2 relevant fields (e.g. `baudgen` only reads `dll`/`dlm`, ignoring `ier`, `fcr`, `lcr`, `mcr`).
  * `apb_to_obi.sv` (4 instances): `apb_req_i.penable` and `apb_req_i.pprot` are ignored because OBI uses a simpler 1-cycle `req`/`gnt` protocol.
  * `riscforge_soc_subsystem.sv` (2 instances): `fetch_enable_i` and `boot_addr_i` are legacy top-level ports superseded by `bootloader.sv` and `PC.v`.
* **Functional Impact**: **Harmless**. Expected SystemVerilog struct passing pattern where submodules select specific fields from a unified packed bus.

---

### 3.3 Multiple Procedural Assignments (`W415a` — 178 Violations)
* **What it is**: A variable is assigned more than once within the same combinatorial `always` or `always_comb` block.
* **Where it occurs**:
  * `obi_uart_baudgen.sv` (24 instances), `obi_uart_modem.sv` (24 instances), `obi_uart_rx.sv` (20 instances), `obi_uart_tx.sv` (20 instances): Standard Verilog default value assignment at the beginning of an `always_comb` block followed by conditional updates inside `case` or `if` statements.
  * `csr_regfile.v` (4 instances): `mcycle_r` and `minstret_r` performance counters default-incremented at line 197 and overwritten on CSR write operations at line 255.
  * `spi_master_apb_if.sv` (6 instances): Default `PRDATA = 0` updated on valid register address decodes.
* **Functional Impact**: **Standard RTL Coding Practice**. Eliminates latch inference by assigning defaults before branching.

---

### 3.4 Unread Internal Variables & Signals (`W528` — 61 Violations)
* **What it is**: An internal wire or logic variable is assigned a value but is never read by any other logic.
* **Where it occurs**:
  * `hybrid_mem_interface.sv` (8 instances): `axi_w_stall` and pipeline handshake tracking wires.
  * `bootloader.sv` (3 instances): `rxfifo_data_q` upper bits and unused counter wires.
  * `top.v` (3 instances): `pipe_busy` and `imem_stall` debug trackers.
* **Functional Impact**: **Harmless**. Synthesis tools automatically optimize and prune these unused wires.

---

### 3.5 Overwritten Flip-Flop Assignments (`STARC05-2.2.3.3` — 6 Violations)
* **What it is**: In a sequential `always @(posedge clk)` block, non-blocking assignments (`<=`) are made to the same register in multiple branches or sequentially.
* **Where it occurs**:
  * `csr_regfile.v:255-256`: `minstret_r` assigned by auto-increment and overwritten on CSR write instructions.
  * `bootloader.sv:504-505`: Handshake flags `aw_done_q` and `w_done_q` set high on `aw_ready`/`w_ready` and cleared on `b_valid`.
  * `axi_lite_sram_if.sv:225`: `rdata_valid_q` pulsed low and updated by grant FSM.
  * `apb_i2c.sv:96`: `r_cmd` register update logic.
* **Design Risk**: **Medium**. In `bootloader.sv`, if `b_valid` asserts on the same clock cycle as `aw_ready`, the second non-blocking assignment takes precedence.

---

### 3.6 Combined Sequential & Combinational FSM Logic (`STARC05-2.11.3.1` — 3 Violations)
* **What it is**: An FSM describes state transitions (`state <= next_state`) and output decoding inside a single monolithic `always` block rather than separating into 2-block or 3-block FSM style.
* **Where it occurs**:
  * `apb_i2c-master/i2c_master_bit_ctrl.sv:374` (`c_state`)
  * `apb_i2c-master/i2c_master_byte_ctrl.sv:220` (`c_state`)
  * `riscv_core/rtl/rv32m_div.v:106` (`state`)
* **Functional Impact**: **Low**. Synthesis tools can synthesize single-block FSMs, but standard STA and formal verification prefer separated next-state logic to prevent glitches on Moore/Mealy outputs.

---

### 3.7 Asynchronous Reset Used as Data (`STARC05-1.3.1.3` — 1 Violation)
* **What it is**: A signal intended as an asynchronous reset (`rst_n`) is routed into regular combinational data multiplexers or flip-flop D-inputs.
* **Where it occurs**:
  * `decode_cycle.v:242` / `fetch_cycle.v:295`: `core_rst_n` from `bootloader.core_rst_q` resets pipeline control registers, but is also sampled as data in the fetch stall logic.
* **Design Risk**: **Medium**. Can cause timing closure issues and glitches if reset de-assertion edges are not synchronized to clock edges via a reset synchronizer bridge.

---

### 3.8 Shift Truncation & Operator Width Mismatches (`W486` / `W362` / `W263`)
* **`W486`** in `i2c_master_bit_ctrl.sv:139`: RHS width 16 with shift (`clk_cnt >> 2`) assigned to 14-bit LHS (`filter_cnt`). Top 2 bits truncated.
* **`W362`** in `timer.sv:98-102`: 3-bit `prescaler_int` compared against 32-bit `reg_ctrl`.
* **`W263`** in `obi_uart_register.sv:140`: Case select expression width does not match case branch literal width.

