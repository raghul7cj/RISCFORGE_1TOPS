# SPI Master Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.4, APB slot 4, base address 0x4000_4000.
- Test level: SPI master component with a behavioral BFM.
- Existing detailed overview: [SPI datapath report](../../../datapath_verification/spi0/design_overview_and_test_report.md). Use as historical context unless its source identity matches this run.

## Retained execution evidence

- Run: 20261019_run02 follow-up, Vivado XSim 2022.2.
- Top: tb_apb_spi_master_bfm.
- Result: PASS, 26 checks and 9 observed EOT events, including TC6.
- Evidence: [run manifest](../../artifacts/component_first/20261019_run02/spi/eot_retry/run_manifest.json), [simulation log](../../artifacts/component_first/20261019_run02/spi/eot_retry/sim.log), [compile log](../../artifacts/component_first/20261019_run02/spi/eot_retry/compile.log), [elaboration log](../../artifacts/component_first/20261019_run02/spi/eot_retry/elab.log), [bench snapshot](../../artifacts/component_first/20261019_run02/spi/eot_retry/spi_master_m_bfm_tb.sv), [BFM snapshot](../../artifacts/component_first/20261019_run02/spi/eot_retry/spi_bfm.sv), and [focused waveform](../../artifacts/component_first/20261019_run02/spi/eot_retry/spi_focused.vcd).

## What the result establishes

The follow-up counts the public EOT pulse so it remains observable after an APB FIFO read. It uses the same SPI RTL snapshot and the complete TC1-TC6 bench.

## Limitations and open obligations

This is component BFM evidence, not SoC firmware-driven flash access or full SoC peripheral sign-off. The run 02 top-level reproducibility.json has a stale earlier SPI caveat; the follow-up manifest and log record the newer PASS.
