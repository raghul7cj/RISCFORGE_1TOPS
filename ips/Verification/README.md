# RISCFORGE Verification Evidence Index

This directory organizes verification evidence for the active RISCFORGE SoC. The master verification plan remains [RISCFORGE_Verification_Plan_RevB.docx](../RISCFORGE_Verification_Plan_RevB.docx). This index, the matrix, and the component records are its evidence companion; they do not replace its requirements, test design, or sign-off rules.

## How to use this evidence set

See the [review and future test roadmap](verification_roadmap.md) for existing peripheral plan locations, documentation gaps, and the ordered work needed for stronger verification claims.

Start with [verification_matrix.csv](verification_matrix.csv) to find the latest retained result for a block. Open the component record for the test boundary, checks, verdict, and limitations. Follow its run links to the preserved testbench or filelist, compile and elaboration logs, simulation log, and run metadata.

The original run folders are kept in place. This pass reorganizes documentation by linking to them; it does not move, edit, or rerun the source artifacts. Results are recorded as existing-run evidence, not as newly verified results. A PASS in a component record does not automatically close a Rev B check ID. The check-to-test mapping and required SoC-level scope must also be established.

## Controlled evidence states

- PASS: a retained run reports a passing result for the stated boundary.
- INCOMPLETE: the test did not produce a complete functional verdict.
- NO_RETAINED_RUN: no qualifying run was found in the reviewed checkpoints. This does not assert that no testbench or other historical run exists.
- NOT_INTEGRATED: the block is specified or present as an IP, but is not instantiated in this SoC configuration.
- PLANNED: specified by the master plan, with no qualifying execution evidence recorded here.

## Component records

### APB peripherals

- [I2C](components/apb/i2c.md)
- [Timer0](components/apb/timer0.md)
- [UART](components/apb/uart.md)
- [GPIO](components/apb/gpio.md)
- [SPI](components/apb/spi.md)
- [Timer1](components/apb/timer1.md)
- [AON watchdog](components/apb/aon_watchdog.md)

### Memory and boot

- [Single-port SRAM](components/memory/sram_sp.md)
- [Boot path](components/memory/boot_path.md)

### Fabric and monitors

- [AXI-Lite to APB bridge](components/fabric/axi_lite_to_apb.md)
- [SoC APB aperture](components/fabric/apb_aperture.md)
- [AXI-Lite crossbar](components/fabric/axi_lite_xbar.md)
- [APB timeout monitor](components/fabric/apb_timeout_monitor.md)
- [Monitors and checkers](components/observability/monitors_and_checkers.md)

## Evidence and interpretation notes

1. RISCFORGE_Verification_Plan_RevB.docx defines the intended verification scope and per-device test design. It distinguishes integrated APB devices from the specified but unintegrated AON watchdog.
2. The [run 01 report](artifacts/component_first/20261018_run01/README.md) and [run 01 reproducibility manifest](artifacts/component_first/20261018_run01/reproducibility.json), plus the [run 02 report](artifacts/component_first/20261019_run02/README.md) and [run 02 reproducibility manifest](artifacts/component_first/20261019_run02/reproducibility.json), are the source for execution outcomes and source identity. Run 01 is dated 2026-10-18; run 02 is dated 2026-10-19.
3. Older datapath overview reports are retained background material. Where their tool/source identity is not tied to a retained run, they are not used as current pass evidence.
4. The run 02 README records the later SPI EOT follow-up as 26/26 passing. Its top-level reproducibility.json still contains the earlier TC6 caveat; the SPI follow-up's own run_manifest.json and logs record the corrected result.
5. The run 02 Timer0 integration used a staged XSim-compatible testbench and filelist. That evidence must not be represented as a run of the checked-in integration bench.

## Standards basis

The documentation uses a tailored test-plan, test-specification, execution-record, and completion-summary structure informed by ISO/IEC/IEEE 29119-2 and 29119-3. The system and hardware V&V framing is aligned to IEEE 1012-2024. This repository does not claim formal conformance to those standards.
