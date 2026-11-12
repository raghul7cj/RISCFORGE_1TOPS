# Archived reference — G6.10 External SPI boot (transferred to Malay)

This record is preserved for history and moved out of the active CJ gate list at the user's direction.

**Official workbook status:** In Progress (sheet G6, supplied workbook).

## Testbench, evidence and remaining work

Historical boot records live outside this subgate package; bind image, flash transfer, SRAM contents, handoff and executed pass/fail to current candidate.

## Design (RTL / spec)

- `ips/RTL_SOC/riscforge_soc_subsystem.sv`
- `ips/bootloader/`
- `ips/spi_master_ip/`

## Verification

- (none in Verification)

## Evidence

- `ips/Verification/plans/soc_testbench_framework_20261104/` (framework only)
- `ips/Verification/gates/G1_architecture/SoC_Architecture_Map_Boot.md` (copied)

## HTML references

- `ips/Verification/gates/G6_soc_verification/SOC_TESTBENCH_ARCHITECTURE.html` (canonical: `ips/Verification/plans/soc_testbench_framework_20261104/SOC_TESTBENCH_ARCHITECTURE.html`)

## Traceability

See CJ subgate map and gate report. RTL, test presence, simulation result and official status are separate evidence claims.

## Reference files (checked against this workspace)

- [bootloader.sv](../../../../bootloader/bootloader.sv)
- [SOC_TESTBENCH_ARCHITECTURE.html](../../../../Verification/plans/soc_testbench_framework_20261104/SOC_TESTBENCH_ARCHITECTURE.html)
- [SoC_Architecture_Map_Boot.md](../../../../documentation/signoff/SoC_Architecture_Map_Boot.md)
- [1TOPS_PROJECT_CHECKLIST.md](../../../../Verification/signoff/1TOPS_PROJECT_CHECKLIST.md)

### Referenced but not present here

- `ips/spi_master_ip/README.md`

## Gate-prefixed local HTML copies

- [SoC testbench framework copy](../../../gates/G6_soc_verification/G6_SOC_TESTBENCH_ARCHITECTURE.html)
