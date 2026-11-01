# GPIO Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.2, APB slot 3, base address 0x4000_3000.
- Test level: direct GPIO APB wrapper/component.

## Retained execution evidence

- Run: 20261018_run01, Vivado XSim 2022.2.
- Top: tb_gpio_apb_directed.
- Result: PASS, 312 checks passed and 0 failed.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261018_run01/reproducibility.json), [simulation log](../../artifacts/component_first/20261018_run01/gpio/sim.log), [compile log](../../artifacts/component_first/20261018_run01/gpio/compile.log), [elaboration log](../../artifacts/component_first/20261018_run01/gpio/elab.log), [XSim filelist](../../artifacts/component_first/20261018_run01/gpio/xvlog.f), and [original Xcelium filelist](../../artifacts/component_first/20261018_run01/gpio/original_xrun_filelist.f).

## What the result establishes

The retained run records a direct GPIO component result. Separately, the Oct 19 APB aperture test checks slot routing with synthetic responders.

## Limitations and open obligations

The direct GPIO bench bypasses the SoC APB decoder. The aperture test checks routing but not GPIO RTL behavior. Together they do not prove every Rev B GPIO case or full firmware interrupt delivery. Recover the case-level report and trace it to the Rev B GPIO checks.
