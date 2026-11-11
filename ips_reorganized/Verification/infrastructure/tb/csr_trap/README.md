# CSR and trap skeleton

[Architecture, diagrams and verification goal](../../../doc/CSR_TRAP_TESTBENCH_ARCHITECTURE.html)

Invocation root for both filelists is `rtl/ips`. Compile each filelist
independently and select the top named in its header comment. Example
VCS compile/elaboration templates, run from `rtl/ips`:

```sh
vcs -full64 -f Verification/filelists/tier1_unit/tb_csr_corner_unit.f -o simv_csr_corner

vcs -full64 -f Verification/filelists/tier1_unit/tb_core_csr_trap.f -o simv_core_csr_trap
```

Equivalent simulator command syntax may differ. These are templates only;
they have not been run in this environment.

## Tops and wiring

- `tb_csr_corner_unit` connects every `csr_regfile` port through
  `csr_corner_if`. Reset is active low and remains asserted.
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

Validation: source paths, explicit DUT port names and hierarchical probe names
were inspected statically. No compiler/elaboration or simulation result is
available. The interface drive blocks contain only bench-owned inputs; reset
remains asserted throughout the bounded skeleton lifecycle.

Parent static review confirmed 31/31 named CSR DUT ports and 21/21 named core
DUT ports connected, with no missing, unknown or duplicate port names. All 3
unit-filelist and 39 core-filelist source paths exist. Clocking/modport names
are unique in both interfaces. These checks do not establish SV syntax,
elaboration, event scheduling correctness or functional behavior.
