# Directed retirement verification chain

Scope: Real core with injected memory waits and timer input. An expected instruction path and final-state checks support the declared functional bins; not full-SoC peripheral verification.

```mermaid
flowchart LR
  assembly["Three assembly programs"]:::present
  build["ELF + SRAM image build"]:::present
  driver["TB memory + timer drivers"]:::present
  oracle["Software path reference"]:::present
  dut["Real top core"]:::present
  checker["PC + counter + memory / checks at clock edges"]:::present
  report["Passing-bin collection / coverage.json"]:::present
  assembly -->|"assemble"| build
  build -->|"ELF / SRAM images"| driver
  build -->|"assembled words"| oracle
  driver -->|"memory / waits / timer"| dut
  dut -->|"WB/CSR"| checker
  oracle -->|"expected PCs"| checker
  checker -->|"verdict"| report
  classDef present fill:#e8f1ff,stroke:#2b6cb0,color:#111
  classDef planned fill:#fff8e1,stroke:#b7791f,stroke-dasharray:5 3,color:#111
  classDef absent fill:#fdecea,stroke:#c53030,stroke-dasharray:2 2,color:#111
  classDef uninspected fill:#f2f2f2,stroke:#888,stroke-dasharray:2 4,color:#444
```

Source identity: `raghul7cj/RISCFORGE_1TOPS verification_infra + source-overlay 8647af8b6fe7` @ `25d7b8ebf4ae8ab4da39f144df097676145e3dae`. Spec: `testbench.spec.json` (sha256 `7d5a3572d30b`).

| Element | Status | Source | Symbol |
|---|---|---|---|
| assembly | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:185` | `for case in [` |
| build | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:189` | `riscv64-unknown-elf-gcc` |
| driver | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:4` | `module tb_checklist;` |
| oracle | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:32` | `def execute_reference(` |
| dut | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:23` | `top #(.RESET_PC` |
| checker | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:86` | `before_count=dut.csr_file.minstret_r;` |
| report | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:242` | `summary["functional_checklist_closed"]` |
| assembly -> build | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:190` | `HERE / f"{case}.S"` |
| build -> driver | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:209` | `f"+HEX={image.with_suffix` |
| build -> oracle | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:201` | `reference = execute_reference(words, labels)` |
| driver -> dut | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:29` | `.timer_irq_i(timer_irq)` |
| dut -> checker | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:86` | `before_count=dut.csr_file.minstret_r;` |
| oracle -> checker | present | `ips_reorganized/Verification/minstret_retirement/checklist/tb_checklist.sv:43` | `$readmemh(reference,expected_pc` |
| checker -> report | present | `ips_reorganized/Verification/minstret_retirement/checklist/run_checklist.py:218` | `passed = result.returncode == 0` |

Unknown / not inspected (deliberately not drawn as fact):
- The interrupt acceptance cycle is aligned to the reported precise PC, not independently predicted.
- The per-cycle consume predicate mirrors the contract; the reference path length, traps and final memory are independent checks.
