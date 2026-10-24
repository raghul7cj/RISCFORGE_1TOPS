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

## Limitations and open obligations

- The patch is staged in `ips/Verification/artifacts/component_first/20261024_uart_delta_isolation/apb_to_obi_fix.sv`. It is pending application to canonical `ips/SOC_FILES/include/obi/apb_to_obi.sv` and `ips/apb_uart-main/include/obi/apb_to_obi.sv`.
- Full SoC-level firmware UART transmission through `riscforge_soc_subsystem.sv` remains to be executed under Stage 6.
