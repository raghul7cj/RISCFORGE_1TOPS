# RISCFORGE SoC JasperGold Superlint Run

## Run identity

- Date reported by JasperGold: 2026-10-18 00:25:32 IST
- Tool: JasperGold 2025.06 FCS 64-bit
- Top: `riscforge_soc_subsystem`
- JasperGold process exit: 0
- Elaborated hierarchy: 110 Verilog modules (97 synthesized), 6 packages, 0 black boxes
- Signoff design statistics: 42,731 gates and 9,184 flops
- RTL manifest: `RTL_SOC/soc_subsystem.f`
- The SoC RTL instantiates `apb_uart`, which instantiates `apb_uart_wrap`. The canonical filelist omitted the wrapper and OBI UART dependencies, so the temporary JasperGold filelist adds those 11 sources. No project RTL or canonical filelist was changed.

## Superlint report results

| Report domain | Errors | Warnings | Info | Waived |
|---|---:|---:|---:|---:|
| LINT | 1 | 35 | 3 | 0 |
| DFT_FUNCTIONAL | 0 | 15 | 0 | 0 |

The primary structural error is `RST_IS_DCMB`: `sys_rst_n_raw` is reported as combinational logic driving the asynchronous reset of `sys_rst_sync_q[0]` at `RTL_SOC/riscforge_soc_subsystem.sv:515`. Review the reset synchronizer architecture and the rule interpretation before changing RTL; the report identifies a structural reset concern, not a simulation failure.

Warnings include unregistered inputs, open or unused ports, output ports read internally, and top-level outputs flagged as unregistered. The detailed report has source locations and instance names. The DFT domain reports 15 warnings, mostly `OTP_NO_RGTM` outputs.

## Count-scope note

The console log also prints an internal extraction tally of 24 errors, 1,368 warnings, and 3 info. This is not the same count as the exported LINT and DFT report tables above. Keep both records and reconcile their scopes before using the count as a sign-off metric.

## Filelist issue found during the run

The first attempt failed elaboration because `apb_uart_wrap` was absent from `soc_subsystem.f`. The completed run used a JasperGold-specific list derived from that manifest and supplied the instantiated OBI UART chain. The project manifest remains unchanged; update it separately if it is intended to be the canonical SoC source list.

## Artifacts

- `reports/superlint_summary.txt` — category totals
- `reports/superlint_violations.txt` — detailed findings
- `reports/superlint_violations_by_severity.txt` — severity totals
- `reports/superlint_violations.csv` — machine-readable findings
- `reports/superlint_signoff.txt` and `.html` — signoff report
- `logs/jg_run.log` — complete JasperGold console log
- `logs/attempt1_filelist_elaboration_failure.log` — initial missing-wrapper failure
- `source_snapshot/jg_soc.f` and `source_snapshot/lint.tcl` — effective run inputs
- `run_manifest.txt` — source hashes and snapshot identity
