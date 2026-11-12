# CJ responsibility — G4 unit and core verification

Subgate: 4.12. See [CJ subgate map](../../CJ_SUBGATE_MAP.md).

## Mirrored source documents

- `CSR_TRAP_VERIFICATION_STATUS.md` copied from `ips/Verification/doc/status/CSR_TRAP_VERIFICATION_STATUS.md`.
- `CSR_TRAP_CORNER_TESTPLAN.md` copied from `ips/Verification/doc/plans/CSR_TRAP_CORNER_TESTPLAN.md`.

The 552-check CSR unit run checks the CSR register block; it is not by itself proof of reset-vector fetch, asynchronous interrupt acceptance, handler execution or MRET resumption at core level. The core CSR/trap harness is separately identified as a reset-held skeleton in the source status document.

## Review navigation

- [Coach-facing G4 report](G4_report.html)
- IRQ unit evidence for 4.12: [unit verification](G4_IRQ_UNIT_VERIFICATION.html) and [functional coverage](G4_IRQ_UNIT_COVERAGE.html). Both are supporting unit evidence, not pipeline entry closure.
- Subgate pages: [subgates/](subgates/)

