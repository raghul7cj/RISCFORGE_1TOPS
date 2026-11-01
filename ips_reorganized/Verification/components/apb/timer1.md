# Timer1 Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.6, APB slot 5, base address 0x4000_5000.
- Test level: direct timer component.

## Retained execution evidence

- Run: 20261019_run02, Vivado XSim 2022.2.
- Top: timer_component_tb with two timer instances representing Timer0 and Timer1.
- Result: PASS, included in the 9/9 shared checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/timers/sim.log), and [shared testbench](../../artifacts/component_first/20261019_run02/timers/timer_component_tb.sv).

## What the result establishes

The shared bench checks reset values, independent count/stop behavior, compare and overflow IRQs, invalid-register reads, and APB responses.

## Limitations and open obligations

The retained report gives an aggregate count for the two-instance bench rather than a separate Timer1 count. No Timer1-specific SoC firmware flow is recorded in these checkpoints. Map instance-specific tests and interrupt reachability obligations before sign-off.
