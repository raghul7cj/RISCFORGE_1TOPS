# RISC-V Architectural Compliance Verification Handoff & Context Report

This document summarizes the current status, directory structure, files, and exact execution flow of the RISC-V Architectural Compliance framework (RISCOF) set up for the 5-stage RISCForge core. It serves as a context handoff block for future sessions.

---

## 1. Project Overview & Scope
The goal of this sub-system is to verify the architectural compliance of the 5-stage in-order RISCForge pipeline against the official RISC-V ISA specifications using the **RISCOF** framework.

### Environment Context
* **Host OS**: Windows (Workspace files reside under `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl`)
* **Simulation OS**: WSL2 Linux
  * **WSL Target Path**: `/home/raghul7cj/RISCFORGE_1TOPS/`
  * **RISC-V Toolchain**: Installed in WSL at `/home/raghul7cj/riscv/bin/` (specifically `riscv32-unknown-elf-gcc` and `riscv32-unknown-elf-nm`)
  * **Python Environment**: Virtualenv active at `/home/raghul7cj/riscof_env`
  * **Simulation Engine**: Icarus Verilog (`iverilog` / `vvp`)

---

## 2. Directory Structure & Key Files

The compliance suite is organized as follows:

```
rtl/
├── riscof_rtl_5/                   # Verilog source files configured for RISCOF simulation
│   ├── top.v                       # CPU Core Top module
│   ├── tb_riscof.v                 # Testbench wrapper with signature dumping logic
│   └── (ALU, decoders, memory, etc.)
└── verification/
    └── riscof/                     # RISCOF Workspace
        ├── run_compliance.bat      # Windows batch file to sync code and launch tests
        ├── run_riscof.sh           # Bash entry point inside WSL to set up env and run RISCOF
        ├── config.ini              # Main configuration file mapping DUT and Reference Models
        ├── test_list_single.yaml   # Run list for a single compliance test (add-01.S)
        ├── riscforge/              # Custom RISCOF plugin for the riscforge DUT
        │   ├── riscof_riscforge.py # Python plugin defining compilation & simulation launch steps
        │   └── env/                # Compliance header links and linker scripts
        └── sail_cSim/              # Reference model configuration (using Sail simulator)
```

---

## 3. Step-by-Step Execution Sequence

When the user runs `run_compliance.bat` on Windows, the following sequence occurs:

```mermaid
sequenceDiagram
    participant Win as Windows Host
    participant WSL as WSL Environment
    participant RISCOF as RISCOF Framework
    participant Compiler as GCC Toolchain
    participant Sim as Icarus Verilog (vvp)
    participant Sail as Sail Reference Sim

    Win->>WSL: Sync folder (optional) / cp -r rtl /home/raghul7cj/
    Win->>WSL: Run run_riscof.sh
    WSL->>WSL: Activate riscof_env & export riscv/bin PATH
    WSL->>RISCOF: riscof testlist --config=config.ini
    RISCOF->>Compiler: Compile test (.S assembly) to ELF
    RISCOF->>Compiler: Extract begin_sig, end_sig, and tohost address via nm
    RISCOF->>WSL: Split ELF into imem.hex and dmem.hex
    RISCOF->>Sim: Compile core & run tb_riscof.v with signatures plusargs
    Sim->>Sim: Run to completion; dump signature memory region to file
    RISCOF->>Sail: Run test in Sail reference model
    Sail->>Sail: Dump reference signature file
    RISCOF->>RISCOF: Diff DUT signature vs Reference signature
    RISCOF-->>Win: Return Pass/Fail report
```

### Detailed Command Walkthrough

1. **Host-to-WSL Sync**: 
   `run_compliance.bat` optionally deletes the target directory `/home/raghul7cj/RISCFORGE_1TOPS` in WSL and recopies the entire Windows workspace `rtl` folder there using `wsl cp -r`.
2. **Environment Activation**:
   `run_riscof.sh` executes in WSL:
   * Appends `$HOME/riscv/bin` to `$PATH`.
   * Activates the virtual python environment: `source $HOME/riscof_env/bin/activate`.
3. **RISCOF Orchestration**:
   * Validates configs and builds the test list using `riscof testlist`.
   * Invokes the custom plugin class `riscforge` defined in `riscof_riscforge.py`.
4. **Compilation & NM extraction**:
   * For each test in the list, compiles the assembly code to ELF.
   * Runs `nm` on the ELF and parses the stdout to extract the hexadecimal memory addresses of:
     * `begin_signature` (start of test outcomes)
     * `end_signature` (end of test outcomes)
     * `tohost` (special address signaling end-of-simulation)
5. **Split Memory & Sim Execution**:
   * Runs `elf_to_hex.py` to convert the ELF into `imem.hex` and `dmem.hex`.
   * Compiles the Verilog files using `iverilog` into a `riscof_sim` binary.
   * Runs simulation via `vvp` passing the extracted NM addresses as plusargs:
     ```bash
     vvp riscof_sim +begin_sig=<addr> +end_sig=<addr> +tohost_addr=<addr> +sig_file=<path>
     ```
6. **Signature Verification**:
   * The testbench `tb_riscof.v` monitors the write address of `dmem` matching `tohost_addr`.
   * When written, the simulation stops and loops through `begin_sig` to `end_sig` in `Data_Memory`, writing each 32-bit word line-by-line in hexadecimal to the `.signature` file.
   * RISCOF compares the DUT `.signature` file to the reference `.signature` generated by Sail.

---

## 4. Current Configuration Details
* **Linker script**: Located at `riscforge/env/link.ld`, setting the memory start address to `0x80000000`.
* **Arch test suit**: Located at `../riscv-arch-test/` relative to the workspace path.
* **Work directory**: Output artifacts are written inside the temporary `riscof_work/` directory, which is cleaned before each test execution to prevent stale signature checks.
