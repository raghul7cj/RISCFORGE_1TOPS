# RISCFORGE SoC — integrated RTL, peripherals and verification

> Source snapshot: `verification_infra` at `2fedb8320c3b010bbba8dddc56e4ecdf8b7fb031` (2026-11-01). This README is an orientation guide, **not a tape-out signoff**.

## What is in this directory?

`ips_reorganized/` is the integrated SoC development and verification tree. **Do not confuse this tree with the legacy root-level CPU directories** or with `Sw/` (which is historical reference). The canonical firmware development tree is `Verification/firmware/`.

| Directory | Role |
|---|---|
| [RTL_SOC/](RTL_SOC/) | SoC top `riscforge_soc_subsystem.sv`, memory/boot integration, and SoC-level testbenches/filelists |
| [riscv_core/rtl/](riscv_core/rtl/) | RV32IM_Zicsr five-stage core, CSR/trap/MRET, MMIO, interrupt gateway and class arbiter |
| [axi_lite_xbar/](axi_lite_xbar/) and [axi_lite_to_apb/](axi_lite_to_apb/) | SoC bus fabric, address decoding and APB conversion |
| [gpio-master/](gpio-master/), [apb_uart-main/](apb_uart-main/), [apb_i2c-master/](apb_i2c-master/), [spi_master_ip/](spi_master_ip/) | GPIO, UART, I2C and SPI RTL and component benches |
| [apb_timer-master/](apb_timer-master/) | Two timer instances, interrupts and component tests |
| [bootloader/](bootloader/), [spi_slave_infinion/](spi_slave_infinion/), [i2c_slave_at24c02/](i2c_slave_at24c02/) | Hardware SPI bootloader and external device behavioral models |
| [clic-master/](clic-master/) and [aon_timer/](aon_timer/) | Standalone IP/reference code; **do not infer current SoC integration** |
| [Verification/](Verification/) | Layered testbench, monitors, BFMs, scoreboards, firmware, filelists, run evidence, status tracker |
| [Sw/](Sw/) | Frozen legacy software reference; active work belongs in `Verification/firmware/` |

## System architecture as checked in

- CPU: five-stage, in-order RV32IM_Zicsr with machine-mode CSRs and precise trap/MRET logic.
- Reset address/boot: 64-byte boot ROM at `0x0000_0000`, 32 KiB ISRAM at `0x0001_0000`, 32 KiB DSRAM at `0x0002_0000`; hardware bootloader supports SPI flash→SRAM loading.
- Peripheral MMIO through AXI-Lite/APB: I2C `0x4000_0000`, Timer0 `0x4000_1000`, UART `0x4000_2000`, GPIO `0x4000_3000`, SPI `0x4000_4000`, Timer1 `0x4000_5000` (4 KiB windows).
- Interrupts: in-core gateway + `irq_arbiter`, **13 local sources** (MTIP cause 7 and fast-local causes 16–27). Class 2 fixed order, classes 1/0 round-robin, software-owned `mintprio` threshold. SoC `ext_irq_i` (MEIP) and `sw_irq_i` (MSIP) are currently tied low; a standalone `clic-master/` directory does not make this a PLIC or CLINT/CLIC integration.
- Reset synchronization exists in the SoC top; a completed CDC/RDC signoff is not established.

Read [SoC RTL](RTL_SOC/riscforge_soc_subsystem.sv), [current IRQ coverage contract](Verification/IRQ_UNIT_COVERAGE_PLAN.md), [interrupt integration plan](Verification/MINTPRIO_INTEGRATION_AND_PREEMPTION_PLAN.md) and [software/SoC specification](Sw/soc_spec.md) before changing architecture.

## Verification and reproducibility

Start with [Verification/README.md](Verification/README.md), [the evidence matrix](Verification/verification_matrix.csv), [the phase-status snapshot](Verification/status/PHASE_STATUS.md), [per-component evidence records](Verification/components/) and [retained run artifacts](Verification/artifacts/).

- Focused component PASS evidence exists for SRAM, GPIO, UART, I2C, SPI, timers, AXI-Lite-to-APB bridge, crossbar, and APB timeout monitor. These are scoped **component** claims.
- Retained staged SoC integration evidence includes boot→Timer0 (52/52 checks), with explicit staged-bench/source-identity qualifications.
- Interrupt-unit regression reports 196,608 arbiter snapshots and 100% of **declared unit functional coverage bins**, not complete pipeline/firmware preemption signoff.
- `Verification/status/PHASE_STATUS.md` records P0 still **IN PROGRESS** and open defects/actions, not a signed RTL freeze.
- The checked-in infrastructure includes XSim and Xcelium evidence; use of those tools does **not** satisfy a checklist that specifically requires VCS/SpyGlass/other approved EDA signoff without a documented approval/waiver.

Execution entry points: `Verification/Makefile` (legacy/focused IRQ VCS flow), `Verification/firmware/Makefile` (bare-metal images), `Verification/filelists/` (tiered filelists), `Verification/infrastructure/tb/soc_tb_top.sv` (unified SoC bench). Paths, simulator environment and licensing must be verified before treating a run as reproducible.

## Signoff and outstanding work

See [the project signoff audit](Verification/signoff/README.md) and [the checklist mirror](Verification/signoff/1TOPS_PROJECT_CHECKLIST.md). The workbook's 124 items span G0–G9; **no gate is signed off** based only on checked-in source files or earlier isolated tests. In particular: PLIC, CLINT/CLIC, 4 KiB ROM and two boot-mode strap behaviors in the external checklist do not match the present architecture.

Before release, agree on the architecture vs program-checklist discrepancies, pin final RTL/filelist hashes, perform a candidate-matched integrated regression, close ISA/trap/IRQ and all-peripheral firmware tests, record coverage/waivers, then obtain tool-qualified synthesis, STA, DFT, physical verification and faculty/coach approvals.

## Evidence discipline

A `PASS` in an isolated bench or a smoke simulation proves only its named DUT boundary and source version. Never promote it to an all-peripheral, entire CPU, or tape-out signoff without a case-to-requirement map, source identity, complete results, and approvals. Historical run directories and reports must remain immutable.
