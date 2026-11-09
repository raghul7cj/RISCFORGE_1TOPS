# Focused core-port regression

This is development verification for the selective malay core port. It is not a replacement for RISCOF, riscv-dv, benchmark validation, interrupt integration, VCS signoff, or FPGA validation.

Requirements: Python 3, Icarus Verilog 12+, and riscv64-unknown-elf-gcc/binutils supporting RV32IM_Zicsr/ILP32. Run from repository root under Linux/WSL:

```sh
python3 ips_reorganized/Verification/core_port_20261109/run_tests.py
python3 ips_reorganized/Verification/core_port_20261109/run_leaf.py
```

Use `--rtl-root PATH` to select an explicit core source directory, `--baseline-rtl PATH` to include an unchanged baseline comparison, and `--output-dir PATH` to preserve a separate run. run_leaf.py accepts rtl-root/output-dir only. Generated ELF, assembly, images and logs are retained under build/ by default.

The core harness uses synchronous instruction memory and a data responder with declared 0/1/4-cycle waits, explicit byte writes and a bounded watchdog. Firmware independently checks expected arithmetic/register/trap values and reports through a reserved data-memory store. PASS requires that store to carry 1; a different value or timeout fails the simulator. No forced pipeline signals are used in these core tests. The separate execute-stage leaf test drives boundary inputs to exercise completion holding and cancellation, including the next transaction after abort.

The legality sweep fixes rs1/rs2/rd to nonzero fields and enumerates 128 opcodes x 8 funct3 x 128 funct7 combinations, then checks four exact SYSTEM guards. It checks the selected RV32IM field policy, not every encoding/state/CSR-access combination. FENCE/FENCE.I and WFI recognition preserve the donor policy; CSR-address validation is not established here.

The direct tests do not measure code/functional coverage, establish an architectural retirement oracle, or run the saved failing random seeds. Icarus warnings from existing multiplier widths are retained. Full-SoC Verilator lint uses the complete Verification/filelists/tier3_soc/soc_subsystem.f, -DXSIM compatibility and -Wno-fatal for existing warnings; this is elaboration evidence, not clean signoff lint.
