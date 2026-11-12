# CSR and trap skeleton

[Architecture, diagrams and verification goal](../../../doc/CSR_TRAP_TESTBENCH_ARCHITECTURE.html)

Invocation root for both filelists is `rtl/ips`. Compile each filelist
independently and select the top named in its header comment. Example
VCS compile/elaboration templates, run from `rtl/ips`:

```sh
vcs -full64 -f Verification/filelists/tier1_unit/tb_csr_corner_unit.f -o simv_csr_corner

vcs -full64 -f Verification/filelists/tier1_unit/tb_core_csr_trap.f -o simv_core_csr_trap
```

Equivalent simulator command syntax may differ. The VCS templates themselves
have not been run here; the local XSim path is scripted under
[Running the benches](#running-the-benches).

## Tops and wiring

- `tb_csr_corner_unit` connects every `csr_regfile` port through
  `csr_corner_if` and runs five directed suites: `status_cases`,
  `metadata_cases`, `collision_cases`, `counter_cases` and `reset_cases`.
- `tb_core_csr_trap` instantiates the actual `riscv_core/rtl/top.v` with
  `RESET_PC=0x80000000`, a `core_corner_imem` read shell, and a
  `core_corner_dmem` responder shell. The data base convention is
  not configured yet. IRQ pins default low. The core remains in reset.
- `core_csr_trap_probe` passively connects writeback exception, trap-commit,
  MRET-commit and memory request observations. It does not drive the DUT.
- The core environment package provides typed scenario/event/result objects,
  virtual-interface handles, separate scheduler and scoreboard mailboxes, and
  a bounded start/stop lifecycle. Three reset-held clock edges run passive
  observation and then print `SKELETON/INCOMPLETE`.
- `observe_cb` samples pre-edge pipeline/request activity; `state_cb` samples
  settled CSR state before the falling edge following the update. Pipeline and
  CSR-state records carry distinct phase tags and reach both observation queues.
  Simultaneous activity remains in
  independent flags in one snapshot. `valid_W` and the current non-exception
  retirement classification are recorded separately.

## Engineer extension points

- `TODO(USER_REF_MODEL)`: independent CSR/trap architectural model, memory
  effect ledger and approved checks.
- `TODO(USER_COVERAGE)`: named groups, explicit approved bins/crosses and
  checked-result sampling. The no-op attempt hook is reached through the
  scheduler's passive observation queue; checked-result sampling is not called.
- `TODO(USER_STIMULUS)`: programs, trigger-window scheduling, response
  schedules and unit/core scenarios.

The instruction shell connects clock/reset, enable, write, mask, address and
write-data pins, but currently returns an asynchronous placeholder NOP. It
does not validate SRAM timing. The data shell connects the full request and
response boundary, ties read data/stall/error to zero, and provides typed
program/data-response configuration hooks; it implements no latency, error,
storage, or memory effects. `DATA_BASE` is intentionally omitted until an
address map is reviewed. The unit top has typed no-op model and coverage hooks.

No reference model, coverage bins, or stimulus were implemented. No PASS,
functional correctness, or coverage closure is claimed. The environment is
strictly `SKELETON/INCOMPLETE`.

Initial handback (2026-11-04): source paths, explicit DUT port names and
hierarchical probe names were inspected statically; no compiler/elaboration
or simulation result had been established at that point. The interface drive
blocks contain only bench-owned inputs; reset remains asserted throughout
the bounded skeleton lifecycle.

Parent static review confirmed 31/31 named CSR DUT ports and 21/21 named core
DUT ports connected, with no missing, unknown or duplicate port names. All 3
unit-filelist and 39 core-filelist source paths exist. Clocking/modport names
are unique in both interfaces. These checks do not establish SV syntax,
elaboration, event scheduling correctness or functional behavior.

## Running the benches

From `rtl/ips/Verification` with Vivado XSim 2022.2 on `PATH`:

```powershell
pwsh -NoProfile -File .\run_csr_trap_units.ps1                          # both benches
pwsh -NoProfile -File .\run_csr_trap_units.ps1 -Bench csr_corner_unit   # unit only
```

Each invocation compiles the bench's filelist, elaborates and simulates into a
dated `artifacts/csr_trap_units_<timestamp>/` directory holding `compile.log`,
`elaborate.log`, `simulation.log` and `source_sha256.txt`.

## Execution check — 2026-11-11

[Unit run logs and source hashes](../../../artifacts/csr_trap_units_20261111_175150/)

| Unit suite | Cases | Checked result |
|---|---|---|
| `u_status` trap/MRET status transitions | 8 | 24 checks, 0 failures |
| `u_metadata` cause, `mepc`, `mtval` | 168 | 504 checks, 0 failures |
| `u_reset` | 4 | 24 checks, 0 failures |
| `u_collision` | 40 | spec-pending, observation only |
| `u_counter` | 16 | spec-pending, observation only |

The unit bench ends with `UNIT_DONE|checks=552|failures=0|spec_pending=56` at
8936 ns. Each of the five unit covergroups reports `100.000`, but those bins
are one bin per planned case, sampled when the case executes: this is
observed-attempt coverage, not closure of value, priority or cross bins.

The 56 spec-pending cases print the observed register value and assert no
expected result, so they cannot fail and do not establish write-priority or
counter-collision behavior.

`tb_core_csr_trap` compiles (39 sources), elaborates and runs to 30 ns with the
core reset-held: `checks=0`, `SKELETON/INCOMPLETE`. It has no stimulus,
reference model or core coverage bins yet.

Both benches were also compiled, elaborated and run with the older
[closure check](../../../artifacts/csr_trap_closure_check_20261111/run_170540/CLOSURE_STATUS.md)
before the unit suites were implemented; that record describes the
reset-held skeleton only.

XCRG report generation still crashes with process status `0xC0000374`, so
coverage numbers above come from the in-simulation covergroup report, not from
a coverage database report.
