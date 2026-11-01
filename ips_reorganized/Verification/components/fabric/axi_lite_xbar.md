# AXI-Lite Crossbar Evidence Record

## Identity and test basis

- Master-plan reference: Section 14 fabric verification in RISCFORGE_Verification_Plan_RevB.docx.
- DUT: axi_lite_xbar/axi_lite_xbar.sv and its configured SoC dependencies.
- Intended scope: arbitration, routing, response association, and contention/error cases required by the master plan.

## Retained execution evidence

No dedicated quantified crossbar run was identified in the reviewed component-first checkpoints 20261018_run01 and 20261019_run02. The SoC APB aperture test exercises a real bridge and map but does not constitute crossbar sign-off.

## Status and next evidence

Status: NO_RETAINED_RUN in these checkpoints. Search for an independently retained crossbar regression and verify its source identity before changing this status. Otherwise define a test record from the master plan and retain arbitration/contention cases with per-case verdicts.
