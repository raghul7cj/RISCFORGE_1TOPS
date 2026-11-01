# UART Evidence Record

## Identity and test basis

- Master-plan reference: Section 15.7, APB slot 2, base address 0x4000_2000.
- Intended scopes include APB/register behavior and UART TX/RX pin behavior; keep those claims separate.

## Retained execution evidence

- Baseline Run: 20261019_run02, Vivado XSim 2022.2.
  - Result: INCOMPLETE. Compile and elaboration pass; simulation stops advancing after reset checks at 60 ns.
  - Evidence: [run reproducibility manifest](../../artifacts/component_first/20261019_run02/reproducibility.json), [simulation log](../../artifacts/component_first/20261019_run02/uart/sim.log), [compile log](../../artifacts/component_first/20261019_run02/uart/compile.log), [elaboration log](../../artifacts/component_first/20261019_run02/uart/elab.log), [adapter replay](../../artifacts/component_first/20261019_run02/uart/debug/sim_adapter.log), [replay notes](../../artifacts/component_first/20261019_run02/uart/debug/delta_replay_notes.txt).
- Root Cause Isolation & Fix Verification Run: 20261024_uart_delta_isolation, Vivado XSim 2022.2.
  - Result: ROOT CAUSE ISOLATED & FIX PROVEN (69/69 PASS on `tb_apb_uart_thorough`).
  - Evidence: [investigation report](../../artifacts/component_first/20261024_uart_delta_isolation/README.md), [reproducibility manifest](../../artifacts/component_first/20261024_uart_delta_isolation/reproducibility.json), [side-by-side reproducer bench](../../artifacts/component_first/20261024_uart_delta_isolation/test_adapter.sv), [verified decoupled adapter](../../artifacts/component_first/20261024_uart_delta_isolation/apb_to_obi_fix.sv), [full regression log](../../artifacts/component_first/20261024_uart_delta_isolation/tb_uart_thorough_xsim_pass.log).

## What the results establish

1. **Root Cause Confirmed**: The stall at 60 ns in Vivado XSim is caused by a procedural intermediate assignment glitch in `apb_to_obi.sv` (`obi_req_o.req = 1'b0;` followed by `obi_req_o.req = apb_req_i.psel;` inside `always_comb begin : obi_fsm`). When connected to downstream combinational grant generation (`obi_rsp_o.gnt = obi_req_i.req` in `obi_uart_register.sv`), XSim enters an infinite zero-delay delta-cycle feedback loop ($\Delta_0 \rightarrow \Delta_\infty$). Cadence Xcelium avoids the stall due to IEEE 1800-2009 combinational optimization which collapses intermediate procedural assignments.
2. **Decoupled Fix Proven**: Decoupling `assign obi_req_o.req = (obi_phase_q == ADDR) ? apb_req_i.psel : 1'b0;` removes all procedural sensitivity to `obi_rsp_i.gnt`.
3. **Decisive Verification**: In `test_adapter.sv`, the original code stalls at 60 ns while the decoupled code finishes in 81 ns. In full regression, `tb_apb_uart_thorough.sv` passes **69/69 checks across all 30 test cases** at 127,946 ns with 0 failures.

## Status (updated 2026-10-28)

- **Component closure: CLOSED** for the stall investigation (tracker item DEF-002). Matrix row APB-02 is PASS for the component boundary only.
- Not closed: golden RTL patch, SoC-level UART, Rev B 15.7 scenario-to-check mapping.

## Limitations and open obligations

- The patch is staged in `ips/Verification/artifacts/component_first/20261024_uart_delta_isolation/apb_to_obi_fix.sv`. As checked on 2026-10-28, golden `ips/SOC_FILES/include/obi/apb_to_obi.sv` and `ips/apb_uart-main/include/obi/apb_to_obi.sv` are still the original (lines 112 and 119 still assign `obi_req_o.req` procedurally; both copies are byte-identical, SHA-256 prefix B0699F6A). Apply the patch to both, then re-run `tb_apb_uart_thorough` against the golden files and record the new identity (tracker ACT-001).
- `uart_test.f` compiles the fix from `scratch/uart_xsim_test/apb_to_obi_fix.sv`, a path outside the retained artifact. Repoint it to the staged copy in this run folder so the run is reproducible (DEF-007).
- The 69/69 result applies to the `apb_uart` OBI-wrapper DUT in `tb_apb_uart_thorough.sv`. `RTL_SOC/soc_subsystem.f` comments claim `apb_uart.sv` is self-contained and that the OBI chain was removed, yet `apb_uart.sv` describes itself as an APB wrapper of the OBI UART and the `obi_uart*` sources exist under `SOC_FILES/include/obi/`. Confirm which UART the master SoC filelist elaborates before relying on this result at SoC level (DEF-006).
- Stage 2 and Stage 3 SoC proofs touched slots 0, 1 and 5 only, so they do not exercise the UART. Full SoC-level firmware UART transmission through `riscforge_soc_subsystem.sv` remains to be executed under Stage 6.
