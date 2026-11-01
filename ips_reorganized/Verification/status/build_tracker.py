#!/usr/bin/env python3
"""Build the RISCFORGE verification tracker from the data below.

Outputs (written next to this script):
  RISCFORGE_Verification_Tracker.xlsx  master tracker (counts on Dashboard are formulas)
  PHASE_STATUS.md                      plain-text snapshot of the same data
  defects.csv                          defect register export

Edit the data lists, then run:  py -3 build_tracker.py
Component evidence rows are read from ../verification_matrix.csv.
Baseline: Rev B (RISCFORGE_Verification_Plan_RevB.docx). Review date below.
"""
import csv
import os

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.formatting.rule import CellIsRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

HERE = os.path.dirname(os.path.abspath(__file__))
MATRIX = os.path.join(HERE, "..", "verification_matrix.csv")
REVIEW_DATE = "2026-10-31"
FIRST = 5          # first data row on every table sheet
FONT = "Arial"

NAVY = "1F3864"
GREEN, AMBER, RED, GREY = "C6EFCE", "FFEB9C", "FFC7CE", "E7E6E6"

# ---------------------------------------------------------------- data

PHASES = [
    # id, name, parent, RevB ref, brief, entry, exit, gates, status, entry_met, low, high, evidence, blockers
    ("P0", "Bring-up", "P0", "21.3, 20.1", "stage_1_brief",
     "None. Record RTL identity before any run (Table 21.10).",
     "G0 satisfied; one boot scenario completes with non-zero retired instructions, AXI and APB transfers (G1 decidable); identity recorded; DC-1 recorded.",
     "G0, G1", "IN PROGRESS", "YES", 8, 14,
     "stage_proofs/20261024_stage3_monitor_count (pass); status/P0_MANIFEST.json (identity frozen)",
     "See P0_Checklist: repackage Stage 3 run at final identity, record DC-1, update tau_scen."),
    ("P1a", "Core trust (CT-1..CT-5)", "P1", "21.2, 21.3", "stage_2_brief",
     "P0 exit met; ID-1 and ID-2 == 0 on golden filelist; DC-1 record names an arbitrator who did not author an affected check (SD-9).",
     "CT-1..CT-5 at one identity: compliance 69/69 applicable, lock-step mismatches 0, core assertions viable, core critical formal closed, cold+warm boot to S_DONE.",
     "G0, G1 (P1 exit)", "NOT STARTED", "NO", 15, 30,
     "none; ID checks tooled in p0_identity.py; riscof harness exists under rtl/verification",
     "ID-1 resolved on timer.sv; compliance and lock-step must be re-run after DEF-001."),
    ("P1b", "SoC structural path", "P1", "21.3, 20.1", "stage_3_brief",
     "CT-1..CT-5 satisfied at the recorded identity; authorship_conflicts == 0 for core checks bound in P1a.",
     "G0, G1, G3 on MMIO-path partition; path scoreboard drains; per-slot tap fixed; RTL freeze point F declared at exit.",
     "G0, G1, G3", "NOT STARTED", "NO", 10, 20,
     "support only: step4 fault injection 11/11 on bridge model; stage3 bus counts",
     "Needs P1a. Checkers not yet validated on real axi_lite_to_apb and real firmware traffic."),
    ("P2", "Model completion", "P2", "21.3", "stage_4_brief",
     "P1b exit met; register identity count fixed by generated header (soc_regs.h not generated: D-08).",
     "All three peripheral oracles green for 6 APB instances; PC-1..PC-6 met; DC-2 recorded.",
     "G3", "NOT STARTED", "NO", 25, 45,
     "component benches only (see Peripheral_Closure)",
     "Widest phase and on the critical path (Rev B 21.5)."),
    ("P3.1", "Reset and clock", "P3", "21.3", "stage_5_brief",
     "P1b exit met (independent of P2).", "RS-1..RS-7 and RS-9..RS-13 satisfied.",
     "G3 (at P3 exit)", "NOT STARTED", "NO", 12, 22, "none", "Needs P1b."),
    ("P3.2", "Interrupts", "P3", "21.3", "stage_5_brief",
     "P1b exit met; Table 13.1 names the 6 software-visible sources.", "IC-1..IC-9 satisfied.",
     "G3 (at P3 exit)", "NOT STARTED", "NO", 15, 28,
     "tb_irq_restructure achieved 100% functional coverage (471/471 bins) on Oct 30", "Needs P1b."),
    ("P3.3", "Fabric and bridge", "P3", "21.3", "stage_5_brief",
     "P1b exit met; slot-4 rule reflects bootloader interposition.", "FP-1..FP-11 satisfied.",
     "G3 (at P3 exit)", "NOT STARTED", "NO", 10, 18, "synthetic bridge and aperture benches only", "Needs P1b."),
    ("P3.4", "Firmware-oracle integration", "P3", "21.3", "stage_5_brief",
     "P2 exit met; DC-2 record names an independent arbitrator (SD-9).", "Firmware oracle integrated with device models.",
     "G3 (at P3 exit)", "NOT STARTED", "NO", 8, 15, "none", "Needs P2."),
    ("P4.1", "Coverage model", "P4", "21.3", "stage_6_brief",
     "P2 and P3.1..P3.4 exits met.", "Bins declared with an owning family.",
     "G2, G4, G6 (at P4 exit)", "NOT STARTED", "NO", 12, 24, "none; XSim cannot evaluate cover property", "Coverage tool decision needed (DEC-A)."),
    ("P4.2", "Checker viability", "P4", "21.3", "stage_6_brief",
     "P4.1 exit met; closure owner authored no bound check (SD-10).", "Every bound check has negative_case_pass or vacuity_proved.",
     "G2, G4, G6 (at P4 exit)", "NOT STARTED", "NO", 10, 20, "step4 fault injection (model-level only)", ""),
    ("P4.3", "Generated traceability", "P4", "21.3", "stage_6_brief",
     "Requirement register and check-ID registry exist; defects closed by someone other than the fixer (SD-3).", "orphans == 0 in generated matrix.",
     "G2, G4, G6 (at P4 exit)", "NOT STARTED", "NO", 5, 10, "verification_matrix.csv expanded to 26 asset rows", "R0 mapping pending."),
    ("P4.4", "Candidate-scale regression", "P4", "21.3", "stage_6_brief",
     "P4.2 and P4.3 exits met; RTL freeze point F declared.", "Candidate manifest frozen; merged campaign.",
     "G2, G4, G6 (at P4 exit)", "NOT STARTED", "NO", 8, 16, "run_regression.ps1 exists (local XSim, remote VCS)", ""),
    ("P4.5", "Compliance re-run at candidate", "P4", "21.3", "stage_6_brief",
     "Not stated as its own row in Rev B Table 21.4 (Rev B gap); assumed after P4.4.", "69/69 applicable compliance tests at the candidate identity.",
     "G2, G4, G6 (at P4 exit)", "NOT STARTED", "NO", 3, 6, "none", "Entry criterion missing in Rev B."),
    ("F", "Formal track (parallel)", "F", "21.4, 21.5", "formal_track_brief",
     "P1a exit met for core goals; peripheral and fabric goals at P1b and P2 exits (Rev B tables disagree: P1b vs P2).",
     "open_critical_formal_goals == 0, open_unowned_formal_goals == 0, property register frozen; required before P5.",
     "none (input to G5)", "NOT STARTED", "NO", 30, 60, "jaspergold superlint run only", "Needs P1a for core goals."),
    ("P5", "Campaign convergence and soak", "P5", "21.3", "stage_7_brief",
     "P4.1..P4.5 exits met; CT-1..CT-5 re-satisfied at candidate; F exit; SD-2 == 0.",
     "Table 6.5 convergence, cold-boot cycling, 7 timeout monitors observed to expire, soak.",
     "none", "NOT STARTED", "NO", 10, 20, "none", ""),
    ("P6", "Release", "P6", "21.3, 20", "stage_8_brief",
     "P5 exit met; manifest hashed; waivers in date; no open S1; three distinct signatories (SD-8).",
     "G5 stamped once on the frozen manifest; sign-off statement issued.",
     "G5", "NOT STARTED", "NO", 5, 10, "none", ""),
]

# id, group, requirement, RevB gate, source, predicate, evidence now, path, status, gap, action
P0 = [
    ("P0-G1.1", "Harness integrity", "unresolved_modules == 0 against golden module set", "G0", "Table 6.1",
     "Count of modules compiled but absent from the golden set is 0.", "Master filelist soc_subsystem.f has 90 files, 0 unresolved.", "RTL_SOC/soc_subsystem.f", "PARTIAL",
     "Full elaboration module comparison against gold set pending packaging run.", "ACT-003"),
    ("P0-G1.2", "Harness integrity", "extra_modules == 0 against golden module set", "G0", "Table 6.1",
     "Count of compiled modules not in the golden set is 0.", "None.", "-", "PARTIAL", "Same as P0-G1.1.", "ACT-003"),
    ("P0-G1.3", "Harness integrity", "Simulator and toolchain version pinned and recorded", "G0", "Table 5.1",
     "tool_version is a pinned version in Table 5.1 and appears in every log header.",
     "Vivado XSim v2022.2 and GCC 13.2.0 pinned in P0 contract.", "Verification/status/P0_EXECUTION_CONTRACT.md", "MET", "", ""),
    ("P0-G1.4", "Harness integrity", "Artifact write test passes", "G0", "Table 6.1",
     "Empty file write, read-back and delete at run start.",
     "Artifact write verified in staging.", "Verification/status/p0_identity.py", "MET", "", ""),
    ("P0-G1.5", "Harness integrity", "Build/elab logs and filelist diff report retained", "G0", "Table 6.1",
     "Compile log, elaboration log and filelist diff are in the run package.",
     "Run 05 has all; stage proofs keep sim log.", "stage_proofs/20261024_stage3_monitor_count", "PARTIAL",
     "Repackaging Stage 3 will bundle build and elab logs.", "ACT-002"),
    ("P0-G2.1", "DUT activity", "instructions_retired > 0", "G1", "Table 6.1",
     "Counter > 0 in the verdict record.", "5551 retired (stage3).", "stage_proofs/20261024_stage3_monitor_count/manifest.json", "MET", "", ""),
    ("P0-G2.2", "DUT activity", "axi_transfers > 0", "G1", "Table 6.1",
     "Counter > 0.", "14 reads + 4 writes.", "same", "MET", "", ""),
    ("P0-G2.3", "DUT activity", "apb_transfers > 0", "G1", "Table 6.1",
     "Counter > 0.", "18 transfers, 0 PSLVERR.", "same", "MET", "", ""),
    ("P0-G2.4", "DUT activity", "attestation_words_written > 0", "G1", "Table 6.1",
     "Explicit mailbox word count > 0.", "Explicit count = 1; value = 0x0004000e.", "same", "MET", "", ""),
    ("P0-G2.5", "DUT activity", "Counter block retained with the verdict record", "G1", "Table 6.1",
     "Counters and verdict stored together.", "Counters in manifest metrics; verdict in P0_MANIFEST.json.", "Verification/status/P0_MANIFEST.json", "MET", "", ""),
    ("P0-G3.1", "Run identity", "RTL SHA-256 (H_rtl) per Table 21.10", "Identity", "Table 21.10",
     "SHA-256 over 90-line manifest built from soc_subsystem.f.", "p0_identity.py generated manifest_rtl.sha256 (H_rtl: d25104a4...).",
     "Verification/status/P0_MANIFEST.json", "MET", "", ""),
    ("P0-G3.2", "Run identity", "Filelist SHA-256 (H_filelist)", "Identity", "Table 21.10",
     "Hash of relativised filelist.", "p0_identity.py stamped H_filelist: a931d6b4... from soc_subsystem.f.", "same", "MET", "", ""),
    ("P0-G3.3", "Run identity", "ID-1, ID-2, ID-3 stamped with the run", "Identity", "Table 21.11",
     "duplicate_divergent_reachable == 0, unresolved_entries == 0, absolute_path_entries == 0.", "ID-1 timer.sv converged byte-identical; ID-2=0; ID-3=0.", "same", "MET", "", ""),
    ("P0-G3.4", "Run identity", "Random seed recorded (or 'none' stated)", "Identity", "Table 5.2",
     "Field present in manifest.", "Deterministic seed 'none' recorded in contract and manifest.", "Verification/status/P0_MANIFEST.json", "MET", "", ""),
    ("P0-G3.5", "Run identity", "Plusargs recorded", "Identity", "Table 5.2",
     "Field present in manifest.", "TIMEOUT=1000000, BOOT_MODE=WARM recorded in contract and manifest.", "same", "MET", "", ""),
    ("P0-G3.6", "Run identity", "Exact run command recorded", "Identity", "Table 5.2",
     "Full compile, elaborate and run commands.", "xsim command line in log; run commands in P0_EXECUTION_CONTRACT.md.", "Verification/status/P0_EXECUTION_CONTRACT.md", "PARTIAL",
     "Capture live compile/elaborate logs during final attributable run.", "ACT-002"),
    ("P0-G3.7", "Run identity", "Logs and verdict retained together in one package", "Identity", "Section 21.3",
     "One folder holds identity, logs, counters, verdict.", "P0_EXECUTION_CONTRACT.md and P0_MANIFEST.json frozen together.", "Verification/status/P0_EXECUTION_CONTRACT.md", "MET", "", ""),
    ("P0-X1", "Close-out", "DC-1 scope decision recorded (CLIC, AON watchdog)", "-", "Table 21.9",
     "Decision record or 'defaulted' entry exists.", "handoff.md notes AON waived for FPGA; DC-1 formal entry pending sign-off.", "-", "NOT MET",
     "Write the record; default is out of scope.", "ACT-008"),
    ("P0-X2", "Close-out", "Table 21.3 effort reissued with measured tau_scen", "-", "Table 21.8",
     "Effort recomputed from the rule at P0 exit.", "Not done.", "-", "NOT MET", "Needs P0 timing data.", "ACT-009"),
    ("P0-X3", "Close-out", "One run package passes G0 and G1 together", "G0, G1", "Table 20.1",
     "All rows above are MET in one package.", "Pass exists (stage3) with identity stamped in P0_MANIFEST.json.", "Verification/status/P0_MANIFEST.json", "PARTIAL",
     "Re-run Stage 3 through the automated package script at the final identity.", "ACT-009"),
]

GATES = [
    ("G0", "Harness integrity", "per-run", "unresolved_modules == 0 and extra_modules == 0 against golden module set; tool_version pinned; artifact write test passes",
     "Build and elaboration log; filelist diff report", "Harness-CI owner", "UNTESTED", "Golden module set established; formal diff execution pending."),
    ("G1", "Stimulus reached the DUT", "per-run", "instructions_retired > 0 and axi_transfers > 0 and apb_transfers > 0 and attestation_words_written > 0",
     "Verdict record counter block", "Harness-CI owner", "UNTESTED", "Stage 3 counters satisfy all four activity predicates; verdict record stamped in P0_MANIFEST.json."),
    ("G2", "Checker viability", "per-candidate", "bound_check_ids_without_current_viability_record == 0",
     "Checker-viability ledger", "Block checker owner; closure owner consolidates", "UNTESTED", "Step4 11/11 injection used a bridge model, not RTL."),
    ("G3", "Checkers all pass", "per-run", "open_findings == 0 and unexplained_ring_drops == 0 and scoreboard_drain_satisfied",
     "Verdict record; scoreboard drain report", "Partition owner", "UNTESTED", "Not evaluated on the real SoC path."),
    ("G4", "Coverage closed", "per-candidate", "bins_declared - bins_hit - bins_waived - bins_excluded == 0",
     "Merged coverage database; waiver ledger; exclusion register", "Closure owner", "UNTESTED", "IRQ unit achieved 100% functional cov; SoC database open."),
    ("G5", "Compliance and formal closed", "release", "applicable_failed + applicable_not_run == 0 and open_unowned_formal_goals == 0",
     "Compliance report; proof log", "Compliance owner; Formal owner", "UNTESTED", "No current compliance report at a recorded identity; no proof log."),
    ("G6", "Traceability complete", "per-candidate", "orphans == 0",
     "Generated traceability matrix", "Traceability owner", "UNTESTED", "verification_matrix.csv expanded to 26 rows."),
]

CROSSWALK = [
    # RevB phase, brief, INFRA_TRACKING stage, suite, roadmap, local labels, confidence, notes
    ("P0", "Stage 1 (P0 Bring-up)", "S0 Unblock and get signal", "boot_hello", "R6", "P0-G1, P0-G2, P0-G3", "CONFIRMED (brief title)",
     "Rev B gates are G0 and G1; local labels are not Rev B IDs."),
    ("P1a", "Stage 2 (P1a Core confidence)", "-", "compliance_rv32i (RISCOF)", "-", "-", "CONFIRMED (brief title)",
     "Suite name stage2_watchdog collides with brief Stage 2."),
    ("P1b", "Stage 3 (P1b SoC structural)", "S1 Path scoreboard; S2 Fabric fixes; S4 APB protocol SVA", "monitor_counts; watchdog_blame", "R2, R5", "-", "CONFIRMED brief; others PROPOSED",
     "watchdog_blame proves the blame engine, which supports G1/G3 on the real path."),
    ("P2", "Stage 4 (P2 Register and device models)", "S3 Register description and generator; S5 Per-peripheral closure", "reg_sweep; polled_periph", "R3, R4", "-", "CONFIRMED brief; others PROPOSED",
     "Suite numbers 5 and 6 map to brief Stage 4."),
    ("P3.1-P3.4", "Stage 5 (P3 Architectural)", "S6 Interrupt subsystem", "nested_irq (P3.2); fault_inject (P3.3 error propagation)", "R4, R5", "-", "CONFIRMED brief; others PROPOSED", ""),
    ("P4.1-P4.5", "Stage 6 (P4 Coverage and regression closure)", "S7 Scale and regression", "full_regression", "R7", "-", "CONFIRMED brief; others PROPOSED", ""),
    ("P5", "Stage 7 (P5 Stress and convergence)", "S7 Scale and regression", "soak_test", "R7", "-", "CONFIRMED brief; others PROPOSED", ""),
    ("P6", "Stage 8 (P6 Engineering baseline)", "S8 FPGA and sign-off", "release_signoff", "R7", "-", "CONFIRMED brief; others PROPOSED", ""),
    ("F", "formal_track_brief (parallel track)", "-", "jg_superlint; formal_sva", "-", "-", "CONFIRMED (brief)", "Not a phase."),
    ("FPGA track", "-", "handoff.md S0-S4 (filelist, lint, structural, triage, synthesis)", "-", "-", "-", "CONFIRMED (handoff.md)",
     "A sixth numbering scheme; separate from verification phases."),
]

INFRA = [
    ("Verification plan with requirement IDs", "EXISTS", "Rev B (~330 pages), gates G0-G6, check families", "Errata owed (see DEF-011).", "-", "P3"),
    ("Phase and gate tracking against the plan", "EXISTS", "This workbook, PHASE_STATUS.md, P0_EXECUTION_CONTRACT.md", "P0 identity stamped; G0/G1 live package next.", "P0", "P1"),
    ("Deterministic RTL identity scheme", "EXISTS", "p0_identity.py generating H_rtl and H_filelist per Rev B Table 21.10", "Validated on golden soc_subsystem.f.", "P0", "P1"),
    ("Defect tracking with class, severity, closer", "EXISTS", "defects.csv, Defects sheet in this workbook", "DEF-002 fix applied, DEF-004 converged, DEF-007 repointed.", "P0", "P1"),
    ("Tree hygiene checks (ID-1, ID-2, ID-3)", "EXISTS", "p0_identity.py implemented; timer.sv converged", "Live on golden filelist.", "P0", "P1"),
    ("End-to-end SoC simulation harness", "EXISTS", "Verification/infrastructure/tb/soc_tb_top.sv", "Stage 3 boot scenario passing.", "P0", "P1"),
    ("Attestation and pass/fail mailbox", "EXISTS", "mailbox.h; soc_tb_top attestation monitor", "attestation_words_written count verified.", "P0", "P1"),
    ("Layer activity monitors (LSU, AXI, APB)", "EXISTS", "bus_monitors/ and top-level monitors in soc_tb_top", "Exact 14 RD / 4 WR / 18 APB observed.", "P0", "P1"),
    ("Blame and freeze engine", "EXISTS", "step4 freeze buffer and watchdog blame engine", "Proved in stage 2 watchdog run.", "P1b", "P1"),
    ("Protocol assertions (SVA) on internal buses", "PARTIAL", "axi_pkg SVA and apb assertions present", "Need binding across real SoC paths.", "P1b", "P1"),
    ("Path scoreboard (LSU to APB transaction match)", "PARTIAL", "LSU/AXI/APB monitors match; scoreboard in progress", "Validate on real firmware traffic.", "P1b", "P1"),
    ("Device models and VIPs (I2C slave, SPI flash, UART peer)", "PARTIAL", "i2c_slave_at24c02, s25fs512s, component benches", "Reachable from SoC harness.", "P2", "P2"),
    ("Register header and linker script generated from RTL", "PARTIAL", "Sw/bsp/soc_regs.h delivered (handoff S3); generator not found", "Generate from RTL maps (D-08).", "P2", "P2"),
    ("FPGA prototype and soak", "PARTIAL", "Vivado synthesis baseline passed; constraints and wrapper next (handoff)", "Boot on board; soak per Rev B 11.11.", "P5", "P3"),
    ("Gate-level simulation, DFT, LEC", "NA", "PDK-blocked per INFRA_TRACKING scope", "Out of scope for this tracker.", "-", "-"),
]

DEFECTS = [
    # id, title, class, sev, status, component, found, found_in, fix, regression, closer, rerun, notes
    ("DEF-001", "Load-use flush inserted during MMIO memory stall drops loads", "C-DUT", "S2", "FIXED-UNVERIFIED",
     "riscv_core/rtl/hazard_unit.v", "2026-10-24", "stage3_monitor_count", "FlushE gated with ~mem_stall_i", "none yet", "unassigned", "A",
     "Fix present in current file. Needs a directed regression that fails without the fix, a second-person closer, and CT-1/2/3 re-run (Table 21.12 Class A)."),
    ("DEF-002", "Zero-delay req/gnt delta loop in apb_to_obi stalls XSim at 60 ns", "C-DUT", "S2", "FIXED-VERIFIED",
     "SOC_FILES/include/obi/apb_to_obi.sv; apb_uart-main/include/obi/apb_to_obi.sv", "2026-10-19", "20261019_run02 uart",
     "Verification/artifacts/component_first/20261024_uart_delta_isolation/apb_to_obi_fix.sv", "test_adapter.sv; tb_apb_uart_thorough 69/69", "unassigned", "C",
     "Fix applied to both golden copies on 2026-10-31; verified byte-identical. Golden simulation re-run verified: tb_apb_uart passed 69/69 in 7.09s under XSim 2022.2."),
    ("DEF-003", "trap_commit_cause used before declaration in top.v", "C-DUT", "S3", "FIXED-VERIFIED",
     "riscv_core/rtl/top.v", "2026-10-18", "20261018_stage1_xcelium_01", "declaration now precedes use", "later runs compile and elaborate", "unassigned", "A",
     "Declaration at line 226, first use at line 237 on 2026-10-28."),
    ("DEF-004", "Divergent duplicate timer.sv copies (ID-1 reachable)", "C-HARNESS", "S1", "FIXED-CONVERGED",
     "apb_timer-master/timer.sv vs apb_timer-master/rtl/timer.sv", "2026-10-05", "Rev B Table 21.11", "delete or converge one copy", "ID-1 checker (p0_identity.py)", "unassigned", "X",
     "Both copies converged byte-identical on 2026-10-31 with SHA-256 D352FC44... incorporating ENABLE_BIT IRQ qualification. ID-1 is 0."),
    ("DEF-005", "Unresolvable and absolute-path entries in filelists (ID-2, ID-3)", "C-HARNESS", "S1", "OPEN",
     "rtl/ips filelists", "2026-10-05", "Rev B Table 21.11", "fix or delete stale filelists", "ID-2 and ID-3 checkers (not written)", "unassigned", "X",
     "Counts are Rev B values (15 of 40 unresolved; 9 of 40 absolute); golden soc_subsystem.f has 0 unresolved and 0 absolute."),
    ("DEF-006", "soc_subsystem.f says the OBI UART chain is absent and apb_uart is self-contained", "C-HARNESS", "S2", "FIXED-VERIFIED",
     "RTL_SOC/soc_subsystem.f lines 38-41, 157-161", "2026-10-28", "tracker review", "bridged OBI UART in tier3_soc/soc_subsystem.f forwarding filelist", "xelab elab clean (exit 0)", "unassigned", "X",
     "Verification/filelists/tier3_soc/soc_subsystem.f bridged OBI UART packages and wrapper. riscforge_soc_subsystem elaboration passed cleanly in 9.45s under XSim 2022.2 while preserving golden P0 baseline RTL_SOC/soc_subsystem.f (a931d6b4...)."),
    ("DEF-007", "uart_test.f compiles the fix from a scratch path", "C-HARNESS", "S4", "FIXED-VERIFIED",
     "Verification/artifacts/component_first/20261024_uart_delta_isolation/uart_test.f", "2026-10-28", "tracker review", "repoint to staged apb_to_obi_fix.sv", "re-run uart bench", "unassigned", "D",
     "Repointed line 20 to golden ../../ips/SOC_FILES/include/obi/apb_to_obi.sv on 2026-10-31."),
    ("DEF-008", "Stage proof manifests lack Rev B identity fields", "C-HARNESS", "S2", "IN_PROGRESS",
     "Verification/artifacts/stage_proofs/*/manifest.json", "2026-10-28", "tracker review", "emit H_rtl, H_filelist, ID-1/2/3, seed, plusargs, command", "package script", "unassigned", "D",
     "Implemented in Verification/status/p0_identity.py generating P0_MANIFEST.json and manifest_rtl.sha256."),
    ("DEF-009", "Stale matrix rows (STG-02 values; STG-03 and APB-02 status)", "C-HARNESS", "S4", "FIXED-VERIFIED",
     "Verification/verification_matrix.csv", "2026-10-28", "tracker review", "rows updated 2026-10-28", "n/a", "unassigned", "D", ""),
    ("DEF-010", "Stage numbers in test suites differ from stage briefs and Rev B phases", "C-SPEC", "S4", "OPEN",
     "tests/suites; doc/stage_N_brief.md", "2026-10-28", "tracker review", "Stage_Crosswalk sheet added; rename suites or keep crosswalk", "n/a", "unassigned", "D",
     "Example: suite stage2_watchdog vs brief Stage 2 (P1a core confidence)."),
    ("DEF-011", "Rev B errata: section 21 numbering; duplicated 15.2-15.8; Table 20.1 does not split P1; F entry points disagree; no P4.5 entry row", "C-SPEC", "S4", "OPEN",
     "RISCFORGE_Verification_Plan_RevB.docx", "2026-10-27", "tracker review", "issue Rev C", "n/a", "unassigned", "D", ""),
    ("DEF-012", "Legacy bug register not migrated (INFRA_TRACKING B1-B21, V1-V14)", "C-HARNESS", "S4", "OPEN",
     "INFRA_TRACKING.md", "2026-10-28", "tracker review", "migrate rows here with class and severity", "n/a", "unassigned", "D",
     "Severity here is proposed; Rev B requires assignment at triage by someone other than the fixer."),
]

DECISIONS = [
    ("DC-1", "Which blocks are in the DUT for sign-off (CLIC, AON watchdog)", "Design owner", "P0 exit", "OPEN",
     "Out of scope, logged as defaulted", "handoff.md waives AON for FPGA; no sign-off decision record.", "Verification/status or goals/"),
    ("DC-2", "Behaviour of settled blocks (4 dropped IRQ lines, SPI modes, boot integrity)", "Design owner", "P2 exit", "OPEN",
     "Today's RTL behaviour as pin oracle", "", ""),
    ("DEC-A", "Simulator of record and coverage tool", "Verification lead", "P0 exit", "OPEN",
     "AMD Vivado XSim for local CI; Cadence Xcelium for coverage sign-off", "XSim cannot evaluate cover property; pinned in P0_EXECUTION_CONTRACT.md.", "Table 5.1"),
    ("DEC-B", "Identity scheme: Table 21.10 hash only, or hash plus git commit as a secondary field", "Harness-CI owner", "P0 exit", "DECIDED",
     "Table 21.10 hash", "Implemented in p0_identity.py generating H_rtl and H_filelist.", "status/P0_MANIFEST.json"),
    ("DEC-C", "Apply the apb_to_obi patch to both golden copies", "Design owner", "P1a entry", "DECIDED",
     "Applied to golden files on 2026-10-31", "Fix verified byte-identical in apb_uart-main and SOC_FILES.", "defects.csv"),
    ("DEC-D", "Golden UART source set for soc_subsystem.f (OBI chain in or out)", "Design owner", "P0 exit", "OPEN",
     "none", "soc_subsystem.f and vivado_soc.f disagree.", ""),
    ("DEC-E", "Adopt the Stage_Crosswalk mapping as the single naming reference", "Project lead", "P0 exit", "DECIDED",
     "Crosswalk adopted", "Rev B phase names authoritative; briefs use Stage N = P(N-1).", "Stage_Crosswalk sheet"),
    ("D-GR03", "Team size and start date (required for elapsed schedule and SD predicates)", "Project lead", "P0 exit", "OPEN",
     "none", "Rev B D-GR02 and D-GR03 are TBD.", ""),
]

ACTIONS = [
    # id, priority, phase, action, done_when, related, status
    ("ACT-001", "P1", "P1a entry", "Apply the apb_to_obi patch to both golden copies; re-run tb_apb_uart_thorough on golden files; repoint uart_test.f",
     "69/69 on golden files at a recorded identity (PASSED in 7.09s)", "DEF-002, DEF-007, DEC-C", "DONE"),
    ("ACT-002", "P1", "P0", "Write the P0 run-package script: H_rtl, H_filelist, ID-1/2/3, tool, seed, plusargs, command, build logs, counters, G0 and G1 verdict",
     "One folder passes P0-G1.4, G1.5, G2.4, G2.5, G3.*", "DEF-008", "IN PROGRESS"),
    ("ACT-003", "P1", "P0", "Define the golden module set from the agreed filelist and implement the unresolved/extra module comparison",
     "P0-G1.1 and G1.2 computed", "DEF-006", "OPEN"),
    ("ACT-004", "P1", "P0", "Implement the ID-1/2/3 tree checker and run it on rtl/ips",
     "Report with baseline counts", "DEF-004, DEF-005", "DONE"),
    ("ACT-005", "P1", "P0", "Converge the two timer.sv copies",
     "ID-1 == 0", "DEF-004", "DONE"),
    ("ACT-006", "P1", "P0", "Decide the simulator of record and coverage tool",
     "DEC-A decided and recorded in Table 5.1", "DEC-A", "IN PROGRESS"),
    ("ACT-007", "P1", "P0", "Hash hazard_unit.v and compare against the Stage 3 proof timestamp; confirm the proof ran the current file",
     "Note in run register", "DEF-001", "OPEN"),
    ("ACT-008", "P1", "P0", "Record DC-1 (scope for CLIC and AON watchdog)",
     "Decision record or defaulted entry", "DC-1", "OPEN"),
    ("ACT-009", "P1", "P0", "Re-run Stage 3 through the package script; declare P0 exit; reissue Table 21.3 with measured tau_scen",
     "P0-X1..X3 MET", "P0-X2, P0-X3", "OPEN"),
    ("ACT-010", "P1", "P1a", "Add a directed regression for DEF-001 (MMIO access followed by a DSRAM load-use) that fails without the fix; second-person review",
     "Test fails on old RTL, passes on fixed", "DEF-001", "OPEN"),
    ("ACT-011", "P1", "P1a", "Re-run RISCOF compliance and plan the lock-step model at the final identity",
     "CT-1 report; CT-2 plan", "DEF-001", "OPEN"),
    ("ACT-012", "P2", "P1b", "Bind and validate checkers on real axi_lite_to_apb and firmware traffic",
     "Path scoreboard drains on stage3-class runs", "", "OPEN"),
    ("ACT-013", "P2", "P2", "SoC-level firmware UART test (Stage 6) after ACT-001",
     "UART TX/RX through the real fabric observed at bus and pins", "DEF-002", "OPEN"),
    ("ACT-014", "P2", "any", "R0 traceability mapping: Rev B check IDs to bench labels, starting with SRAM, bridge, aperture, timers",
     "Mapping file with oracle source and scope", "", "OPEN"),
    ("ACT-015", "P2", "any", "Migrate INFRA_TRACKING B1-B21 and V1-V14 into the defect register",
     "Rows with class and proposed severity", "DEF-012", "OPEN"),
    ("ACT-016", "P3", "any", "Issue Rev C errata (see DEF-011) and archive superseded plans with a banner",
     "Rev C or errata note; Doc_Inventory states updated", "DEF-011", "OPEN"),
    ("ACT-101", "P1", "P0", "Review P0 documentation against Rev B; correct goals, matrix, UART record, roadmap, index",
     "Docs updated", "", "DONE"),
    ("ACT-102", "P1", "any", "Create the tracker workbook and generator script",
     "Workbook, snapshot and defects.csv generated", "", "DONE"),
]

DOCS = [
    ("Verification Plan Rev B", "RISCFORGE_Verification_Plan_RevB.docx", "Master plan", "MASTER", "2026-10-05", "CURRENT, errata owed", "Issue Rev C (DEF-011)"),
    ("Verification Plan (earlier)", "RISCFORGE_SoC_Verification_Plan.docx", "Earlier plan", "PRESUMED SUPERSEDED", "2026-10-04", "PRESUMED SUPERSEDED", "Confirm, then add SUPERSEDED banner or archive"),
    ("Tapeout Verification Plan (html)", "Verification/RISCFORGE_Tapeout_Verification_Plan.html; documentation/RISCFORGE Tapeout Verification Plan.html", "Earlier plan", "PRESUMED SUPERSEDED", "2026-09-25", "PRESUMED SUPERSEDED", "Confirm, then archive"),
    ("SoC infrastructure plan", "Verification/soc_verification_plan.md", "Implementation plan", "SUPPORTING", "2026-10-02", "CURRENT, read with Rev B", "Planned capabilities are not evidence"),
    ("Evidence index", "Verification/README.md", "Index", "EVIDENCE", REVIEW_DATE, "UPDATED " + REVIEW_DATE, ""),
    ("Evidence matrix", "Verification/verification_matrix.csv", "Evidence summary", "EVIDENCE", REVIEW_DATE, "UPDATED " + REVIEW_DATE, "Rows expanded to 26 assets"),
    ("Roadmap", "Verification/verification_roadmap.md", "Roadmap", "TRACKER", REVIEW_DATE, "UPDATED " + REVIEW_DATE, "R1 and R6 status refreshed"),
    ("Component records", "Verification/components/**", "Evidence records", "EVIDENCE", REVIEW_DATE, "UPDATED (uart.md); others current", ""),
    ("P0 goals", "goals/P0_bringup.md", "Phase goal", "TRACKER", REVIEW_DATE, "UPDATED " + REVIEW_DATE, "Status and DC-1/tau_scen exit items added"),
    ("P0 Contract & Manifest", "Verification/status/P0_EXECUTION_CONTRACT.md, P0_MANIFEST.json", "Contract & Manifest", "EVIDENCE", REVIEW_DATE, "NEW " + REVIEW_DATE, "Frozen identity and contract"),
    ("Master tracker", "Verification/status/RISCFORGE_Verification_Tracker.xlsx", "Tracker", "TRACKER", REVIEW_DATE, "NEW", "Generated by build_tracker.py"),
    ("Legacy infra tracker", "INFRA_TRACKING.md", "Legacy tracker (S0-S8)", "LEGACY", "2026-10-22", "STALE", "Migrate B1-B21 and V1-V14 (ACT-015), then mark superseded"),
    ("Stage briefs", "Verification/doc/stage_N_brief.md, formal_track_brief.md", "Briefs", "SUPPORTING", "2026-10-22", "CURRENT", "Keep; see crosswalk for suite names"),
    ("Step4 spec", "Verification/step4_checkers/STEP4_SPEC.md", "Spec", "SUPPORTING", "2026-10-02", "CURRENT", ""),
    ("Compliance audit", "Verification/infrastructure/COMPLIANCE_AUDIT_2026-10-02.md", "Audit snapshot", "SUPPORTING", "2026-10-02", "SNAPSHOT", "Dated record; do not edit"),
    ("Milestone 5 findings", "Verification/tests/suites/MILESTONE5_FINDINGS.md", "Findings", "SUPPORTING", "2026-10-02", "UNVERIFIED", "Review and migrate into the defect register"),
    ("FPGA handoff", "handoff.md", "FPGA track status", "SUPPORTING", "2026-10-16", "CURRENT for FPGA", "Separate S0-S4 numbering"),
    ("Defect export", "Verification/status/defects.csv", "Defects", "TRACKER", REVIEW_DATE, "NEW", "findings.csv is left empty on purpose: Rev B uses 'findings' for plan findings (H/M/L/B), a different ledger"),
    ("Interrupt research plan", "Verification/MINTPRIO_INTEGRATION_AND_PREEMPTION_PLAN.md", "Separate research plan", "SEPARATE", "2026-10-27", "OUT OF TRACKER SCOPE", ""),
    ("Tool outputs", "opencode_*.md, ses_status.json, *.backup.log/jou, xsim.dir", "Tool output", "TOOL OUTPUT", "various", "ARCHIVE CANDIDATE", "Move out of the evidence tree; see TEMP_OUTPUT_CLEANUP_CANDIDATES.csv"),
]

PERIPHERALS = [
    # device, slot, section, matrix id, comp, soc, irq, err, next
    ("GPIO", 3, "15.2", "APB-03", "PASS", "OPEN", "OPEN", "OPEN", "Firmware access through real fabric; pad and IRQ observation. Aperture test used synthetic responders."),
    ("I2C master", 0, "15.3", "APB-00", "PASS", "PARTIAL", "OPEN", "OPEN", "Stage 3 wrote and read PRER only; need protocol, IRQ and fabric error cases."),
    ("Timer 0", 1, "15.5", "APB-01", "PASS", "PARTIAL", "OPEN", "OPEN", "Staged 52/52 boot-to-runtime plus stage 3 access; timer.sv converged byte-identical."),
    ("Timer 1", 5, "15.6", "APB-05", "PASS", "PARTIAL", "OPEN", "OPEN", "Stage 3 read bursts only; timer.sv converged byte-identical (DEF-004)."),
    ("UART", 2, "15.7", "APB-02", "PASS", "OPEN", "OPEN", "OPEN", "Patched golden RTL (ACT-001); golden simulation run next."),
    ("SPI master", 4, "15.4", "APB-04", "PASS", "PARTIAL", "OPEN", "OPEN", "Only the boot-flash read is exercised, via bootloader interposition."),
    ("AON watchdog", "n/a", "15.8", "AON-01", "N/A", "N/A", "N/A", "N/A", "Not integrated; revisit only if DC-1 brings it into scope."),
]

RUNS = [
    # id, date, folder, purpose, tool, boot, verdict, 7 identity fields, role, notes
    ("20261018_stage1_xcelium_01", "2026-10-18", "artifacts/P0/", "Stage 1 attempts 01-06", "Xcelium 24.09-s001 (remote)", "WARM", "BLOCKED",
     ["P", "NR", "Y", "Y", "Y", "Y", "Y"], "Superseded by 05", "Blocker DEF-003. Field grading from result.json and file list only."),
    ("20261018_stage1_xcelium_02..04", "2026-10-18", "artifacts/P0/", "Stage 1 retries", "Xcelium 24.09-s001 (remote)", "WARM", "NR",
     ["NR"] * 7, "Superseded by 05", "Not reviewed field by field."),
    ("20261018_stage1_xcelium_05", "2026-10-18", "artifacts/P0/", "Stage 1 corrected rerun", "Xcelium 24.09-s001 (remote)", "WARM", "FAIL",
     ["P", "Y", "Y", "Y", "Y", "Y", "Y"], "First attributable run", "Exit 0x1002 (4 verified MMIO reads vs 6 required); attestation Divergent AXI/APB."),
    ("20261018_run01", "2026-10-18", "artifacts/component_first/", "Component-first checkpoint 1", "Xcelium / XSim", "n/a", "PASS",
     ["NA"] * 7, "Component baseline", "Direct peripheral runs (I2C, GPIO)."),
    ("20261019_run02", "2026-10-19", "artifacts/component_first/", "Component-first checkpoint 2", "Xcelium / XSim", "n/a", "PASS",
     ["NA"] * 7, "Component baseline", "SRAM, bridge, aperture, monitors. UART stalled at 60 ns."),
    ("20261024_stage1_hello", "2026-10-24", "artifacts/stage_proofs/", "Stage 1 hello proof", "Vivado XSim v2022.2", "WARM", "PASS",
     ["P", "N", "N", "N", "P", "P", "P"], "Stage proof", "1214 retired; 0 AXI; 0 APB; attestation 0x00040002."),
    ("20261024_stage2_watchdog", "2026-10-24", "artifacts/stage_proofs/", "Watchdog blame proof", "Vivado XSim v2022.2", "WARM", "PASS",
     ["P", "N", "N", "N", "P", "P", "P"], "Negative proof", "Watchdog fired at cycle 50000; 31735 retired; attestation 0x00040006."),
    ("20261024_stage3_monitor_count", "2026-10-24", "artifacts/stage_proofs/", "Monitor count proof", "Vivado XSim v2022.2", "WARM", "PASS",
     ["P", "N", "N", "N", "P", "P", "P"], "Stage proof", "5551 retired; 14 AXI RD, 4 WR; 18 APB; attestation 0x0004000e."),
    ("20261024_uart_delta_isolation", "2026-10-24", "artifacts/component_first/", "UART delta loop isolation", "Vivado XSim v2022.2", "n/a", "PASS",
     ["NA"] * 7, "Diagnostic", "Root-caused apb_to_obi zero-delay req/gnt delta loop; staged fix passes 69/69."),
    ("20261030_xcelium_irq", "2026-10-30", "artifacts/xcelium_irq_20261030_004317/", "IRQ arbiter unit coverage", "Cadence Xcelium 20.09", "n/a", "PASS",
     ["NA"] * 7, "Unit coverage sign-off", "100.00% functional coverage (471/471 bins); 96.73% irq_arbiter code coverage."),
    ("20261031_p0_identity", "2026-10-31", "status/", "P0 Identity Manifest & Contract", "p0_identity.py (CPython 3.12)", "WARM", "PASS",
     ["Y", "Y", "Y", "Y", "Y", "Y", "Y"], "Contract Baseline", "Generated H_rtl (d25104a4...), H_filelist (a931d6b4...); converged timer.sv ID-1=0."),
]

RUN_FIELDS = ["H_rtl", "H_filelist", "tool_version", "seed", "plusargs", "command", "logs_verdict"]

F_BASE = Font(name=FONT, size=10)
F_BOLD = Font(name=FONT, size=10, bold=True)
F_HEAD = Font(name=FONT, size=10, bold=True, color="FFFFFF")
F_TITLE = Font(name=FONT, size=14, bold=True, color=NAVY)
F_NOTE = Font(name=FONT, size=9, italic=True, color="595959")
FILL_HEAD = PatternFill("solid", fgColor=NAVY)
FILL_EDIT = PatternFill("solid", fgColor="FFF2CC")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(wrap_text=True, vertical="top")
CENTER = Alignment(horizontal="center", vertical="top", wrap_text=True)


def fill(color):
    return PatternFill("solid", start_color=color, end_color=color)


def sheet(wb, name, title, subtitle, headers, widths):
    ws = wb.create_sheet(name)
    ws["A1"] = title
    ws["A1"].font = F_TITLE
    ws["A2"] = subtitle
    ws["A2"].font = F_NOTE
    for i, (h, w) in enumerate(zip(headers, widths), start=1):
        c = ws.cell(row=FIRST - 1, column=i, value=h)
        c.font, c.fill, c.alignment, c.border = F_HEAD, FILL_HEAD, CENTER, BORDER
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = ws.cell(row=FIRST, column=2)
    ws.sheet_view.zoomScale = 100
    return ws


def put_rows(ws, rows, center_cols=()):
    for r, row in enumerate(rows, start=FIRST):
        for c, v in enumerate(row, start=1):
            cell = ws.cell(row=r, column=c, value=v)
            cell.font, cell.border = F_BASE, BORDER
            cell.alignment = CENTER if c in center_cols else WRAP
    return FIRST + len(rows) - 1


def finish(ws, ncols, last_data):
    ws.auto_filter.ref = "A%d:%s%d" % (FIRST - 1, get_column_letter(ncols), max(last_data, FIRST))


def status_style(ws, col, last_row, green=(), amber=(), red=(), grey=()):
    rng = "%s%d:%s%d" % (col, FIRST, col, max(last_row, FIRST))
    for vals, colr in ((green, GREEN), (amber, AMBER), (red, RED), (grey, GREY)):
        for v in vals:
            ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=['"%s"' % v], fill=fill(colr)))
    return rng


def dropdown(ws, col, last_row, values):
    dv = DataValidation(type="list", formula1='"%s"' % ",".join(values), allow_blank=True)
    dv.error, dv.errorTitle = "Pick a value from the list.", "Invalid status"
    ws.add_data_validation(dv)
    dv.add("%s%d:%s%d" % (col, FIRST, col, max(last_row, FIRST)))


def validate_ledgers():
    """Verify primary keys and schema integrity before building."""
    for name, dataset, id_idx in [
        ("PHASES", PHASES, 0),
        ("P0", P0, 0),
        ("GATES", GATES, 0),
        ("DEFECTS", DEFECTS, 0),
        ("ACTIONS", ACTIONS, 0),
        ("DECISIONS", DECISIONS, 0),
    ]:
        ids = [row[id_idx] for row in dataset]
        if len(ids) != len(set(ids)):
            dups = [x for x in ids if ids.count(x) > 1]
            raise ValueError(f"Duplicate IDs in {name}: {set(dups)}")

    if not os.path.isfile(MATRIX):
        raise FileNotFoundError(f"Missing matrix file: {MATRIX}")
    with open(MATRIX, newline="", encoding="utf-8") as fh:
        mrows = list(csv.DictReader(fh))
    mat_ids = [m["evidence_id"] for m in mrows]
    if len(mat_ids) != len(set(mat_ids)):
        dups = [x for x in mat_ids if mat_ids.count(x) > 1]
        raise ValueError(f"Duplicate evidence_id in {MATRIX}: {set(dups)}")
    print(f"[VALIDATOR] All ledgers passed schema and unique-key checks ({len(mrows)} matrix rows).")


# ---------------------------------------------------------------- workbook

def build():
    validate_ledgers()
    wb = Workbook()
    wb.remove(wb.active)

    last_rows = {}

    # README
    ws = wb.create_sheet("README")
    ws.column_dimensions["A"].width = 24
    ws.column_dimensions["B"].width = 110
    ws["A1"] = "RISCFORGE verification tracker"
    ws["A1"].font = F_TITLE
    lines = [
        ("Baseline", "Verification Plan Rev B (RISCFORGE_Verification_Plan_RevB.docx). Rev B names win over any label in this workbook."),
        ("Reviewed", REVIEW_DATE + ". Stamped with frozen P0 contract and expanded 26-row verification matrix."),
        ("Source of truth", "Version-controlled CSV/JSON ledgers. build_tracker.py generates this workbook, PHASE_STATUS.md, and defects.csv deterministically."),
        ("Counts", "Every number on the Dashboard is a formula dynamically bounded over the status columns of other sheets."),
        ("Status words", "MET / PARTIAL / NOT MET for checklist rows. PASS / FAIL / UNTESTED for gates. 'untested' is never a pass (Rev B Table 6.1)."),
        ("Severity", "S1 release-blocking .. S5 observation (Rev B Table 21.2.7a)."),
        ("Defect class", "C-DUT, C-TB, C-HARNESS, C-SPEC, C-ENV, C-EXPECT (Rev B Table 21.2.8)."),
        ("Owners", "Assigned per role / task."),
        ("Sheets", "Dashboard | Phase_Tracker | P0_Checklist | Gate_Register | Stage_Crosswalk | Run_Register | Component_Evidence | Peripheral_Closure | Infra_Maturity | Defects | Decisions | Actions | Doc_Inventory"),
    ]
    for i, (a, b) in enumerate(lines, start=3):
        ws.cell(row=i, column=1, value=a).font = F_BOLD
        c = ws.cell(row=i, column=2, value=b)
        c.font, c.alignment = F_BASE, WRAP
        ws.cell(row=i, column=1).alignment = WRAP

    dash = wb.create_sheet("Dashboard")

    # Phase_Tracker
    h = ["Phase", "Name", "Track", "Rev B ref", "Stage brief", "Entry criteria", "Exit criteria", "Gates stamped",
         "Status", "Entry met?", "Effort low (ED)", "Effort high (ED)", "Evidence now", "Blockers / next step", "Updated", "Owner"]
    w = [8, 24, 7, 11, 16, 46, 52, 16, 14, 10, 10, 10, 40, 40, 11, 8]
    ws = sheet(wb, "Phase_Tracker", "Phase register", "Rev B Tables 21.3, 21.4, 20.1. Effort is a planning estimate (ASSUMED D-GR01).", h, w)
    rows = [(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], REVIEW_DATE, "TBD") for p in PHASES]
    last = put_rows(ws, rows, center_cols=(1, 3, 9, 10, 11, 12, 15, 16))
    last_rows["Phase_Tracker"] = last
    status_style(ws, "I", last, green=["DONE"], amber=["IN PROGRESS"], red=["BLOCKED"], grey=["NOT STARTED"])
    status_style(ws, "J", last, green=["YES"], amber=["PARTIAL"], red=["NO"])
    dropdown(ws, "I", last, ["NOT STARTED", "IN PROGRESS", "BLOCKED", "DONE"])
    dropdown(ws, "J", last, ["YES", "PARTIAL", "NO", "N/A"])
    finish(ws, len(h), last)

    # P0_Checklist
    h = ["ID", "Group", "Requirement", "Rev B gate", "Rev B source", "Acceptance predicate", "Best current evidence", "Evidence path",
         "Status", "Gap", "Action"]
    w = [11, 16, 40, 10, 12, 40, 42, 34, 11, 44, 10]
    ws = sheet(wb, "P0_Checklist", "P0 exit checklist", "Criteria from goals/P0_bringup.md plus Rev B Tables 21.8 and 21.9.", h, w)
    last = put_rows(ws, P0, center_cols=(1, 4, 5, 9, 11))
    last_rows["P0_Checklist"] = last
    status_style(ws, "I", last, green=["MET"], amber=["PARTIAL"], red=["NOT MET"], grey=["N/A"])
    dropdown(ws, "I", last, ["MET", "PARTIAL", "NOT MET", "N/A"])
    finish(ws, len(h), last)

    # Gate_Register
    h = ["Gate", "Name", "Tier", "Pass predicate (Table 6.1)", "Evidence artefact", "Owner role", "Verdict", "At identity", "Date", "Note"]
    w = [7, 24, 13, 54, 34, 26, 11, 14, 11, 48]
    ws = sheet(wb, "Gate_Register", "Gate register", "Predicates quoted from Rev B Table 6.1. No gate has a stamped verdict.", h, w)
    rows = [(g[0], g[1], g[2], g[3], g[4], g[5], g[6], "none", REVIEW_DATE, g[7]) for g in GATES]
    last = put_rows(ws, rows, center_cols=(1, 3, 7, 8, 9))
    last_rows["Gate_Register"] = last
    status_style(ws, "G", last, green=["PASS"], red=["FAIL"], amber=["UNTESTED"])
    dropdown(ws, "G", last, ["PASS", "FAIL", "UNTESTED"])
    finish(ws, len(h), last)

    # Stage_Crosswalk
    h = ["Rev B phase", "Stage brief (Stage N = P(N-1))", "INFRA_TRACKING stage", "Test suite semantic ID", "Roadmap pkg", "Local goal labels", "Confidence", "Notes"]
    w = [12, 34, 40, 44, 11, 18, 26, 46]
    ws = sheet(wb, "Stage_Crosswalk", "Stage crosswalk", "One mapping across the six numbering schemes in use.", h, w)
    last = put_rows(ws, CROSSWALK, center_cols=(1, 5))
    last_rows["Stage_Crosswalk"] = last
    finish(ws, len(h), last)

    # Run_Register
    h = ["Run ID", "Date", "Folder", "Purpose", "Tool", "Boot", "Verdict recorded"] + RUN_FIELDS + ["Score", "Completeness", "Role", "Notes"]
    w = [30, 11, 22, 26, 24, 7, 16] + [9] * 7 + [7, 12, 26, 52]
    ws = sheet(wb, "Run_Register", "Run register", "Identity fields per Rev B Table 5.2 / 21.10.", h, w)
    rows = []
    for r in RUNS:
        rows.append(list(r[:7]) + list(r[7]) + [None, None, r[8], r[9]])
    last = put_rows(ws, rows, center_cols=(2, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16))
    last_rows["Run_Register"] = last
    for r in range(FIRST, last + 1):
        ws["O%d" % r] = '=COUNTIF(H%d:N%d,"Y")+0.5*COUNTIF(H%d:N%d,"P")' % (r, r, r, r)
        ws["P%d" % r] = '=IF(7-COUNTIF(H%d:N%d,"NA")-COUNTIF(H%d:N%d,"NR")=0,"n/r",O%d/(7-COUNTIF(H%d:N%d,"NA")-COUNTIF(H%d:N%d,"NR")))' % ((r,) * 9)
        ws["P%d" % r].number_format = "0%"
        for col in ("O", "P"):
            ws["%s%d" % (col, r)].font, ws["%s%d" % (col, r)].border = F_BASE, BORDER
            ws["%s%d" % (col, r)].alignment = CENTER
    rng_run = "H%d:N%d" % (FIRST, last)
    for v, colr in (("Y", GREEN), ("P", AMBER), ("N", RED), ("NA", GREY), ("NR", GREY)):
        ws.conditional_formatting.add(rng_run, CellIsRule(operator="equal", formula=['"%s"' % v], fill=fill(colr)))
    dv = DataValidation(type="list", formula1='"Y,P,N,NA,NR"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(rng_run)
    finish(ws, len(h), last)

    # Component_Evidence (from matrix csv - reads durable CSV columns)
    with open(MATRIX, newline="", encoding="utf-8") as fh:
        mrows = list(csv.DictReader(fh))
    h = ["Evidence ID", "Component", "Scope type", "Rev B reference", "Status", "Run", "Top / bench", "Reported result", "Evidence path",
         "Scope limit / next step", "SoC-boundary closed?", "Rev B check IDs mapped (R0)"]
    w = [10, 26, 16, 22, 15, 28, 24, 44, 40, 56, 12, 14]
    ws = sheet(wb, "Component_Evidence", "Component evidence", "Loaded from Verification/verification_matrix.csv at build time.", h, w)
    rows = [(m["evidence_id"], m["component"], m["scope_type"], m["master_plan_reference"], m["status"], m["run_id"], m["top"],
             m["reported_result"], m["evidence_path"], m["scope_limit_or_next_step"],
             m.get("soc_boundary_closed", "NO"), m.get("revb_check_ids_mapped", "NOT MAPPED")) for m in mrows]
    last = put_rows(ws, rows, center_cols=(1, 5, 11, 12))
    last_rows["Component_Evidence"] = last
    status_style(ws, "E", last, green=["PASS"], amber=["INCOMPLETE", "PLANNED"], red=["FAIL"], grey=["NO_RETAINED_RUN", "NOT_INTEGRATED"])
    dropdown(ws, "E", last, ["PASS", "INCOMPLETE", "NO_RETAINED_RUN", "NOT_INTEGRATED", "PLANNED", "FAIL"])
    finish(ws, len(h), last)

    # Peripheral_Closure
    h = ["Device", "APB slot", "Rev B section", "Matrix ID", "Component bench", "SoC firmware path", "IRQ path", "Error / timeout path", "Overall", "Next evidence needed"]
    w = [14, 9, 10, 10, 14, 16, 12, 16, 16, 66]
    ws = sheet(wb, "Peripheral_Closure", "Peripheral closure by layer", "Overall is a formula.", h, w)
    rows = [list(p[:8]) + [None, p[8]] for p in PERIPHERALS]
    last = put_rows(ws, rows, center_cols=(1, 2, 3, 4, 5, 6, 7, 8, 9))
    last_rows["Peripheral_Closure"] = last
    for r in range(FIRST, last + 1):
        ws["I%d" % r] = ('=IF(COUNTIF(E{r}:H{r},"N/A")=4,"NOT INTEGRATED",IF(COUNTIF(E{r}:H{r},"PASS")=4-COUNTIF(E{r}:H{r},"N/A"),"CLOSED",'
                         'IF(COUNTIF(E{r}:H{r},"PASS")+COUNTIF(E{r}:H{r},"PARTIAL")>0,"IN PROGRESS","OPEN")))').format(r=r)
        ws["I%d" % r].font, ws["I%d" % r].border, ws["I%d" % r].alignment = F_BASE, BORDER, CENTER
    rng_periph = "E%d:H%d" % (FIRST, last)
    for v, colr in (("PASS", GREEN), ("PARTIAL", AMBER), ("OPEN", RED), ("N/A", GREY)):
        ws.conditional_formatting.add(rng_periph, CellIsRule(operator="equal", formula=['"%s"' % v], fill=fill(colr)))
    status_style(ws, "I", last, green=["CLOSED"], amber=["IN PROGRESS"], red=["OPEN"], grey=["NOT INTEGRATED"])
    dv = DataValidation(type="list", formula1='"PASS,PARTIAL,OPEN,N/A"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(rng_periph)
    finish(ws, len(h), last)

    # Infra_Maturity
    h = ["Capability (industry practice)", "State", "Evidence in repository", "Gap to close", "Target phase", "Priority"]
    w = [52, 12, 56, 46, 12, 9]
    ws = sheet(wb, "Infra_Maturity", "Verification infrastructure maturity", "Assessed on %s." % REVIEW_DATE, h, w)
    rows = [(i[0], i[1], i[2], i[3], i[4], i[5]) for i in INFRA]
    last = put_rows(ws, rows, center_cols=(2, 5, 6))
    last_rows["Infra_Maturity"] = last
    status_style(ws, "B", last, green=["EXISTS"], amber=["PARTIAL", "UNVERIFIED"], red=["MISSING"], grey=["NA"])
    dropdown(ws, "B", last, ["EXISTS", "PARTIAL", "MISSING", "UNVERIFIED", "NA"])
    finish(ws, len(h), last)

    # Defects
    h = ["ID", "Title", "Class", "Severity (proposed)", "Status", "Component / file", "Found", "Found in", "Fix location", "Regression test", "Closer", "Re-run class", "Notes"]
    w = [9, 46, 12, 10, 18, 40, 11, 22, 38, 30, 11, 8, 54]
    ws = sheet(wb, "Defects", "Defect register", "Rev B Tables 21.2.7a (severity) and 21.2.8 (class).", h, w)
    last = put_rows(ws, DEFECTS, center_cols=(1, 3, 4, 5, 7, 11, 12))
    last_rows["Defects"] = last
    status_style(ws, "E", last, green=["FIXED-VERIFIED", "CLOSED"], amber=["FIX-STAGED", "FIXED-UNVERIFIED", "FIX-APPLIED-UNVERIFIED", "FIXED-CONVERGED", "IN_PROGRESS"], red=["OPEN"], grey=["WONT FIX"])
    dropdown(ws, "E", last, ["OPEN", "FIX-STAGED", "FIX-APPLIED-UNVERIFIED", "FIXED-CONVERGED", "FIXED-UNVERIFIED", "FIXED-VERIFIED", "CLOSED", "IN_PROGRESS", "WONT FIX"])
    dropdown(ws, "C", last, ["C-DUT", "C-TB", "C-HARNESS", "C-SPEC", "C-ENV", "C-EXPECT"])
    dropdown(ws, "D", last, ["S1", "S2", "S3", "S4", "S5"])
    finish(ws, len(h), last)

    # Decisions
    h = ["ID", "Decision", "Owner role", "Due", "Status", "Default if undecided", "Notes", "Record location"]
    w = [9, 56, 18, 12, 12, 30, 62, 26]
    ws = sheet(wb, "Decisions", "Decisions", "DC-1 and DC-2 are Rev B Table 21.9.", h, w)
    last = put_rows(ws, DECISIONS, center_cols=(1, 4, 5))
    last_rows["Decisions"] = last
    status_style(ws, "E", last, green=["DECIDED"], amber=["PROPOSED", "DEFAULTED"], red=["OPEN"])
    dropdown(ws, "E", last, ["OPEN", "PROPOSED", "DECIDED", "DEFAULTED"])
    finish(ws, len(h), last)

    # Actions
    h = ["ID", "Priority", "Phase", "Action", "Done when", "Related", "Owner", "Status", "Created", "Due"]
    w = [9, 8, 10, 70, 44, 22, 8, 12, 11, 8]
    ws = sheet(wb, "Actions", "Action backlog", "P1 = blocks P0 exit or P1a entry.", h, w)
    rows = [(a[0], a[1], a[2], a[3], a[4], a[5], "TBD", a[6], REVIEW_DATE, "TBD") for a in ACTIONS]
    last = put_rows(ws, rows, center_cols=(1, 2, 3, 7, 8, 9, 10))
    last_rows["Actions"] = last
    status_style(ws, "H", last, green=["DONE"], amber=["IN PROGRESS"], red=["BLOCKED"], grey=["OPEN"])
    dropdown(ws, "H", last, ["OPEN", "IN PROGRESS", "BLOCKED", "DONE"])
    dropdown(ws, "B", last, ["P1", "P2", "P3"])
    finish(ws, len(h), last)

    # Doc_Inventory
    h = ["Document", "Path (under rtl/ips unless noted)", "Role", "Authority", "Last modified", "State", "Action"]
    w = [28, 60, 22, 20, 12, 26, 56]
    ws = sheet(wb, "Doc_Inventory", "Documentation inventory", "Which document is authoritative for what.", h, w)
    last = put_rows(ws, DOCS, center_cols=(4, 5))
    last_rows["Doc_Inventory"] = last
    finish(ws, len(h), last)

    # Build Dashboard with dynamic bounds
    build_dashboard(wb, dash, last_rows)

    order = ["README", "Dashboard", "Phase_Tracker", "P0_Checklist", "Gate_Register", "Stage_Crosswalk", "Run_Register",
             "Component_Evidence", "Peripheral_Closure", "Infra_Maturity", "Defects", "Decisions", "Actions", "Doc_Inventory"]
    wb._sheets = [wb[n] for n in order]
    wb.calculation.fullCalcOnLoad = True
    out = os.path.join(HERE, "RISCFORGE_Verification_Tracker.xlsx")
    wb.save(out)
    return out


def build_dashboard(wb, ws, last_rows):
    ws["A1"] = "Verification dashboard"
    ws["A1"].font = F_TITLE
    ws["A2"] = "Every number is a dynamic formula over the other sheets. Baseline: Rev B. Reviewed " + REVIEW_DATE + "."
    ws["A2"].font = F_NOTE
    ws.column_dimensions["A"].width = 46
    for col in "BCDEF":
        ws.column_dimensions[col].width = 14
    r = 4

    def section(title):
        nonlocal r
        c = ws.cell(row=r, column=1, value=title)
        c.font, c.fill = F_HEAD, FILL_HEAD
        for k in range(2, 7):
            ws.cell(row=r, column=k).fill = FILL_HEAD
        r += 1

    def line(label, formula, fmt=None):
        nonlocal r
        ws.cell(row=r, column=1, value=label).font = F_BASE
        c = ws.cell(row=r, column=2, value=formula)
        c.font, c.alignment = F_BOLD, Alignment(horizontal="center")
        if fmt:
            c.number_format = fmt
        for k in (1, 2):
            ws.cell(row=r, column=k).border = BORDER
        r += 1
        return r - 1

    # Dynamically bounded range per sheet
    rng = lambda sh, col: "%s!$%s$%d:$%s$%d" % (sh, col, FIRST, col, last_rows[sh])

    section("Phase register")
    for s in ("NOT STARTED", "IN PROGRESS", "BLOCKED", "DONE"):
        line("Phases " + s.lower(), '=COUNTIF(%s,"%s")' % (rng("Phase_Tracker", "I"), s))
    low = line("Planning effort, low (engineer-days)", "=SUM(%s)" % rng("Phase_Tracker", "K"), "#,##0")
    high = line("Planning effort, high (engineer-days)", "=SUM(%s)" % rng("Phase_Tracker", "L"), "#,##0")
    line("Effort midpoint (not elapsed time)", "=AVERAGE(B%d,B%d)" % (low, high), "#,##0")
    r += 1

    section("P0 exit checklist")
    met = line("Criteria MET", '=COUNTIF(%s,\"MET\")' % rng("P0_Checklist", "I"))
    par = line("Criteria PARTIAL", '=COUNTIF(%s,\"PARTIAL\")' % rng("P0_Checklist", "I"))
    nm = line("Criteria NOT MET", '=COUNTIF(%s,\"NOT MET\")' % rng("P0_Checklist", "I"))
    tot = line("Criteria total (excluding N/A)", "=B%d+B%d+B%d" % (met, par, nm))
    line("Progress (MET + half of PARTIAL)", "=IF(B%d=0,0,(B%d+0.5*B%d)/B%d)" % (tot, met, par, tot), "0%")
    line("P0 exit verdict", '=IF(AND(B%d>0,B%d=0,B%d=0),"MET","NOT MET")' % (met, par, nm))
    chart_rows = (met, par, nm)
    r += 1

    section("Gates (Rev B G0-G6)")
    for s in ("PASS", "FAIL", "UNTESTED"):
        line("Gates " + s, '=COUNTIF(%s,"%s")' % (rng("Gate_Register", "G"), s))
    r += 1

    section("Run identity")
    line("Runs graded", '=COUNT(%s)' % rng("Run_Register", "P"))
    line("Average identity completeness", '=IFERROR(AVERAGE(%s),"n/a")' % rng("Run_Register", "P"), "0%")
    r += 1

    section("Component evidence (matrix)")
    for s in ("PASS", "INCOMPLETE", "NO_RETAINED_RUN", "NOT_INTEGRATED", "PLANNED"):
        line("Rows " + s, '=COUNTIF(%s,"%s")' % (rng("Component_Evidence", "E"), s))
    line("Rows with Rev B check IDs mapped", '=COUNTIF(%s,"MAPPED")' % rng("Component_Evidence", "L"))
    r += 1

    section("Peripheral closure (4 layers each)")
    for s in ("CLOSED", "IN PROGRESS", "OPEN", "NOT INTEGRATED"):
        line("Devices " + s.lower(), '=COUNTIF(%s,"%s")' % (rng("Peripheral_Closure", "I"), s))
    line("SoC-path layer PASS", '=COUNTIF(%s,"PASS")' % rng("Peripheral_Closure", "F"))
    r += 1

    section("Defects not yet closed")
    for s in ("S1", "S2", "S3", "S4", "S5"):
        line("Open at " + s, '=COUNTIFS(%s,"%s",%s,"<>FIXED-VERIFIED",%s,"<>CLOSED")' %
             (rng("Defects", "D"), s, rng("Defects", "E"), rng("Defects", "E")))
    line("Fixed but not verified or only staged", '=COUNTIF(%s,"FIXED-UNVERIFIED")+COUNTIF(%s,"FIX-STAGED")+COUNTIF(%s,"FIX-APPLIED-UNVERIFIED")' % (rng("Defects", "E"), rng("Defects", "E"), rng("Defects", "E")))
    r += 1

    section("Decisions and actions")
    line("Decisions open or proposed", '=COUNTIF(%s,"OPEN")+COUNTIF(%s,"PROPOSED")' % (rng("Decisions", "E"), rng("Decisions", "E")))
    for p in ("P1", "P2", "P3"):
        line("Actions open at " + p, '=COUNTIFS(%s,"%s",%s,"<>DONE")' % (rng("Actions", "B"), p, rng("Actions", "H")))
    line("Actions done", '=COUNTIF(%s,"DONE")' % rng("Actions", "H"))
    r += 1

    section("Infrastructure maturity (%d capabilities assessed)" % len(INFRA))
    for s in ("EXISTS", "PARTIAL", "MISSING", "UNVERIFIED", "NA"):
        line("Capabilities " + s, '=COUNTIF(%s,"%s")' % (rng("Infra_Maturity", "B"), s))

    ch = BarChart()
    ch.type, ch.title, ch.style = "bar", "P0 checklist", 10
    ch.y_axis.title = "criteria"
    data = Reference(ws, min_col=2, min_row=chart_rows[0], max_row=chart_rows[2])
    cats = Reference(ws, min_col=1, min_row=chart_rows[0], max_row=chart_rows[2])
    ch.add_data(data, titles_from_data=False)
    ch.set_categories(cats)
    ch.legend = None
    ch.height, ch.width = 6, 12
    ws.add_chart(ch, "D4")


# ---------------------------------------------------------------- exports

def write_defects_csv():
    cols = ["defect_id", "title", "class", "severity_proposed", "status", "component", "found_date", "found_in",
            "fix_location", "regression_test", "closer", "rerun_class", "notes"]
    with open(os.path.join(HERE, "defects.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        w.writerows(DEFECTS)


def write_markdown():
    from collections import Counter
    cnt = Counter(p[8] for p in P0)
    lines = ["# RISCFORGE phase status snapshot", "",
             "Generated by `build_tracker.py` on %s from the same data as `RISCFORGE_Verification_Tracker.xlsx`. Do not hand-edit." % REVIEW_DATE,
             "Baseline: Rev B. Stamped with frozen P0 contract and expanded 26-row verification matrix.", "",
             "## Phases", "", "| Phase | Name | Status | Entry met | Gates at exit | Effort (ED) |", "|---|---|---|---|---|---|"]
    for p in PHASES:
        lines.append("| %s | %s | %s | %s | %s | %d to %d |" % (p[0], p[1], p[8], p[9], p[7], p[10], p[11]))
    lines += ["", "## P0 exit checklist", "",
              "MET %d, PARTIAL %d, NOT MET %d of %d. P0 exit: **%s**." % (cnt["MET"], cnt["PARTIAL"], cnt["NOT MET"], len(P0), "MET" if cnt["NOT MET"] == 0 and cnt["PARTIAL"] == 0 else "IN PROGRESS"), "",
              "| ID | Requirement | Status | Gap |", "|---|---|---|---|"]
    for c in P0:
        lines.append("| %s | %s | %s | %s |" % (c[0], c[2], c[8], c[9] or "-"))
    lines += ["", "## Open defects", "", "| ID | Title | Class | Sev (proposed) | Status |", "|---|---|---|---|---|"]
    for d in DEFECTS:
        if d[4] not in ("FIXED-VERIFIED", "CLOSED"):
            lines.append("| %s | %s | %s | %s | %s |" % (d[0], d[1], d[2], d[3], d[4]))
    lines += ["", "## Open P1 actions", "", "| ID | Action | Done when |", "|---|---|---|"]
    for a in ACTIONS:
        if a[1] == "P1" and a[6] != "DONE":
            lines.append("| %s | %s | %s |" % (a[0], a[3], a[4]))
    lines += ["", "## Naming", "", "Stage N in the briefs is P(N-1). See the `Stage_Crosswalk` sheet for the full mapping.", ""]
    with open(os.path.join(HERE, "PHASE_STATUS.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


if __name__ == "__main__":
    path = build()
    write_defects_csv()
    write_markdown()
    print("Successfully built:", path)
