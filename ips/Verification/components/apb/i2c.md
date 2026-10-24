# I2C Master Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.3, APB slot 0, base address 0x4000_0000.
- Test level: direct APB component with a pin-level I2C slave model.
- Existing detailed overview: [I2C datapath report](../../../datapath_verification/i2c0/design_overview_and_test_report.md). Treat that overview as historical context unless its source identity matches the retained run.

## Retained execution evidence

- Run: 20261018_run01, Vivado XSim 2022.2.
- Top: i2c_thorough_tb.
- Result: PASS, 90/90 checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261018_run01/reproducibility.json), [simulation log](../../artifacts/component_first/20261018_run01/i2c/sim.log), [compile log](../../artifacts/component_first/20261018_run01/i2c/compile.log), [elaboration log](../../artifacts/component_first/20261018_run01/i2c/elab.log), [XSim filelist](../../artifacts/component_first/20261018_run01/i2c/xvlog.f), and [original Xcelium filelist](../../artifacts/component_first/20261018_run01/i2c/original_xrun_filelist.f).

## What the result establishes

The run summary identifies a direct APB bench with a pin model. The saved filelist names the I2C RTL and i2c_thorough_tb.sv.

## Limitations and open obligations

The retained run summary does not enumerate all 90 checks here. Recover the individual case list from the bench/log and map it to the master-plan check IDs. This result alone does not demonstrate the full SoC firmware-to-EEPROM path.
