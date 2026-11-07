# Core block-level UVM benches

Block-level UVM testbenches for three units of the RV32IM core (`../rtl`), each with constrained-random
stimulus, a reference model written from the RISC-V spec and the core's control encodings, covergroups,
and Xcelium code coverage.

| Unit | DUT | Bench | Tests |
| --- | --- | --- | --- |
| `alu` | `ALU.v` | `alu/alu_pkg.sv` | `alu_test` |
| `dec` | `Control_Unit_Top.v` (+ `Main_Decoder`, `ALU_Decoder`, `opcode_check`) and `Sign_Extend.v` | `dec/dec_pkg.sv` | `dec_test`, `dec_illegal_test` |
| `haz` | `hazard_unit.v` | `haz/haz_pkg.sv` | `haz_test` |

Each `*_pkg.sv` holds the interface, item, sequence, driver, monitor, scoreboard, coverage, env, test and
the `*_tb` top. The reference model is in `*_ref.svh`.

## What is checked

- **ALU**: all 11 operations plus the 5 unused encodings (must give 0), result, `Zero`, the three compare
  flags. Operands biased to 0, 1, `0x7FFFFFFF`, `0x80000000`, `0xFFFFFFFF`, equal operands, shift amounts 0-31.
- **Decoder**: every legal RV32IM + Zicsr instruction: all control outputs, `ALUControl`, the immediate for
  every format, `csr_op`/`csr_imm_mode`, `mret`, and `illegal_instr = 0`.
  `dec_illegal_test` sends invalid encodings (bad opcode, funct3, funct7, shift amount, SYSTEM) and expects
  `illegal_instr = 1`.
- **Hazard unit**: forwarding A/B (MEM over WB, never x0), load-use, CSR-to-GPR and CSR read-after-write
  stalls, stalls and flushes with memory stall, M-unit stall, branch redirect, exceptions in EX/MEM,
  writeback redirect and the flush one-hot.

## Run (from this folder)

```bash
make run UNIT=alu
make run UNIT=dec TEST=dec_illegal_test
make run UNIT=haz N=20000 SEED=5
make regress
make cov_report
```

`make regress` runs every test with seeds `1 2 3` (`SEEDS=`), 5000 items each (`N=`), and prints one line per
run with the check counts and functional coverage. `make cov_report` merges each unit's runs and writes
`logs/cov_<unit>.txt` (code + functional coverage per instance).

## Known result

`dec_illegal_test` fails: `opcode_check.v` only checks the 7-bit opcode, so invalid funct3/funct7/shift
encodings, `sret`/`uret` and bad SYSTEM forms are executed instead of raising an illegal-instruction exception.
