# RISCFORGE SoC testbench framework plan

Planning baseline: 4 November 2026. Scope: verification architecture and implementation roadmap only. No RTL or testbench implementation was changed, and no new simulation result is claimed by this package.

## Recommendation

Build a **small object-oriented SystemVerilog environment**, using the real SoC and firmware as the main system-level stimulus source. Retain static modules/interfaces for the DUT, pin timing and assertions. Use classes for scenario configuration, transactions, agents, reference models, scoreboards and coverage. Reuse proven existing pieces through adapters; replace incorrect assumptions rather than carrying them into a second checker stack.

Do not start with a full UVM conversion. SV already provides classes, constrained randomization, typed mailboxes, virtual interfaces and covergroups. UVM helps standardize component lifecycle, sequencing, analysis connections and register integration; it does not supply the SoC-specific stimulus, device behavior, register semantics or checking. The full SoC has no exposed AXI master port for a VIP to own. Most system stimulus must execute on the core or enter through real pins.

Keep a **thin UVM integration path** documented in [02_ARCHITECTURE_AND_FILES.md](02_ARCHITECTURE_AND_FILES.md). Activate it if an item-specific decision requires UVM, or an available qualified UVM VIP materially reduces implementation. Do not maintain two independent verification models. The external checklist's literal UVM requirement remains an acceptance decision; this recommendation does not mark it waived.

## What to build first

1. Establish one build identity and a tested observation adapter for the current SoC. The present core has **13 interrupt sources**; legacy observations still use six. Soft reset is filtered. The GPIO window ends at `0x4000_3800`, leaving a decode hole.
2. Complete an independently reviewed register/field inventory and implement semantic frontdoor tests through firmware. All six APB peripherals are required, including both channels of each timer, UART banks and GPIO aliases.
3. Add completion-based bus, register, pin and IRQ scoreboards. Prove each check can detect a deliberate error before trusting a clean run.
4. Run directed memory, peripheral and interrupt software, then constrained mixed workloads and reset stress. Separate full-SoC evidence from fabric/component evidence.
5. Close declared functional bins and candidate code coverage on an attributable manifest, with negative proofs, coverage holes and exclusions visible.

## Read this package

| Document | Purpose |
|---|---|
| [01_BASELINE_AND_REQUIREMENTS.md](01_BASELINE_AND_REQUIREMENTS.md) | What already exists, current top boundary, plan/checklist differences and reuse decisions |
| [02_ARCHITECTURE_AND_FILES.md](02_ARCHITECTURE_AND_FILES.md) | Final architecture, component goals/contracts, ownership, proposed files and UVM alternative |
| [03_REGISTER_VERIFICATION.md](03_REGISTER_VERIFICATION.md) | Complete register inventory, semantic model, frontdoor stimulus and closure for 6.2/6.3 |
| [04_STIMULUS_AND_COVERAGE.md](04_STIMULUS_AND_COVERAGE.md) | Concrete directed/random/software stimuli, coverage sampling, closure and stress budgets |
| [05_EXECUTION_AND_EVIDENCE.md](05_EXECUTION_AND_EVIDENCE.md) | Ordered implementation stages, acceptance criteria, evidence schemas and regression gates |
| [06_REVIEW_AND_DECISIONS.md](06_REVIEW_AND_DECISIONS.md) | Independent GPT-6.1 Sol High review findings and final dispositions |
| [SOC_TESTBENCH_ARCHITECTURE.html](SOC_TESTBENCH_ARCHITECTURE.html) | Illustrated, searchable, printable version of the complete plan |
| [SOURCE_SNAPSHOT.json](SOURCE_SNAPSHOT.json) | Digests of selected sources inspected for this plan; not a simulation or synthesis manifest |

All paths in the proposed file tree are **future implementation targets** unless explicitly identified as existing. The plan does not create placeholder SV files that could be mistaken for delivered capability.

## Completion means

For each required item, the package must identify the requirement, check, stimulus, observed DUT activity, result, candidate identity and coverage. A mailbox PASS, a compiled ELF, a high unit-coverage percentage or a runner script alone is insufficient. Failures remain failures; checks and coverage targets are not weakened to produce green output.

Primary targets are checklist **6.1, 6.2, 6.8 and 6.12–6.17**. The architecture also provides the mechanisms for 6.3–6.7, 6.9–6.11 and 6.18. Release tagging and final authorization under 6.19 remain a separate release activity. Rev B's gate **G6 means traceability**, not this checklist's G6 work package.
