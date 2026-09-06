# SPI Master UVM VIP

UVM 1.2 verification IP for the PULP/ETH-Zurich `apb_spi_master` RTL
(`rtl/` — unmodified copy of the sources you provided). It replaces the
legacy `spi_bfm.sv` / `spi_slave_bfm.sv` / directed testbenches with a
reusable, constrained-random UVM environment.

## Directory layout

```
spi_master_uvm_vip/
├── rtl/                     DUT sources (unmodified)
├── tb/
│   ├── spi_reg_defines.svh  register offsets / bitfield macros
│   ├── interfaces/          apb_if, spi_if (plain SV interfaces)
│   ├── agents/
│   │   ├── apb_agent/       APB3 master agent (driver/monitor/sequencer)
│   │   └── spi_agent/       SPI reactive-slave agent
│   ├── env/                 env_config, virtual sequencer, scoreboard, coverage, env
│   ├── seq_lib/             APB sequences, SPI sequences, virtual sequences
│   ├── tests/                spi_base_test + all concrete tests
│   ├── spi_uvm_pkg.sv       single compile unit, `includes everything above
│   └── top/spi_tb_top.sv    HDL/HVL top: DUT + interfaces + run_test()
├── sim/
│   ├── filelist.f
│   └── Makefile
└── docs/README.md           (this file)
```

## Architecture

```
                     spi_virtual_sequencer
                     (vsqr: apb_sqr, spi_sqr, vif, buffer_depth)
                        │                    │
             ┌──────────┘                    └───────────┐
             ▼                                            ▼
        apb_agent (ACTIVE)                          spi_agent (ACTIVE)
   ┌───────────────────────┐                 ┌───────────────────────────┐
   │ apb_sequencer          │                 │ spi_sequencer              │
   │ apb_driver  ───────────┼──apb_if──►DUT   │ spi_driver (reactive slave)│
   │ apb_monitor ◄──────────┼──apb_if──DUT    │ spi_monitor (bit recon.)   │
   └───────────┬────────────┘                 └─────────────┬─────────────┘
               │ apb_transaction                              │ spi_transaction
               ▼                                              ▼
                       spi_scoreboard  +  spi_coverage
```

- **apb_agent**: drives/monitors the APB3 register interface exactly as an
  AMBA APB master would (SETUP → ACCESS phase, honours PREADY wait-states —
  including the DUT's TXFIFO-full/RXFIFO-empty backpressure).
- **spi_agent**: the DUT is a SPI *master*, so the VIP plays the SPI
  *slave*. `spi_driver` is a reactive slave: arm it with a burst of 32-bit
  words and a chip-select index, and it shifts them back MSB-first the
  instant that `spi_csn` goes low (standard 1-bit or quad 4-bit lanes,
  generalising the legacy `spi_slave_bfm`). `spi_monitor` passively
  reconstructs whatever the master shifts out on `spi_sdo` into 32-bit
  words for the scoreboard/coverage.
- **spi_scoreboard**: fully automatic, black-box (register-map only, no
  hierarchical DUT probing):
  - **TX check**: every word written to `REG_TXFIFO` is expected to
    reappear, in order, as the tail of the next captured SPI burst.
  - **RX check**: every word read from `REG_RXFIFO` is expected to match,
    in order, the words a sequence armed the SPI slave driver with (via
    `spi_scoreboard::add_expected_rx_words()`, called by the virtual
    sequences in `virtual_seq_lib.sv`).
- **spi_coverage**: register access × direction cross, STATUS command-bit
  legality (illegal to set two of rd/wr/qrd/qwr at once), chip-select
  usage, and SPI burst word-count/mode coverage.

## Tests

| Test | What it exercises |
|---|---|
| `spi_smoke_read_test` | single standard-mode word read |
| `spi_sequential_read_test` | 4 back-to-back single-word reads |
| `spi_burst_read_test` | 4 words in one CS assertion |
| `spi_quad_read_test` | quad-mode (`qrd`) burst on CS1 |
| `spi_write_test` | TXFIFO → MOSI data-path check |
| `spi_overflow_test` | RX FIFO backpressure/stall + drain/recovery |
| `spi_empty_fifo_stall_test` | PREADY stall on an early RXFIFO read |
| `spi_reset_test` | mid-transfer `swrst` clears FIFO, returns to IDLE |
| `spi_random_test` | constrained-random mix of reads/writes (`+NUM_TRANS=`) |
| `spi_regression_test` | the 3 directed corner cases + a large random batch — default nightly test |

All constrained-random knobs (`clk_div`, one-hot `csreg`, `quad` with a
70/30 dist, word count `[1:8]`, word content) live in
`seq_lib/virtual_seq_lib.sv` as `rand` fields + `constraint` blocks on
`spi_master_read_vseq` / `spi_master_write_vseq` — extend those, or the
`spi_regression_test` loop, for wider regression.

## Running

```bash
cd sim
export UVM_HOME=/path/to/uvm-1.2
make TOOL=questa TEST=spi_regression_test NUM_TRANS=200 SEED=3 run
```

No SystemVerilog/UVM simulator was available in the sandbox this VIP was
authored in, so the code has been carefully hand-reviewed against the UVM
1.2 LRM/base-class semantics but **has not been compiled**. Budget time for
a first-pass compile/lint cleanup (typedef ordering, simulator-specific
`rand`-on-queue support, etc.) before treating this as sign-off-ready.

## Known scope limitation: cmd/addr/dummy phase timing

`spi_driver` starts shifting its armed response words the instant CS
asserts. It does not model the cycle counts of the DUT's CMD/ADDR/DUMMY
controller states before the DATA phase. `spi_master_read_vseq` /
`spi_master_write_vseq` therefore constrain `cmd_bits == addr_bits == 0`
and the relevant dummy field `== 0`, keeping every generated transaction to
a pure data-phase transfer — which is also all the legacy testbench ever
exercised. To lift this limitation, extend `spi_transaction` with a
`preamble_symbols` field (computed from `cmd_len`/`addr_len`/`dummy_*` and
the DUT's quad-scaling rule, see `spi_master_controller.sv`) and have
`spi_driver` idle-shift that many symbols before starting on
`resp_words`.

## Does the RISC-V/AXI SoC context matter for this VIP?

Not for this IP's own verification boundary, no — and that's intentional,
not an oversight:

- `apb_spi_master` is an **APB3 slave peripheral**. Its entire external
  contract is the APB register interface plus the SPI pins. In a RISC-V
  SoC it normally hangs off an AXI-to-APB bridge, but that bridge and the
  AXI fabric in front of it are a *different* piece of IP with their own
  verification responsibility (protocol compliance, arbitration, outstanding
  transactions, etc.) — none of which this peripheral's logic can influence
  or be influenced by. Bolting an AXI VIP onto this environment would add
  simulation cost without adding coverage of anything `apb_spi_master`
  actually does.
- This is the standard "IP-level VIP tests at the IP's own bus, SoC-level
  VIP tests at the SoC boundary" split: your chip/subsystem testbench
  drives AXI into the bridge and should reuse *this* APB agent in
  **passive/monitor mode** (`apb_agent_config.is_active = UVM_PASSIVE`) on
  the APB side of the bridge to get the same scoreboard/coverage for free,
  while an AXI master VIP drives the RISC-V-side transactions.
- Where the SoC context *would* matter to this VIP: if the SoC's APB
  bridge introduces non-standard wait-state behaviour, a different
  `APB_ADDR_WIDTH`/decode offset, or shares `spi_csn`/`spi_sdi` pins with
  other muxed peripherals, those are configuration knobs already exposed
  here (`APB_ADDR_WIDTH` parameter, `apb_agent_config`, `spi_if`'s 4
  independent CS lines) rather than reasons to add new agents.

So: keep this VIP APB+SPI only; instantiate it (agents in passive mode as
needed) inside your larger AXI/RISC-V SoC testbench rather than growing it
to include an AXI agent itself.
