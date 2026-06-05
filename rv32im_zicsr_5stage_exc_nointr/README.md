# RV32IM_Zicsr 5-Stage RISC-V CPU Core

This folder contains a verified, synthesizable RTL implementation of a **5-stage in-order RISC-V CPU Core** supporting the **RV32IM** Instruction Set Architecture and the **Zicsr** privileged extension.

---

## 1. Specifications & Feature Status

### Supported Architecture (RV32IM_Zicsr)
* **RV32I (Base Integer Instruction Set):** Core pipeline controls, hazard detection, bypassing, load/store execution, and branch/jump logic.
* **M Extension (Hardware Multiply/Divide):** Integrated Booth-encoded Dadda multiplier and a non-restoring sequential integer divider.
* **Zicsr Extension (CSR Support):** Full implementation of core Machine-mode Control and Status Registers (`mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mtval`, `mip`).

### Milestone Implementation Status
| Feature Class | Status | Details |
| :--- | :---: | :--- |
| **Arithmetic / ALU** | **Validated** | 32-bit ALU with branch flags output and dual-port compatibility. |
| **M-Extension (Mul)** | **Validated** | Booth-encoded 3-stage pipelined multiplier with sign-extension fix. |
| **M-Extension (Div)** | **Validated** | 32-cycle sequential non-restoring divider with overflow/underflow checks. |
| **Precise Traps / Exceptions** | **Validated** | Precise "propagate-and-commit" exception bus handling `ecall`, `ebreak`, and `illegal_instr`. |
| **Interrupts** | **Stubbed** | Asynchronous interrupts are disabled/bypassed. CLIC is stubbed out via `clic.sv`. |

---

## 2. Directory & Module Structure

The RTL is organized as a flat delivery directory to simplify imports into Electronic Design Automation (EDA) tools (such as AMD Vivado, Synopsys Design Compiler, or Yosys).

### Core Pipeline Stages
* **`top.v`**: Top-level wrapper instantiating pipeline cycles, hazard unit, exception controller, and CSR register file.
* **`fetch_cycle.v`**: Instantiates Program Counter, Instruction Memory, and computes the next PC logic.
* **`decode_cycle.v`**: Generates control signals, reads Register File, extends immediates, and pipes decode registers.
* **`execute_cycle.v`**: Manages operands forwarding/bypassing, runs ALU, and instantiates the M-extension block.
* **`memory_cycle.v`**: Manages Data Memory write/read access and byte/half-word/word alignment.
* **`writeback_cycle.v`**: Selects the writeback source for the Register File.

### Execution & Math Modules
* **`ALU.v` / `ALU_Decoder.v`**: Core arithmetic execution units.
* **`rv32m_unit.v`**: Execution multiplexer wrapping multiplier and divider operations.
* **`rv32m_mul.v` / `booth_enc.v` / `csa.v` / `pp_gen.v`**: booth-encoded multiplier arithmetic pipeline.
* **`rv32m_div.v`**: Non-restoring divider state machine.

### Control, Privilege, & System Utility Modules
* **`Control_Unit_Top.v` / `Main_Decoder.v` / `opcode_check.v`**: Control logic and op decoders.
* **`csr_regfile.v`**: Machine-mode CSR storage and access permissions.
* **`wb_trap_mret_commit_controller.v`**: Precise exception commit and state restoration (`mret`) logic.
* **`hazard_unit.v`**: Data hazard stalling, forwarding mux control, and pipeline flushing.
* **`ls_unit.v`**: Load-store alignment unit.
* **`clic.sv`**: **Dummy Stub.** Preserves the CLIC port and parameter signatures but features bypassed dummy outputs.
* **`JB_unit.v`**: Jump/Branch comparison evaluator.
* **`PC.v` / `PC_Adder.v` / `Sign_Extend.v` / `Mux2.v` / `Mux_3_by_1.v`**: Helper logic cells.

### Memory & State Blocks
* **`Register_File.v`**: Dual asynchronous read, single synchronous write register file.
* **`Instruction_Memory.v`**: Local simulation Instruction ROM.
* **`Data_Memory.v`**: Local simulation RAM.

---

## 3. Linting & Elaboration Flow

### A. Vivado Synthesis Elaboration (Linting)
To run Vivado syntax checks and design elaboration without executing simulation code, you can use the non-project mode TCL script.

1. Open a terminal or **Vivado TCL Shell**.
2. Navigate to the export directory.
3. Run the following command:
   ```bash
   vivado -mode batch -source lint_export.tcl
   ```
*(Note: Run `synth_design -rtl -top top` to execute elaboration).*

### B. WSL Verilator Linting
For fast, strict compiler warnings check, you can run Verilator inside WSL. 

1. Open a WSL shell in this directory.
2. Run the lint check using:
   ```bash
   verilator --lint-only -Wall -y . --top-module top top.v
   ```
*(Note: To run a clean check ignoring standard non-critical warnings like unused signals/pins and width-expansions, run: `verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN -y . --top-module top top.v`)*

---

## 4. Verification Setup (Testbench Structure)

Verification is maintained in the sibling development folder (`../5_stage/tb/tb_sv_oop_csr_exc`). 

### Testbench Hierarchy
```
5_stage/tb/tb_sv_oop_csr_exc/
├── tb_top.sv                     # Testbench top (handles clocking, interfaces, instantiation)
├── commit_if.sv                  # SystemVerilog interface monitoring retired instructions
├── commit_monitor.sv             # Monitors retired instructions from Writeback stage
├── commit_transaction.sv         # Data container for instruction transaction properties
├── commit_scoreboard.sv          # Retirement scoreboard comparing RTL commits with ISS model
├── scoreboard_model.md           # Scoreboard prediction and execution flow notes
└── run_tb.ps1                    # Automation script to compile and run simulation
```

### Running Simulations
The testbench uses Xilinx Vivado Simulator (`xelab` and `xsim`).
To run the automated Spike-comparison scoreboard simulation suite:
```powershell
powershell -ExecutionPolicy Bypass -File ./run_tb.ps1
```
The scoreboard monitors the Writeback stage commits, updating its internal model and checking retired instruction register writes, memory updates, and PC flows.
