# Timer0 Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.5, APB slot 1, base address 0x4000_1000.
- Test levels: direct timer component and SoC boot-to-runtime integration.

## Retained execution evidence

- Run 20261019_run02 direct component: PASS, 9/9 checks using two timer instances. Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/timers/sim.log), and [testbench](../../artifacts/component_first/20261019_run02/timers/timer_component_tb.sv).
- Run 20261019_run02 integration: PASS, 52/52 checks. Evidence: [simulation log](../../artifacts/component_first/20261019_run02/timer0_integration/sim_timescale_preserved.log), [staged bench](../../artifacts/component_first/20261019_run02/timer0_integration/tb_xsim_compat.sv), and [staged filelist](../../artifacts/component_first/20261019_run02/timer0_integration/xsim_filelist.f).

## What the result establishes

The direct bench checks reset values, independent counting and stopping, compare/overflow IRQs, invalid-register reads, and APB response. The integration run observed boot loading, Timer0 MMIO, and a committed DSRAM result.

## Limitations and open obligations

Timer0 integration used staged XSim compatibility sources. The direct test is a shared two-instance component bench. Map individual checks to Rev B IDs; do not infer all SoC interrupt and firmware-flow criteria from these counts.
