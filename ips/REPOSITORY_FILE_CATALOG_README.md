# Repository file catalog

Snapshot: 2026-10-22. This is a path-level planning inventory for the current `ips/` tree. The CSV has one row for every file present when it was generated, including generated output and historical material. It is not a list of files approved for publication: `REVIEW` rows require a person to decide based on source-of-truth, licensing, sensitivity, and reproducibility.

## Columns

- `CurrentPath`: path relative to the current `ips/` folder.
- `Disposition`: `KEEP` means retain at the current path for the low-risk first push; `MOVE` means the target structure proposes a new path; `EXCLUDE` means generated, private/session, or duplicated output should not enter the repository; `REVIEW` means a human decision is needed before publishing.
- `ProposedPath`: target path relative to the proposed standalone repository root. Blank means do not plan to publish the file unless a review changes the decision.
- `Category` and `Reason`: why it was classified and the main follow-up needed.
- `Bytes`: current file size, useful for finding large assets.

## Review rules

1. Treat source RTL, testbenches, software, scripts, constraints, and filelists as candidate project inputs. Check active filelists before calling a source active or deleting a duplicate.
2. Keep only authored, current documentation and concise, reproducible verification evidence. Raw simulator logs, work databases, waveforms, EDA snapshots, caches, and compiled build products belong in ignored output directories.
3. Preserve golden firmware or memory images only when their source, generator, and intended use are documented. Do not ignore all `.hex` or `.mem` files.
4. Check third-party provenance and redistribution terms for every vendored RTL library, VIP model, paper, archive, executable, and report before a public push.
5. `MOVE` paths are proposed destinations, not completed moves. Verify filelists and runner working directories whenever a move is implemented.
6. This catalog covers `ips/` only. Parent-folder files and credentials must be reviewed separately. Do not copy credential-bearing local guidance into the public repository.

Regenerate this catalog after the tree changes. Review `REVIEW` rows first, then exclude generated outputs, then implement moves in small groups with their filelists and scripts.



## Snapshot summary

The catalog covers 3,883 original files plus its five planning documents. Current classifications:

- `EXCLUDE`: 2266 files
- `KEEP`: 2 files
- `MOVE`: 622 files
- `REVIEW`: 995 files

A large REVIEW count is intentional: filenames alone cannot establish third-party license rights, whether a duplicate is active, or whether old evidence is still valid. Resolve those rows before treating the repository as ready for a public push.



