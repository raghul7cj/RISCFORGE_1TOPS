# Step4 checker self-proof

Vivado XSim 2022.2; the isolated copy of `run_step4.ps1` passed all required gates:

- Disassembler self-test: 31 passed, 0 failed.
- Clean traffic: 0 findings with LSU=17, AXI writes=8, AXI reads=9, APB transfers=14.
- Fault matrix: 11 injected faults, 11 expected check IDs, 0 mismatches.
- Runner verdict: `STEP 4 SELF-PROOF: GREEN.`

The checker self-proof uses `step4_apb_bridge_model`, not the real `axi_lite_to_apb`. It validates the checker and fault-injection logic, not real SoC timeout propagation or Stage1 accounting. XSim also reports unsupported `cover property` statements in the SVA files; this run verifies the procedural checker/fault matrix, not functional coverage closure.

Run with `.\run_step4.ps1`. The source snapshot, file list, runner output, compile/elaboration/simulation logs, and generated report are preserved in this directory.
