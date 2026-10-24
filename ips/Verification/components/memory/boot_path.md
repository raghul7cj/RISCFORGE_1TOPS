# Boot and Timer0 Runtime Evidence Record

## Identity and test basis

- Master-plan reference: Sections 12 and 15 of RISCFORGE_Verification_Plan_RevB.docx.
- DUT boundary: boot ROM, bootloader, SPI flash model, ISRAM loading, core release, Timer0 MMIO, and DSRAM result store.
- Test level: SoC integration.

## Retained execution evidence

- Run 20261019_run02: PASS, 52/52 checks in soc_timer0_boot_run_tb. See the [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/timer0_integration/sim_timescale_preserved.log), [staged bench](../../artifacts/component_first/20261019_run02/timer0_integration/tb_xsim_compat.sv), [filelist](../../artifacts/component_first/20261019_run02/timer0_integration/xsim_filelist.f), and [exit status](../../artifacts/component_first/20261019_run02/timer0_integration/exit_status_timescale_corrected.txt).
- Run 20261018_run01: cold boot plus warm-reset retention passed 36 checks. See the [run report](../../artifacts/component_first/20261018_run01/README.md) and [simulation log](../../artifacts/component_first/20261018_run01/boot/sim.log).

## What the result establishes

The Oct 19 run observed flash power-up, SPI read activity, returned boot data, all 11 ISRAM words, Timer0 MMIO, and the DSRAM result commit.

## Limitations and open obligations

The Oct 19 run used a staged XSim-compatible testbench and filelist, not the checked-in integration bench. Its time-unit correction and delayed DSRAM-commit check are testbench setup changes. Keep this evidence distinct from a run of the current checked-in source set.
