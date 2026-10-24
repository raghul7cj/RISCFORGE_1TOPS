# RISCFORGE 1TOPS SoC — FPGA Implementation Exploration Handoff
**Document ID: FPGA-HANDOFF-STAGE-4**  
**Date: 2026-10-16**  
**Author: Antigravity Orchestrator**  

---

## 1. Executive Intent & Target Hardware

### Objective
Execute a rigorous, stage-gated FPGA implementation exploration for the **RISCFORGE 1TOPS SoC** (a 5-stage pipelined RV32IM core integrated with 6 APB peripherals, AXI-Lite crossbar, BootROM, dual 32 KB SRAMs, and bus monitors) targeting the **Digilent Nexys4 DDR** board.

### Target Device
* **FPGA Part**: AMD Artix-7 `xc7a100tcsg324-1`
* **Board**: Digilent Nexys4 DDR
* **Toolchain**: AMD Vivado 2022.2 (64-bit)
* **EDA Orchestration Mode**: Live MCP server (`vivado-ai`) + Vivado Tcl / batch scripting.

---

## 2. Completed Implementation Stages (S0 – S4 Status: READY FOR SIGNOFF)

| Stage | Focus Area | Status | Verified Metrics & Resolutions |
|:---:|:---|:---:|:---|
| **S0** | **Filelist & Packaging** | ✅ PASS | Created canonical manifest `vivado_soc.f` (100 source files). Added missing bus monitors (`bus_monitors/apb_timeout_monitor.sv`, `axi_lite_timeout_monitor.sv`). Resolved D-114. |
| **S1** | **RTL Structural Lint** | ✅ PASS | Elaboration clean in Vivado 2022.2 (`synth_design -rtl -rtl_skip_mlo -top riscforge_soc_subsystem`). Resolved S1-F001 (`irq_gateway.v` & `irq_arbiter.v` integrated). **0 Errors, 0 Critical Warnings**. |
| **S2** | **Structural Checks** | ✅ PASS | 18,022 instantiated cells; **0 Blackboxes**; 1 Primary Clock domain (`clk_i`); 5 Reset domains catalogued. |
| **S3** | **Defect Triage & Warnings** | ✅ PASS | Audited all 1,615 warnings across 9 Synth IDs (100% waivable). Triaged RevB defects (D-003, D-180, D-015, D-008, D-013). Delivered `Sw/bsp/soc_regs.h` and updated `link.ld`. |
| **S4** | **Synthesis Baseline** | ✅ PASS | Synthesized out-of-context clean (**0 Errors, 0 Critical Warnings**). **9,785 LUTs (15.4%)**, **7,314 FFs (5.8%)**, **16 BRAM tiles (11.9%)**, **0 Latches**, **0 Distributed RAM**. |

---

## 3. Key Architectural Decisions & Resolved Invariants

### 1. APB-Enclosed OBI UART Architecture
* **External Interface**: The top SoC connects to `apb_uart` via standard AMBA APB4 (`0x4000_2000`).
* **Internal Enclosure**: Inside `apb_uart.sv`, the wrapper instantiates `apb_to_obi.sv`, which converts APB phases into Open Bus Interface (OBI) cycles. The internal core `obi_uart.sv` and its 5 submodules (`obi_uart_baudgen`, `tx`, `rx`, `register`, `interrupts`, `modem`) handle UART operations.
* **Invariant**: The OBI UART files in `SOC_FILES/include/obi/` are **mandatory** internal components and must remain in all filelists.

### 2. D-114 Timer IP Discrepancy & Filelist Re-Routing
* **Root File**: `apb_timer-master/timer.sv` was restored to its exact untouched repository baseline.
* **Newer Origin**: `apb_timer-master/rtl/timer.sv` contains the bugfix qualifying interrupt generation and auto-counter-clear with `TIMER_CTRL.ENABLE_BIT`.
* **Manifest Routing**: All EDA manifests (`vivado_soc.f`, `jaspergold/jg_soc.f`, `spyglass/spyglass.prj`) route to the newer origin: `../apb_timer-master/rtl/timer.sv`.

### 3. S1-F001 IRQ Gateway & Arbiter Insertion
* `riscv_core/rtl/irq_gateway.v` and `irq_arbiter.v` were added to `jg_soc.f` (lines 129-130), `spyglass.prj` (lines 117-118), and `vivado_soc.f` immediately before `top.v`. This resolved the synthesis-blocking blackbox errors.

### 4. S4-F001 ISRAM Block RAM Template Optimization
* `Instruction_Memory.v` was converted from an address-registered combinational array read to a canonical synchronous read-first Block RAM template with `(* ram_style = "block" *)`.
* **Impact**: Inferred 8 dedicated `RAMB36E1` tiles; eliminated 2,048 `RAM128X1D` distributed LUTRAM primitives; reduced slice LUTs by 48.2% (from 18,885 down to 9,785); eliminated 4,352 multiplexers.

### 5. D-003 Interrupt Line Mapping
* The in-core arbiter prioritizes 6 active lines: GPIO (`mip[16]`), I2C (`mip[17]`), SPI (`mip[18]`), UART (`mip[19]`), Timer 0 Compare MTIP (`mip[7]`), and SPI EoT (`mip[27]`).
* Dropped lines `mip[20:26]` (Timer 0 overflow and Timer 1 channels) are bypassed at core top; standard MTIP provides complete functional timer interrupt capability.

### 6. D-180 Always-On (AON) Timer & Reset
* `aon_timer.sv` is TileLink-UL (OpenTitan) and uninstantiated. Formally waived for FPGA.
* Board reset is mapped cleanly: `hard_rst_ni` to CPU Reset button (`C12`), `soft_rst_ni` to Center button `BTNC` (`N17`).

---

## 4. Active Tool Environment & Vivado Session

* **Vivado Version**: 2022.2 (64-bit)
* **Active Vivado MCP Session**: `vivado-20261016-001015-ab0472e6`
  * Process ID: `20636`
  * Webserver: `http://localhost:8088`
  * Working Directory: `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/FPGA Implementation Plan`
* **Canonical Filelist**: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\vivado_soc.f`

---

## 5. Next Steps for Next Session: STAGE 5 (Constraints, Pinout & Top Wrapper)

When starting the new chat, immediately proceed with **Stage 5**:

### Action Plan for Stage 5:
1. **Create Nexys4 DDR Constraints File (`riscforge_nexys4ddr.xdc`)**:
   - Primary 100 MHz oscillator: Pin `E3` (`IOSTANDARD LVCMOS33`, `create_clock -period 10.000 -name sys_clk_pin [get_ports clk_i]`).
   - Hardware Resets: CPU Reset button `C12` (`hard_rst_ni`), Center button `BTNC` `N17` (`soft_rst_ni`).
   - USB-UART Bridge: Pin `C4` (`uart_rx_i`), Pin `D4` (`uart_tx_o`).
   - GPIO Interface: 16 Board LEDs (`H17`, `K15`, `J13`, `N14`, etc.) and 16 Slide Switches (`J15`, `L16`, `M13`, etc.).
2. **Top-Level FPGA Board Wrapper**:
   - Create a clean board wrapper (`riscforge_nexys4ddr_top.sv`) instantiating `riscforge_soc_subsystem`.
   - Wrap I2C tri-states (`scl_i/o/oen` and `sda_i/o/oen`) using `IOBUF` primitives.
   - Tie off unused test/scan/bootloader ports (`boot_addr_i = 32'h0`, `fetch_enable_i = 1'b1`).
3. **Execute Full Timing & Pinout Synthesis**:
   - Apply constraints and run `check_timing` and `report_clock_networks`.

---

## 6. Key Project Deliverables to Reference

1. **Presentation Sign-Off Document (.docx)**:  
   [`FPGA Implementation Plan/RISCFORGE_FPGA_PreImplementation_Signoff_Report.docx`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/FPGA%20Implementation%20Plan/RISCFORGE_FPGA_PreImplementation_Signoff_Report.docx)  
   Contains visual diagrams for Stage roadmap, OBI UART enclosure, D-114 timer routing, IRQ architecture, and warning breakdown.
2. **Master Plan Index**:  
   [`FPGA Implementation Plan/README.md`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/FPGA%20Implementation%20Plan/README.md)
3. **Comprehensive Triage Report**:  
   [`FPGA Implementation Plan/TRIAGE_AND_METHODOLOGY_REPORT.md`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/FPGA%20Implementation%20Plan/TRIAGE_AND_METHODOLOGY_REPORT.md)
4. **Execution Log**:  
   [`FPGA Implementation Plan/EXECUTION_LOG.md`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/FPGA%20Implementation%20Plan/EXECUTION_LOG.md)
5. **Software MMIO Register Header**:  
   [`Sw/bsp/soc_regs.h`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/Sw/bsp/soc_regs.h)

