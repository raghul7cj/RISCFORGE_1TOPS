# RISCFORGE 1TOPS — Cadence JasperGold Superlint Audit Report

**Tool:** Cadence JasperGold Superlint 2025.06 FCS 64-bit  
**Top-Level Module:** `riscforge_soc_subsystem`  
**Host:** `172.16.33.51`  
**Synthesis Gate Count:** 40,923 Gates | **Flip-Flop Count:** 8,813 Registers  
**Black Boxes:** 0 (100% Hierarchy Elaborated)  

---

## 1. Executive Summary & Violation Metrics

| Rule Domain | Category | Errors | Warnings | Info | Total | Key Violations Flagged |
|:---|:---|:---:|:---:|:---:|:---:|:---|
| **STRUCTURAL** | Reset Tree Architecture | **1** | **7** | 0 | 8 | Combinational reset generation (`RST_IS_DCMB`), Unregistered top IOs (`MOD_NO_IPRG`) |
| **CODINGSTYLE** | Port Connectivity & Reads | 0 | **17** | **3** | 20 | Unconnected instance ports (`OTP_UC_INST`), Output port internal reads (`OTP_NR_READ`), Unused inputs (`INP_NO_LOAD`), Redefined macros (`MAC_NR_DMUL`) |
| **FILEFORMAT** | Naming & Filenames | 0 | **1** | 0 | 1 | Interface name mismatch (`FIL_MS_DUNM`) |
| **DFT_FUNCTIONAL** | Testability / Timing | 0 | **19** | 0 | 19 | Unregistered primary outputs (`OTP_NO_RGTM`) |
| **DESIGN_BUILD** | Analyze & Elaboration | 0 | **618** | 0 | 618 | Bitwidth truncation & port width mismatch (`VERI-1209`, `VERI-1330`, `VERI-2418`) |
| **TOTAL** | | **1** | **662** | **3** | **666** | **Zero Black Boxes, 1 Error, Clean Elaboration** |

---

## 2. Structural Violations Deep-Dive

### 2.1. Combinational Reset Net Driving Flops (`RST_IS_DCMB`) [ERROR]
- **Rule Tag:** `RST_IS_DCMB`
- **Severity:** `Error`
- **Location:** `../RTL_SOC/riscforge_soc_subsystem.sv:469`
- **Violation Message:** `Net 'sys_rst_n' generated from combinational logic is driving reset of one or more flip-flops [Flip-flop: i_isram_axi_if.state_q[0]]`
- **Impacted Instances (185 Flip-Flop Registers):**
  - **ISRAM AXI-Lite Interface (`i_isram_axi_if`):** `state_q`, `rdata_q`, `wstrb_q`, `reject_q`, `wdata_q`, `rdata_valid_q`, `addr_q`
  - **DSRAM AXI-Lite Interface (`i_dsram_axi_if`):** `state_q`, `rdata_q`, `reject_q`, `wstrb_q`, `wdata_q`, `addr_q`, `rdata_valid_q`
  - **ISRAM / DSRAM Arbiter Muxes (`i_isram_mux`, `i_dsram_mux`):** `port0_granted_q`, `port1_granted_q`
  - **AXI-Lite to APB Bridge (`i_axi_lite_to_apb`):** `apb_state_q`, FIFOs `i_fifo.write_pointer_q`, `read_pointer_q`, `mem_q`, `status_cnt_q`, Round-Robin Arbiter `rr_q`, `lock_q`, `req_q`
  - **AXI-Lite Crossbar (`i_axi_lite_xbar`):** Demux FIFOs (`gen_slv_port_demux[*].i_axi_lite_demux`), Spill registers (`spill_register_flushable_i.gen_spill_reg.a_data_q`, `b_data_q`, `a_full_q`, `b_full_q`), Error slaves (`i_axi_err_slv`), Mux arbiters (`i_aw_arbiter`, `i_ar_arbiter`)
- **Root Cause & Architectural Context:**
  In `riscforge_soc_subsystem.sv`, the system reset signal is generated combinationally:
  ```systemverilog
  assign sys_rst_n = hard_rst_ni & soft_rst_ni & ~boot_sw_rst_req;
  ```
  While logically sound for combining hardware reset, software reset, and warm boot restart requests, ASIC/FPGA static lint and synthesis engines classify any logic gate (AND/OR) on the asynchronous reset distribution network as a potential glitch hazard.
- **Recommended Remedy (Design Phase):**
  Instantiate a dedicated Reset Synchronizer module (e.g., standard 2-FF synchronizer with asynchronous assert and synchronous de-assert) clocked by `clk_i` to generate a glitch-free `sys_rst_n_sync` before driving the system flop reset pins.

---

### 2.2. Unregistered Top-Level Inputs (`MOD_NO_IPRG`) [WARNING]
- **Rule Tag:** `MOD_NO_IPRG`
- **Severity:** `Warning`
- **Locations:** `../RTL_SOC/riscforge_soc_subsystem.sv` lines 251, 252, 290, 325-328
- **Flagged Signals:**
  - `hard_rst_ni` (Line 251)
  - `soft_rst_ni` (Line 252)
  - `uart_sin_i` (Line 290)
  - `spi_sdi0_i` (Line 325)
  - `spi_sdi1_i` (Line 326)
  - `spi_sdi2_i` (Line 327)
  - `spi_sdi3_i` (Line 328)
- **Explanation:**
  JasperGold flags primary chip inputs that directly feed internal combinational logic without an immediate boundary input register. For asynchronous inputs (`uart_sin_i`, `spi_sdi*_i`), multi-stage CDC synchronizers or boundary flip-flops are recommended to avoid setup/hold timing degradation at the chip I/O pad ring.

---

## 3. Coding Style Violations Deep-Dive

### 3.1. Output Port Read Internally (`OTP_NR_READ`) [WARNING]
- **Rule Tag:** `OTP_NR_READ`
- **Severity:** `Warning`
- **Location:** `../RTL_SOC/riscforge_soc_subsystem.sv`
- **Flagged Signals:**
  - `boot_done_o` (Line 708)
  - `uart_int_o` (Line 1131)
  - `spi_events_o` (Line 1132)
  - `i2c_interrupt_o` (Line 1133)
  - `gpio_global_interrupt_o` (Line 1134)
  - `timer0_irq_o` (Line 1135)
- **Root Cause:**
  In Verilog-2001 / SystemVerilog, when an `output` port is read as an RHS operand or used as an input to internal submodules (such as routing peripheral interrupt outputs into the core CLIC or interrupt combiner), older tools flag `OTP_NR_READ`. In modern SystemVerilog `output logic` or `output wire`, this is valid syntax, but clean coding convention often defines an internal wire (e.g. `uart_int_s`) and connects `assign uart_int_o = uart_int_s;`.

---

### 3.2. Unconnected Instance Outputs (`OTP_UC_INST`) [WARNING]
- **Rule Tag:** `OTP_UC_INST`
- **Severity:** `Warning`
- **Locations & Submodules:**
  1. `i_instr_fetch_demux` (`../RTL_SOC/riscforge_soc_subsystem.sv:670, 673, 681`):
     - `core_gnt_o`, `core_rvalid_o`: Ignored in unified instruction memory fetch demux.
     - `isram_addr_o[1:0]`: Sub-word address bits not required by word-addressed SRAM.
  2. `i_dsram_mux` (`../RTL_SOC/riscforge_soc_subsystem.sv:820, 826`):
     - `port0_gnt_o`, `port0_rvalid_o`: Unused response handshakes for direct core data access.
  3. `i_axi_lite_to_apb` (`../RTL_SOC/riscforge_soc_subsystem.sv:902`):
     - `apb_req_o[1].pprot`: Protection attributes unused by peripheral slaves.
  4. `i_riscv_core` (`../RTL_SOC/riscforge_soc_subsystem.sv:1106`):
     - `PCSrcE1`: Top-level debug branch status port left open at SoC boundary.
  5. `i_core_data_if` (`../RTL_SOC/riscforge_soc_subsystem.sv:1173`):
     - `sram_addr[29:13]`: Upper address bits beyond 8K-word (32 KB) local DSRAM boundary.
  6. `i_bootloader` (`../RTL_SOC/riscforge_soc_subsystem.sv:1203`):
     - `apb_mst_req_o.pprot`: APB master protection flags unconnected.

---

### 3.3. Unloaded Primary Inputs (`INP_NO_LOAD`) [WARNING]
- **Rule Tag:** `INP_NO_LOAD`
- **Severity:** `Warning`
- **Location:** `../RTL_SOC/riscforge_soc_subsystem.sv:258, 259`
- **Signals:** `fetch_enable_i`, `boot_addr_i`
- **Context:** Top-level debug/bootstrap hook pins defined in the top module interface for future test modes, but currently tied or unused internally.

---

### 3.4. Duplicate Macro Definitions (`MAC_NR_DMUL`) [INFO]
- **Rule Tag:** `MAC_NR_DMUL`
- **Severity:** `Info`
- **Files:** `spi_master_fifo.sv:11`, `spi_master_apb_if.sv:11`, `apb_spi_master.sv:11`
- **Message:** Macro `` `define log2(x) `` defined with identical body across three separate SPI master RTL files.

---

## 4. DFT / Boundary Timing Violations (`OTP_NO_RGTM`) [WARNING]

- **Rule Tag:** `OTP_NO_RGTM` (Total: 19 Violations)
- **Flagged Pins:**
  - `boot_done_o` (Line 264)
  - `gpio_global_interrupt_o` (Line 309), `gpio_pin_level_interrupts_o` (Line 310), `gpio_tx_en_o` (Line 307)
  - `i2c_scl_o` (Line 270), `i2c_sda_o` (Line 273)
  - `spi_csn0_o` .. `spi_csn3_o` (Lines 316-319), `spi_sdo0_o` (Line 321), `spi_events_o` (Line 329)
  - `timer0_irq_o` (Line 280), `timer1_irq_o` (Line 285)
  - `uart_dtrn_o`, `uart_out1n_o`, `uart_out2n_o`, `uart_rtsn_o`, `uart_sout_o` (Lines 291-296)
- **Explanation:**
  JasperGold DFT/Superlint rule flags top-level outputs directly driven by combinational multiplexing or internal logic rather than dedicated boundary output flip-flops. While normal for peripheral pad multiplexing, registering boundary outputs ensures predictable external pad-to-pad IO timing budgets during physical place & route.

---

## 5. File Format Violations (`FIL_MS_DUNM`) [WARNING]

- **Rule Tag:** `FIL_MS_DUNM`
- **Severity:** `Warning`
- **Location:** `../SOC_FILES/include/register_interface/reg_intf.sv:22`
- **Message:** Interface name `REG_BUS` differs from containing file name `reg_intf.sv`. Standard Cadence design style recommends matching module/interface names with source filenames for clean file management.

