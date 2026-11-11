# RISC-V Core vs. Spike ISS Lockstep Co-Simulation (`core-spike-lockstep-comparision`)

Automated bare-metal compilation, Reference ISS execution, RTL simulation, and commit-by-commit architectural lockstep verification environment for the **5-stage pipelined RV32IM_Zicsr processor core** (`top.v`), covering verification checklist items **0.3** (GNU Toolchain), **0.4** (Spike ISS), and **5.1** (Automated ISS vs. RTL Comparison Flow).

---

## 1. Verification Flow Overview

```
  c/*.c (main.c / baremetal_helloworld.c)  +  asm/start.s  +  ld/linker.ld
                                    │
                                    ▼
         riscv64-unknown-elf-gcc (-march=rv32im_zicsr -mabi=ilp32 -O0)
                                    │
                                    ▼
                           elf/<TARGET>.elf
                   ┌────────────────┴────────────────┐
                   │                                 │
                   ▼                                 ▼
         objcopy -j sections               Spike ISS (--log-commits)
    ┌──────────────┴──────────────┐                  │
    ▼                             ▼                  ▼
hex/imem.hex                 hex/dmem.hex     logs/spike_<TARGET>.log
(.text only)        (.rodata/.data/.tohost/.bss)     │
    └──────────────┬──────────────┘                  │
                   ▼                                 │
     Cadence Xcelium (xrun -64bit -sv)               │
     tb/tb_top.v + rtl/*.v                           │
     [WB Commit Monitor + tohost Trap]               │
                   │                                 │
                   ▼                                 │
         logs/rtl_<TARGET>.log                       │
                   │                                 │
                   └────────────────┬────────────────┘
                                    ▼
              scripts/compare_traces.py (--start-pc=0x80000000)
                                    │
                   ┌────────────────┴────────────────┐
                   ▼                                 ▼
        100% Lockstep Match              Divergence / Truncation
     Exit Code 0 (PASSED)                Exit Code 1 (FAILED)
     logs/compare_<tag>.log              Prints PC, Opcode & Diff
```

> **Visual Diagrams:** Architectural diagrams are available in [`images/`](images/): [`diag_flow.png`](images/diag_flow.png), [`diag_tb.png`](images/diag_tb.png), [`diag_memory_map.png`](images/diag_memory_map.png), and [`diag_trace_compare.png`](images/diag_trace_compare.png). *(Note: Those diagrams illustrate the earlier unified-RAM Icarus Verilog flow; the current [`Makefile`](Makefile) uses Cadence Xcelium `xrun` and split `IMEM`/`DMEM` hex sections via [`ld/linker.ld`](ld/linker.ld).)*

---

## 2. Directory Structure

```text
core-spike-lockstep-comparision/
├── Makefile                        # End-to-end build, Spike, Xcelium & comparison targets
├── env_setup.csh                   # tcsh environment setup (RISC-V tools, Xcelium 24.09, venv)
├── asm/
│   ├── start.s                     # Reset entry (_start), mie clear, sp init, call main, HTIF tohost
│   └── baremetal_helloworld.s      # Generated/reference assembly listing
├── c/
│   ├── baremetal_helloworld.c      # Bare-metal string copy benchmark into sim_buffer[]
│   └── main.c                      # Function call + loop array sum testbench program
├── ld/
│   └── linker.ld                   # Harvard-split memory map: IMEM (rx) & DMEM (rw)
├── rtl/                            # 5-stage RV32IM_Zicsr core RTL & simulation memory models
│   ├── top.v                       # Top-level 5-stage core (RESET_PC = 0x80000000)
│   ├── Instruction_Memory.v        # Instruction_Memory_new (1-cycle sync read, +imem_hex support)
│   ├── Data_Memory.v               # Data_Memory (0-cycle comb read, byte-enable writes, +dmem_hex)
│   ├── fetch_cycle.v / decode_cycle.v / execute_cycle.v / memory_cycle.v / writeback_cycle.v
│   ├── hazard_unit.v / ls_unit.v / csr_regfile.v / rv32m_unit.v / ...
├── tb/
│   ├── tb_top.v                    # Core + IMEM/DMEM wrapper, WB commit monitor, tohost detector
│   ├── tb_rv32m_unit.v             # Standalone RV32M unit testbench (auxiliary)
│   ├── rv32m_assertions.sv         # RV32M SVA checkers
│   └── rv32m_coverage.sv           # RV32M covergroups
├── scripts/
│   └── compare_traces.py           # Lockstep Spike vs. RTL commit trace comparator
├── elf/                            # Compiled RISC-V ELFs (baremetal_helloworld.elf, main.elf)
├── disass/                         # objdump disassembly listings (*.disass)
├── hex/                            # Segregated Verilog hex images (imem.hex, dmem.hex)
├── logs/                           # Spike logs, RTL commit logs, xrun logs, comparison reports
├── docs/                           # Reference PDF documentation (rv32m_verification_architecture.pdf)
├── images/                         # Flow, testbench, memory map, and comparator PNG diagrams
└── sim/                            # Simulation artifacts (waves/snapshots)
```

---

## 3. Memory Map & Split Hex Generation

[`ld/linker.ld`](ld/linker.ld) partitions the 64 KB address space at `0x8000_0000` into strict executable and read/write segments to avoid `RWX` ELF segments and isolate code from data:

| Region | Permissions | Address Range | Size | Mapped Sections | Extracted To |
| :--- | :---: | :--- | :---: | :--- | :--- |
| **`IMEM`** | `rx` (Read + Execute) | `0x8000_0000` – `0x8000_7FFF` | 32 KB | `.text.init`, `.text` | [`hex/imem.hex`](hex/imem.hex) |
| **`DMEM`** | `rw` (Read + Write) | `0x8000_8000` – `0x8000_FFFF` | 32 KB | `.rodata`, `.data`, `.sdata`, `.tohost`, `.bss`, `.sbss`, Stack (top `0x8001_0000` ↓) | [`hex/dmem.hex`](hex/dmem.hex) |

- **Why `.rodata` lives in `DMEM`:** String literals (such as `"hello world !\n"` in [`c/baremetal_helloworld.c`](c/baremetal_helloworld.c)) are loaded by CPU load instructions (`lbu`/`lw`) over the Load/Store Unit (`lsu_mem_*`) bus, so read-only data must reside in `Data_Memory`.
- **Word Addressing:** `objcopy` shifts addresses by `-0x80000000` with `--verilog-data-width=4`. Thus `imem.hex` begins at `@00000000` (`0x8000_0000`), and `dmem.hex` begins at `@00002000` (word offset `(0x8000_8000 - 0x8000_0000) >> 2`). Both [`rtl/Instruction_Memory.v`](rtl/Instruction_Memory.v) and [`rtl/Data_Memory.v`](rtl/Data_Memory.v) model 262,144 × 32-bit words (1 MB) starting at `0x8000_0000` and accept `+imem_hex=` / `+dmem_hex=` runtime plusargs.

---

## 4. Testbench & Termination Mechanism (`tb/tb_top.v`)

[`tb/tb_top.v`](tb/tb_top.v) wraps the DUT (`top #(.RESET_PC(32'h80000000))`) alongside synchronous [`Instruction_Memory_new`](rtl/Instruction_Memory.v) and combinational-read [`Data_Memory`](rtl/Data_Memory.v):

- **Writeback Commit Monitor:** Samples at `negedge clk` when `dut.valid_W && !dut.exc_valid_W` to emit Spike-matching lines into `logs/rtl_<TARGET>.log`:
  - GPR writeback (`dut.RegWriteW_gated && dut.RDW != 0`): `core   0: 3 0x<PC> (0x<INSTR>) x<rd> 0x<val>`
  - Store instruction (`cur_opcode == 7'b0100011`): `core   0: 3 0x<PC> (0x<INSTR>) mem 0x<addr> 0x<data>`
  - Control/other commits: `core   0: 3 0x<PC> (0x<INSTR>)`
- **HTIF `tohost` Halt Protocol:** [`asm/start.s`](asm/start.s) writes `1` to the `.tohost` symbol upon return from `main()`, then enters a `wfi` / `j 1b` parking loop. `Makefile` extracts `tohost`'s address via `riscv64-unknown-elf-nm` and passes `+tohost_addr=<addr>` to `xrun`. Upon detecting `lsu_mem_we && (lsu_mem_addr == tohost_addr)`, `tb_top` runs a 3-cycle pipeline drain (`halt_countdown <= 3'd3`) so final writeback commits flush to disk before `$finish`.
- **Plusargs Supported:** `+imem_hex=<path>`, `+dmem_hex=<path>`, `+tohost_addr=<hex>`, `+max_cycles=<int>` (default `50000`), `+log_file=<path>`, and `+dump_vcd=<0|1>`.

---

## 5. Lockstep Trace Comparator (`scripts/compare_traces.py`)

[`scripts/compare_traces.py`](scripts/compare_traces.py) parses both trace logs, discards Spike's boot ROM preamble (`0x00001000`–`0x00001010`) until `PC == 0x80000000` (`--start-pc`), and verifies every retired instruction in lockstep:

1. **Program Counter (`PC`) equality**
2. **32-bit Instruction Opcode equality**
3. **Destination GPR name & writeback value equality** (ignoring `x0`)
4. **Store memory address & data equality**
5. **Trace completion bound:** Ensures `abs(total_spike - total_rtl) <= 3` (accounting for pipeline drain instructions after `tohost` write)

On any divergence, comparison halts at the first mismatch, records `FAIL` with the expected vs. observed commit states and raw line numbers in the output log, prints a diagnostic box to stdout, and **exits with status code `1`**.

---

## 6. How to Run

### Environment Setup
In a Cadence/RISC-V lab shell (`tcsh`), source [`env_setup.csh`](env_setup.csh) first (adjust paths if your Spike or Xcelium install differs):
```tcsh
source env_setup.csh
```

### `Makefile` Targets

| Command | Action | Generated Comparison Log |
| :--- | :--- | :--- |
| `make check` *(or `make`)* | Full flow (compile ELF, disass, split hex, run Spike + `xrun`, compare) on `baremetal_helloworld` | [`logs/compare_check.log`](logs/compare_check.log) |
| `make main` | Full flow targeting [`c/main.c`](c/main.c) (`TARGET=main`) | `logs/compare_main.log` |
| `make baremetal_helloworld` | Full flow targeting [`c/baremetal_helloworld.c`](c/baremetal_helloworld.c) | `logs/compare_baremetal_helloworld.log` |
| `make TARGET=main check` | Run `check` flow against custom `TARGET` (`c/<TARGET>.c`) | [`logs/compare_main_check.log`](logs/compare_main_check.log) |
| `make test-mismatch` | Injects a deliberate RTL register corruption (`0xDEADBEEF`) to verify fail detection & exit code 1 | `logs/compare_test-mismatch.log` |
| `make compile` / `make hex` / `make spike` / `make rtl` / `make compare` | Execute individual pipeline stages | — |
| `make clean` | Clean build artifacts (`elf/*`, `disass/*`, `hex/*`, `sim/*`, `logs/*`, `*.vcd`) | — |

**Configurable Make Variables:**
- `TARGET` (default: `baremetal_helloworld`)
- `PREFIX` (default: `riscv64-unknown-elf-`)
- `SPIKE` (default: `$(HOME)/riscv_tools/bin/spike`)
- `XRUN` (default: `xrun`)
- `MAX_CYCLES` (default: `50000`)

---

## 7. Verified Results & Sign-Off Evidence

| Program (`TARGET`) | Spike Instructions | RTL Instructions | Verified Lockstep Count | Status | Retained Log Evidence |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **`baremetal_helloworld`** | 261 | 262 | **261 / 261** | **PASSED (0 deviations)** | [`logs/compare_check.log`](logs/compare_check.log) |
| **`main`** | 134 | 135 | **134 / 134** | **PASSED (0 deviations)** | [`logs/compare_main_check.log`](logs/compare_main_check.log) |
| **Fault Injection (`test-mismatch`)** | — | — | Halts at first mismatch | **VERIFIED (Exit 1)** | Run via `make test-mismatch` |

### Excerpt from `logs/compare_check.log`
```text
================================================================================
                 RISC-V LOCKSTEP EXECUTION COMPARISON REPORT                   
================================================================================
 Generated      : 2026-11-10 20:49:36
 Spike ISS Trace: logs/spike_baremetal_helloworld.log (261 instructions parsed)
 RTL Trace      : logs/rtl_baremetal_helloworld.log (262 instructions parsed)
 Reset PC       : 0x80000000
================================================================================
...
 #256   PASS    0x80000010   0x00008297   x5=0x80008010                x5=0x80008010                -
 #257   PASS    0x80000014   0x03028293   x5=0x80008040                x5=0x80008040                -
 #258   PASS    0x80000018   0x00100313   x6=0x00000001                x6=0x00000001                -
 #259   PASS    0x8000001c   0x0062a023   mem[0x80008040]=0x00000001   mem[0x80008040]=0x00000001   -
 #260   PASS    0x80000020   0x10500073   -                            -                            -
--------------------------------------------------------------------------------------------------------------

================================================================================
 *** [PASSED] ISS vs RTL LOCKSTEP COMPARISON SUCCEEDED! ***
================================================================================
  Total Instructions Verified : 261
  Instructions Passed         : 261 / 261
  Instructions Failed         : 0
  Deviation Status            : ZERO DEVIATIONS (100% LOCKSTEP MATCH)
================================================================================
```
