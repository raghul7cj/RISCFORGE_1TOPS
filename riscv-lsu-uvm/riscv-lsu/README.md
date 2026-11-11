# RISC-V RV32I LSU UVM Verification Environment

UVM 1.2 Verification Environment for the **RV32I Load/Store Unit** (`ls_unit.v` from the G0 core).

## Project Structure

```
riscv-lsu-uvm/riscv-lsu/
├── design/
│   └── ls_unit.v            # User's RV32I Load/Store Unit RTL (DUT)
├── tb/
│   ├── lsu_pkg.sv            # RV32I memory op enums, funct3 encodings, parameters
│   ├── lsu_if.sv             # Interface bundling core pipeline & memory bridge busses
│   ├── lsu_transaction.sv    # Sequence item with RV32I instructions & golden predictors
│   ├── lsu_driver.sv         # Drives CPU pipeline inputs + emulates memory bridge
│   ├── lsu_monitor.sv        # Reconstructs transactions from memory requests
│   ├── lsu_scoreboard.sv     # Verifies req/we, address, strobes, shifting, extensions
│   ├── lsu_coverage.sv       # Functional coverage (all 8 instructions, offsets, strobes, signs)
│   ├── lsu_sequences.sv      # Seven stimulus sequences (smoke, all-ops, offsets, signs, stalls)
│   ├── lsu_agent.sv          # UVM Agent (Driver + Sequencer + Monitor)
│   ├── lsu_env.sv            # UVM Environment (Agent → Scoreboard + Coverage)
│   ├── lsu_tests.sv          # Test library (smoke, coverage, stress, regression)
│   ├── lsu_assertions.sv     # SVA protocol checkers & invariant assertions
│   └── top_tb.sv             # Top-level TB instantiating DUT & interface
└── scripts/
    ├── compile.do             # Questa / ModelSim script
    ├── run_xrun.sh            # Cadence Xcelium execution script
    ├── run_regression.py      # Automated Python regression runner
    ├── html_11-11-2026_03~32~16/ # Cadence IMC HTML Coverage Report
    └── sim/                   # Test simulation output directories & waveforms
        ├── lsu_smoke_test_1001/
        ├── lsu_coverage_test_1001/
        ├── lsu_stress_test_1001/
        └── lsu_regression_test_1001/
```

## RTL Module Interface (`ls_unit.v`)

```
                           ┌─────────────────────────── ls_unit ────────────────────────────┐
                           │                                                                │
    core_addr[31:0] ───────┼─► mem_addr[31:0] (direct pass-through)                         │
                           │   └─► [1:0] byte_offset                                        │
                           │             │                                                  │
    lsunit[4:0] ───────────┼─► Control Unpacker                                             │
                           │     ├─► is_ls_valid ────────► mem_req                          │
                           │     ├─► is_store_op ────────► mem_we                           │
                           │     ├─► is_load_op                                             │
                           │     └─► ls_funct3[2:0]                                         │
                           │             │                                                  │
    core_wdata[31:0] ──────┼─────────────┴─► [Store Alignment & Strobe Unit]                │
                           │                   ├─► mem_wdata[31:0] (shifted per offset)     │
                           │                   └─► mem_be[3:0] (SB: 1-hot, SH: 2-hot, SW)   │
                           │                                                                │
    mem_rdata[31:0] ───────┼─────────────┬─► [Load Data Formatting Unit]                    │
                           │             │     (LB/LBU/LH/LHU slicing + sign/zero extend)   │
                           │             └───────────────► core_rdata[31:0]                 │
                           │                                                                │
    mem_stall ─────────────┼───► AND (with mem_req) ─────► core_stall                       │
    mem_err ───────────────┼───► Passthrough ────────────► core_err                         │
                           └────────────────────────────────────────────────────────────────┘
```

## Verification Scope & Sign-Off Criteria (Sub-Gate 4.7)

Sub-Gate 4.7 requirement: **"All size x offset combinations and signed/unsigned loads covered"**

| Check Category | Verification Details | Scoreboard Status |
|---|---|:---:|
| **Control Decoding** | `mem_req == lsunit[4]`, `mem_we == (lsunit[4] & lsunit[3])` | **PASS** |
| **Address Passthrough** | `mem_addr == core_addr` (zero-cycle latency) | **PASS** |
| **Store Byte Strobes** | `SB` → 1-hot mask at offset (`0001`, `0010`, `0100`, `1000`), `SH` → 2-hot (`0011`, `1100`), `SW` → `1111` | **PASS** |
| **Store Data Alignment** | Barrel shifting `core_wdata << (offset * 8)` across all 4 byte lanes | **PASS** |
| **Signed Loads** | `LB` / `LH` correctly sign-extended (both negative $MSB=1$ and positive $MSB=0$) | **PASS** |
| **Unsigned Loads** | `LBU` / `LHU` correctly zero-extended | **PASS** |
| **Full Word Reads** | `LW` 32-bit pass-through without corruption | **PASS** |
| **Handshake & Errors** | `core_stall == (mem_req & mem_stall)`, `core_err == mem_err` | **PASS** |

## Test Suite

| Test Name | Description | Total Checks | Outcome |
|---|---|:---:|:---:|
| `lsu_smoke_test` | Basic sanity check running 20 Word read/write operations | 80 | **PASS (0 errors)** |
| `lsu_coverage_test` | Exhaustive sequence hitting all 8 instructions, all offsets, and sign-extension | 340 | **PASS (0 errors)** |
| `lsu_stress_test` | Back-to-back operations with random back-pressure stalls (`mem_stall`) | 480 | **PASS (0 errors)** |
| `lsu_regression_test` | Complete comprehensive verification suite combining all directed and random sequences | **1134** | **PASS (0 errors)** |

## Verification Results & Sign-Off Proof

Executed on Cadence Xcelium 24.09-s001:

### 1. Scoreboard Summary
```text
UVM_INFO lsu_scoreboard.sv @ 16035000: uvm_test_top.m_env.m_scoreboard [SCB] ==================== SCOREBOARD REPORT ====================
UVM_INFO lsu_scoreboard.sv @ 16035000: uvm_test_top.m_env.m_scoreboard [SCB] Total Checks: 1134  |  PASS: 1134  |  FAIL: 0
UVM_INFO lsu_scoreboard.sv @ 16035000: uvm_test_top.m_env.m_scoreboard [SCB] >>> ALL FUNCTIONAL AND ALIGNMENT CHECKS PASSED <<<
UVM_INFO lsu_scoreboard.sv @ 16035000: uvm_test_top.m_env.m_scoreboard [SCB] ===========================================================
```

### 2. Functional Coverage Report (100.0% Closed)
```text
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] ==================== COVERAGE REPORT ====================
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] Instruction Space : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] Byte Offsets      : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] Byte Strobe Mask  : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] Sign Extension    : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] Bridge Handshake  : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV]   hs.cp_stall      : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV]   hs.cp_resp       : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV]   hs.cx_stall_resp : 100.0%
UVM_INFO lsu_coverage.sv @ 16035000: uvm_test_top.m_env.m_coverage [COV] =========================================================
```

### 3. Protocol Assertions (SVA)
All 8 SVA assertions (`p_mem_req_decode`, `p_mem_we_decode`, `p_mem_addr_passthrough`, `p_core_stall_gating`, `p_core_err_passthrough`, `p_idle_quiescent`, `p_store_be_legal`, `p_load_be_zero`) passed with **0 violations**.

## Running the Verification

### Cadence Xcelium (`xrun`)
```bash
cd scripts
export PATH=/home/install/XCELIUM2409/tools/bin:$PATH
export LM_LICENSE_FILE=5280@14.139.1.126
./run_xrun.sh lsu_regression_test      # or lsu_smoke_test, lsu_coverage_test, lsu_stress_test
```
All artifacts (log, `xcelium.d`, `cov_work`, waves) are written to `scripts/sim/<test>_<seed>/`.  
Clean everything with:
```bash
./run_xrun.sh clean
```
