# RISCFORGE — Stage 3 Brief (P1b: SoC Structural Path)

**Goal:** Independently verify that one firmware-issued MMIO request reaches the correct peripheral **exactly once** and returns the correct response through the integrated AXI4-Lite/APB path. **Start with one path, not a complete bus VIP framework.**

**Source:** `RISCFORGE_Verification_Plan_RevB`, §§5, 8–9, 14, 20–21. This is a *reduced execution milestone* for P1b, not completion of every P1b checker or gate.

## Scope

1. **Choose one simple existing APB target.** Prefer GPIO or a timer register with a documented expected value. Avoid the SPI bootloader-interposed slot for the first checker. Confirm the actual address map, top-level connections, reset, and monitor attachment points from RTL and an independently reviewed expected register definition.
2. **Create a tiny self-checking MMIO scenario.** From firmware, perform at least one write and readback (plus a read-only/reset-value check when meaningful). Use Stage 1's runnable SoC boot/test path; do not create a second harness.
3. **Observe both sides of the fabric.** Passively record the core-facing AXI-Lite request/response and the selected APB setup/access/completion. Count accepted handshakes, not signal-level pulses; keep each transaction's address, access direction, data, response, and cycle/order.
4. **Check correspondence and protocol.** Match an accepted AXI request to its expected APB effect and returned response, accounting for legal wait cycles. Detect wrong address, wrong byte strobes/data, wrong response, duplicates, missing completions, and undrained outstanding requests. Add 2–3 focused protocol assertions/checks; avoid reproducing the interconnect RTL as the oracle.
5. **Prove the checker detects failure.** Deliberately corrupt a *test expectation* or inject a safe modeled error and confirm an attributed FAIL. Restore the valid case. Preserve both logs and the exact run identity.

## Done when

- [ ] The Stage 1 entry point executes one self-checking APB MMIO test on the integrated SoC.
- [ ] AXI and APB monitors show matching transactions and checked data/responses; no unexplained duplicates, drops, or pending items remain.
- [ ] The checker distinguishes **PASS / FAIL / TIMEOUT** and catches a deliberate negative case.
- [ ] At least one read and one write are covered; unsupported targets/paths are listed as **NOT TESTED**, not passed.
- [ ] Existing Stage 1 smoke and Stage 2 core regressions remain runnable, with any regressions identified.

## Deliverables (only these)

- One MMIO firmware test and two small passive bus observation points (reuse monitors if present).
- One transaction-correspondence checker with end-of-test drain/timeout handling.
- Logs, transaction summary, machine-readable verdict, and negative-case evidence.
- `p1b_findings.md`: verified path, observed discrepancies, and expansion priorities.

## Not in Stage 3

No full UVM/cocotb migration, reusable VIP product, all-slot register models, random traffic generators, full SoC coverage closure, AXI multi-master stress, interrupt campaigns, or formal sign-off. These can follow once the first path works.

## Next stage

**Stage 4 (selective P2):** extend the checker/model to one more device or a representative register class, then consider a dedicated CSR UVM environment as a separate learning track.

## Codex instruction

> Reuse Stage 1's simulator and Stage 2's core evidence. First identify exact bus signals, monitor hooks, and one peripheral's expected register semantics. Propose at most five incremental tasks. Do not refactor the whole harness; build the smallest end-to-end MMIO check, demonstrate one failing negative case, and save commands, diffs, traces, and verdicts.
