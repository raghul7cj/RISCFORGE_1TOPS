# RISCFORGE Quick-Routing & Workflow Map

Quick-reference directory map for AI models and engineers.

## Directory Quick Index

| Keyword / Functional Area | Directory | Primary Target Files |
|:---|:---|:---|
| **SoC Top / Subsystem** | `RTL_SOC/` | [riscforge_soc_subsystem.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv), [soc_subsystem.f](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/soc_subsystem.f) |
| **SRAM & Muxing** | `RTL_SOC/` | [sram_mux.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/sram_mux.sv), [sram_sp.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/sram_sp.sv) |
| **Boot ROM & Demux** | `RTL_SOC/` | `boot_rom.sv`, `instr_fetch_demux.sv` |
| **RISC-V Core Top** | `riscv_core/rtl/` | [top.v](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/top.v) |
| **Core Pipeline Stages** | `riscv_core/rtl/` | `fetch_cycle.v`, `decode_cycle.v`, `execute_cycle.v`, `memory_cycle.v`, `writeback_cycle.v` |
| **CSRs & Trap Controller** | `riscv_core/rtl/` | `csr_regfile.v`, `wb_trap_mret_commit_controller.v` |
| **Hazard & Forwarding** | `riscv_core/rtl/` | `hazard_unit.v` |
| **ALU / Multiplier / Divider**| `riscv_core/rtl/` | `ALU.v`, `rv32m_unit.v`, `rv32m_mul.v`, `rv32m_div.v` |
| **Memory / LSU Interface** | `riscv_core/rtl/` | `hybrid_mem_interface.sv`, `ls_unit.v`, `imem_controller.v` |
| **Bootloader (SPI to SRAM)** | `bootloader/` | [bootloader.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/bootloader/bootloader.sv), `bootloader_tb_all_testcases.sv` |
| **AXI4-Lite Crossbar** | `axi_lite_xbar/` | [axi_lite_xbar.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_xbar/axi_lite_xbar.sv) |
| **AXI to APB Bridge** | `axi_lite_to_apb/` | [axi_lite_to_apb.sv](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/axi_lite_to_apb/axi_lite_to_apb.sv) |
| **Bus Timeout Monitors** | `bus_monitors/` | `axi_lite_timeout_monitor.sv`, `apb_timeout_monitor.sv` |
| **UART (APB)** | `apb_uart-main/rtl/` | `apb_uart.sv`, `apb_uart_wrap.sv` |
| **Dual Timer (APB)** | `apb_timer-master/rtl/`| `apb_timer.sv`, `timer.sv` |
| **AON Timer** | `aon_timer/rtl/` | `aon_timer.sv`, `aon_timer_core.sv` |
| **I2C Master** | `apb_i2c-master/` | `apb_i2c.sv`, `i2c_master_byte_ctrl.sv` |
| **GPIO (APB/AXI)** | `gpio-master/` | `gpio.sv`, `gpio_apb_wrap.sv` |
| **SPI Master** | `spi_master_ip/spi_master/` | `apb_spi_master.sv`, `spi_master_controller.sv` |
| **CLIC (Interrupts)** | `clic-master/` | `clic.sv`, `clic_apb.sv`, `clic_target.sv` |
| **External VIP Slaves** | `i2c_slave_at24c02/`, `spi_slave_infinion/` | Simulation models for EEPROM & SPI Flash |
| **Software, BSP & Tests** | `Sw/` | `Sw/bsp/`, `Sw/tests/`, `Sw/tools/`, [soc_spec.md](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/Sw/soc_spec.md) |
| **Interrupt Verification** | `Verification/` | `tb1_interrupts.sv`, `run_tb1.ps1` |
| **SoC Subsystem TBs** | `RTL_SOC/` | `soc_imem_boot_tb.sv`, `soc_regtest_tb.sv`, `soc_montest_tb.sv` |
| **Formal & Lint (JG)** | `jaspergold/` | `lint.tcl`, `jg_soc.f`, `run_jaspergold.ps1` |
| **Lint & CDC (SpyGlass)** | `spyglass/` | `spyglass.prj`, `run_spyglass.tcl`, `run_spyglass.ps1` |
| **Docs & Specifications** | `documentation/` | Architecture specs, tapeout plans, arbitration docs |

---

## Agent Operation Rules

- **Zero Blind Wandering**: Do not read multiple files to discover what is where. Reference this map directly.
- **Ambiguity Guard**: If the user prompt does not specify a specific block or test (e.g., "debug the memory error"), **ask a single targeted clarifying question** instead of reading 10-20 files across core and SoC.
- **Slice Reading**: Read only targeted lines (10–100 lines) of the specific module required.
