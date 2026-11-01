# RISCFORGE P0 Bring-Up Execution Contract

> **Document ID:** RF-CONTRACT-P0-2026-B  
> **Status:** FROZEN EXECUTION CONTRACT  
> **Baseline:** Verification Plan Rev B (`RISCFORGE_Verification_Plan_RevB.docx`), Section 21 & Table 21.10  
> **Date Stamped:** 2026-10-31  

---

## 1. P0 Bring-Up Scope & Purpose

Phase 0 (Bring-up) establishes that the verification harness can build the intended SoC subsystem, deliver valid stimulus to the DUT, achieve non-zero instruction retirement and bus transactions, and retain full execution provenance. P0 does not assert broader architectural or functional sign-off (which belongs to P1–P6).

---

## 2. Pinned Environment & Tools

All P0 evaluation must be executed on the following pinned environment (satisfying Rev B Table 5.1 / P0-G1.3):

* **Host Operating System:** Windows 11 Enterprise / Pro (64-bit)
* **EDA Simulator of Record:** AMD Vivado XSim v2022.2 (SW Build 3671981)
  * Secondary / Reference Simulator: Cadence Xcelium 20.09 / 22.09
* **Software Toolchain:** GNU RISC-V GCC 13.2.0 (`riscv64-unknown-elf-gcc`, target `-march=rv32im_zicsr -mabi=ilp32 -O2 -nostartfiles`)
* **Python Environment:** CPython 3.12 (via `py.exe` / Python launcher)

---

## 3. Golden Design Identity (Rev B Table 21.10)

The golden design source set is fixed strictly to `RTL_SOC/soc_subsystem.f`.

* **Master Filelist:** `RTL_SOC/soc_subsystem.f`
* **Filelist SHA-256 (`H_filelist`):** `a931d6b425a197bb03ac237378839b7628cc0893743bc59f25a4d29f1a0e5407`
* **Design File Count:** 90 verified source files (0 unresolved, 0 absolute paths)
* **RTL Composite Manifest (`manifest_rtl.sha256`):** Byte-wise sorted ASCII list of `<sha256>  <posix_path>` with LF line endings.
* **RTL SHA-256 (`H_rtl`):** `d25104a436315617194263f1c3338eb1c4e596b0390cb5a34df91219c3b2edf1`

### Identity Predicates:
* **ID-1 (Reachable Divergent Copies):** `timer.sv` copies converged byte-identical (`D352FC44...`); `apb_to_obi.sv` golden copies converged byte-identical (`91ED8D6E...`).
* **ID-2 (Unresolved Entries):** 0 unresolved entries in master filelist.
* **ID-3 (Absolute Path Entries):** 0 absolute paths in master filelist.

---

## 4. Acceptance Predicates (Gates G0 & G1)

### Gate G0 (Harness Integrity)
Pass only when all of the following are satisfied in a single package:
1. `unresolved_modules == 0` against the golden module set.
2. `extra_modules == 0` against the golden module set.
3. Simulator and toolchain versions pinned and recorded (Section 2).
4. Artifact write test passes cleanly.
5. Compilation log, elaboration log, and filelist diff report retained together.

### Gate G1 (Stimulus Reached DUT)
In the P0 boot scenario (`boot_hello` / `stage3_monitor_count`), record and require:
1. `instructions_retired > 0` (Empirical baseline: 5,551).
2. `axi_transfers > 0` (Empirical baseline: 14 reads + 4 writes = 18).
3. `apb_transfers > 0` (Empirical baseline: 18 transfers, 0 PSLVERR).
4. `attestation_words_written > 0` (Explicit count = 1; value = `0x0004000e`).
5. Complete counter block and signed verdict retained with the manifest.

### Scenario Acceptance Thresholds (Stage 3 Profile):
* Instructions Retired: $\ge 5,000$
* AXI Read Transfers: $\ge 14$
* AXI Write Transfers: $\ge 4$
* APB Bus Transfers: $\ge 18$
* Fatal Checks / Vacuity Violations: Exactly $0$

---

## 5. Frozen Evidence Baseline

* **Reference Passing Run:** `Verification/artifacts/stage_proofs/20261024_stage3_monitor_count`
* **Test:** `stage3_monitor_count` (Boot Mode: WARM, Timeout: 1,000,000 cycles)
* **Status:** Passed DUT execution; repackaging at final identity stamps complete P0 exit.
