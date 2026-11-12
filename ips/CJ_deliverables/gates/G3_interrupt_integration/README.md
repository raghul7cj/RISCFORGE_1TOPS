# CJ responsibility — G3 interrupt integration

Subgates: 3.4 and 3.6. See [CJ subgate map](../../CJ_SUBGATE_MAP.md).

Keep the workbook's PLIC and CLINT/CLIC requirements visible. A custom local controller, standalone CLIC files, and core-level injected IRQ tests do not alone establish SoC integration or an approved alternative. Record any accepted disposition with approver and scope.

## Revision note (IRQ reconciliation)

The gate pages in this directory were reconciled against the RTL now on disk. [G3_IRQ_ARCH_and_TB.html](G3_IRQ_ARCH_and_TB.html) is the single source of truth for the as-coded path and the test plan, built on the former `G3_core_interrupts.html` with the former `G3_vf_interrupt_verification.html` merged in. [G3_IRQ_Architecture.html](G3_IRQ_Architecture.html) is the lean G3.4 decision and block-contract record. [G3_core_interrupts.html](G3_core_interrupts.html) and [G3_vf_interrupt_verification.html](G3_vf_interrupt_verification.html) are now pointer stubs; their previous content is archived verbatim under [superseded/](superseded/). All are derived from the originals under `ips/documentation/` (`RISCFORGE IRQ Architecture.html`, `html/core_interrupts.html`, `html/vf_interrupt_verification.html`), which stay unchanged as the pre-implementation record. Where a claim here contradicts an original, this directory is the reconciled version and the original is dated.

- **Disposition:** G3.4 records that neither a PLIC nor a CLIC is used; the direct in-core interface is chosen. This is an architecture rationale (speed and simplicity over runtime reconfigurability), not a measured latency or frequency advantage. The workbook cell is unchanged and no approval is inferred.
- **Implemented, as coded:** 13 channels (cause 7 plus 16-27), `irq_gateway` edge/event/level capture, `irq_arbiter` three classes (2 fixed, 1 and 0 round robin), `mintprio` 2-bit class threshold at 0x7C0. `mintlvl` (0x7C1), `mintctl` (0x7C2) and hardware nesting are proposal only.
- **Source map:** [G3_IRQ_ARCH_and_TB.html section 2](G3_IRQ_ARCH_and_TB.html#channels), with a validated spec and diagram in [diagrams/](diagrams/). Baseline is a content hash because this workspace is not a git checkout.
- **Verification ownership:** the canonical unit verification and coverage record is G4.12 ([unit verification](../G4_core_verification/G4_IRQ_UNIT_VERIFICATION.html), [unit coverage](../G4_core_verification/G4_IRQ_UNIT_COVERAGE.html)). G3 does not restate those as SoC passes. G3.6 timer integration and G6 end-to-end remain open.

## Review navigation

- [Coach-facing G3 report](G3_report.html)
- [Single source of truth: IRQ architecture and testbench](G3_IRQ_ARCH_and_TB.html)
- [Architecture decision and block contracts](G3_IRQ_Architecture.html)
- [Archived core interrupt path](superseded/G3_core_interrupts.html) and [archived verification guide](superseded/G3_vf_interrupt_verification.html)
- Subgate pages: [subgates/](subgates/)

