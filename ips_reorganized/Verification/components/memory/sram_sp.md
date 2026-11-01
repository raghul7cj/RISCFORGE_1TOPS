# Single-Port SRAM Evidence Record

## Identity and test basis

- Master-plan reference: memory and fabric verification sections of RISCFORGE_Verification_Plan_RevB.docx.
- DUT: RTL_SOC/sram_sp.sv, exercised as a standalone single-port memory component.
- Test level: component.
- Oracle: directed read/write expectations in the retained testbench.

## Retained execution evidence

- Run: 20261019_run02, Vivado XSim 2022.2.
- Top: sram_sp_component_tb.
- Result: PASS, 7/7 checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/sram/sim.log), [compile log](../../artifacts/component_first/20261019_run02/sram/compile.log), [elaboration log](../../artifacts/component_first/20261019_run02/sram/elab.log), and [testbench snapshot](../../artifacts/component_first/20261019_run02/sram/sram_sp_component_tb.sv).

## What the result establishes

The report lists first and last word access, byte lanes, zero write mask, read-first behavior, a subsequent read, and chip-select hold among the checked behaviors.

## Limitations and open obligations

This is a component result. It does not by itself prove the core DSRAM path, AXI SRAM adapter, address decoding, or full memory-path scoreboard. Map the seven checks to the applicable master-plan memory obligations before claiming closure.
