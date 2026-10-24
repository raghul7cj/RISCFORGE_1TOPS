---
description: Critical verification engineering invariants for RISCFORGE SoC and multi-agent testbench execution
trigger: always_on
---

# RISCFORGE SoC Verification & Multi-Agent Swarm Invariants

These invariants MUST be adhered to across all verification testbenches, checkers, scoreboards, and multi-agent execution flows:

## 1. Decoupled Checker Mailbox Architecture (Anti-Race Invariant)
- When multiple protocol checkers, SVAs, or scoreboards report findings to a central diagnostic hub, **never** allow multiple procedural blocks to drive a single shared write pointer (`hub.evt_w`) on the same clock edge.
- Mailbox queues must enforce bounded modulo indexing (`(r + k) % SLOTS`) and guard against uninitialized pushes: only read and forward when `ev_q[ev_r].vld == 1'b1`.

## 2. Dual-Sided Anti-Vacuity Verification
- A test pass must require two independent, non-trusting confirmations:
  1. **Firmware Side**: Writing a valid attestation activity signature to DSRAM (`0x0002_0008`) and the verified mailbox opcode `CMD_PASS`.
  2. **Testbench Side**: Independent assertion that `total_retired_instr > 0`, MMIO bus transaction count $> 0$, and fatal error count `n_find == 0`.
- An execution with zero retired instructions or zero bus activity is strictly marked as a **VACUOUS PASS / FAILURE**.

## 3. Mailbox Command Protocol Synchronization
- Firmware headers (`mailbox.h`) must strictly mirror SystemVerilog testbench package constants (`tb_pkg.sv`):
  - `CMD_PASS = 0xC0DE_C0DE`
  - `CMD_FAIL = 0xBAAD_F00D`
  - `CMD_HALT = 0xDEAD_BEEF`
- Never alter these opcodes unilaterally in C headers without updating the testbench package, as mismatches cause silent simulation hangs.

## 4. Hierarchical RTL Net Probing Veracity
- Testbench probes into core internals must bind to verified signals in `riscv_core/rtl/top.v`:
  - `irq_winner_id[4:0]`, `irq_winner_class[1:0]`, `trap_commit_valid`, `mret_commit`
- Never probe fictitious names (e.g. `dut.u_core.irq_req` or `dut.u_core.irq_ack`).

## 5. Quota-Aware Swarm Delegation to OpenCode
- For high-volume multi-agent verification, formal audits, or regression debugging that would exhaust commercial API quotas, automatically route execution to the local OpenCode server (`http://127.0.0.1:4096`) utilizing discovered free-tier models (such as `space-bunny-free`) with high reasoning effort (`xhigh`).
