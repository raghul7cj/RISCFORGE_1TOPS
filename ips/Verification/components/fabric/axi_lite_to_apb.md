# AXI-Lite to APB Bridge Evidence Record

## Identity and test basis

- Master-plan reference: Section 14 fabric verification in RISCFORGE_Verification_Plan_RevB.docx.
- DUT: axi_lite_to_apb/axi_lite_to_apb.sv.
- Test level: bridge component.
- Stimulus: retained AXI/APB BFM testbench.

## Retained execution evidence

- Run: 20261019_run02, Vivado XSim 2022.2.
- Top: tb_axi_lite_to_apb.
- Result: PASS, 28/28 checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/bridge/sim.log), [compile log](../../artifacts/component_first/20261019_run02/bridge/compile.log), [elaboration log](../../artifacts/component_first/20261019_run02/bridge/elab.log), [bench snapshot](../../artifacts/component_first/20261019_run02/bridge/tb_axi_lite_to_apb.sv), and [filelist](../../artifacts/component_first/20261019_run02/bridge/xvlog.f).

## What the result establishes

The retained report says the BFM samples handshakes at the active edge and waits for responses without consuming them early. A timeout guard was added for hung transactions.

## Limitations and open obligations

The BFM timing change is verification-only. The result does not establish all SoC crossbar, address-map, peripheral-register, or firmware-path obligations. Map each of the 28 checks to the master-plan test basis before treating it as sign-off evidence.
