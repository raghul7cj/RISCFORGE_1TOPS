# APB Timeout Monitor Evidence Record

## Identity and test basis

- Master-plan reference: Sections 8 and 14 of RISCFORGE_Verification_Plan_RevB.docx.
- DUT: bus_monitors/apb_timeout_monitor.sv, the actual timeout-monitor RTL.
- Test level: component.

## Retained execution evidence

- Run: 20261019_run02, Vivado XSim 2022.2.
- Top: tb_apb_timeout_monitor.
- Result: PASS, 14/14 checks.
- Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [run notes](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/README.md), [simulation log](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/simulation.log), [captured output](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/simulation.stdout.log), [filelist](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/unit.f), and [testbench](../../artifacts/component_first/20261019_run02/monitor/apb_timeout_unit/inputs/tb_apb_timeout_monitor.sv).

## What the result establishes

The bench checks transparent response, completion before threshold, timeout pulse and SLVERR/sentinel response, sticky status, status clearing after access, and reset recovery.

## Limitations and open obligations

This is standalone monitor-RTL evidence. It does not prove timeout injection and recovery through the real SoC bridge/core or Stage1 firmware traffic accounting.
