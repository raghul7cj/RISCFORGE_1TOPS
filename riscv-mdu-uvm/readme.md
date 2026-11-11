# RV32M Coprocessor UVM Verification Environment

A robust, enterprise-grade **UVM 1.2 Testbench** tailored for the **RV32M Coprocessor Unit** (`rv32m_unit`), customized from `uvm_tb_templates`.

---

## 1. Architecture Overview

The UVM verification environment encapsulates the design under test with comprehensive functional coverage, formal concurrent assertions, and a hardware-accurate golden reference model.

```
                                      +---------------------------------------------+
                                      |                 rv32m_env                   |
                                      |                                             |
   +--------------------+             |   +-------------------------------------+   |
   |     Sequences      |             |   |             rv32m_agent             |   |
   | - directed_corner  |             |   |                                     |   |
   | - rand_seq         |             |   |  +------------+     +------------+  |   |
   | - mul_stress       |             |   |  |  Sequencer |     |   Driver   |  |   |
   | - div_stress       |  =======>   |   |  +------------+     +-----+------+  |   |
   +--------------------+             |   |                        |            |   |
                                      |   |                        | vif.drv_cb |   |
                                      |   |                        v            |   |
                                      |   |                 [ rv32m_if ]        |   |
                                      |   |                        |            |   |
                                      |   |                        | vif.mon_cb |   |
                                      |   |                        v            |   |
                                      |   |                 +------------+      |   |
                                      |   |                 |  Monitor   |      |   |
                                      |   |                 +-----+------+      |   |
                                      |   +-----------------------|-------------+   |
                                      |                           |                 |
                                      |            +--------------+--------------+  |
                                      |            |                             |  |
                                      |            v                             v  |
                                      |   +-----------------+           +-----------------+
                                      |   |   Scoreboard    |           |    Coverage     |
                                      |   | - ref_model     |           | - 8 Covergroups |
                                      |   | - Latency check |           | - Crosses       |
                                      |   +-----------------+           +-----------------+
                                      +---------------------------------------------+
                                                             |
                                                             | (Non-intrusive bind)
                                                             v
                                      +---------------------------------------------+
                                      |              rv32m_assertions               |
                                      | - 14 Concurrent Formal SVA Temporal Checks  |
                                      +---------------------------------------------+
                                                             |
                                                             v
                                      +---------------------------------------------+
                                      |              DUT: rv32m_unit                |
                                      | - Booth-Dadda 3-Stage Multiplier Pipeline   |
                                      | - 32-Iteration Non-Restoring Divider FSM    |
                                      +---------------------------------------------+
```

---

## 2. Directory Structure

| File | Component | Description |
| :--- | :--- | :--- |
| [`interface.sv`](interface.sv) | `rv32m_if` | SystemVerilog interface with synchronous driver and monitor clocking blocks and modports. |
| [`seq_item.sv`](seq_item.sv) | `rv32m_transaction` | Randomized transaction item with smart operand distribution (corners, boundaries, powers-of-two). |
| [`sequence.sv`](sequence.sv) | Sequences | Contains `rv32m_directed_corner_seq` (79 exhaustive vectors), `rv32m_rand_seq`, `rv32m_mul_stress_seq`, and `rv32m_div_stress_seq`. |
| [`sequencer.sv`](sequencer.sv) | `rv32m_sequencer` | UVM sequencer parameterised to `rv32m_transaction`. |
| [`driver.sv`](driver.sv) | `rv32m_driver` | Drives single-cycle `valid_in` pulses, monitors pipeline `stall`, and awaits `valid_out`. |
| [`monitor.sv`](monitor.sv) | `rv32m_monitor` | Synchronously tracks transaction initiation, measures cycle latency, and broadcasts completed items. |
| [`scoreboard.sv`](scoreboard.sv) | `rv32m_scoreboard` | Contains RISC-V golden reference oracle (`ref_model`), latency checker (3-cycle MUL, 35-cycle normal DIV, 2-cycle corner DIV), and destination register preservation check. |
| [`coverage.sv`](coverage.sv) | `rv32m_coverage` | UVM Subscriber with **8 distinct covergroups** (`cg_mul`, `cg_mulh`, `cg_mulhsu`, `cg_mulhu`, `cg_div`, `cg_divu`, `cg_rem`, `cg_remu`) and operand cross coverage. |
| [`rv32m_assertions.sv`](rv32m_assertions.sv) | SVA Checker | 14 concurrent temporal properties checking handshake protocols, stall windows, latency bounds, and arithmetic invariants; attaches via `bind`. |
| [`agent.sv`](agent.sv) | `rv32m_agent` | Encapsulates driver, sequencer, and monitor. |
| [`env.sv`](env.sv) | `rv32m_env` | Top-level environment binding agent, scoreboard, and coverage subscriber. |
| [`rand_test.sv`](rand_test.sv) | Test Suite | Contains `rv32m_rand_test`, `rv32m_directed_test`, `rv32m_stress_test`, and `rv32m_regression_test`. |
| [`testbench.sv`](testbench.sv) | `tb` (Top TB) | 100 MHz clock/reset generator, DUT instantiation, and UVM bootstrap. |
| [`filelist.f`](filelist.f) | Filelist | Clean include and source file list for one-line compilation. |
| [`run_xrun.sh`](run_xrun.sh) | Runner Script | Execution script configured for Cadence Xcelium 24.09. |
| [`Makefile`](Makefile) | Build System | One-touch targets for directed, random, stress, and regression suites. |

---

## 3. How to Run Simulations

### Using `Makefile`
```bash
# Run the complete multi-stage regression (Directed Corner + Random + Stress)
make test-regression

# Run 79-vector directed & corner suite
make test-directed

# Run 200 randomized transactions
make test-random

# Run high-volume multiplier and divider stress
make test-stress

# Clean simulation outputs
make clean
```

### Using `run_xrun.sh` directly (Cadence Xcelium)
```bash
# Default regression test
./run_xrun.sh rv32m_regression_test 1001

# Specific test with custom seed
./run_xrun.sh rv32m_directed_test 42
./run_xrun.sh rv32m_rand_test 5005
./run_xrun.sh rv32m_stress_test 9999
```

### Using Synopsys VCS
```bash
make vcs-regression SEED=1001
```

---

## 4. Verification Sign-Off Results (Cadence Xcelium 24.09)

The full regression test suite (`rv32m_regression_test`, Seed 1001) was executed using **Cadence Xcelium 24.09-s001** and verified against the golden mathematical reference model.

### 4.1 Scoreboard Summary

| Metric | Result | Status |
| :--- | :---: | :---: |
| **Total Checks Evaluated** | **35,471** | Passed |
| **Passed Checks** | **35,471** | 100.0% Pass |
| **Failed Checks** | **0** | Zero Mismatches |
| **Hardware Latency Deviations** | **0** | Zero Violations |
| **UVM Error / Fatal Reports** | **0 / 0** | Clean Sign-off |
| **Final Verification Verdict** | **100% SUCCESS** | **PASSED** |

*Evidence Log:* [`sim/rv32m_regression_test_1001/xrun_rv32m_regression_test_1001.log`](sim/rv32m_regression_test_1001/xrun_rv32m_regression_test_1001.log)

---

## 5. Functional Coverage Sign-Off (100.00% Closure)

Coverage extracted via Cadence Integrated Metrics Center (IMC) from the unified coverage database (`cov_work/`):

| Covergroup | Scope / Verification Target | Coverage (%) |
| :--- | :--- | :---: |
| **`cg_instruction`** | All 8 M-extension opcodes cross destination registers `rd` | **100.00%** |
| **`cg_mul`** | Lower 32-bit product across all operand sign combinations, zeros, and powers-of-2 | **100.00%** |
| **`cg_mulh`** | Signed upper 32-bit product, $-2^{31} \times -2^{31}$ corner ($0x40000000$), upper $-1$ | **100.00%** |
| **`cg_mulhsu`** | Mixed signed $\times$ unsigned upper product across sign quadrants and MSB transitions | **100.00%** |
| **`cg_mulhu`** | Unsigned upper 32-bit product, maximum saturation corner ($0xFFFFFFFE$) | **100.00%** |
| **`cg_div`** | Signed division across all 4 sign quadrants, divide-by-zero, $-2^{31} / -1$ overflow | **100.00%** |
| **`cg_divu`** | Unsigned division across full 32-bit range, divide-by-zero ($0xFFFFFFFF$), $A < B$ | **100.00%** |
| **`cg_rem`** | Signed remainder, remainder-by-zero, signed overflow, remainder sign invariant | **100.00%** |
| **`cg_remu`** | Unsigned remainder, remainder-by-zero ($rs1$), exact multiples ($Rem = 0$) | **100.00%** |
| **TOTAL OVERALL** | **Complete Functional Coverage Closure** | **100.00%** |

*Interactive HTML Coverage Report:* [`html_11-11-2026_05~29~56/index.html`](html_11-11-2026_05~29~56/index.html)

---

## 6. Formal Concurrent Assertions (SVA) Verification

All **14 temporal assertions** defined in [`rv32m_assertions.sv`](rv32m_assertions.sv) bound non-intrusively to `rv32m_unit` executed with **zero violations**:
- `p_stall_immediate` (`valid_in |-> stall`): Immediate cycle 0 stall assertion verified.
- `p_mutex_submodules` (`not (mul_valid && div_valid)`): Mutual exclusion verified.
- `p_valid_out_pulse` (`valid_out |=> !valid_out`): 1-cycle completion pulse verified.
- `p_no_unknown_outputs`: No X/Z unknown values on `result` or `rd_out`.
- `p_rd_preservation`: Destination register `rd` index preserved across multi-cycle operations.
- `p_mul_3cycles`: Fixed 3-cycle Booth-Dadda multiplier latency verified.
- `p_div_zero_fast` & `p_signed_overflow_fast`: Speculative 2-cycle fast exit for divide-by-zero and signed overflow verified.
- `p_div_normal_latency`: Exact 35-cycle radix-2 non-restoring division iterations verified.
- `p_rem_sign_invariant`: Non-zero remainder sign strictly matches dividend sign verified.
