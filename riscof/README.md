# RISC-V Architectural Compliance Verification (RISCOF) Framework

This repository houses the complete **RISC-V Architectural Test (RISCOF)** verification harness and regression environment for the synthesizable **5-stage pipelined RV32IM processor core** (`RISCFORGE_1TOPS`).

The verification suite co-simulates the synthesizable Verilog RTL against the official **Spike Golden Model** (`riscv-isa-sim`), validating instruction execution, pipeline hazards, and memory operations via deterministic architectural signature matching.

---

## 🚀 Verification Status

* **Target ISA:** `RV32IM` (Base Integer + Hardware Multiply/Divide)
* **Framework Version:** `RISCOF v1.25.3` / `riscv_isac v0.6.6` / `riscv_config v3.7.0`
* **Reference Golden Model:** Spike (`riscv-isa-sim` v1.1.1-dev)
* **Simulator:** Icarus Verilog (`iverilog` / `vvp` v12.0)
* **Compliance Pass Rate:** **100% (49 / 49 tests passed)**

```
================================================================================
                               RISCOF TEST SUMMARY
================================================================================
  Category                              Tests Run       Passed       Failed
--------------------------------------------------------------------------------
  RV32I Base Integer Arithmetic (R-type)    9              9            0
  RV32I Immediate Arithmetic (I-type)      10             10            0
  RV32I Upper Immediate (lui, auipc)        2              2            0
  RV32I Conditional Branches                6              6            0
  RV32I Unconditional Jumps (jal, jalr)     2              2            0
  RV32I Load Operations (lb, lh, lw...)     5              5            0
  RV32I Store Operations (sb, sh, sw)       3              3            0
  RV32M Hardware Multiplication             4              4            0
  RV32M Hardware Division & Remainder       4              4            0
  Architectural Hints (fence, srl NOPs)     2              2            0
  Privilege / JALR Alignment (misalign1)    1              1            0
--------------------------------------------------------------------------------
  TOTAL ARCHITECTURAL TESTS                49             49            0 (100%)
================================================================================
```

Interactive HTML Report: [`riscof_work/report.html`](riscof_work/report.html)  
Detailed Technical Report: [`riscof_report.pdf`](riscof_report.pdf)

---

## 📂 Repository Directory Layout

```
.
├── config.ini                  # Master RISCOF configuration linking DUT & Spike plugins
├── riscof_report.pdf           # Comprehensive 11-page publication-grade verification report
├── riscof_work/                # Simulation scratchpad, generated Makefiles, signatures, report.html
├── firmware/                   # Standalone bare-metal C & Assembly firmware testbench
│   ├── start.s                 # Reset startup vector and stack initialization
│   ├── main.c                  # Core C workload application
│   ├── link.ld                 # Firmware memory linker script
│   └── tb_firmware.v           # Dedicated firmware testbench runner
├── spike/                      # Spike Golden Reference plugin
│   ├── riscof_spike.py         # Spike execution harness
│   ├── spike_isa.yaml          # Golden reference ISA specification (RV32IM)
│   └── spike_platform.yaml     # Spike memory map and execution platform config
├── riscv-arch-test/            # Official RISC-V architectural compliance test suite
├── RISCFORGE_1TOPS/            # Synthesizable RTL, core sub-blocks, and SoC IPs
│   ├── ips_reorganized/
│   │   └── riscv_core/rtl/     # Verified 5-stage RV32IM core implementation
│   ├── riscof_rtl_5/           # Direct core RTL staging directory for simulation
│   └── rv32im_zicsr_.../       # Extended RTL with CSRs and trap controller
└── riscof_rtl_backup/          # Reference backup of RTL wrapper scripts and environments
```

---

## 🛠️ Verification Environment Setup

### 1. Prerequisites
Ensure the following toolchains are installed on Ubuntu 24.04 LTS / WSL2:

```bash
# 1. GNU RISC-V Cross-Compiler Toolchain
sudo apt install gcc-riscv64-unknown-elf

# 2. Icarus Verilog Simulator
sudo apt install iverilog

# 3. Python Virtual Environment dependencies
sudo apt install python3-venv python3-pip
```

### 2. Virtual Environment Setup
Activate the pre-configured virtual environment containing RISCOF:

```bash
cd /home/pocharam/riscof
source riscof_env/bin/activate
riscof --version
```

---

## ⚙️ Running the Compliance Regression

### Execute Full 49-Test Suite
Run the push-button regression with parallel workers (`jobs=4`):

```bash
cd /home/pocharam/riscof
source riscof_env/bin/activate

riscof run --config=config.ini \
           --suite=riscv-arch-test/riscv-test-suite/ \
           --env=riscv-arch-test/riscv-test-suite/env
```

### Reviewing Test Results
* **Terminal Summary:** Detailed stdout logs print for each test phase.
* **HTML Report:** Open `riscof_work/report.html` in any browser to inspect per-instruction test traces and cycle counts.
* **Signatures:** Per-test architectural signatures are dumped in:
  ```
  riscof_work/rv32i_m/<CATEGORY>/src/<TEST>.S/dut/DUT-riscof_rtl.signature
  riscof_work/rv32i_m/<CATEGORY>/src/<TEST>.S/ref/Reference-spike.signature
  ```

---

## 🔬 Hardware Architecture & Testbench Highlights

```
                       +---------------------------------------+
                       |             RV32IM Core               |
                       |       5-Stage In-Order Pipeline       |
                       +---------------------------------------+
                                  │                 │
         imem_addr [29:0]         │                 │  lsu_mem_addr, wdata, be
                                  ▼                 ▼
             +────────────────────────+         +────────────────────────+
             |   Instruction Memory   |         |      Data Memory       |
             |   8 MB (2,097,152 x 32)|         |   8 MB (2,097,152 x 32)|
             +────────────────────────+         +────────────────────────+
                                                    │
                                                    │ lsu_mem_we && addr == tohost
                                                    ▼
                                        +────────────────────────+
                                        |   Execution Monitor    |
                                        |   & Signature Dumper   |
                                        +────────────────────────+
```

1. **Harvard Memory Decoupling:** Decoupled `Instruction_Memory` (1-cycle synchronous read) and `Data_Memory` (combinational read, byte-masked synchronous write) prevent pipeline stalls during compliance runs.
2. **Base Relocation (`RESET_PC = 0x80000000`):** Automated address shifting (`objcopy --change-addresses=-0x80000000`) aligns physical ELF addresses directly with word index `0` of the memory arrays.
3. **8 MB Memory Allocation:** Sized `MEM_DEPTH = 2,097,152` words ($8\,\text{MB}$) to accommodate wide 20-bit branch spans (e.g., `jal-01.S` jumping across $4.79\,\text{MB}$).
4. **Hardware `tohost` Trap Monitor:** Intercepts write transactions to the `.tohost` trap address (`sw x1, tohost`), waits 5 clock cycles for pipeline retirement, and serializes the signature memory window `[begin_signature, end_signature)` directly into `DUT-riscof_rtl.signature`.
5. **Exact Destination Register (`rd`) Capture:** Test macros (`TEST_RR_OP` $\rightarrow$ `TEST_CASE` $\rightarrow$ `RVTEST_SIGUPD`) automatically issue `sw rd, offset(sig_base)` following every instruction execution, verifying that internal CPU register updates correctly commit to RAM.

---

## 📑 Documentation

* **Formal Technical Report:** [`riscof_report.pdf`](riscof_report.pdf)  
  *Covers microarchitecture specifications, pipeline stage wiring, macro expansion mechanics, and signature tables.*
* **Verification Log:** [`riscof_work/database.yaml`](riscof_work/database.yaml)  
  *Full test suite database generated by RISCOF.*
