# Proposed Repository Catalog

**Snapshot:** 2026-10-22  
**Scope:** all files under the current standalone SoC workspace, ips/.  
**Full file-level record:** [REPOSITORY_FILE_CATALOG.csv](REPOSITORY_FILE_CATALOG.csv), which includes current path, proposed path, disposition, rationale, and byte size for every file.

This document turns that inventory into a reviewable repository plan. It proposes destinations; it does not move, delete, or approve publication of any source.

## Proposed repository tree

```text
RISCFORGE_1TOPS/                 # repository root is the current ips/ contents
├── README.md                    # project scope, architecture, build and status
├── LICENSE / NOTICE             # only after ownership and third-party terms are resolved
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── CODEOWNERS
├── .gitignore / .gitattributes
├── .github/
│   ├── ISSUE_TEMPLATE/          # bug and feature forms
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/               # portable checks first; EDA jobs only on equipped runners
├── rtl/
│   ├── soc/                     # current RTL_SOC integration RTL
│   ├── core/riscv_core/         # current riscv_core source and core filelist
│   ├── ip/
│   │   ├── interconnect/        # AXI-Lite crossbar
│   │   ├── bridges/             # AXI-Lite to APB
│   │   ├── peripherals/         # GPIO, I2C, SPI, timers, UART, AON timer
│   │   ├── interrupts/clic/     # CLIC IP and register packages
│   │   ├── register_interface/  # only after provenance/license review
│   │   ├── bootloader/
│   │   └── bus_monitors/
│   └── third_party/             # versioned, licensed imported sources; preserve origin while comparing copies
├── verification/
│   ├── soc/{tests,checkers,monitors,vip,filelists}/
│   ├── unit/timer/              # timer UVM bench and simulator runners
│   ├── datapath/                # current datapath_verification suites
│   ├── software/{bsp,drivers,suites}/
│   ├── regression/
│   ├── fixtures/                # documented golden images only
│   └── scripts/
├── software/{bsp,tests}/        # maintained SoC firmware and BSP
├── memory_images/               # sourced/golden flash and SRAM images
├── docs/
│   ├── architecture/            # architecture, memory map, interfaces, figures
│   ├── verification/{plans,reports,evidence}/
│   ├── fpga/
│   ├── research/interrupts/
│   ├── software/
│   ├── project/
│   └── development/             # workflow and sanitized agent guidance
├── tools/
│   ├── software/                # ELF-to-hex and image generation
│   └── eda/{jaspergold,spyglass}/
└── archive/                     # only reviewed legacy source needed for history/reproduction
```

Keep source filelists with the flow they build. Any later move must update those filelists and runner working directories in the same change. Do not merge the existing UART, crossbar, or SOC_FILES include copies until content comparison, upstream provenance, and licenses are recorded.

## File disposition summary

| Disposition | Files | Meaning |
|---|---:|---|
| MOVE | 622 | Proposed destination is assigned; preserve the file if the destination's review requirements are met. |
| REVIEW | 995 | A person must decide whether and how to publish it. |
| EXCLUDE | 2266 | Generated, local, empty, or task/session output is not proposed for the public source tree. |
| KEEP | 3 | Catalog/planning documents retained at repository root. |

There are **0 proposed destination collisions** after keeping each imported include copy under a distinct source namespace. MOVE targets are now unique. **14 review items** have no destination until a person resolves whether they are durable project material or local/task state.

### Proposed target areas

| Target area | Mapped files |
|---|---:|
| `AGENTS.md` | 1 |
| `archive/legacy/draft_irq` | 36 |
| `archive/legacy/instr_module` | 6 |
| `docs/architecture/ARCHITECTURE_SUMMARY.md` | 1 |
| `docs/architecture/cv32T risc clic paper.pdf` | 1 |
| `docs/architecture/figures` | 110 |
| `docs/architecture/gpio.md` | 1 |
| `docs/architecture/Interrupt_Arbitration_Fix_Plan.docx` | 1 |
| `docs/architecture/RISCFORGE Interrupt Proposal.html` | 1 |
| `docs/architecture/RISCFORGE IRQ Arbitration Presentation.html` | 1 |
| `docs/architecture/RISCFORGE IRQ Architecture.html` | 1 |
| `docs/architecture/RISCFORGE SoC Architecture.html` | 1 |
| `docs/architecture/RISCFORGE SoC Peripheral Verification and Bus Resilience.html` | 1 |
| `docs/architecture/RISCFORGE Tapeout Verification Plan.html` | 1 |
| `docs/development/agent-guidance` | 2 |
| `docs/development/handoff.md` | 1 |
| `docs/development/WORKFLOW_MAP.md` | 1 |
| `docs/fpga/EXECUTION_LOG.md` | 1 |
| `docs/fpga/figures` | 7 |
| `docs/fpga/handoff.md` | 1 |
| `docs/fpga/make_report_docx.py` | 1 |
| `docs/fpga/README.md` | 1 |
| `docs/fpga/reports` | 1 |
| `docs/fpga/RISCFORGE_FPGA_PreImplementation_Signoff_Report.docx` | 1 |
| `docs/fpga/STAGE-0_Filelist_Audit.md` | 1 |
| `docs/fpga/STAGE-1_RTL_Lint.md` | 1 |
| `docs/fpga/STAGE-2_Structural_Checks.md` | 1 |
| `docs/fpga/STAGE-3_RTL_Defect_Triage.md` | 1 |
| `docs/fpga/STAGE-4_Synthesis_Baseline.md` | 1 |
| `docs/fpga/STAGE-5_Constraints_IO.md` | 1 |
| `docs/fpga/STAGE-6_Implementation.md` | 1 |
| `docs/fpga/STAGE-7_Bitstream_Validation.md` | 1 |
| `docs/fpga/TRIAGE_AND_METHODOLOGY_REPORT.md` | 1 |
| `docs/project/P0_bringup.md` | 1 |
| `docs/research/interrupts` | 80 |
| `docs/software/Makefile` | 1 |
| `docs/software/soc_spec.md` | 1 |
| `docs/software/sw_plan.html` | 1 |
| `docs/software/sw_plan.md` | 1 |
| `docs/verification/evidence` | 19 |
| `docs/verification/INFRA_TRACKING.md` | 1 |
| `docs/verification/infrastructure` | 9 |
| `docs/verification/plans` | 2 |
| `docs/verification/reports` | 32 |
| `docs/verification/RISCFORGE_Tapeout_Verification_Plan.html` | 1 |
| `docs/verification/SoC Verification Infrastructure_ Integration Guide.html` | 1 |
| `docs/verification/soc_verification_plan.md` | 1 |
| `memory_images/gen_flash_image.py` | 1 |
| `memory_images/i2c_regtest/build.py` | 1 |
| `memory_images/i2c_regtest/i2c_regtest_dmem.hex` | 1 |
| `memory_images/i2c_regtest/i2c_regtest_flash.mem` | 1 |
| `memory_images/i2c_regtest/i2c_regtest_imem.hex` | 1 |
| `memory_images/i2c_regtest/i2c_regtest_params.svh` | 1 |
| `memory_images/i2c_regtest/i2c_regtest.c` | 1 |
| `memory_images/i2c_regtest/i2c_regtest.dump` | 1 |
| `memory_images/i2c_regtest/i2c_regtest.map` | 1 |
| `memory_images/i2c_regtest/link.ld` | 1 |
| `memory_images/i2c_regtest/README.md` | 1 |
| `memory_images/i2c_regtest/startup.S` | 1 |
| `memory_images/montest/build.py` | 1 |
| `memory_images/montest/montest_dmem.hex` | 1 |
| `memory_images/montest/montest_flash.mem` | 1 |
| `memory_images/montest/montest_imem.hex` | 1 |
| `memory_images/montest/montest_params.svh` | 1 |
| `memory_images/montest/montest.c` | 1 |
| `memory_images/montest/montest.dump` | 1 |
| `memory_images/montest/montest.map` | 1 |
| `memory_images/regtest/build.py` | 1 |
| `memory_images/regtest/link.ld` | 1 |
| `memory_images/regtest/regtest_dmem.hex` | 1 |
| `memory_images/regtest/regtest_flash.mem` | 1 |
| `memory_images/regtest/regtest_imem.hex` | 1 |
| `memory_images/regtest/regtest_params.svh` | 1 |
| `memory_images/regtest/regtest.c` | 1 |
| `memory_images/regtest/regtest.dump` | 1 |
| `memory_images/regtest/regtest.map` | 1 |
| `memory_images/regtest/startup.S` | 1 |
| `memory_images/riscforge_bootrom.hex` | 1 |
| `memory_images/riscforge_timer0_dmem.hex` | 1 |
| `memory_images/riscforge_timer0_flash_spi.mem` | 1 |
| `memory_images/riscforge_timer0_flash.mem` | 1 |
| `memory_images/riscforge_timer0_test.hex` | 1 |
| `memory_images/timer/riscforge_bootrom.hex` | 1 |
| `memory_images/timer/riscforge_timer0_dmem.hex` | 1 |
| `memory_images/timer/riscforge_timer0_flash_spi.mem` | 1 |
| `memory_images/timer/riscforge_timer0_flash.mem` | 1 |
| `memory_images/timer/riscforge_timer0_test.hex` | 1 |
| `rtl/core/riscforge_soc_subsystem_dut.f` | 1 |
| `rtl/core/rtl` | 33 |
| `rtl/ip/bootloader` | 8 |
| `rtl/ip/bridges` | 4 |
| `rtl/ip/bus_monitors` | 2 |
| `rtl/ip/interconnect` | 3 |
| `rtl/ip/interrupts` | 14 |
| `rtl/ip/peripherals` | 98 |
| `rtl/soc/axi_lite_sram_if.sv` | 1 |
| `rtl/soc/boot_rom.sv` | 1 |
| `rtl/soc/imem_sram_wrapper.sv` | 1 |
| `rtl/soc/instr_fetch_demux.sv` | 1 |
| `rtl/soc/riscforge_soc_subsystem.sv` | 1 |
| `rtl/soc/riscv_core_stub.sv` | 1 |
| `rtl/soc/sram_mux.sv` | 1 |
| `rtl/soc/sram_sp.sv` | 1 |
| `rtl/third_party/include-copies` | 303 |
| `rtl/third_party/register_interface` | 24 |
| `rtl/third_party/SOC_FILES` | 168 |
| `software/bsp/crt0.S` | 1 |
| `software/bsp/link.ld` | 1 |
| `software/bsp/soc_regs.h` | 1 |
| `software/bsp/uart_min.h` | 1 |
| `software/tests/datapath_smoke_test.s` | 1 |
| `software/tests/uart_smoke_test.c` | 1 |
| `tools/eda/jaspergold` | 4 |
| `tools/eda/spyglass` | 5 |
| `tools/software/elf_to_hex.py` | 1 |
| `verification/datapath/i2c0` | 14 |
| `verification/datapath/spi0` | 15 |
| `verification/datapath/UART0` | 15 |
| `verification/evidence/archive` | 305 |
| `verification/fixtures/dmem.hex` | 1 |
| `verification/fixtures/imem.hex` | 1 |
| `verification/fixtures/tb1_test1_timer_dmem.hex` | 1 |
| `verification/fixtures/tb1_test1_timer_imem.hex` | 1 |
| `verification/fixtures/tb1_test1_timer.hex` | 1 |
| `verification/fixtures/tb1_test2_all_sources_dmem.hex` | 1 |
| `verification/fixtures/tb1_test2_all_sources_imem.hex` | 1 |
| `verification/fixtures/tb1_test2_all_sources.hex` | 1 |
| `verification/fixtures/tb1_test3_priority_dmem.hex` | 1 |
| `verification/fixtures/tb1_test3_priority_imem.hex` | 1 |
| `verification/fixtures/tb1_test3_priority.hex` | 1 |
| `verification/fixtures/tb1_test4_mintprio_dmem.hex` | 1 |
| `verification/fixtures/tb1_test4_mintprio_imem.hex` | 1 |
| `verification/fixtures/tb1_test4_mintprio.hex` | 1 |
| `verification/fixtures/tb1_test5_hazard_dmem.hex` | 1 |
| `verification/fixtures/tb1_test5_hazard_imem.hex` | 1 |
| `verification/fixtures/tb1_test5_hazard.hex` | 1 |
| `verification/fixtures/tb1_test6_collision_dmem.hex` | 1 |
| `verification/fixtures/tb1_test6_collision_imem.hex` | 1 |
| `verification/fixtures/tb1_test6_collision.hex` | 1 |
| `verification/fixtures/tb1_test7_mret_dmem.hex` | 1 |
| `verification/fixtures/tb1_test7_mret_imem.hex` | 1 |
| `verification/fixtures/tb1_test7_mret.hex` | 1 |
| `verification/regression/build_stages.sh` | 1 |
| `verification/regression/dump_session.py` | 1 |
| `verification/regression/elf_to_hex_clean.py` | 1 |
| `verification/regression/launch_opencode_verifier.py` | 1 |
| `verification/regression/run_regression.ps1` | 1 |
| `verification/scripts/fix_filelist.py` | 1 |
| `verification/scripts/gen_filelists.py` | 1 |
| `verification/scripts/run_freeze_stress.ps1` | 1 |
| `verification/scripts/run_rf_mon_challenge.ps1` | 1 |
| `verification/scripts/run_rf_mon_smoke.ps1` | 1 |
| `verification/soc/checkers` | 23 |
| `verification/soc/filelists` | 19 |
| `verification/soc/monitors` | 8 |
| `verification/soc/tb` | 12 |
| `verification/soc/tests` | 21 |
| `verification/soc/vip` | 4 |
| `verification/software/bsp` | 10 |
| `verification/software/drivers` | 10 |
| `verification/software/suites` | 8 |
| `verification/unit/timer` | 17 |
| `verification/vip/i2c_slave_at24c02` | 8 |
| `verification/vip/spi_flash_model` | 19 |

### Current-folder disposition counts

| Current folder/path | Move | Review | Exclude |
|---|---:|---:|---:|
| `.agents` | 0 | 6 | 159 |
| `.claude` | 0 | 0 | 1 |
| `AGENTS.md` | 0 | 1 | 0 |
| `aon_timer` | 10 | 0 | 10 |
| `apb_i2c-master` | 10 | 0 | 1 |
| `apb_timer-master` | 23 | 0 | 64 |
| `apb_uart-main` | 6 | 147 | 30 |
| `axi_lite_to_apb` | 4 | 0 | 0 |
| `axi_lite_xbar` | 3 | 156 | 0 |
| `bootloader` | 8 | 0 | 4 |
| `bus_monitors` | 2 | 0 | 0 |
| `check_opencode.ps1` | 0 | 1 | 0 |
| `CLAUDE.md` | 0 | 1 | 0 |
| `clic-master` | 14 | 0 | 0 |
| `compile_merged_check.log` | 0 | 0 | 1 |
| `datapath_verification` | 44 | 0 | 2 |
| `documentation` | 117 | 2 | 6 |
| `findings.csv` | 0 | 0 | 1 |
| `FPGA Implementation Plan` | 21 | 1 | 54 |
| `goals` | 1 | 0 | 0 |
| `gpio-master` | 16 | 0 | 25 |
| `gpio.md` | 1 | 0 | 0 |
| `handoff.md` | 0 | 1 | 0 |
| `i2c_slave_at24c02` | 0 | 8 | 0 |
| `INFRA_TRACKING.md` | 1 | 0 | 0 |
| `instr_module` | 0 | 6 | 0 |
| `Interrupt research` | 70 | 10 | 105 |
| `jaspergold` | 4 | 12 | 644 |
| `mem_files` | 40 | 0 | 3 |
| `old files` | 0 | 36 | 55 |
| `register_interface` | 0 | 24 | 0 |
| `RISCFORGE_SoC_Verification_Plan.docx` | 0 | 1 | 0 |
| `RISCFORGE_Verification_Plan_RevB.docx` | 0 | 1 | 0 |
| `riscv_core` | 34 | 0 | 0 |
| `RTL_SOC` | 25 | 0 | 8 |
| `ses_status.json` | 0 | 1 | 0 |
| `SoC Verification Infrastructure_ Integration Guide.html` | 1 | 0 | 0 |
| `SOC_FILES` | 0 | 168 | 0 |
| `spi_master_ip` | 50 | 0 | 26 |
| `spi_slave_infinion` | 0 | 20 | 1 |
| `spyglass` | 5 | 22 | 1 |
| `Sw` | 11 | 0 | 0 |
| `Verification` | 99 | 370 | 948 |
| `vivado_soc.f` | 1 | 0 | 0 |
| `WORKFLOW_MAP.md` | 1 | 0 | 0 |
| `xelab.log` | 0 | 0 | 1 |
| `xelab.pb` | 0 | 0 | 1 |
| `xsim.dir` | 0 | 0 | 113 |
| `xvlog.log` | 0 | 0 | 1 |
| `xvlog.pb` | 0 | 0 | 1 |

## Proposed file moves

Every MOVE row is listed below. Proposed paths are relative to the future repository root.

| Current path | Proposed path | Category |
|---|---|---|
| `documentation/ARCHITECTURE_SUMMARY.md` | `docs/architecture/ARCHITECTURE_SUMMARY.md` | Architecture documentation |
| `documentation/figures/_BRIEF.md` | `docs/architecture/figures/_BRIEF.md` | Architecture documentation |
| `documentation/figures/_BRIEF2_PRESENTABILITY.md` | `docs/architecture/figures/_BRIEF2_PRESENTABILITY.md` | Architecture documentation |
| `documentation/figures/_BRIEF3_SPLITS.md` | `docs/architecture/figures/_BRIEF3_SPLITS.md` | Architecture documentation |
| `documentation/figures/_figstyle.py` | `docs/architecture/figures/_figstyle.py` | Architecture documentation |
| `documentation/figures/d_aon_timer.py` | `docs/architecture/figures/d_aon_timer.py` | Architecture documentation |
| `documentation/figures/d_apb_timer.py` | `docs/architecture/figures/d_apb_timer.py` | Architecture documentation |
| `documentation/figures/d_apb_timing.py` | `docs/architecture/figures/d_apb_timing.py` | Architecture documentation |
| `documentation/figures/d_axil_apb_bridge.py` | `docs/architecture/figures/d_axil_apb_bridge.py` | Architecture documentation |
| `documentation/figures/d_clic.py` | `docs/architecture/figures/d_clic.py` | Architecture documentation |
| `documentation/figures/d_fig20_axi_apb_timing.py` | `docs/architecture/figures/d_fig20_axi_apb_timing.py` | Architecture documentation |
| `documentation/figures/d_fig21_axi_mon.py` | `docs/architecture/figures/d_fig21_axi_mon.py` | Architecture documentation |
| `documentation/figures/d_fig22_apb_mon.py` | `docs/architecture/figures/d_fig22_apb_mon.py` | Architecture documentation |
| `documentation/figures/d_fig23_monitors_shared.py` | `docs/architecture/figures/d_fig23_monitors_shared.py` | Architecture documentation |
| `documentation/figures/d_fig24_uart_register_map.py` | `docs/architecture/figures/d_fig24_uart_register_map.py` | Architecture documentation |
| `documentation/figures/d_fig25_wakeup.py` | `docs/architecture/figures/d_fig25_wakeup.py` | Architecture documentation |
| `documentation/figures/d_fig26_watchdog.py` | `docs/architecture/figures/d_fig26_watchdog.py` | Architecture documentation |
| `documentation/figures/d_fig27_i2c_bit_engine.py` | `docs/architecture/figures/d_fig27_i2c_bit_engine.py` | Architecture documentation |
| `documentation/figures/d_fig28_i2c_error_branches.py` | `docs/architecture/figures/d_fig28_i2c_error_branches.py` | Architecture documentation |
| `documentation/figures/d_fig29_i2c_clock_stretching.py` | `docs/architecture/figures/d_fig29_i2c_clock_stretching.py` | Architecture documentation |
| `documentation/figures/d_fig33_soc_irq_live_vs_clic.py` | `docs/architecture/figures/d_fig33_soc_irq_live_vs_clic.py` | Architecture documentation |
| `documentation/figures/d_fig34_exception_priority.py` | `docs/architecture/figures/d_fig34_exception_priority.py` | Architecture documentation |
| `documentation/figures/d_fig36_load_use_bubble.py` | `docs/architecture/figures/d_fig36_load_use_bubble.py` | Architecture documentation |
| `documentation/figures/d_gpio_map.py` | `docs/architecture/figures/d_gpio_map.py` | Architecture documentation |
| `documentation/figures/d_gpio_sync.py` | `docs/architecture/figures/d_gpio_sync.py` | Architecture documentation |
| `documentation/figures/d_gpio.py` | `docs/architecture/figures/d_gpio.py` | Architecture documentation |
| `documentation/figures/d_i2c_fsm.py` | `docs/architecture/figures/d_i2c_fsm.py` | Architecture documentation |
| `documentation/figures/d_i2c_wave.py` | `docs/architecture/figures/d_i2c_wave.py` | Architecture documentation |
| `documentation/figures/d_irq_arb.py` | `docs/architecture/figures/d_irq_arb.py` | Architecture documentation |
| `documentation/figures/d_monitors.py` | `docs/architecture/figures/d_monitors.py` | Architecture documentation |
| `documentation/figures/d_pipeline.py` | `docs/architecture/figures/d_pipeline.py` | Architecture documentation |
| `documentation/figures/d_soc_addressmap.py` | `docs/architecture/figures/d_soc_addressmap.py` | Architecture documentation |
| `documentation/figures/d_soc_boot_sequence.py` | `docs/architecture/figures/d_soc_boot_sequence.py` | Architecture documentation |
| `documentation/figures/d_soc_topology.py` | `docs/architecture/figures/d_soc_topology.py` | Architecture documentation |
| `documentation/figures/d_spi_fsm.py` | `docs/architecture/figures/d_spi_fsm.py` | Architecture documentation |
| `documentation/figures/d_spi_mode.py` | `docs/architecture/figures/d_spi_mode.py` | Architecture documentation |
| `documentation/figures/d_trap_fsm.py` | `docs/architecture/figures/d_trap_fsm.py` | Architecture documentation |
| `documentation/figures/d_uart_fsm.py` | `docs/architecture/figures/d_uart_fsm.py` | Architecture documentation |
| `documentation/figures/d_uart_internals.py` | `docs/architecture/figures/d_uart_internals.py` | Architecture documentation |
| `documentation/figures/d_xbar.py` | `docs/architecture/figures/d_xbar.py` | Architecture documentation |
| `documentation/figures/fig01_soc_topology.png` | `docs/architecture/figures/fig01_soc_topology.png` | Architecture documentation |
| `documentation/figures/fig01_soc_topology.svg` | `docs/architecture/figures/fig01_soc_topology.svg` | Architecture documentation |
| `documentation/figures/fig02_soc_address_map.png` | `docs/architecture/figures/fig02_soc_address_map.png` | Architecture documentation |
| `documentation/figures/fig02_soc_address_map.svg` | `docs/architecture/figures/fig02_soc_address_map.svg` | Architecture documentation |
| `documentation/figures/fig03_axi_xbar_internals.png` | `docs/architecture/figures/fig03_axi_xbar_internals.png` | Architecture documentation |
| `documentation/figures/fig03_axi_xbar_internals.svg` | `docs/architecture/figures/fig03_axi_xbar_internals.svg` | Architecture documentation |
| `documentation/figures/fig04_axil_to_apb_bridge_fsm.png` | `docs/architecture/figures/fig04_axil_to_apb_bridge_fsm.png` | Architecture documentation |
| `documentation/figures/fig04_axil_to_apb_bridge_fsm.svg` | `docs/architecture/figures/fig04_axil_to_apb_bridge_fsm.svg` | Architecture documentation |
| `documentation/figures/fig05_bus_timeout_monitors.png` | `docs/architecture/figures/fig05_bus_timeout_monitors.png` | Architecture documentation |
| `documentation/figures/fig05_bus_timeout_monitors.svg` | `docs/architecture/figures/fig05_bus_timeout_monitors.svg` | Architecture documentation |
| `documentation/figures/fig06_apb_protocol_timing.png` | `docs/architecture/figures/fig06_apb_protocol_timing.png` | Architecture documentation |
| `documentation/figures/fig06_apb_protocol_timing.svg` | `docs/architecture/figures/fig06_apb_protocol_timing.svg` | Architecture documentation |
| `documentation/figures/fig07_uart_internals.png` | `docs/architecture/figures/fig07_uart_internals.png` | Architecture documentation |
| `documentation/figures/fig07_uart_internals.svg` | `docs/architecture/figures/fig07_uart_internals.svg` | Architecture documentation |
| `documentation/figures/fig08_uart_tx_rx_fsm.png` | `docs/architecture/figures/fig08_uart_tx_rx_fsm.png` | Architecture documentation |
| `documentation/figures/fig08_uart_tx_rx_fsm.svg` | `docs/architecture/figures/fig08_uart_tx_rx_fsm.svg` | Architecture documentation |
| `documentation/figures/fig09_apb_timer_internals.png` | `docs/architecture/figures/fig09_apb_timer_internals.png` | Architecture documentation |
| `documentation/figures/fig09_apb_timer_internals.svg` | `docs/architecture/figures/fig09_apb_timer_internals.svg` | Architecture documentation |
| `documentation/figures/fig10_aon_timer_fsm.png` | `docs/architecture/figures/fig10_aon_timer_fsm.png` | Architecture documentation |
| `documentation/figures/fig10_aon_timer_fsm.svg` | `docs/architecture/figures/fig10_aon_timer_fsm.svg` | Architecture documentation |
| `documentation/figures/fig11_i2c_master_fsm.png` | `docs/architecture/figures/fig11_i2c_master_fsm.png` | Architecture documentation |
| `documentation/figures/fig11_i2c_master_fsm.svg` | `docs/architecture/figures/fig11_i2c_master_fsm.svg` | Architecture documentation |
| `documentation/figures/fig12_i2c_timing_waveform.png` | `docs/architecture/figures/fig12_i2c_timing_waveform.png` | Architecture documentation |
| `documentation/figures/fig12_i2c_timing_waveform.svg` | `docs/architecture/figures/fig12_i2c_timing_waveform.svg` | Architecture documentation |
| `documentation/figures/fig13_spi_master_fsm.png` | `docs/architecture/figures/fig13_spi_master_fsm.png` | Architecture documentation |
| `documentation/figures/fig13_spi_master_fsm.svg` | `docs/architecture/figures/fig13_spi_master_fsm.svg` | Architecture documentation |
| `documentation/figures/fig14_gpio_internals.png` | `docs/architecture/figures/fig14_gpio_internals.png` | Architecture documentation |
| `documentation/figures/fig14_gpio_internals.svg` | `docs/architecture/figures/fig14_gpio_internals.svg` | Architecture documentation |
| `documentation/figures/fig15_clic_internals.png` | `docs/architecture/figures/fig15_clic_internals.png` | Architecture documentation |
| `documentation/figures/fig15_clic_internals.svg` | `docs/architecture/figures/fig15_clic_internals.svg` | Architecture documentation |
| `documentation/figures/fig16_irq_arbitration.png` | `docs/architecture/figures/fig16_irq_arbitration.png` | Architecture documentation |
| `documentation/figures/fig16_irq_arbitration.svg` | `docs/architecture/figures/fig16_irq_arbitration.svg` | Architecture documentation |
| `documentation/figures/fig17_rv32_pipeline.png` | `docs/architecture/figures/fig17_rv32_pipeline.png` | Architecture documentation |
| `documentation/figures/fig17_rv32_pipeline.svg` | `docs/architecture/figures/fig17_rv32_pipeline.svg` | Architecture documentation |
| `documentation/figures/fig18_trap_mret_fsm.png` | `docs/architecture/figures/fig18_trap_mret_fsm.png` | Architecture documentation |
| `documentation/figures/fig18_trap_mret_fsm.svg` | `docs/architecture/figures/fig18_trap_mret_fsm.svg` | Architecture documentation |
| `documentation/figures/fig19_soc_boot_sequence.png` | `docs/architecture/figures/fig19_soc_boot_sequence.png` | Architecture documentation |
| `documentation/figures/fig19_soc_boot_sequence.svg` | `docs/architecture/figures/fig19_soc_boot_sequence.svg` | Architecture documentation |
| `documentation/figures/fig20_axi_lite_to_apb_bridge_timing.png` | `docs/architecture/figures/fig20_axi_lite_to_apb_bridge_timing.png` | Architecture documentation |
| `documentation/figures/fig20_axi_lite_to_apb_bridge_timing.svg` | `docs/architecture/figures/fig20_axi_lite_to_apb_bridge_timing.svg` | Architecture documentation |
| `documentation/figures/fig21_axi_lite_timeout_monitor.png` | `docs/architecture/figures/fig21_axi_lite_timeout_monitor.png` | Architecture documentation |
| `documentation/figures/fig21_axi_lite_timeout_monitor.svg` | `docs/architecture/figures/fig21_axi_lite_timeout_monitor.svg` | Architecture documentation |
| `documentation/figures/fig22_apb_timeout_monitor.png` | `docs/architecture/figures/fig22_apb_timeout_monitor.png` | Architecture documentation |
| `documentation/figures/fig22_apb_timeout_monitor.svg` | `docs/architecture/figures/fig22_apb_timeout_monitor.svg` | Architecture documentation |
| `documentation/figures/fig23_monitor_escalation.png` | `docs/architecture/figures/fig23_monitor_escalation.png` | Architecture documentation |
| `documentation/figures/fig23_monitor_escalation.svg` | `docs/architecture/figures/fig23_monitor_escalation.svg` | Architecture documentation |
| `documentation/figures/fig24_uart_register_map.png` | `docs/architecture/figures/fig24_uart_register_map.png` | Architecture documentation |
| `documentation/figures/fig24_uart_register_map.svg` | `docs/architecture/figures/fig24_uart_register_map.svg` | Architecture documentation |
| `documentation/figures/fig25_aon_timer_wakeup_path.png` | `docs/architecture/figures/fig25_aon_timer_wakeup_path.png` | Architecture documentation |
| `documentation/figures/fig25_aon_timer_wakeup_path.svg` | `docs/architecture/figures/fig25_aon_timer_wakeup_path.svg` | Architecture documentation |
| `documentation/figures/fig26_aon_timer_watchdog_path.png` | `docs/architecture/figures/fig26_aon_timer_watchdog_path.png` | Architecture documentation |
| `documentation/figures/fig26_aon_timer_watchdog_path.svg` | `docs/architecture/figures/fig26_aon_timer_watchdog_path.svg` | Architecture documentation |
| `documentation/figures/fig27_i2c_bit_engine.png` | `docs/architecture/figures/fig27_i2c_bit_engine.png` | Architecture documentation |
| `documentation/figures/fig27_i2c_bit_engine.svg` | `docs/architecture/figures/fig27_i2c_bit_engine.svg` | Architecture documentation |
| `documentation/figures/fig28_i2c_error_branches.png` | `docs/architecture/figures/fig28_i2c_error_branches.png` | Architecture documentation |
| `documentation/figures/fig28_i2c_error_branches.svg` | `docs/architecture/figures/fig28_i2c_error_branches.svg` | Architecture documentation |
| `documentation/figures/fig29_i2c_clock_stretching.png` | `docs/architecture/figures/fig29_i2c_clock_stretching.png` | Architecture documentation |
| `documentation/figures/fig29_i2c_clock_stretching.svg` | `docs/architecture/figures/fig29_i2c_clock_stretching.svg` | Architecture documentation |
| `documentation/figures/fig30_spi_mode_and_backpressure.png` | `docs/architecture/figures/fig30_spi_mode_and_backpressure.png` | Architecture documentation |
| `documentation/figures/fig30_spi_mode_and_backpressure.svg` | `docs/architecture/figures/fig30_spi_mode_and_backpressure.svg` | Architecture documentation |
| `documentation/figures/fig31_gpio_input_synchroniser.png` | `docs/architecture/figures/fig31_gpio_input_synchroniser.png` | Architecture documentation |
| `documentation/figures/fig31_gpio_input_synchroniser.svg` | `docs/architecture/figures/fig31_gpio_input_synchroniser.svg` | Architecture documentation |
| `documentation/figures/fig32_gpio_register_map_and_output.png` | `docs/architecture/figures/fig32_gpio_register_map_and_output.png` | Architecture documentation |
| `documentation/figures/fig32_gpio_register_map_and_output.svg` | `docs/architecture/figures/fig32_gpio_register_map_and_output.svg` | Architecture documentation |
| `documentation/figures/fig33_soc_irq_live_vs_clic.png` | `docs/architecture/figures/fig33_soc_irq_live_vs_clic.png` | Architecture documentation |
| `documentation/figures/fig33_soc_irq_live_vs_clic.svg` | `docs/architecture/figures/fig33_soc_irq_live_vs_clic.svg` | Architecture documentation |
| `documentation/figures/fig34_exception_priority.png` | `docs/architecture/figures/fig34_exception_priority.png` | Architecture documentation |
| `documentation/figures/fig34_exception_priority.svg` | `docs/architecture/figures/fig34_exception_priority.svg` | Architecture documentation |
| `documentation/figures/fig36_rv32_load_use_bubble.png` | `docs/architecture/figures/fig36_rv32_load_use_bubble.png` | Architecture documentation |
| `documentation/figures/fig36_rv32_load_use_bubble.svg` | `docs/architecture/figures/fig36_rv32_load_use_bubble.svg` | Architecture documentation |
| `documentation/figures/RISCFORGE_Figure_Set.html` | `docs/architecture/figures/RISCFORGE_Figure_Set.html` | Architecture documentation |
| `gpio.md` | `docs/architecture/gpio.md` | GPIO design note |
| `documentation/RISCFORGE Interrupt Proposal.html` | `docs/architecture/RISCFORGE Interrupt Proposal.html` | Architecture documentation |
| `documentation/RISCFORGE IRQ Arbitration Presentation.html` | `docs/architecture/RISCFORGE IRQ Arbitration Presentation.html` | Architecture documentation |
| `documentation/RISCFORGE IRQ Architecture.html` | `docs/architecture/RISCFORGE IRQ Architecture.html` | Architecture documentation |
| `documentation/RISCFORGE SoC Architecture.html` | `docs/architecture/RISCFORGE SoC Architecture.html` | Architecture documentation |
| `documentation/RISCFORGE SoC Peripheral Verification and Bus Resilience.html` | `docs/architecture/RISCFORGE SoC Peripheral Verification and Bus Resilience.html` | Architecture documentation |
| `documentation/RISCFORGE Tapeout Verification Plan.html` | `docs/architecture/RISCFORGE Tapeout Verification Plan.html` | Architecture documentation |
| `WORKFLOW_MAP.md` | `docs/development/WORKFLOW_MAP.md` | Project workflow map |
| `FPGA Implementation Plan/EXECUTION_LOG.md` | `docs/fpga/EXECUTION_LOG.md` | FPGA plan/source |
| `FPGA Implementation Plan/figures/diag1_stages.png` | `docs/fpga/figures/diag1_stages.png` | FPGA plan/source |
| `FPGA Implementation Plan/figures/diag2_uart_obi.png` | `docs/fpga/figures/diag2_uart_obi.png` | FPGA plan/source |
| `FPGA Implementation Plan/figures/diag3_timer_routing.png` | `docs/fpga/figures/diag3_timer_routing.png` | FPGA plan/source |
| `FPGA Implementation Plan/figures/diag4_irq_subsystem.png` | `docs/fpga/figures/diag4_irq_subsystem.png` | FPGA plan/source |
| `FPGA Implementation Plan/figures/diag5_warnings_chart.png` | `docs/fpga/figures/diag5_warnings_chart.png` | FPGA plan/source |
| `FPGA Implementation Plan/figures/make_all_diags.py` | `docs/fpga/figures/make_all_diags.py` | FPGA plan/source |
| `FPGA Implementation Plan/figures/make_diag1.py` | `docs/fpga/figures/make_diag1.py` | FPGA plan/source |
| `FPGA Implementation Plan/handoff.md` | `docs/fpga/handoff.md` | FPGA plan/source |
| `FPGA Implementation Plan/make_report_docx.py` | `docs/fpga/make_report_docx.py` | FPGA plan/source |
| `FPGA Implementation Plan/README.md` | `docs/fpga/README.md` | FPGA plan/source |
| `FPGA Implementation Plan/reports/s4_utilization.rpt` | `docs/fpga/reports/s4_utilization.rpt` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-0_Filelist_Audit.md` | `docs/fpga/STAGE-0_Filelist_Audit.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-1_RTL_Lint.md` | `docs/fpga/STAGE-1_RTL_Lint.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-2_Structural_Checks.md` | `docs/fpga/STAGE-2_Structural_Checks.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-3_RTL_Defect_Triage.md` | `docs/fpga/STAGE-3_RTL_Defect_Triage.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-4_Synthesis_Baseline.md` | `docs/fpga/STAGE-4_Synthesis_Baseline.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-5_Constraints_IO.md` | `docs/fpga/STAGE-5_Constraints_IO.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-6_Implementation.md` | `docs/fpga/STAGE-6_Implementation.md` | FPGA plan/source |
| `FPGA Implementation Plan/STAGE-7_Bitstream_Validation.md` | `docs/fpga/STAGE-7_Bitstream_Validation.md` | FPGA plan/source |
| `FPGA Implementation Plan/TRIAGE_AND_METHODOLOGY_REPORT.md` | `docs/fpga/TRIAGE_AND_METHODOLOGY_REPORT.md` | FPGA plan/source |
| `goals/P0_bringup.md` | `docs/project/P0_bringup.md` | Project milestone plan |
| `Interrupt research/build_v2_slides.py` | `docs/research/interrupts/build_v2_slides.py` | Interrupt research source |
| `Interrupt research/fig1_soc_block_diagram.svg` | `docs/research/interrupts/fig1_soc_block_diagram.svg` | Interrupt research source |
| `Interrupt research/fig2_current_fixed_priority_irq.svg` | `docs/research/interrupts/fig2_current_fixed_priority_irq.svg` | Interrupt research source |
| `Interrupt research/fig3_proposed_round_robin_irq.svg` | `docs/research/interrupts/fig3_proposed_round_robin_irq.svg` | Interrupt research source |
| `Interrupt research/generate_all_slides.py` | `docs/research/interrupts/generate_all_slides.py` | Interrupt research source |
| `Interrupt research/In-Core Zicsr Interrupt Subsystem Proposal.html` | `docs/research/interrupts/In-Core Zicsr Interrupt Subsystem Proposal.html` | Interrupt research source |
| `Interrupt research/irq_subsystem_paper.html` | `docs/research/interrupts/irq_subsystem_paper.html` | Interrupt research source |
| `Interrupt research/Lean Fast-Interrupt Entry_ Final Proposal.html` | `docs/research/interrupts/Lean Fast-Interrupt Entry_ Final Proposal.html` | Interrupt research source |
| `Interrupt research/M1 and M2_ Stage-by-Stage Design Walkthrough.html` | `docs/research/interrupts/M1 and M2_ Stage-by-Stage Design Walkthrough.html` | Interrupt research source |
| `Interrupt research/Option B_ Bounded Arbitration and Bank-less Saving.html` | `docs/research/interrupts/Option B_ Bounded Arbitration and Bank-less Saving.html` | Interrupt research source |
| `Interrupt research/pptx/LICENSE.txt` | `docs/research/interrupts/pptx/LICENSE.txt` | Interrupt research source |
| `Interrupt research/pptx/scripts/__init__.py` | `docs/research/interrupts/pptx/scripts/__init__.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/add_slide.py` | `docs/research/interrupts/pptx/scripts/add_slide.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/clean.py` | `docs/research/interrupts/pptx/scripts/clean.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/helpers/__init__.py` | `docs/research/interrupts/pptx/scripts/office/helpers/__init__.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/helpers/pptx_chart.py` | `docs/research/interrupts/pptx/scripts/office/helpers/pptx_chart.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/helpers/pptx_slide.py` | `docs/research/interrupts/pptx/scripts/office/helpers/pptx_slide.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/helpers/pptx_theme.py` | `docs/research/interrupts/pptx/scripts/office/helpers/pptx_theme.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ecma/fouth-edition/opc-contentTypes.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ecma/fouth-edition/opc-contentTypes.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ecma/fouth-edition/opc-coreProperties.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ecma/fouth-edition/opc-coreProperties.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ecma/fouth-edition/opc-digSig.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ecma/fouth-edition/opc-digSig.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ecma/fouth-edition/opc-relationships.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ecma/fouth-edition/opc-relationships.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-chart.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-chart.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-chartDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-chartDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-diagram.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-diagram.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-lockedCanvas.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-lockedCanvas.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-main.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-main.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-picture.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-picture.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-spreadsheetDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-spreadsheetDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-wordprocessingDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/dml-wordprocessingDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/pml.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/pml.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-additionalCharacteristics.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-additionalCharacteristics.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-bibliography.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-bibliography.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-commonSimpleTypes.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-commonSimpleTypes.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-customXmlDataProperties.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-customXmlDataProperties.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-customXmlSchemaProperties.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-customXmlSchemaProperties.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesCustom.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesCustom.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesExtended.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesExtended.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesVariantTypes.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-documentPropertiesVariantTypes.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-math.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-math.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-relationshipReference.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/shared-relationshipReference.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/sml.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/sml.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-main.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-main.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-officeDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-officeDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-presentationDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-presentationDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-spreadsheetDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-spreadsheetDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-wordprocessingDrawing.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/vml-wordprocessingDrawing.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/wml.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/wml.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/xml.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/ISO-IEC29500-4_2016/xml.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/mce/mc.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/mce/mc.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-2010.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-2010.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-2012.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-2012.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-2018.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-2018.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-cex-2018.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-cex-2018.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-cid-2016.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-cid-2016.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-sdtdatahash-2020.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-sdtdatahash-2020.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/schemas/microsoft/wml-symex-2015.xsd` | `docs/research/interrupts/pptx/scripts/office/schemas/microsoft/wml-symex-2015.xsd` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/soffice.py` | `docs/research/interrupts/pptx/scripts/office/soffice.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validate.py` | `docs/research/interrupts/pptx/scripts/office/validate.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validators/__init__.py` | `docs/research/interrupts/pptx/scripts/office/validators/__init__.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validators/base.py` | `docs/research/interrupts/pptx/scripts/office/validators/base.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validators/docx.py` | `docs/research/interrupts/pptx/scripts/office/validators/docx.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validators/pptx.py` | `docs/research/interrupts/pptx/scripts/office/validators/pptx.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/office/validators/redlining.py` | `docs/research/interrupts/pptx/scripts/office/validators/redlining.py` | Interrupt research source |
| `Interrupt research/pptx/scripts/thumbnail.py` | `docs/research/interrupts/pptx/scripts/thumbnail.py` | Interrupt research source |
| `Interrupt research/pptx/SKILL.md` | `docs/research/interrupts/pptx/SKILL.md` | Interrupt research source |
| `Interrupt research/research on implimentations in interrupts.md` | `docs/research/interrupts/research on implimentations in interrupts.md` | Interrupt research source |
| `Interrupt research/RISCFORGE IRQ Arbitration Presentation.html` | `docs/research/interrupts/RISCFORGE IRQ Arbitration Presentation.html` | Interrupt research source |
| `Interrupt research/RISCFORGE SoC Architecture.html` | `docs/research/interrupts/RISCFORGE SoC Architecture.html` | Interrupt research source |
| `Interrupt research/riscforge_soc_architecture.svg` | `docs/research/interrupts/riscforge_soc_architecture.svg` | Interrupt research source |
| `Sw/Makefile` | `docs/software/Makefile` | Software specification/planning |
| `Sw/soc_spec.md` | `docs/software/soc_spec.md` | Software specification/planning |
| `Sw/sw_plan.html` | `docs/software/sw_plan.html` | Software specification/planning |
| `Sw/sw_plan.md` | `docs/software/sw_plan.md` | Software specification/planning |
| `INFRA_TRACKING.md` | `docs/verification/INFRA_TRACKING.md` | Verification status source |
| `Verification/infrastructure/doc/formal_track_brief.md` | `docs/verification/infrastructure/formal_track_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_1_brief.md` | `docs/verification/infrastructure/stage_1_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_2_brief.md` | `docs/verification/infrastructure/stage_2_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_3_brief.md` | `docs/verification/infrastructure/stage_3_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_4_brief.md` | `docs/verification/infrastructure/stage_4_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_5_brief.md` | `docs/verification/infrastructure/stage_5_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_6_brief.md` | `docs/verification/infrastructure/stage_6_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_7_brief.md` | `docs/verification/infrastructure/stage_7_brief.md` | Verification documentation |
| `Verification/infrastructure/doc/stage_8_brief.md` | `docs/verification/infrastructure/stage_8_brief.md` | Verification documentation |
| `SoC Verification Infrastructure_ Integration Guide.html` | `docs/verification/SoC Verification Infrastructure_ Integration Guide.html` | Verification guide |
| `mem_files/gen_flash_image.py` | `memory_images/gen_flash_image.py` | Memory fixture or generator |
| `mem_files/i2c_regtest/build.py` | `memory_images/i2c_regtest/build.py` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest_dmem.hex` | `memory_images/i2c_regtest/i2c_regtest_dmem.hex` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest_flash.mem` | `memory_images/i2c_regtest/i2c_regtest_flash.mem` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest_imem.hex` | `memory_images/i2c_regtest/i2c_regtest_imem.hex` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest_params.svh` | `memory_images/i2c_regtest/i2c_regtest_params.svh` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest.c` | `memory_images/i2c_regtest/i2c_regtest.c` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest.dump` | `memory_images/i2c_regtest/i2c_regtest.dump` | Memory fixture or generator |
| `mem_files/i2c_regtest/i2c_regtest.map` | `memory_images/i2c_regtest/i2c_regtest.map` | Memory fixture or generator |
| `mem_files/i2c_regtest/link.ld` | `memory_images/i2c_regtest/link.ld` | Memory fixture or generator |
| `mem_files/i2c_regtest/README.md` | `memory_images/i2c_regtest/README.md` | Memory fixture or generator |
| `mem_files/i2c_regtest/startup.S` | `memory_images/i2c_regtest/startup.S` | Memory fixture or generator |
| `mem_files/montest/build.py` | `memory_images/montest/build.py` | Memory fixture or generator |
| `mem_files/montest/montest_dmem.hex` | `memory_images/montest/montest_dmem.hex` | Memory fixture or generator |
| `mem_files/montest/montest_flash.mem` | `memory_images/montest/montest_flash.mem` | Memory fixture or generator |
| `mem_files/montest/montest_imem.hex` | `memory_images/montest/montest_imem.hex` | Memory fixture or generator |
| `mem_files/montest/montest_params.svh` | `memory_images/montest/montest_params.svh` | Memory fixture or generator |
| `mem_files/montest/montest.c` | `memory_images/montest/montest.c` | Memory fixture or generator |
| `mem_files/montest/montest.dump` | `memory_images/montest/montest.dump` | Memory fixture or generator |
| `mem_files/montest/montest.map` | `memory_images/montest/montest.map` | Memory fixture or generator |
| `mem_files/regtest/build.py` | `memory_images/regtest/build.py` | Memory fixture or generator |
| `mem_files/regtest/link.ld` | `memory_images/regtest/link.ld` | Memory fixture or generator |
| `mem_files/regtest/regtest_dmem.hex` | `memory_images/regtest/regtest_dmem.hex` | Memory fixture or generator |
| `mem_files/regtest/regtest_flash.mem` | `memory_images/regtest/regtest_flash.mem` | Memory fixture or generator |
| `mem_files/regtest/regtest_imem.hex` | `memory_images/regtest/regtest_imem.hex` | Memory fixture or generator |
| `mem_files/regtest/regtest_params.svh` | `memory_images/regtest/regtest_params.svh` | Memory fixture or generator |
| `mem_files/regtest/regtest.c` | `memory_images/regtest/regtest.c` | Memory fixture or generator |
| `mem_files/regtest/regtest.dump` | `memory_images/regtest/regtest.dump` | Memory fixture or generator |
| `mem_files/regtest/regtest.map` | `memory_images/regtest/regtest.map` | Memory fixture or generator |
| `mem_files/regtest/startup.S` | `memory_images/regtest/startup.S` | Memory fixture or generator |
| `mem_files/riscforge_bootrom.hex` | `memory_images/riscforge_bootrom.hex` | Memory fixture or generator |
| `mem_files/riscforge_timer0_dmem.hex` | `memory_images/riscforge_timer0_dmem.hex` | Memory fixture or generator |
| `mem_files/riscforge_timer0_flash_spi.mem` | `memory_images/riscforge_timer0_flash_spi.mem` | Memory fixture or generator |
| `mem_files/riscforge_timer0_flash.mem` | `memory_images/riscforge_timer0_flash.mem` | Memory fixture or generator |
| `mem_files/riscforge_timer0_test.hex` | `memory_images/riscforge_timer0_test.hex` | Memory fixture or generator |
| `mem_files/timer/riscforge_bootrom.hex` | `memory_images/timer/riscforge_bootrom.hex` | Memory fixture or generator |
| `mem_files/timer/riscforge_timer0_dmem.hex` | `memory_images/timer/riscforge_timer0_dmem.hex` | Memory fixture or generator |
| `mem_files/timer/riscforge_timer0_flash_spi.mem` | `memory_images/timer/riscforge_timer0_flash_spi.mem` | Memory fixture or generator |
| `mem_files/timer/riscforge_timer0_flash.mem` | `memory_images/timer/riscforge_timer0_flash.mem` | Memory fixture or generator |
| `mem_files/timer/riscforge_timer0_test.hex` | `memory_images/timer/riscforge_timer0_test.hex` | Memory fixture or generator |
| `riscv_core/riscforge_soc_subsystem_dut.f` | `rtl/core/riscforge_soc_subsystem_dut.f` | Core RTL/filelist |
| `riscv_core/rtl/ALU_Decoder.v` | `rtl/core/rtl/ALU_Decoder.v` | Core RTL/filelist |
| `riscv_core/rtl/ALU.v` | `rtl/core/rtl/ALU.v` | Core RTL/filelist |
| `riscv_core/rtl/axi_pkg.sv` | `rtl/core/rtl/axi_pkg.sv` | Core RTL/filelist |
| `riscv_core/rtl/booth_enc.v` | `rtl/core/rtl/booth_enc.v` | Core RTL/filelist |
| `riscv_core/rtl/Control_Unit_Top.v` | `rtl/core/rtl/Control_Unit_Top.v` | Core RTL/filelist |
| `riscv_core/rtl/csa.v` | `rtl/core/rtl/csa.v` | Core RTL/filelist |
| `riscv_core/rtl/csr_regfile.v` | `rtl/core/rtl/csr_regfile.v` | Core RTL/filelist |
| `riscv_core/rtl/decode_cycle.v` | `rtl/core/rtl/decode_cycle.v` | Core RTL/filelist |
| `riscv_core/rtl/execute_cycle.v` | `rtl/core/rtl/execute_cycle.v` | Core RTL/filelist |
| `riscv_core/rtl/fetch_cycle.v` | `rtl/core/rtl/fetch_cycle.v` | Core RTL/filelist |
| `riscv_core/rtl/hazard_unit.v` | `rtl/core/rtl/hazard_unit.v` | Core RTL/filelist |
| `riscv_core/rtl/hybrid_mem_interface.sv` | `rtl/core/rtl/hybrid_mem_interface.sv` | Core RTL/filelist |
| `riscv_core/rtl/imem_controller.v` | `rtl/core/rtl/imem_controller.v` | Core RTL/filelist |
| `riscv_core/rtl/irq_arbiter.v` | `rtl/core/rtl/irq_arbiter.v` | Core RTL/filelist |
| `riscv_core/rtl/irq_gateway.v` | `rtl/core/rtl/irq_gateway.v` | Core RTL/filelist |
| `riscv_core/rtl/JB_unit.v` | `rtl/core/rtl/JB_unit.v` | Core RTL/filelist |
| `riscv_core/rtl/ls_unit.v` | `rtl/core/rtl/ls_unit.v` | Core RTL/filelist |
| `riscv_core/rtl/Main_Decoder.v` | `rtl/core/rtl/Main_Decoder.v` | Core RTL/filelist |
| `riscv_core/rtl/memory_cycle.v` | `rtl/core/rtl/memory_cycle.v` | Core RTL/filelist |
| `riscv_core/rtl/Mux_3_by_1.v` | `rtl/core/rtl/Mux_3_by_1.v` | Core RTL/filelist |
| `riscv_core/rtl/Mux2.v` | `rtl/core/rtl/Mux2.v` | Core RTL/filelist |
| `riscv_core/rtl/opcode_check.v` | `rtl/core/rtl/opcode_check.v` | Core RTL/filelist |
| `riscv_core/rtl/PC_Adder.v` | `rtl/core/rtl/PC_Adder.v` | Core RTL/filelist |
| `riscv_core/rtl/PC.v` | `rtl/core/rtl/PC.v` | Core RTL/filelist |
| `riscv_core/rtl/pp_gen.v` | `rtl/core/rtl/pp_gen.v` | Core RTL/filelist |
| `riscv_core/rtl/Register_File.v` | `rtl/core/rtl/Register_File.v` | Core RTL/filelist |
| `riscv_core/rtl/rv32m_div.v` | `rtl/core/rtl/rv32m_div.v` | Core RTL/filelist |
| `riscv_core/rtl/rv32m_mul.v` | `rtl/core/rtl/rv32m_mul.v` | Core RTL/filelist |
| `riscv_core/rtl/rv32m_unit.v` | `rtl/core/rtl/rv32m_unit.v` | Core RTL/filelist |
| `riscv_core/rtl/Sign_Extend.v` | `rtl/core/rtl/Sign_Extend.v` | Core RTL/filelist |
| `riscv_core/rtl/top.v` | `rtl/core/rtl/top.v` | Core RTL/filelist |
| `riscv_core/rtl/wb_trap_mret_commit_controller.v` | `rtl/core/rtl/wb_trap_mret_commit_controller.v` | Core RTL/filelist |
| `riscv_core/rtl/writeback_cycle.v` | `rtl/core/rtl/writeback_cycle.v` | Core RTL/filelist |
| `bootloader/bootloader_32KB_sram.f` | `rtl/ip/bootloader/bootloader_32KB_sram.f` | Bootloader RTL and benches |
| `bootloader/bootloader_tb_all_testcases_32KB_sram.sv` | `rtl/ip/bootloader/bootloader_tb_all_testcases_32KB_sram.sv` | Bootloader RTL and benches |
| `bootloader/bootloader_tb_all_testcases.sv` | `rtl/ip/bootloader/bootloader_tb_all_testcases.sv` | Bootloader RTL and benches |
| `bootloader/bootloader_tb_barebone.sv` | `rtl/ip/bootloader/bootloader_tb_barebone.sv` | Bootloader RTL and benches |
| `bootloader/bootloader_tb_basic.sv` | `rtl/ip/bootloader/bootloader_tb_basic.sv` | Bootloader RTL and benches |
| `bootloader/bootloader_tb.sv` | `rtl/ip/bootloader/bootloader_tb.sv` | Bootloader RTL and benches |
| `bootloader/bootloader.f` | `rtl/ip/bootloader/bootloader.f` | Bootloader RTL and benches |
| `bootloader/bootloader.sv` | `rtl/ip/bootloader/bootloader.sv` | Bootloader RTL and benches |
| `axi_lite_to_apb/axi_lite_to_apb.sv` | `rtl/ip/bridges/axi_lite_to_apb/axi_lite_to_apb.sv` | AXI-Lite to APB bridge |
| `axi_lite_to_apb/axi_pkg.sv` | `rtl/ip/bridges/axi_lite_to_apb/axi_pkg.sv` | AXI-Lite to APB bridge |
| `axi_lite_to_apb/axilite2apb_file.f` | `rtl/ip/bridges/axi_lite_to_apb/axilite2apb_file.f` | AXI-Lite to APB bridge |
| `axi_lite_to_apb/tb_axi_lite_to_apb.sv` | `rtl/ip/bridges/axi_lite_to_apb/tb_axi_lite_to_apb.sv` | AXI-Lite to APB bridge |
| `bus_monitors/apb_timeout_monitor.sv` | `rtl/ip/bus_monitors/apb_timeout_monitor.sv` | Bus monitor RTL |
| `bus_monitors/axi_lite_timeout_monitor.sv` | `rtl/ip/bus_monitors/axi_lite_timeout_monitor.sv` | Bus monitor RTL |
| `axi_lite_xbar/axi_lite_xbar.sv` | `rtl/ip/interconnect/axi_lite_xbar/axi_lite_xbar.sv` | AXI-Lite interconnect |
| `axi_lite_xbar/tb_axi_lite_xbar.sv` | `rtl/ip/interconnect/axi_lite_xbar/tb_axi_lite_xbar.sv` | AXI-Lite interconnect |
| `axi_lite_xbar/xbar_file.f` | `rtl/ip/interconnect/axi_lite_xbar/xbar_file.f` | AXI-Lite interconnect |
| `clic-master/clic_apb.sv` | `rtl/ip/interrupts/clic/clic_apb.sv` | CLIC IP source |
| `clic-master/clic_gateway.sv` | `rtl/ip/interrupts/clic/clic_gateway.sv` | CLIC IP source |
| `clic-master/clic_pkg.sv` | `rtl/ip/interrupts/clic/clic_pkg.sv` | CLIC IP source |
| `clic-master/clic_reg_adapter.sv` | `rtl/ip/interrupts/clic/clic_reg_adapter.sv` | CLIC IP source |
| `clic-master/clic_target.sv` | `rtl/ip/interrupts/clic/clic_target.sv` | CLIC IP source |
| `clic-master/clic.sv` | `rtl/ip/interrupts/clic/clic.sv` | CLIC IP source |
| `clic-master/clicint_reg_pkg.sv` | `rtl/ip/interrupts/clic/clicint_reg_pkg.sv` | CLIC IP source |
| `clic-master/clicint_reg_top.sv` | `rtl/ip/interrupts/clic/clicint_reg_top.sv` | CLIC IP source |
| `clic-master/clicintv_reg_pkg.sv` | `rtl/ip/interrupts/clic/clicintv_reg_pkg.sv` | CLIC IP source |
| `clic-master/clicintv_reg_top.sv` | `rtl/ip/interrupts/clic/clicintv_reg_top.sv` | CLIC IP source |
| `clic-master/clicvs_reg_pkg.sv` | `rtl/ip/interrupts/clic/clicvs_reg_pkg.sv` | CLIC IP source |
| `clic-master/clicvs_reg_top.sv` | `rtl/ip/interrupts/clic/clicvs_reg_top.sv` | CLIC IP source |
| `clic-master/mclic_reg_pkg.sv` | `rtl/ip/interrupts/clic/mclic_reg_pkg.sv` | CLIC IP source |
| `clic-master/mclic_reg_top.sv` | `rtl/ip/interrupts/clic/mclic_reg_top.sv` | CLIC IP source |
| `aon_timer/LICENSE` | `rtl/ip/peripherals/aon_timer/LICENSE` | AON timer IP |
| `aon_timer/rtl/aon_timer_core.sv` | `rtl/ip/peripherals/aon_timer/rtl/aon_timer_core.sv` | AON timer IP |
| `aon_timer/rtl/aon_timer_reg_pkg.sv` | `rtl/ip/peripherals/aon_timer/rtl/aon_timer_reg_pkg.sv` | AON timer IP |
| `aon_timer/rtl/aon_timer_reg_top.sv` | `rtl/ip/peripherals/aon_timer/rtl/aon_timer_reg_top.sv` | AON timer IP |
| `aon_timer/rtl/aon_timer.sv` | `rtl/ip/peripherals/aon_timer/rtl/aon_timer.sv` | AON timer IP |
| `aon_timer/tb_files/prim_alert_receiver.sv` | `rtl/ip/peripherals/aon_timer/tb_files/prim_alert_receiver.sv` | AON timer IP |
| `aon_timer/tb_watchdog_full.f` | `rtl/ip/peripherals/aon_timer/tb_watchdog_full.f` | AON timer IP |
| `aon_timer/tb_watchdog_full.sv` | `rtl/ip/peripherals/aon_timer/tb_watchdog_full.sv` | AON timer IP |
| `aon_timer/tb_watchdog.f` | `rtl/ip/peripherals/aon_timer/tb_watchdog.f` | AON timer IP |
| `aon_timer/tb_watchdog.sv` | `rtl/ip/peripherals/aon_timer/tb_watchdog.sv` | AON timer IP |
| `gpio-master/gpio_apb_wrap.sv` | `rtl/ip/peripherals/gpio/gpio_apb_wrap.sv` | GPIO IP and block verification |
| `gpio-master/gpio_axi_lite_wrap.sv` | `rtl/ip/peripherals/gpio/gpio_axi_lite_wrap.sv` | GPIO IP and block verification |
| `gpio-master/gpio_input_stage_no_clk_gates.sv` | `rtl/ip/peripherals/gpio/gpio_input_stage_no_clk_gates.sv` | GPIO IP and block verification |
| `gpio-master/gpio_input_stage.sv` | `rtl/ip/peripherals/gpio/gpio_input_stage.sv` | GPIO IP and block verification |
| `gpio-master/gpio_lint_top.sv` | `rtl/ip/peripherals/gpio/gpio_lint_top.sv` | GPIO IP and block verification |
| `gpio-master/gpio_lint.f` | `rtl/ip/peripherals/gpio/gpio_lint.f` | GPIO IP and block verification |
| `gpio-master/gpio_reg_pkg.sv` | `rtl/ip/peripherals/gpio/gpio_reg_pkg.sv` | GPIO IP and block verification |
| `gpio-master/gpio_reg_top.sv` | `rtl/ip/peripherals/gpio/gpio_reg_top.sv` | GPIO IP and block verification |
| `gpio-master/gpio.sv` | `rtl/ip/peripherals/gpio/gpio.sv` | GPIO IP and block verification |
| `gpio-master/lint.tcl` | `rtl/ip/peripherals/gpio/lint.tcl` | GPIO IP and block verification |
| `gpio-master/reports/gpio_superlint_all_domains.txt` | `rtl/ip/peripherals/gpio/reports/gpio_superlint_all_domains.txt` | GPIO IP and block verification |
| `gpio-master/reports/gpio_superlint_lint.txt` | `rtl/ip/peripherals/gpio/reports/gpio_superlint_lint.txt` | GPIO IP and block verification |
| `gpio-master/reports/gpio_superlint_violations.txt` | `rtl/ip/peripherals/gpio/reports/gpio_superlint_violations.txt` | GPIO IP and block verification |
| `gpio-master/tb_gpio_apb_directed.f` | `rtl/ip/peripherals/gpio/tb_gpio_apb_directed.f` | GPIO IP and block verification |
| `gpio-master/tb_gpio_apb_directed.sv` | `rtl/ip/peripherals/gpio/tb_gpio_apb_directed.sv` | GPIO IP and block verification |
| `gpio-master/tb_gpio.sv` | `rtl/ip/peripherals/gpio/tb_gpio.sv` | GPIO IP and block verification |
| `apb_i2c-master/apb_i2c.sv` | `rtl/ip/peripherals/i2c/apb_i2c.sv` | I2C IP/test source |
| `apb_i2c-master/directed_tb.sv` | `rtl/ip/peripherals/i2c/directed_tb.sv` | I2C IP/test source |
| `apb_i2c-master/directed.log.txt` | `rtl/ip/peripherals/i2c/directed.log.txt` | I2C IP/test source |
| `apb_i2c-master/files_thorough_tb.f` | `rtl/ip/peripherals/i2c/files_thorough_tb.f` | I2C IP/test source |
| `apb_i2c-master/files.f` | `rtl/ip/peripherals/i2c/files.f` | I2C IP/test source |
| `apb_i2c-master/i2c_master_bit_ctrl.sv` | `rtl/ip/peripherals/i2c/i2c_master_bit_ctrl.sv` | I2C IP/test source |
| `apb_i2c-master/i2c_master_byte_ctrl.sv` | `rtl/ip/peripherals/i2c/i2c_master_byte_ctrl.sv` | I2C IP/test source |
| `apb_i2c-master/i2c_master_defines.sv` | `rtl/ip/peripherals/i2c/i2c_master_defines.sv` | I2C IP/test source |
| `apb_i2c-master/i2c_thorough_tb.sv` | `rtl/ip/peripherals/i2c/i2c_thorough_tb.sv` | I2C IP/test source |
| `apb_i2c-master/src_files.yml` | `rtl/ip/peripherals/i2c/src_files.yml` | I2C IP/test source |
| `spi_master_ip/extra/apb_spi_verification.pdf.lnk` | `rtl/ip/peripherals/spi/extra/apb_spi_verification.pdf.lnk` | SPI IP and tool collateral |
| `spi_master_ip/extra/bootloader_implementation_ideas.md` | `rtl/ip/peripherals/spi/extra/bootloader_implementation_ideas.md` | SPI IP and tool collateral |
| `spi_master_ip/extra/BUG/BUFFER ELEMENT VALID POINTER.png` | `rtl/ip/peripherals/spi/extra/BUG/BUFFER ELEMENT VALID POINTER.png` | SPI IP and tool collateral |
| `spi_master_ip/extra/BUG/PREADY PRDATA .png` | `rtl/ip/peripherals/spi/extra/BUG/PREADY PRDATA .png` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs.zip` | `rtl/ip/peripherals/spi/extra/docs.zip` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch01_overview.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch01_overview.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch02_ip_architecture.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch02_ip_architecture.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch03_testbench_architecture.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch03_testbench_architecture.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch04_how_to_use.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch04_how_to_use.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch05_testcase_coverage.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch05_testcase_coverage.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch06_detailed_testcases.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch06_detailed_testcases.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch07_debugging.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch07_debugging.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch08_observation.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch08_observation.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch09_final_results.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch09_final_results.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch10_apb_peripheral_guide.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch10_apb_peripheral_guide.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/chapters/ch11_appendix.tex` | `rtl/ip/peripherals/spi/extra/docs/chapters/ch11_appendix.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/docs/main.tex` | `rtl/ip/peripherals/spi/extra/docs/main.tex` | SPI IP and tool collateral |
| `spi_master_ip/extra/spi_ports.png` | `rtl/ip/peripherals/spi/extra/spi_ports.png` | SPI IP and tool collateral |
| `spi_master_ip/jg/cdc.tcl` | `rtl/ip/peripherals/spi/jg/cdc.tcl` | SPI IP and tool collateral |
| `spi_master_ip/jg/jg_file.f` | `rtl/ip/peripherals/spi/jg/jg_file.f` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/autosave_jqOxeO.db` | `rtl/ip/peripherals/spi/jg/jgproject/autosave_jqOxeO.db` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/autosave_yUKBeQ.db` | `rtl/ip/peripherals/spi/jg/jgproject/autosave_yUKBeQ.db` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/bridge.log.bak` | `rtl/ip/peripherals/spi/jg/jgproject/bridge.log.bak` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/jg_console.log.bak` | `rtl/ip/peripherals/spi/jg/jgproject/jg_console.log.bak` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/jg.cmd` | `rtl/ip/peripherals/spi/jg/jgproject/jg.cmd` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/settings/filterconfigs.xml` | `rtl/ip/peripherals/spi/jg/jgproject/settings/filterconfigs.xml` | SPI IP and tool collateral |
| `spi_master_ip/jg/jgproject/settings/windowlayout.conf` | `rtl/ip/peripherals/spi/jg/jgproject/settings/windowlayout.conf` | SPI IP and tool collateral |
| `spi_master_ip/jg/lint.tcl` | `rtl/ip/peripherals/spi/jg/lint.tcl` | SPI IP and tool collateral |
| `spi_master_ip/jg/reports/cdc_violations_detailed.txt` | `rtl/ip/peripherals/spi/jg/reports/cdc_violations_detailed.txt` | SPI IP and tool collateral |
| `spi_master_ip/jg/reports/cdc_violations.txt` | `rtl/ip/peripherals/spi/jg/reports/cdc_violations.txt` | SPI IP and tool collateral |
| `spi_master_ip/jg/reports/superlint_violations.txt` | `rtl/ip/peripherals/spi/jg/reports/superlint_violations.txt` | SPI IP and tool collateral |
| `spi_master_ip/jg/superlint_report.txt` | `rtl/ip/peripherals/spi/jg/superlint_report.txt` | SPI IP and tool collateral |
| `spi_master_ip/reports/cdc_violations_detailed.txt` | `rtl/ip/peripherals/spi/reports/cdc_violations_detailed.txt` | SPI IP and tool collateral |
| `spi_master_ip/reports/cdc_violations.txt` | `rtl/ip/peripherals/spi/reports/cdc_violations.txt` | SPI IP and tool collateral |
| `spi_master_ip/reports/superlint_violations.txt` | `rtl/ip/peripherals/spi/reports/superlint_violations.txt` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/apb_spi_master.sv` | `rtl/ip/peripherals/spi/spi_master/apb_spi_master.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/instr.mem` | `rtl/ip/peripherals/spi/spi_master/instr.mem` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/prev TB and BFM used/spi_bfm.sv` | `rtl/ip/peripherals/spi/spi_master/prev TB and BFM used/spi_bfm.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/prev TB and BFM used/spi_master_m_bfm_mem_tb.sv` | `rtl/ip/peripherals/spi/spi_master/prev TB and BFM used/spi_master_m_bfm_mem_tb.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/prev TB and BFM used/spi_master_m_bfm_tb_o.sv` | `rtl/ip/peripherals/spi/spi_master/prev TB and BFM used/spi_master_m_bfm_tb_o.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/prev TB and BFM used/spi_master_tb_v2.sv` | `rtl/ip/peripherals/spi/spi_master/prev TB and BFM used/spi_master_tb_v2.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/prev TB and BFM used/spi_slave_bfm.sv` | `rtl/ip/peripherals/spi/spi_master/prev TB and BFM used/spi_slave_bfm.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_file.f` | `rtl/ip/peripherals/spi/spi_master/spi_file.f` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_apb_if.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_apb_if.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_clkgen.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_clkgen.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_controller.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_controller.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_fifo.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_fifo.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_m_bfm_tb.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_m_bfm_tb.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_rx.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_rx.sv` | SPI IP and tool collateral |
| `spi_master_ip/spi_master/spi_master_tx.sv` | `rtl/ip/peripherals/spi/spi_master/spi_master_tx.sv` | SPI IP and tool collateral |
| `apb_timer-master/apb_timer_verif_doc.pdf` | `rtl/ip/peripherals/timer/apb_timer_verif_doc.pdf` | Timer RTL/filelist/docs |
| `apb_timer-master/apb_timer.sv` | `rtl/ip/peripherals/timer/apb_timer.sv` | Timer RTL/filelist/docs |
| `apb_timer-master/files.f` | `rtl/ip/peripherals/timer/files.f` | Timer RTL/filelist/docs |
| `apb_timer-master/rtl/apb_timer.sv` | `rtl/ip/peripherals/timer/rtl/apb_timer.sv` | Timer RTL/filelist/docs |
| `apb_timer-master/rtl/timer.sv` | `rtl/ip/peripherals/timer/rtl/timer.sv` | Timer RTL/filelist/docs |
| `apb_timer-master/timer.sv` | `rtl/ip/peripherals/timer/timer.sv` | Timer RTL/filelist/docs |
| `apb_uart-main/rtl/apb_uart_wrap.sv` | `rtl/ip/peripherals/uart/rtl/apb_uart_wrap.sv` | UART RTL/filelist |
| `apb_uart-main/rtl/apb_uart.sv` | `rtl/ip/peripherals/uart/rtl/apb_uart.sv` | UART RTL/filelist |
| `apb_uart-main/rtl/reg_uart_wrap.sv` | `rtl/ip/peripherals/uart/rtl/reg_uart_wrap.sv` | UART RTL/filelist |
| `apb_uart-main/rtl/tb_apb_uart_thorough.sv` | `rtl/ip/peripherals/uart/rtl/tb_apb_uart_thorough.sv` | UART RTL/filelist |
| `apb_uart-main/rtl/tb_apb_uart.sv` | `rtl/ip/peripherals/uart/rtl/tb_apb_uart.sv` | UART RTL/filelist |
| `apb_uart-main/uart.f` | `rtl/ip/peripherals/uart/uart.f` | UART RTL/filelist |
| `RTL_SOC/axi_lite_sram_if.sv` | `rtl/soc/axi_lite_sram_if.sv` | SoC RTL source |
| `RTL_SOC/boot_rom.sv` | `rtl/soc/boot_rom.sv` | SoC RTL source |
| `RTL_SOC/imem_sram_wrapper.sv` | `rtl/soc/imem_sram_wrapper.sv` | SoC RTL source |
| `RTL_SOC/instr_fetch_demux.sv` | `rtl/soc/instr_fetch_demux.sv` | SoC RTL source |
| `RTL_SOC/riscforge_soc_subsystem.sv` | `rtl/soc/riscforge_soc_subsystem.sv` | SoC RTL source |
| `RTL_SOC/riscv_core_stub.sv` | `rtl/soc/riscv_core_stub.sv` | SoC RTL source |
| `RTL_SOC/sram_mux.sv` | `rtl/soc/sram_mux.sv` | SoC RTL source |
| `RTL_SOC/sram_sp.sv` | `rtl/soc/sram_sp.sv` | SoC RTL source |
| `Sw/bsp/crt0.S` | `software/bsp/crt0.S` | Software BSP source |
| `Sw/bsp/link.ld` | `software/bsp/link.ld` | Software BSP source |
| `Sw/bsp/soc_regs.h` | `software/bsp/soc_regs.h` | Software BSP source |
| `Sw/bsp/uart_min.h` | `software/bsp/uart_min.h` | Software BSP source |
| `Sw/tests/datapath_smoke_test.s` | `software/tests/datapath_smoke_test.s` | Software test source |
| `Sw/tests/uart_smoke_test.c` | `software/tests/uart_smoke_test.c` | Software test source |
| `jaspergold/jg_soc.f` | `tools/eda/jaspergold/jg_soc.f` | JasperGold flow source |
| `jaspergold/lint.tcl` | `tools/eda/jaspergold/lint.tcl` | JasperGold flow source |
| `jaspergold/run_jaspergold.ps1` | `tools/eda/jaspergold/run_jaspergold.ps1` | JasperGold flow source |
| `jaspergold/run_jaspergold.sh` | `tools/eda/jaspergold/run_jaspergold.sh` | JasperGold flow source |
| `spyglass/boot_mechanism_comb_loop.md` | `tools/eda/spyglass/boot_mechanism_comb_loop.md` | SpyGlass flow source |
| `spyglass/run_spyglass.ps1` | `tools/eda/spyglass/run_spyglass.ps1` | SpyGlass flow source |
| `spyglass/run_spyglass.sh` | `tools/eda/spyglass/run_spyglass.sh` | SpyGlass flow source |
| `spyglass/run_spyglass.tcl` | `tools/eda/spyglass/run_spyglass.tcl` | SpyGlass flow source |
| `spyglass/spyglass.prj` | `tools/eda/spyglass/spyglass.prj` | SpyGlass flow source |
| `Sw/tools/elf_to_hex.py` | `tools/software/elf_to_hex.py` | Software build tool |
| `datapath_verification/i2c0/crt0.S` | `verification/datapath/i2c0/crt0.S` | Datapath test source/evidence |
| `datapath_verification/i2c0/datapath_diagnostics_and_fixes.md` | `verification/datapath/i2c0/datapath_diagnostics_and_fixes.md` | Datapath test source/evidence |
| `datapath_verification/i2c0/design_overview_and_test_report.md` | `verification/datapath/i2c0/design_overview_and_test_report.md` | Datapath test source/evidence |
| `datapath_verification/i2c0/dmem.hex` | `verification/datapath/i2c0/dmem.hex` | Datapath test source/evidence |
| `datapath_verification/i2c0/elf_to_hex.py` | `verification/datapath/i2c0/elf_to_hex.py` | Datapath test source/evidence |
| `datapath_verification/i2c0/i2c_min.h` | `verification/datapath/i2c0/i2c_min.h` | Datapath test source/evidence |
| `datapath_verification/i2c0/i2c_smoke_test.c` | `verification/datapath/i2c0/i2c_smoke_test.c` | Datapath test source/evidence |
| `datapath_verification/i2c0/imem.hex` | `verification/datapath/i2c0/imem.hex` | Datapath test source/evidence |
| `datapath_verification/i2c0/link.ld` | `verification/datapath/i2c0/link.ld` | Datapath test source/evidence |
| `datapath_verification/i2c0/Makefile` | `verification/datapath/i2c0/Makefile` | Datapath test source/evidence |
| `datapath_verification/i2c0/run_tb.ps1` | `verification/datapath/i2c0/run_tb.ps1` | Datapath test source/evidence |
| `datapath_verification/i2c0/soc_i2c_verification_report.html` | `verification/datapath/i2c0/soc_i2c_verification_report.html` | Datapath test source/evidence |
| `datapath_verification/i2c0/tb_i2c0.f` | `verification/datapath/i2c0/tb_i2c0.f` | Datapath test source/evidence |
| `datapath_verification/i2c0/tb_i2c0.sv` | `verification/datapath/i2c0/tb_i2c0.sv` | Datapath test source/evidence |
| `datapath_verification/spi0/app.dis` | `verification/datapath/spi0/app.dis` | Datapath test source/evidence |
| `datapath_verification/spi0/crt0.S` | `verification/datapath/spi0/crt0.S` | Datapath test source/evidence |
| `datapath_verification/spi0/datapath_diagnostics_and_fixes.md` | `verification/datapath/spi0/datapath_diagnostics_and_fixes.md` | Datapath test source/evidence |
| `datapath_verification/spi0/design_overview_and_test_report.md` | `verification/datapath/spi0/design_overview_and_test_report.md` | Datapath test source/evidence |
| `datapath_verification/spi0/dmem.hex` | `verification/datapath/spi0/dmem.hex` | Datapath test source/evidence |
| `datapath_verification/spi0/elf_to_hex.py` | `verification/datapath/spi0/elf_to_hex.py` | Datapath test source/evidence |
| `datapath_verification/spi0/imem.hex` | `verification/datapath/spi0/imem.hex` | Datapath test source/evidence |
| `datapath_verification/spi0/link.ld` | `verification/datapath/spi0/link.ld` | Datapath test source/evidence |
| `datapath_verification/spi0/Makefile` | `verification/datapath/spi0/Makefile` | Datapath test source/evidence |
| `datapath_verification/spi0/run_tb.ps1` | `verification/datapath/spi0/run_tb.ps1` | Datapath test source/evidence |
| `datapath_verification/spi0/soc_spi_verification_report.html` | `verification/datapath/spi0/soc_spi_verification_report.html` | Datapath test source/evidence |
| `datapath_verification/spi0/spi_min.h` | `verification/datapath/spi0/spi_min.h` | Datapath test source/evidence |
| `datapath_verification/spi0/spi_smoke_test.c` | `verification/datapath/spi0/spi_smoke_test.c` | Datapath test source/evidence |
| `datapath_verification/spi0/tb_spi0.f` | `verification/datapath/spi0/tb_spi0.f` | Datapath test source/evidence |
| `datapath_verification/spi0/tb_spi0.sv` | `verification/datapath/spi0/tb_spi0.sv` | Datapath test source/evidence |
| `datapath_verification/UART0/app.dis` | `verification/datapath/UART0/app.dis` | Datapath test source/evidence |
| `datapath_verification/UART0/crt0.S` | `verification/datapath/UART0/crt0.S` | Datapath test source/evidence |
| `datapath_verification/UART0/datapath_diagnostics_and_fixes.md` | `verification/datapath/UART0/datapath_diagnostics_and_fixes.md` | Datapath test source/evidence |
| `datapath_verification/UART0/design_overview_and_test_report.md` | `verification/datapath/UART0/design_overview_and_test_report.md` | Datapath test source/evidence |
| `datapath_verification/UART0/dmem.hex` | `verification/datapath/UART0/dmem.hex` | Datapath test source/evidence |
| `datapath_verification/UART0/elf_to_hex.py` | `verification/datapath/UART0/elf_to_hex.py` | Datapath test source/evidence |
| `datapath_verification/UART0/imem.hex` | `verification/datapath/UART0/imem.hex` | Datapath test source/evidence |
| `datapath_verification/UART0/link.ld` | `verification/datapath/UART0/link.ld` | Datapath test source/evidence |
| `datapath_verification/UART0/Makefile` | `verification/datapath/UART0/Makefile` | Datapath test source/evidence |
| `datapath_verification/UART0/run_tb.ps1` | `verification/datapath/UART0/run_tb.ps1` | Datapath test source/evidence |
| `datapath_verification/UART0/soc_datapath_verification_report.html` | `verification/datapath/UART0/soc_datapath_verification_report.html` | Datapath test source/evidence |
| `datapath_verification/UART0/tb_uart0.f` | `verification/datapath/UART0/tb_uart0.f` | Datapath test source/evidence |
| `datapath_verification/UART0/tb_uart0.sv` | `verification/datapath/UART0/tb_uart0.sv` | Datapath test source/evidence |
| `datapath_verification/UART0/uart_min.h` | `verification/datapath/UART0/uart_min.h` | Datapath test source/evidence |
| `datapath_verification/UART0/uart_smoke_test.c` | `verification/datapath/UART0/uart_smoke_test.c` | Datapath test source/evidence |
| `Verification/regression/build_stages.sh` | `verification/regression/build_stages.sh` | Regression automation |
| `Verification/regression/dump_session.py` | `verification/regression/dump_session.py` | Regression automation |
| `Verification/regression/elf_to_hex_clean.py` | `verification/regression/elf_to_hex_clean.py` | Regression automation |
| `Verification/regression/launch_opencode_verifier.py` | `verification/regression/launch_opencode_verifier.py` | Regression automation |
| `Verification/regression/run_regression.ps1` | `verification/regression/run_regression.ps1` | Regression automation |
| `Verification/infrastructure/fix_filelist.py` | `verification/scripts/fix_filelist.py` | Verification runner/tool |
| `Verification/infrastructure/gen_filelists.py` | `verification/scripts/gen_filelists.py` | Verification runner/tool |
| `Verification/infrastructure/run_freeze_stress.ps1` | `verification/scripts/run_freeze_stress.ps1` | Verification runner/tool |
| `Verification/infrastructure/run_rf_mon_challenge.ps1` | `verification/scripts/run_rf_mon_challenge.ps1` | Verification runner/tool |
| `Verification/infrastructure/run_rf_mon_smoke.ps1` | `verification/scripts/run_rf_mon_smoke.ps1` | Verification runner/tool |
| `Verification/infrastructure/checkers/apb_protocol_sva.sv` | `verification/soc/checkers/apb_protocol_sva.sv` | SoC checker |
| `Verification/infrastructure/checkers/axi_lite_protocol_sva.sv` | `verification/soc/checkers/axi_lite_protocol_sva.sv` | SoC checker |
| `Verification/infrastructure/checkers/failure_reporter.sv` | `verification/soc/checkers/failure_reporter.sv` | SoC checker |
| `Verification/infrastructure/checkers/irq_predictor.sv` | `verification/soc/checkers/irq_predictor.sv` | SoC checker |
| `Verification/infrastructure/checkers/mmio_path_scoreboard.sv` | `verification/soc/checkers/mmio_path_scoreboard.sv` | SoC checker |
| `Verification/infrastructure/checkers/register_predictor.sv` | `verification/soc/checkers/register_predictor.sv` | SoC checker |
| `Verification/infrastructure/freeze_stress.f` | `verification/soc/filelists/freeze_stress.f` | Verification filelist/configuration |
| `Verification/infrastructure/rf_mon_challenge.f` | `verification/soc/filelists/rf_mon_challenge.f` | Verification filelist/configuration |
| `Verification/infrastructure/rf_mon_smoke.f` | `verification/soc/filelists/rf_mon_smoke.f` | Verification filelist/configuration |
| `RTL_SOC/soc_i2c_regtest.f` | `verification/soc/filelists/soc_i2c_regtest.f` | SoC source filelist |
| `RTL_SOC/soc_i2c_tb.f` | `verification/soc/filelists/soc_i2c_tb.f` | SoC source filelist |
| `RTL_SOC/soc_imem_boot_vendor.f` | `verification/soc/filelists/soc_imem_boot_vendor.f` | SoC source filelist |
| `RTL_SOC/soc_imem_boot.f` | `verification/soc/filelists/soc_imem_boot.f` | SoC source filelist |
| `RTL_SOC/soc_montest.f` | `verification/soc/filelists/soc_montest.f` | SoC source filelist |
| `RTL_SOC/soc_regtest.f` | `verification/soc/filelists/soc_regtest.f` | SoC source filelist |
| `RTL_SOC/soc_spi_tb.f` | `verification/soc/filelists/soc_spi_tb.f` | SoC source filelist |
| `RTL_SOC/soc_subsystem_vcs.f` | `verification/soc/filelists/soc_subsystem_vcs.f` | SoC source filelist |
| `RTL_SOC/soc_subsystem.f` | `verification/soc/filelists/soc_subsystem.f` | SoC source filelist |
| `RTL_SOC/soc_timer0_boot_run.f` | `verification/soc/filelists/soc_timer0_boot_run.f` | SoC source filelist |
| `RTL_SOC/soc_uart0_tb.f` | `verification/soc/filelists/soc_uart0_tb.f` | SoC source filelist |
| `Verification/infrastructure/soc_verification.esi.f` | `verification/soc/filelists/soc_verification.esi.f` | Verification filelist/configuration |
| `Verification/infrastructure/soc_verification.f` | `verification/soc/filelists/soc_verification.f` | Verification filelist/configuration |
| `Verification/infrastructure/soc_verification.prj` | `verification/soc/filelists/soc_verification.prj` | Verification filelist/configuration |
| `Verification/infrastructure/soc_verification.xsim.f` | `verification/soc/filelists/soc_verification.xsim.f` | Verification filelist/configuration |
| `vivado_soc.f` | `verification/soc/filelists/vivado_soc.f` | SoC filelist |
| `Verification/infrastructure/monitors/apb_monitor.sv` | `verification/soc/monitors/apb_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/axi_lite_monitor.sv` | `verification/soc/monitors/axi_lite_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/fetch_monitor.sv` | `verification/soc/monitors/fetch_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/irq_monitor.sv` | `verification/soc/monitors/irq_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/lsu_monitor.sv` | `verification/soc/monitors/lsu_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/retire_monitor.sv` | `verification/soc/monitors/retire_monitor.sv` | SoC monitor |
| `Verification/infrastructure/monitors/rf_monitor_env.sv` | `verification/soc/monitors/rf_monitor_env.sv` | SoC monitor |
| `Verification/infrastructure/monitors/rf_monitors.sv` | `verification/soc/monitors/rf_monitors.sv` | SoC monitor |
| `Verification/infrastructure/tb/rf_mon_challenger_dut.sv` | `verification/soc/tb/rf_mon_challenger_dut.sv` | SoC verification source |
| `Verification/infrastructure/tb/rf_mon_empirical_challenge_tb.sv` | `verification/soc/tb/rf_mon_empirical_challenge_tb.sv` | SoC verification source |
| `Verification/infrastructure/tb/rf_mon_probe.sv` | `verification/soc/tb/rf_mon_probe.sv` | SoC verification source |
| `Verification/infrastructure/tb/rf_mon_smoke_tb.sv` | `verification/soc/tb/rf_mon_smoke_tb.sv` | SoC verification source |
| `Verification/infrastructure/tb/rf_mon_stub_dut.sv` | `verification/soc/tb/rf_mon_stub_dut.sv` | SoC verification source |
| `Verification/infrastructure/tb/rf_monitor_if.sv` | `verification/soc/tb/rf_monitor_if.sv` | SoC verification source |
| `Verification/infrastructure/tb/soc_gpio_aperture_tb.sv` | `verification/soc/tb/soc_gpio_aperture_tb.sv` | SoC verification source |
| `Verification/infrastructure/tb/soc_tb_top.sv` | `verification/soc/tb/soc_tb_top.sv` | SoC verification source |
| `Verification/infrastructure/tb/sram_sp_component_tb.sv` | `verification/soc/tb/sram_sp_component_tb.sv` | SoC verification source |
| `Verification/infrastructure/tb/tb_apb_timeout_monitor.sv` | `verification/soc/tb/tb_apb_timeout_monitor.sv` | SoC verification source |
| `Verification/infrastructure/tb/tb_freeze_buffer_stress.sv` | `verification/soc/tb/tb_freeze_buffer_stress.sv` | SoC verification source |
| `Verification/infrastructure/tb/tb_pkg.sv` | `verification/soc/tb/tb_pkg.sv` | SoC verification source |
| `Verification/asm/link.ld` | `verification/soc/tests/asm/link.ld` | Assembly test source |
| `Verification/asm/test1_timer.S` | `verification/soc/tests/asm/test1_timer.S` | Assembly test source |
| `Verification/asm/test2_all_sources.S` | `verification/soc/tests/asm/test2_all_sources.S` | Assembly test source |
| `Verification/asm/test3_priority.S` | `verification/soc/tests/asm/test3_priority.S` | Assembly test source |
| `Verification/asm/test4_mintprio.S` | `verification/soc/tests/asm/test4_mintprio.S` | Assembly test source |
| `Verification/asm/test5_hazard.S` | `verification/soc/tests/asm/test5_hazard.S` | Assembly test source |
| `Verification/asm/test6_collision.S` | `verification/soc/tests/asm/test6_collision.S` | Assembly test source |
| `Verification/asm/test7_mret.S` | `verification/soc/tests/asm/test7_mret.S` | Assembly test source |
| `Verification/compile_asm.py` | `verification/soc/tests/compile_asm.py` | Verification source or runner |
| `Verification/gen_tb1_hex.py` | `verification/soc/tests/gen_tb1_hex.py` | Verification source or runner |
| `Verification/Makefile` | `verification/soc/tests/Makefile` | Verification source or runner |
| `Verification/run_tb1.ps1` | `verification/soc/tests/run_tb1.ps1` | Verification source or runner |
| `Verification/run_vcs.sh` | `verification/soc/tests/run_vcs.sh` | Verification source or runner |
| `RTL_SOC/soc_i2c_regtest_tb.sv` | `verification/soc/tests/soc_i2c_regtest_tb.sv` | SoC testbench |
| `RTL_SOC/soc_imem_boot_tb.sv` | `verification/soc/tests/soc_imem_boot_tb.sv` | SoC testbench |
| `RTL_SOC/soc_imem_boot_vendor_tb.sv` | `verification/soc/tests/soc_imem_boot_vendor_tb.sv` | SoC testbench |
| `RTL_SOC/soc_montest_tb.sv` | `verification/soc/tests/soc_montest_tb.sv` | SoC testbench |
| `RTL_SOC/soc_regtest_tb.sv` | `verification/soc/tests/soc_regtest_tb.sv` | SoC testbench |
| `RTL_SOC/soc_timer0_boot_run_tb.sv` | `verification/soc/tests/soc_timer0_boot_run_tb.sv` | SoC testbench |
| `Verification/tb1_interrupts.f` | `verification/soc/tests/tb1_interrupts.f` | Verification source or runner |
| `Verification/tb1_interrupts.sv` | `verification/soc/tests/tb1_interrupts.sv` | Verification source or runner |
| `Verification/infrastructure/vip/gpio_pin_vip.sv` | `verification/soc/vip/gpio_pin_vip.sv` | SoC verification source |
| `Verification/infrastructure/vip/i2c_eeprom_at24c02.sv` | `verification/soc/vip/i2c_eeprom_at24c02.sv` | SoC verification source |
| `Verification/infrastructure/vip/spi_flash_s25fs512s.sv` | `verification/soc/vip/spi_flash_s25fs512s.sv` | SoC verification source |
| `Verification/infrastructure/vip/uart_pin_vip.sv` | `verification/soc/vip/uart_pin_vip.sv` | SoC verification source |
| `Verification/tests/bsp/crt0.s` | `verification/software/bsp/crt0.s` | Verification BSP source |
| `Verification/tests/bsp/isr_dispatch.c` | `verification/software/bsp/isr_dispatch.c` | Verification BSP source |
| `Verification/tests/bsp/isr_dispatch.h` | `verification/software/bsp/isr_dispatch.h` | Verification BSP source |
| `Verification/tests/bsp/link.ld` | `verification/software/bsp/link.ld` | Verification BSP source |
| `Verification/tests/bsp/mailbox.h` | `verification/software/bsp/mailbox.h` | Verification BSP source |
| `Verification/tests/bsp/proof_activity.c` | `verification/software/bsp/proof_activity.c` | Verification BSP source |
| `Verification/tests/bsp/proof_activity.h` | `verification/software/bsp/proof_activity.h` | Verification BSP source |
| `Verification/tests/bsp/soc_regs.h` | `verification/software/bsp/soc_regs.h` | Verification BSP source |
| `Verification/tests/bsp/test_harness.h` | `verification/software/bsp/test_harness.h` | Verification BSP source |
| `Verification/tests/bsp/trap_handler.s` | `verification/software/bsp/trap_handler.s` | Verification BSP source |
| `Verification/tests/drivers/gpio_driver.c` | `verification/software/drivers/gpio_driver.c` | Verification driver source |
| `Verification/tests/drivers/gpio_driver.h` | `verification/software/drivers/gpio_driver.h` | Verification driver source |
| `Verification/tests/drivers/i2c_driver.c` | `verification/software/drivers/i2c_driver.c` | Verification driver source |
| `Verification/tests/drivers/i2c_driver.h` | `verification/software/drivers/i2c_driver.h` | Verification driver source |
| `Verification/tests/drivers/spi_driver.c` | `verification/software/drivers/spi_driver.c` | Verification driver source |
| `Verification/tests/drivers/spi_driver.h` | `verification/software/drivers/spi_driver.h` | Verification driver source |
| `Verification/tests/drivers/timer_driver.c` | `verification/software/drivers/timer_driver.c` | Verification driver source |
| `Verification/tests/drivers/timer_driver.h` | `verification/software/drivers/timer_driver.h` | Verification driver source |
| `Verification/tests/drivers/uart_driver.c` | `verification/software/drivers/uart_driver.c` | Verification driver source |
| `Verification/tests/drivers/uart_driver.h` | `verification/software/drivers/uart_driver.h` | Verification driver source |
| `Verification/tests/suites/MILESTONE5_FINDINGS.md` | `verification/software/suites/MILESTONE5_FINDINGS.md` | Firmware test suite |
| `Verification/tests/suites/stage1_hello/main.c` | `verification/software/suites/stage1_hello/main.c` | Firmware test suite |
| `Verification/tests/suites/stage2_watchdog/main.c` | `verification/software/suites/stage2_watchdog/main.c` | Firmware test suite |
| `Verification/tests/suites/stage3_monitor_count/main.c` | `verification/software/suites/stage3_monitor_count/main.c` | Firmware test suite |
| `Verification/tests/suites/stage4_fault_inject/main.c` | `verification/software/suites/stage4_fault_inject/main.c` | Firmware test suite |
| `Verification/tests/suites/stage5_reg_sweep/main.c` | `verification/software/suites/stage5_reg_sweep/main.c` | Firmware test suite |
| `Verification/tests/suites/stage6_polled_periph/main.c` | `verification/software/suites/stage6_polled_periph/main.c` | Firmware test suite |
| `Verification/tests/suites/stage7_nested_irq/main.c` | `verification/software/suites/stage7_nested_irq/main.c` | Firmware test suite |
| `apb_timer-master/tb/apb_timer_agent.sv` | `verification/unit/timer/apb_timer_agent.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_assertions.sv` | `verification/unit/timer/apb_timer_assertions.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_coverage.sv` | `verification/unit/timer/apb_timer_coverage.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_driver.sv` | `verification/unit/timer/apb_timer_driver.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_env.sv` | `verification/unit/timer/apb_timer_env.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_if.sv` | `verification/unit/timer/apb_timer_if.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_monitor.sv` | `verification/unit/timer/apb_timer_monitor.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_pkg.sv` | `verification/unit/timer/apb_timer_pkg.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_scoreboard.sv` | `verification/unit/timer/apb_timer_scoreboard.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_sequencer.sv` | `verification/unit/timer/apb_timer_sequencer.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_sequences.sv` | `verification/unit/timer/apb_timer_sequences.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_tb.sv` | `verification/unit/timer/apb_timer_tb.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_test.sv` | `verification/unit/timer/apb_timer_test.sv` | Timer unit verification |
| `apb_timer-master/tb/apb_timer_txn.sv` | `verification/unit/timer/apb_timer_txn.sv` | Timer unit verification |
| `apb_timer-master/sim/vcs/run.sh` | `verification/unit/timer/runners/vcs/run.sh` | Timer simulation runner |
| `apb_timer-master/sim/xcelium/run.sh` | `verification/unit/timer/runners/xcelium/run.sh` | Timer simulation runner |
| `apb_timer-master/sim/xcelium/xrun.history` | `verification/unit/timer/runners/xcelium/xrun.history` | Timer simulation runner |

## Unassigned review items

These rows intentionally have no destination until their purpose and sensitivity are confirmed:

| Current path | Review reason |
|---|---|
| `.agents/skills/opencode-swarm/SKILL.md` | Decide whether this is project-wide guidance; sanitize paths, credentials, and personal workflow details before publishing. |
| `.agents/skills/virtuoso-rf-lna-optimizer/scripts/generate_45ghz_schematic.il` | Decide whether this is project-wide guidance; sanitize paths, credentials, and personal workflow details before publishing. |
| `.agents/skills/virtuoso-rf-lna-optimizer/scripts/run_virtuoso_sim.py` | Decide whether this is project-wide guidance; sanitize paths, credentials, and personal workflow details before publishing. |
| `.agents/skills/virtuoso-rf-lna-optimizer/SKILL.md` | Decide whether this is project-wide guidance; sanitize paths, credentials, and personal workflow details before publishing. |
| `check_opencode.ps1` | Determine whether this is team-maintained tooling; remove private session data, credentials, and personal configuration. |
| `CLAUDE.md` | Determine whether this is team-maintained tooling; remove private session data, credentials, and personal configuration. |
| `ses_status.json` | Determine whether this is team-maintained tooling; remove private session data, credentials, and personal configuration. |
| `spi_slave_infinion/infineon-s25fs512s-qspi-verilog-model-simulationmodels-en.zip` | Do not publish until redistribution terms and necessity are confirmed; prefer documented download/source provenance. |
| `Verification/dispatch_optimized_orchestrator.ps1` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |
| `Verification/master_orchestrator_session.xml` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |
| `Verification/opencode_audit_report.md` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |
| `Verification/opencode_space_bunny_raw_audit.md` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |
| `Verification/opencode_swarm_dispatch.ps1` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |
| `Verification/opencode_swarm_sessions.xml` | Review for private prompts, unverified claims, local paths, and whether a curated summary should replace it. |

All other REVIEW and EXCLUDE rows, including imported source copies, binary documents, run evidence, and generated output, are individually listed in the full CSV. The CSV is the authoritative per-file checklist; this Markdown document is its proposed-structure view.

## Publication gates

1. Revoke/rotate exposed credentials and keep credential-bearing parent-folder guidance out of this standalone repository.
2. Resolve REVIEW rows for third-party source, VIP models, papers, archives, duplicate RTL, and binary documents.
3. Keep only authored/current verification plans and concise results with tool version, source revision, command, and date; raw logs and simulator databases remain excluded.
4. Identify the active source of truth for duplicated BSPs, include trees, checkers, and legacy folders using the actual SoC and test filelists.
5. Add a root README, license/notice files after legal review, .gitignore, contribution guidance, and issue/PR templates.
6. Apply folder moves in small batches and check that filelists still resolve. This catalog is not evidence that any simulation currently passes.


