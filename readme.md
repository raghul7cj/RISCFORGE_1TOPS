# RISCFORGE_1TOPS — Random Instruction Stream Generation, Compilation & RTL Simulation (`riscv-dv`)

End-to-end guide for generating random RV32IM (`Zicsr`) instruction streams with Google `riscv-dv`, compiling them into Verilog memory images, running them on the **RISCFORGE `riscv_core` RTL** using Cadence Xcelium (`irun`/`xrun`), comparing retired instruction traces against the **Spike ISS**, and collecting functional coverage.

> **Source Reference:** Derived from [`RANDOM_INSTR_STREAM_FLOW.txt`](RANDOM_INSTR_STREAM_FLOW.txt), [`setup_commands.txt`](setup_commands.txt), and retained run artifacts in [`out_2026-11-12/`](out_2026-11-12/), [`sweep/`](sweep/), and [`html_12-11-2026_01~27~40/`](html_12-11-2026_01~27~40/).  
> **Note on Execution Context:** The `Makefile`, `run.py`, `target/rv32im/`, `rtl_dv_companions/`, and `RISCFORGE_1TOPS/ips/riscv_core/rtl/` sources reside in the `riscv-dv` workspace on the simulation host (e.g., `/home/iiita/riscv-dv`), while this directory retains the flow documentation, generated test artifacts, sweep logs, and IMC coverage reports.

---

## 1. High-Level Flow

```text
  1. GENERATE   : run.py drives riscv-dv (SystemVerilog/UVM generator)
                  -> emits random assembly: out_*/asm_test/<test>_<seed>.S
                  -> runs Spike ISS (--isa rv32im) -> out_*/spike_sim/<test>_0.log
                  -> converts Spike log           -> out_*/spike_trace.csv
                          │
                          ▼
  2. COMPILE    : riscv64-unknown-elf-gcc (-march=rv32im_zicsr -mabi=ilp32)
                  -> produces <test>_0.o / .elf / .bin
                  -> objcopy (--verilog-data-width=4 --reverse-bytes=4) -> test.hex
                  -> objdump (-M no-aliases --adjust-vma=0x80000000)    -> disasm.txt
                          │
                          ▼
  3. RTL SIM    : irun (Cadence Xcelium) elaborates riscv_core RTL + tb_riscv_dv
                  -> loads test.hex via +instr_file and watches +tohost_addr
                  -> logs retired instructions -> out_*/rtl_sim/rtl.log
                  -> scripts/rtl_log_to_trace_csv.py -> out_*/rtl_sim/rtl_trace.csv
                          │
                          ▼
  4. COMPARE    : scripts/rtl_no_trap_ref_compare.py (aligns trailing ecall)
                  -> scripts/instr_trace_compare.py (PC / GPR / MEM diff vs Spike)
                  -> optional functional coverage via make coverage / Cadence IMC
```

---

## 2. Core Under Test & Testbench Architecture

### RTL Design (`RISCFORGE_1TOPS/ips/riscv_core/rtl/`)
The DUT is the `riscv_core` RV32IM + Zicsr pipelined core (`top.v`), featuring:
- 5-stage pipeline (`fetch_cycle.v`, `decode_cycle.v`, `execute_cycle.v`, `memory_cycle.v`, `writeback_cycle.v`)
- Hazard & forwarding control (`hazard_unit.v`, `JB_unit.v`, `Mux2.v`, `Mux_3_by_1.v`)
- RV32M multiply/divide unit (`rv32m_unit.v`, `rv32m_mul.v`, `rv32m_div.v`, `booth_enc.v`, `pp_gen.v`, `csa.v`)
- Load/Store unit & memory interfaces (`ls_unit.v`, `imem_controller.v`, `axi_pkg.sv`, `hybrid_mem_interface.sv`)
- CSR & trap/mret logic (`csr_regfile.v`, `wb_trap_mret_commit_controller.v`, `opcode_check.v`)

### DV Companion Models (`rtl_dv_companions/`)
- **`Instruction_Memory.v`** — behavioral instruction memory loaded from `test.hex`
- **`Data_Memory.v`** — behavioral data memory
- **`tb_riscv_dv.sv`** — top-level testbench wrapping the core and memory models

**Testbench Plusargs:**
- `+instr_file=<test.hex>` — Verilog hex program image linked at reset vector `0x80000000`
- `+tohost_addr=<hex>` — end-of-test (EOT) store address; the testbench monitors this address for the value `1` written by the generated `riscv-dv` EOT routine

**Target ISA & ABI:** `rv32im`, `ilp32` ABI, with `Zicsr` (`-march=rv32im_zicsr`).

---

## 3. Prerequisites & Environment Setup

### 3.1 Shell Environment
From the `riscv-dv` repository root, source the setup script **before** running any `make` or `run.py` commands:

```tcsh
# csh / tcsh
source env_setup.csh
```
```bash
# bash
source env_setup.bash
```

This adds the RISC-V GNU toolchain (`riscv64-unknown-elf-*`), Spike ISS, and Cadence Xcelium/IMC tools to `PATH` and `LD_LIBRARY_PATH`.

### 3.2 Python Dependencies
Python packages required by `run.py` and trace/coverage scripts are listed in [`requirements.txt`](requirements.txt) (`PyYAML`, `bitstring`, `pyvsc`, `tabulate`, `pandas`, etc.).

---

## 4. Step 1 — Generate the Random Instruction Stream

### Recommended (`Makefile`)
From the `riscv-dv` repository root:

```bash
make generate TEST_NAME=riscv_arithmetic_basic_test NUM_TESTS=1 SEED=1
```

### Equivalent Manual Command
```bash
python3 run.py --verbose \
    --custom_target target/rv32im \
    --isa rv32im --mabi ilp32 \
    --test riscv_arithmetic_basic_test \
    --iss spike --simulator ius \
    --sim_opts "+no_fence=1" \
    --gcc_opts="-march=rv32im_zicsr" \
    -i 1 --start_seed 1
```

### Key Options
- **`--custom_target target/rv32im`**: Selects the core-matching target configuration (`riscv_core_setting.sv` and `testlist.yaml`).
- **`TEST_NAME`**: Selects the program generator template from `target/rv32im/testlist.yaml` (e.g., `riscv_arithmetic_basic_test`, `riscv_rand_instr_test`, `riscv_rand_jump_test`, `riscv_loop_test`, `riscv_jump_stress_test`, `riscv_mmu_stress_test`, `riscv_ebreak_test`, `riscv_illegal_instr_test`, `riscv_misaligned_instr_test`, `riscv_unaligned_ld_store_test`).
- **`NUM_TESTS` / `SEED`** (`-i <N> --start_seed <S>`): Generates `N` independently seeded assembly programs starting at seed `S`.
- **Single-pass ISS flow**: `run.py` drives generator compilation/execution (`irun` + UVM `riscv_instr_base_test`), `riscv-gcc` compilation, Spike ISS execution, and Spike log-to-CSV trace conversion.

### Tuning Randomness (`GEN_OPTS`)
Any configuration knob in `src/riscv_instr_gen_config.sv` (such as `instr_cnt`, `num_of_sub_program`, `no_fence`, `disable_compressed_instr`, `no_branch_jump`, `no_load_store`, `no_data_page`) can be overridden via `GEN_OPTS`:

```bash
make base_test GEN_OPTS="+instr_cnt=5000 +num_of_sub_program=2"
make generate TEST_NAME=riscv_base_test GEN_OPTS="+no_branch_jump=1 +no_load_store=1"
```

### Generated Outputs
`run.py` creates `out_<YYYY-MM-DD>/` (for example, [`out_2026-11-12/`](out_2026-11-12/)), and the `Makefile` records the active output directory in `.outdir`, test name in `.testname`, and EOT signature address in `.tohost` (by grepping the Spike log for `'mem <addr> 0x00000001'`):

| Output File | Description |
| :--- | :--- |
| `out_*/asm_test/<test>_0.S` | Generated random RISC-V assembly program |
| `out_*/asm_test/<test>_0.o` / `.elf` / `.bin` | Compiled object, ELF, and flat binary |
| `out_*/asm_test/test.hex` | Verilog 32-bit word memory image (`@00000000` = `0x80000000`) |
| `out_*/asm_test/disasm.txt` | Annotated disassembly (`-M no-aliases`) |
| `out_*/spike_sim/<test>_0.log` | Raw Spike ISS commit log |
| `out_*/spike_trace.csv` | Parsed Spike retired-instruction CSV trace |

---

## 5. Step 2 — Compile & Convert to Memory Image (`test.hex`)

`make simulate` depends on `hex` and `disasm` targets, so image generation normally runs automatically. To build only the memory image:

```bash
make hex
```

### Equivalent Manual Commands
```bash
# 1. Convert flat binary to 32-bit word-wide Verilog hex (byte-reversed for RTL memory)
riscv64-unknown-elf-objcopy -I binary -O verilog \
    --verilog-data-width=4 --reverse-bytes=4 \
    out_*/asm_test/<test>_0.bin out_*/asm_test/test.hex

# 2. Generate no-aliases disassembly adjusted to reset vector 0x80000000
riscv64-unknown-elf-objdump -D -b binary -m riscv:rv32 -M no-aliases \
    --adjust-vma=0x80000000 out_*/asm_test/<test>_0.bin > out_*/asm_test/disasm.txt
```

**Important Notes:**
- The program binary is linked/adjusted to **`0x80000000`** (the core's reset vector).
- **`-M no-aliases` is mandatory**: `rtl_log_to_trace_csv.py` and the coverage parser match exact instruction mnemonics against `riscv_instr_pkg`; pseudo-instruction aliases (such as `csrw` or `jr`) would abort trace-to-CSV conversion.

---

## 6. Step 3 — Run the Stream on the RTL Core

### Recommended (`Makefile`)
```bash
make simulate
```

### Equivalent Manual Commands
1. **Elaborate and simulate with Cadence Xcelium (`irun`)** (exact command structure observed in [`out_2026-11-12/rtl_sim/rtl.history`](out_2026-11-12/rtl_sim/rtl.history)):

   ```bash
   irun -clean -64bit -sv -access +rwc -timescale 1ns/1ps \
        -coverage all -covoverwrite \
        -covworkdir out_*/cov_work \
        -incdir RISCFORGE_1TOPS/ips/riscv_core/rtl \
        RISCFORGE_1TOPS/ips/riscv_core/rtl/*.v \
        RISCFORGE_1TOPS/ips/riscv_core/rtl/*.sv \
        rtl_dv_companions/Instruction_Memory.v \
        rtl_dv_companions/Data_Memory.v \
        rtl_dv_companions/tb_riscv_dv.sv \
        -top tb_riscv_dv \
        +instr_file=out_*/asm_test/test.hex \
        +tohost_addr=0x........ \
        -l out_*/rtl_sim/rtl.log
   ```

2. **Convert the raw RTL commit log to CSV trace:**

   ```bash
   python3 scripts/rtl_log_to_trace_csv.py \
       out_*/rtl_sim/rtl.log out_*/rtl_sim/rtl_trace.csv \
       --disasm out_*/asm_test/disasm.txt
   ```

### How Simulation & Termination Work
- `tb_riscv_dv` loads `test.hex` via `+instr_file`, resets `riscv_core`, and executes from `0x80000000`.
- Every retired instruction is recorded (`PCW`, `InstrW`, `GPR` writebacks, etc.) into `out_*/rtl_sim/rtl.log`, then mapped to `out_*/rtl_sim/rtl_trace.csv` using `disasm.txt`.
- Simulation stops when `+tohost_addr` receives the value `1` (`[TB] tohost write detected at 0x8000e000! Test PASSED.` in [`out_2026-11-12/rtl_sim/rtl.log`](out_2026-11-12/rtl_sim/rtl.log#L68016)).
- If `.tohost` was not detected during `generate`, `tb_riscv_dv` falls back to `0x8000c000` (which only matches `riscv_arithmetic_basic_test`; other tests will not self-terminate). You can override it manually:
  ```bash
  make simulate EOT_ADDR=0x80012000
  ```

---

## 7. Step 4 — Compare RTL Trace Against Spike ISS

### Recommended (`Makefile`)
```bash
make compare
```

### What It Runs
1. **`scripts/rtl_no_trap_ref_compare.py`**: Aligns the traces (drops Spike's trailing `ecall` rows and truncates the RTL trace to the same length, producing `spike_trace.csv.cmp` and `rtl_trace.csv.cmp`).
2. **`scripts/instr_trace_compare.py`**: Compares `PC`, instruction mnemonic/binary, GPR writebacks, and memory accesses instruction-by-instruction, reporting `[PASSED]: <N> matched` or detailing any mismatches.

---

## 8. All-in-One Runs, Multi-Seed Sweeps & Functional Coverage

### Single-Seed Full Flow (`generate` + `simulate` + `compare`)
```bash
make base_test GEN_OPTS="+instr_cnt=5000"
```

### Multi-Seed Regression Sweep
```bash
# Run 10 seeds (generate -> RTL sim -> compare)
make seed_sweep TEST_NAME=riscv_arithmetic_basic_test RTL_SEEDS=10 SEED=1

# Print pass/fail summary per seed
make seed_sweep_report

# ISS-only sweep (skip RTL simulation)
make seed_sweep SKIP_RTL=1
```

### Functional Coverage
```bash
# Coverage from RTL commit trace
make coverage

# Fast coverage from Spike logs only (merges all seeds, no RTL required)
make cov_iss

# Multi-seed, multi-test RTL coverage campaign
make cov_rtl_batch RTL_TESTS="riscv_rand_instr_test riscv_illegal_instr_test" \
     RTL_SEEDS=5 COV_NAME=cov_rtl_mixed
make cov_rtl_report COV_NAME=cov_rtl_mixed
```

---


## 9. Quick Reference Card

```tcsh
source env_setup.csh                                   # 0. Setup environment (required)
make generate TEST_NAME=riscv_arithmetic_basic_test    # 1. Generate random stream + Spike trace
make simulate                                          # 2-3. Build test.hex + run Xcelium RTL sim
make compare                                           # 4. Compare RTL trace vs Spike
make seed_sweep RTL_SEEDS=10                           # 5. Multi-seed regression sweep
make coverage                                          # 6. Collect RTL functional coverage
```
