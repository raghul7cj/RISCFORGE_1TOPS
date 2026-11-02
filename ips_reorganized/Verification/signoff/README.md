# RISCFORGE — 1-TOPS signoff evidence review (2026-11-02)

Review baseline: `verification_infra` commit `2fedb8320c3b010bbba8dddc56e4ecdf8b7fb031`, before documentation-only commits. Source: user-provided `1TOPS_Project_Signoff_Checkl.xlsx` (124 line items G0–G9). Original workbook has **not** been uploaded as a binary GitHub file; see [checklist item index](1TOPS_PROJECT_CHECKLIST.md). The complete annotated workbook was generated as a downloadable conversation artifact under `RISCFORGE_Signoff_Checklist_Audited_2026-11-02.xlsx`; it is not a repo asset.

## Audit outcome (not formal gate status)

| Classification | Items |
|---|---:|
| Partial evidence / implementation present | 51 |
| Specification mismatch | 5 |
| Not demonstrated against full criterion | 63 |
| Optional or needs scope decision | 5 |
| **Total** | **124** |

The original workbook says `Not Started` for all 124 check IDs. The classification above is a repository-read-only evidence assessment, not a replacement for the signoff column and not a claim that any gate has passed.

## Positive evidence — scoped

| Area | Retained result | Do **not** infer |
|---|---|---|
| GPIO | [312/312 component checks](../components/apb/gpio.md) | Entire firmware-driven SoC GPIO/IRQ suite |
| I2C | [90/90 component checks](../components/apb/i2c.md) | Complete system-to-EEPROM path |
| SPI | [26/26 component checks](../components/apb/spi.md) | Full strap-selected external boot |
| UART | [69/69 component checks after XSim adapter fix](../components/apb/uart.md) | End-to-end SoC UART software suite |
| Timer0/1 | [9/9 shared direct component checks](../components/apb/timer0.md); [52/52 staged boot-to-Timer0 checks](../components/memory/boot_path.md) | All timer IRQs delivered through real ISR entry/return |
| SRAM | [7/7 direct checks](../components/memory/sram_sp.md) | Foundry SRAM macros / complete address-map signoff |
| AXI-Lite to APB | [28/28 component checks](../components/fabric/axi_lite_to_apb.md) | Full multi-master stress |
| AXI-Lite crossbar | [79/79 standalone checks](../verification_matrix.csv) | Full SoC crossbar and fabric closure |
| APB aperture | [43/43 synthetic-responder checks](../components/fabric/apb_aperture.md) | Real peripheral traffic closure |
| Interrupt arbiter | [196,608 arbitration snapshots; 100% declared unit functional coverage](../IRQ_UNIT_COVERAGE_PLAN.md), [coverage report](../artifacts/irq_restructure/functional_report_final/xcrg_func_cov_report.txt) | Core commit ordering, peripheral-to-ISR, preemption, interrupted divide/multiply or abort/restart |

[Verification matrix](../verification_matrix.csv) has 26 evidence records. Its component PASS flags have a distinct boundary from full SoC signoff. Existing [P0 status](../status/PHASE_STATUS.md): 13 MET, 5 PARTIAL, 2 NOT MET — P0 still IN PROGRESS. Those counts concern the **separate Rev B P0 exit contract**, not the external G0 workbook gate.

## Blocking specification disagreements

1. **3.4 PLIC:** no PLIC instantiated; current core has a 13-source local class/round-robin arbiter, with `ext_irq_i=0` at the SoC boundary.
2. **3.6 CLINT/CLIC:** `sw_irq_i=0` at SoC boundary; standalone CLIC RTL in tree is not an integrated CLINT or CLIC.
3. **3.9 Boot ROM:** active ROM is **64 bytes**, not the specified **4 KiB**.
4. **1.12 Boot plan:** current autonomous flash-to-SRAM loader does not demonstrate the required external `boot_mode` strap values (0 = internal ROM, 1 = external flash) and fallback.
5. **3.11 Interconnect:** the AXI-Lite crossbar and AXI-Lite→APB bridge are present, but the checklist's specific AXI→AXI-Lite bridge path is not demonstrated as such.

Request design-change approval or explicit per-item waivers. Do not silently rename existing local-IRQ architecture a PLIC/CLINT.

## Other material gates still open

- **G0:** Tool licenses / installed signoff tool acceptance, 28 nm PDK, one-command qualified full regression. Earlier XSim/Xcelium evidence does not automatically satisfy VCS-only checklist language.
- **G1:** Architecture approval, pinout, approved interrupt source map, clock/reset details, budget and formal freeze.
- **G2/G4:** Code lint/CDC and full PC/decode/regfile/ALU/MDU/hazard directed unit coverage and final core sanity.
- **G5:** Final candidate RISCOF/ISS lockstep, riscv-dv seeded campaigns, memory-stall randomization, code/functional coverage, CoreMark/Dhrystone, bug closure.
- **G6:** UVM/IP-VIP coverage against real SoC; register-field closure; all-source peripheral IRQ-to-ISR checks; abort/restart and nesting; real SPI boot strap; long-run traffic, error-path and resets; freeze and full zero-failure regression.
- **G7–G9:** No qualifying final-candidate synthesis/SDC/LEC/DFT/ATPG/GLS, post-route STA/DRC/LVS/IR/EM, final GDS/tapeout/foundry and coach/faculty signoffs found.

## Next actions in recommended order

1. Agree the 5 template-vs-design mismatches with coach, record applicable waiver IDs and revise/freeze architecture map.
2. Produce one frozen RTL + filelist + tool-identity bundle that passes P0 G0/G1 together; resolve source-duplication and DEF-001 regression identity, open defects in [phase status](../status/PHASE_STATUS.md).
3. Run tool-accepted core ISA / traps / interrupts and directed hazard/stall tests on that bundle. Ensure interrupted load/store, MUL/DIV and redirect/replay follow the intended precise-trap contract.
4. Perform real SoC peripheral pin+MMIO+IRQ driven C/ASM tests, including nesting, priority threshold, return context, delayed events, reset, invalid addressing and randomized traffic.
5. Map every checklist criterion to run IDs, RTL hashes, test IDs and coverage bins; secure approvals for each gate. Then begin backend qualification.

**Evidence policy:** always distinguish RTL present, bench present, prior passing test, current frozen RTL passing test, and officially approved gate. Never sign a gate from an unqualified XSim/isolated/staged PASS alone.
