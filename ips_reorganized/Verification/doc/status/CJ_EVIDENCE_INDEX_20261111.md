# CJ Evidence Index — Core Architecture / CSR / Traps / Interrupts / LSU
**Generated:** 2026-11-11 · Workspace: `rtl/ips/Verification` · Owner scope: CJ (architectural correctness + CSR/trap/IRQ/LSU RTL; benchmarks & external SPI boot newly transferred)
**Checklist source:** `rtl/1TOPS OFFICIAL DELIVERABLES/1TOPS_Project_Signoff_Checkl.xlsx` (sheets G1–G6)

> Scope note: This index collects evidence that exists **in this folder** from work dated within the last 7 days. It is not signoff credit; several items remain partial or have open findings (see §6).

---

## 1. Latest-file groups (last 7 days, excluding `build/` / `publication/` / `source_snapshot` duplicates)

| # | Group | Top-level path | Files | Purpose / key result |
|---|---|---|---|---|
| A | CSR/trap unit bench | `infrastructure/tb/`, `tests/csr_trap/`, `filelists/tier1_unit/`, `tools/`, `doc/`, `artifacts/csr_trap_*` | ~510 | XSim unit bench: compile/elab clean; 236 directed bins; 552 expected-value checks, 0 failures; 56 `spec_pending` observations. |
| B | minstret retirement | `minstret_retirement/` | ~278 | Directed retirement-counter verification of `top.v` patch (`instr_retired_W`); 29 functional bins; 12/12 sims pass (waits 0/1/4/9); 13/13 core-port regression pass. |
| C | Core-port regression | `core_port_20261109/` | 18 | Focused core regression vs base/donor: candidate 13/13 pass (MDU, load/MDU, redirect waits, illegal, fetch-fault, trap/MDU, MEPC); legality sweep 131072 combos; MDU-owner leaf; SoC Verilator elaboration 0 errors. |
| D | Hazard / pipeline bench | `hazard_tb/` | 45 | Layered OOP bench (unit + pipeline); Verilator dev campaign: unit 2661 vectors, 342 checked bins, 0 errors; 1 open RTL finding (HZ-F001 ghost store); coverage accounting per group. |
| E | Documentation | `doc/`, `hazard_tb/docs/`, `minstret_retirement/docs/` | ~30 | CSR/trap architecture, corner testplan, verification status, diagrams, gate reports, integrity gate (`check_csr_trap_docs.py` 10/10). |
| F | Plans / SoC TB framework | `plans/`, `system_tb/`, `status/`, `scripts/`, `integration/`, `signoff/` | ~10 | SoC testbench architecture plan (2026-11-04); status tracker builder; integration scripts. |
| G | Top-level runner | `run_csr_trap_units.ps1` | 1 | Reproduces CSR/trap unit bench. |

---

## 2. Checklist item → evidence map (CJ scope)

### G1 — Specification & Architecture
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 1.1 | Core ISA frozen | In Progress | `core_port_20261109/validation.json` (RV32IM Zicsr field policy); `minstret_retirement` programs (RV32IM_Zicsr). Spec doc `Core_Microarchitecture.md` (outside Verification). |
| 1.3 | Privilege modes frozen | In Progress | `minstret_retirement/checklist` (machine-mode traps/MRET); `core_port` trap_mdu/mepc. Spec doc `CSR_and_Trap_Model.md`. |
| 1.4 | CSR list frozen | In Progress | `infrastructure/tb/csr_trap/` (31/31 `csr_regfile` ports); `doc/` CSR/trap architecture; minstret CSR forms. |
| 1.5 | Trap & interrupt model | In Progress | `minstret_retirement/checklist` (ECALL/EBREAK/misaligned/MRET/interrupt bins); `core_port` illegal/fetch_fault/trap_mdu/mepc; `artifacts/csr_trap_*`. |
| 1.9 | Interrupt map frozen | In Progress | `hazard_tb` IRQ characterization (timer interrupt, cause 7, deferral); minstret interrupt bin; `SoC_Architecture_Map_Boot.md` (outside Verification). |

### G2 — Core RTL
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 2.7 | Memory interface / LSU coded | In Progress | `core_port_20261109` load_mdu (waits 0/1/4); minstret LW/SW with 0/1/4/9 wait cycles; `hazard_tb` open finding HZ-F001 (squashed store reaches memory). RTL: `ls_unit.v`. |
| 2.9 | CSR block & trap logic coded | In Progress | `artifacts/csr_trap_closure_check_20261111` (XSim compile/elab + 552 checks/0 fail); `minstret_retirement` (29 bins); `core_port` trap_mdu/mepc/illegal/fetch_fault. RTL: `csr_regfile.v`, `wb_trap_mret_commit_controller.v`. |
| 2.10 | Compressed decoder (N/A if C unsupported) | (blank) | **N/A** — no C extension in scope; no compressed-decoder RTL present. Mark N/A. |

### G3 — Interrupt integration
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 3.4 | PLIC integrated | (blank) | No direct Verification evidence; implementation lives in `clic-master/`. Core-level only: hazard IRQ characterization. **Action: run end-to-end with PLIC model or file waiver.** |
| 3.6 | CLINT/CLIC integrated | (blank) | Same as 3.4; timer interrupt (cause 7) exercised at core level in minstret + hazard. **Action: SoC-level CLINT/CLIC verification pending.** |

### G4 — Unit & core verification
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 4.12 | Reset & interrupt entry verified | In Progress | minstret reset/interrupt bins (cause 7 at precise boundary, mepc save); `core_port` trap_mdu/mepc; CSR unit `u_reset` (4 bins, 24 checks/0 fail); hazard `irq_characterize` (interrupt accepted in EX after MDU release). |

### G5 — Architectural verification
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 5.2 | Official RISC-V ISA / RISCOF tests pass | In Progress | **Not run** (limits in `core_port_20261109/validation.json`: "No official RISCOF or saved riscv-dv seed rerun"). Partial: legality sweep 131072 field combos; minstret 29 bins. **Action: run RISCOF against current RTL.** |
| 5.3 | Privileged / trap tests pass | In Progress | minstret exceptions (ECALL/EBREAK/misaligned/MRET); `core_port` illegal/fetch_fault/trap_mdu/mepc; CSR unit status/metadata (528 checks). |
| 5.7 | Benchmarks run (transferred from Malay) | In Progress | minstret README: Dhrystone smoke/probe pass; CoreMark CRCs match but duration rule fails (no valid score). Integrated evidence: `documentation/core/MINSTRET_RETIREMENT_20261111.md`. |
| 5.10 | Core bug list closed | In Progress | Open finding HZ-F001 (ghost store, issue #30) in `hazard_tb/docs/validation.md`; MDU declaration reorder (XSim VRFC 10-3380) noted in minstret README; `execute_cycle.v:308` `start_M` ordering. **Action: close or waive before claiming.** |

### G6 — SoC verification
| ID | Item | Status (xlsx) | Evidence in this folder |
|---|---|---|---|
| 6.5 | End-to-end interrupt path verified | In Progress | Core-level: minstret timer interrupt (cause 7); hazard IRQ characterization (deferral policy). SoC-level path not yet verified. |
| 6.10 | Boot from external SPI flash passes (transferred from Malay) | In Progress | **No Verification evidence yet** — `plans/soc_testbench_framework_20261104/SOC_TESTBENCH_ARCHITECTURE.html` only. Boot plan in `SoC_Architecture_Map_Boot.md`. **Action: SPI flash model run.** |
| 6.13 | Trap robustness under system load | (blank) | minstret waits 0/1/4/9 with interrupts (held-packet checks); hazard `trap_no_ghost_store` (open); IRQ during busy MDU characterized (deferral). Not closed. |

---

## 3. Quantitative evidence summary

| Metric | Value | Source |
|---|---|---|
| CSR/trap unit bins | 236 (8+168+40+16+4) | `doc/` §3, `tests/csr_trap/generated/cases.stim` |
| CSR/trap expected checks | 552, 0 failures | `doc/` §1 |
| CSR/trap spec_pending observations | 56 (40 collision + 16 counter) | `doc/` §3 |
| minstret functional bins | 29/29 | `minstret_retirement/checklist/README.md` |
| minstret sims | 12/12 (3 programs × 4 waits) | same |
| core-port candidate runs | 13/13 pass | `core_port_20261109/validation.json` |
| core-port base runs | 1/13 pass (only redirect_wait/wait0) | same |
| legality sweep | 131072 combos + 4 SYSTEM guards | same |
| hazard unit vectors | 2661, 342 checked bins, 0 errors (×3 seeds) | `hazard_tb/docs/validation.md` |
| hazard pipeline runs | 12/13 complete, 0 checker errors; 1 open finding | same |
| open RTL findings | HZ-F001 (ghost store, issue #30); MDU decl. ordering (XSim) | same / minstret README |

---

## 4. Supporting deliverables (CJ verification focus)

- **CSR WARL / CSR operation tests, trap-controller & MRET verification:** `artifacts/csr_trap_closure_check_20261111/`, `doc/architecture/CSR_TRAP_TESTBENCH_ARCHITECTURE.html`, `doc/plans/CSR_TRAP_CORNER_TESTPLAN.md`, `doc/status/CSR_TRAP_VERIFICATION_STATUS.md`. Open decisions D1–D6 still pending.
- **Precise exception/interrupt acceptance ordering, CSR write races:** `minstret_retirement/checklist` (trap+MRET collision observations in `doc/` §5); `hazard_tb` (IRQ during busy MDU characterization; HZ-F001).
- **Benchmark configuration, executable images, metrics, reproducibility notes:** `minstret_retirement/checklist/campaigns/20261111T090729Z/` (ELF/bin/hex/dis, reference.json, wait CSVs, coverage.json); Dhrystone smoke/probe pass, CoreMark CRC match but duration fail.
- **External SPI image, bootloader handoff, execution-in-SRAM, pass/fail proof:** Not yet in Verification; needs SPI flash model. Malay supports infrastructure. Boot plan: `SoC_Architecture_Map_Boot.md` (outside this folder).

---

## 5. Open items blocking checklist closure (CJ scope)

1. **5.2 RISCOF / official ISA tests** not run on current RTL.
2. **5.7 Benchmarks** — CoreMark duration rule fails; no valid score yet.
3. **5.10 / 6.13** — HZ-F001 ghost store open (issue #30); MDU declaration ordering (XSim VRFC 10-3380).
4. **3.4 / 3.6 / 6.10** — PLIC/CLIC/SPI-boot need SoC-level evidence or approved waiver.
5. **D1–D6** — CSR collision/counter policy decisions still open (39 collision + 12 counter expectations pending).
6. **Core bins 5–12** (277 bins) defined but 0 sampled; core stimulus not built.

---

## 6. Integrity
- `py tools/check_csr_trap_docs.py` → 10/10 checks pass (ports, filelists, evidence hashes, markers, bin count).
- Source identity for CSR unit run: `sha256:9e68edc9…3903d3c` (10/10 tracked files still match).
- This index is descriptive only; no checklist status was changed in the xlsx.
