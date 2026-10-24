# SoC APB Aperture Routing Evidence Record

## Identity and test basis

- Master-plan reference: Sections 14 and 15 of RISCFORGE_Verification_Plan_RevB.docx.
- DUT boundary: SoC address decode and real AXI-Lite-to-APB bridge routing to six APB slots.
- Test level: SoC integration.

## Retained execution evidence

- Run: 20261019_run02, Vivado XSim 2022.2.
- Top: soc_gpio_aperture_tb.
- Result: PASS, 43/43 checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/gpio_aperture/sim.log), [compile log](../../artifacts/component_first/20261019_run02/gpio_aperture/compile.log), [elaboration log](../../artifacts/component_first/20261019_run02/gpio_aperture/elab.log), [bench sources](../../artifacts/component_first/20261019_run02/gpio_aperture/soc_gpio_aperture_tb.sv) and [companion source](../../artifacts/component_first/20261019_run02/gpio_aperture/tb_soc_gpio_aperture.sv), and [filelist](../../artifacts/component_first/20261019_run02/gpio_aperture/xvlog.f).

## What the result establishes

The report records reads and writes across all six APB slots, selected-slot mask checks, and GPIO alias, gap, and unmapped-address cases.

## Limitations and open obligations

The APB responders are synthetic. This result checks address selection and response routing through the actual bridge/map; it does not exercise the functional RTL of the six peripherals or firmware-originated traffic.
