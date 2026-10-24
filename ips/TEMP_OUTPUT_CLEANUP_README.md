# Temporary Output Cleanup Candidates

**Inventory date:** 2026-10-22  
**Scope:** files currently under ips/.  
**Status:** inventory only. No files have been deleted or moved.

The CSV lists exact relative paths, sizes, last modified times, reasons, and approval state. Batches are disjoint; approving one batch does not approve another. The approval column is PENDING for every row.

## Proposed batches

| Batch | Files | Size | Review level |
|---|---:|---:|---|
| `A_SIM_WORKDIR` | 964 | 96.67 MB | Low |
| `B_PY_CACHE` | 16 | 0.25 MB | Low |
| `C_LOOSE_LOGS` | 109 | 2.14 MB | Review |
| `D1_BUILD_ELF` | 7 | 0.32 MB | Review |
| `D2_BUILD_HEX` | 14 | 0.18 MB | Review |
| `E_VIVADO_AI_STATE` | 8 | 2.08 MB | Review |

### Batch notes

- A_SIM_WORKDIR: XSim, Xcelium, coverage, and Vivado work/cache directories. Lowest risk to remove; tools recreate them.
- B_PY_CACHE: Python caches and bytecode. Lowest risk to remove; Python recreates them.
- C_LOOSE_LOGS: standalone logs, journals, and tool databases outside known archived evidence folders. Review before deleting because failures may be useful evidence.
- D1_BUILD_ELF: compiled test firmware under Verification/build/. Rebuildable if compiler and source are available.
- D2_BUILD_HEX: generated memory images under Verification/build/. Confirm none are golden inputs or required for reproducing a result before deleting.
- E_VIVADO_AI_STATE: .vivado-ai files are held for individual review; they may include useful Tcl setup.

## Deliberately excluded from these deletion batches

Curated and archived evidence under Verification/artifacts/, Verification/infrastructure/runs/, jaspergold/runs/, jaspergold/reports/, and spyglass/reports/ is not presumed temporary. I left those files out so we do not erase potentially useful verification history. If you want, they can be inventoried later as a separate archival review.

## Approving a batch

Review the CSV and reply with batch IDs, for example: Approve A_SIM_WORKDIR and B_PY_CACHE. I will delete only the approved batch after confirming the listed files still match the inventory. No wildcard deletion is authorized by this manifest.

## Batch A review outcome

The user approved `A_SIM_WORKDIR`. The two coverage files in `apb_timer-master/sim/xcelium/cov_work/` are raw Xcelium `.ucm`/`.ucd` database files (about 11 KB total). No saved coverage report was found beside them, and the timer runner removes `cov_work` before launching a new run. They are judged regenerable and not worth preserving as standalone evidence. The attempted file deletion was rejected by the tool safety policy; no candidate files were removed. In the CSV, Batch A is marked `APPROVED_BY_USER` and `BLOCKED_BY_TOOL_POLICY`.
