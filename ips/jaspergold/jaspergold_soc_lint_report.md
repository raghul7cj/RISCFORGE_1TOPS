# RISCFORGE 1TOPS — Cadence JasperGold Superlint Audit Report

**Tool:** Cadence JasperGold Superlint 2025.06 FCS 64-bit  
**Top-Level Module:** `riscforge_soc_subsystem`  
**Host:** `172.16.33.51`  
**Synthesis Gate Count:** 40,923 Gates | **Flip-Flop Count:** 8,813 Registers  
**Black Boxes:** 0 (100% Hierarchy Elaborated)  

---

## 1. Executive Summary & Audit Metrics

Static RTL linting and structural checks were performed on the complete **RISCFORGE 1TOPS SoC Subsystem** using **Cadence JasperGold Superlint (2025.06 FCS 64-bit)** on the dedicated Cadence Server. The design synthesized cleanly with **zero blackboxes** across all 113 modules and 6 SystemVerilog packages.

- **Structural Errors:** 1 (`RST_IS_DCMB` — Combinational `sys_rst_n` driving 185 flip-flops)
- **Lint Warnings:** 25 (`OTP_UC_INST`, `OTP_NR_READ`, `MOD_NO_IPRG`, `INP_NO_LOAD`)
- **DFT / IO Warnings:** 19 (`OTP_NO_RGTM` — Unregistered primary outputs)
- **Info Messages:** 3 (`MAC_NR_DMUL` — Redefined `log2` macro in SPI master)
- **Elaboration Warnings:** 618 (`VERI-1209`, `VERI-1330` — Bitwidth truncations & port mismatches)

---

## 2. Key Findings & Cross-Vendor Comparison

| Analysis Domain | Synopsys SpyGlass (U-2023.03) | Cadence JasperGold (2025.06) | Cross-Tool Alignment |
|:---|:---|:---|:---|
| **Reset Tree Logic** | `W362` (Comb reset expression on `sys_rst_n`) | `RST_IS_DCMB` [Error] (Comb reset driving 185 flops) | **100% Agreement**: Both engines identify combinational reset logic as an ASIC timing hazard. |
| **Bootloader FSM Latches** | `InferLatch` & `SYNTH_12608` (Inferred latch on `warm_boot_q`) | Evaluated during FSM check extraction (0 unclocked latches in gate synthesis) | SpyGlass checks RTL branch completeness; JasperGold synthesizes gated flop tree. |
| **Bitwidth Truncation** | `W110` (33 errors in `rv32m_mul.v` & AXI bridge) | `VERI-1209` & `VERI-1330` (Elab warnings on port & expression size) | **100% Agreement**: Literal shifts and CSA carry-out net width mismatches flagged by both engines. |
| **Port Connectivity** | `W287b` (Unconnected output ports) | `OTP_UC_INST` (9 unconnected instance outputs) | **100% Agreement**: Identifies unread signals (e.g. `PCSrcE1`, `pprot`, sub-word addresses). |
| **Primary IO Boundaries** | `W240` (Unused inputs: `boot_addr_i`, `fetch_enable_i`) | `INP_NO_LOAD` (2 unused inputs), `MOD_NO_IPRG` (7 unreg inputs), `OTP_NO_RGTM` (19 unreg outputs) | **Complementary**: JasperGold provides thorough DFT boundary registration checking. |

---

## 3. Structural Reset Tree Hazard Deep-Dive

In [`riscforge_soc_subsystem.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv#L469), the reset net `sys_rst_n` is computed combinationally:
```systemverilog
assign sys_rst_n = hard_rst_ni & soft_rst_ni & ~boot_sw_rst_req;
```
JasperGold flags `RST_IS_DCMB` because any gate in the asynchronous reset distribution path can introduce transient glitching during reset recovery/removal transitions, affecting 185 flip-flops across the AXI crossbar, AXI-to-APB bridge, and SRAM interfaces.

**Recommended Fix (Design Phase):**
Instantiate a 2-FF reset synchronizer clocked by `clk_i` to produce a glitch-free `sys_rst_n_sync` signal before fanning out to internal flops.

---

## 4. Generated Artifacts & Reports

1. [HTML Verification Report (A4 Layout)](file:///C:/Users/cj/.gemini/antigravity/brain/58801803-ab81-49cd-a13c-b21651525b69/jaspergold_soc_lint_report.html)
2. [Detailed JasperGold Violations Breakdown](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/jaspergold/lint_warnings_jaspergold.md)
3. Raw JasperGold reports stored locally in [`ips/jaspergold/reports/`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/jaspergold/reports/):
   - `superlint_summary.txt`
   - `superlint_violations.txt`
   - `superlint_violations_by_severity.txt`
   - `superlint_violations.csv`
   - `superlint_signoff.html`
   - `superlint_signoff.txt`
   - `superlint_setup.txt`
   - `jg_run.log`

