# Testbench architecture and component contracts

## 1. Final structure

Use one reusable class library with three explicit execution profiles:

```text
Test selection + scenario manifest + seeds + firmware image
                         |
                 scenario_controller
                         |
      +------------------+--------------------+
      |                                       |
 CFG-S: soc_system_tb                  CFG-F: soc_fabric_tb
 complete unchanged SoC              unchanged selected fabric RTL
 core executes C/assembly             AXI master BFMs own input ports
 bootloader loads real flash          controlled target/APB responders
 external pin agents drive peers      randomized backpressure/errors
      |                                       |
      +---- observation adapters / interfaces--+
                         |
      normalized immutable events + reset epochs
                         |
         +---------------+----------------+
         |               |                |
   protocol/path    register/device    IRQ/trap/memory
    scoreboards       scoreboards       scoreboards
         +---------------+----------------+
                         |
        observed coverage + checker viability
                         |
        drain / completion / verdict / run package

 CFG-H: harness self-test tops feed known good/bad event traces,
 prove checkers and drivers, and never count as SoC behavior coverage.
```

CFG-S is the authoritative source for real firmware, real peripheral and end-to-end IRQ claims. CFG-F reaches legal combinations that the embedded masters cannot generate, including two-master contention and arbitrary AXI READY delays. CFG-H proves the instruments. A coverage record always states its profile and exact instantiated DUT scope.

## 2. Ownership and configuration boundaries

In CFG-S, the core/bootloader own all internal bus request signals. The bench owns clock, reset and off-chip input behavior. Hierarchical access is centralized and **read-only during execution**, except documented memory preload while the core is held in the correct reset/boot phase. Do not force internal bus/IRQ signals in positive system tests. Debug fault injection is an explicitly separate negative-proof profile and cannot earn real-peripheral bins.

CFG-F instantiates the actual crossbar, bridge and selected timeout/SRAM-interface RTL using existing parameter interfaces. AXI agents own both requester ports. Target model substitution is declared per variant:

| Variant | Real DUT blocks | Replaced boundary | Useful claim |
|---|---|---|---|
| F-XBAR | Crossbar | Two requesters + three target responders | Arbitration, channel concurrency, decode, ordering, response routing |
| F-APB | Crossbar + bridge + APB timeout monitors | Requesters + six synthetic APB peripherals | Aperture/hole routing, strobes, waits, timeout/error propagation |
| F-SRAM | Crossbar + real SRAM interfaces, access gates and memories | Requesters; APB target may be modeled | SRAM privilege/access policy, byte lanes, contention and errors |
| F-AXI-TMO | Actual `axi_lite_timeout_monitor` at the upstream requester boundary, optionally followed by the real crossbar | Upstream AXI master BFM and controlled downstream responder | Early upstream SLVERR, held downstream request, late completion, swallowed late response, drain and recovery |

Each variant has a resolved filelist and a separate coverage scope. No variant is automatically equivalent to the whole SoC. Do not pretend a response model tests the peripheral it replaces. The first implementation can contain only F-APB; add other variants when their missing obligations justify them.

F-AXI-TMO is mandatory before claiming controlled AXI timeout/drain closure. APB timeout tests do not substitute: their access-abort/block behavior has a separate contract. Test timeout just before/at/after the threshold, late downstream acceptance/response, a new request during drain, exactly one upstream error, no leaked second response, and useful service after recovery. A permanent downstream stall may remain in a bounded diagnosed drain state; do not demand impossible recovery without the downstream or reset assumptions being met.

## 3. Component goals, inputs and outputs

### C01 Static top and electrical interfaces

**Goal:** instantiate unchanged RTL and provide deterministic pin/reset wiring. `soc_system_tb.sv` contains the DUT and interface instances, not test algorithms. Interfaces expose clocking blocks/modports for legal driving/sampling. An I2C resolved bus uses pull-ups and active-low output-enable semantics verified against the leaf RTL. Do not copy the current top's apparent enable-polarity mismatch. SPI CS0 flash and CS1 peer each produce a tri-state response; one resolver selects the legal active peer and flags overlapping selects. GPIO input generation respects selected loopback/external-stimulus mode. Testbench driver ownership is asserted.

**Completion evidence:** independent interface tests, idle levels, reset values, no bus contention, I2C ACK/read sanity and SPI address/command self-tests.

### C02 Observation adapter

**Goal:** isolate hierarchy-dependent references in `soc_observation_adapter.sv`. Export fetch, committed retirement, native LSU, core AXI before/after timeout, bootloader AXI, APB before/after timeout, raw IRQs, gateway/arbiter decisions, trap/mret commits, reset domains and boot state. Widths derive from reviewed configuration (13 IRQ sources now), with elaboration assertions preventing silent truncation.

Sample handshakes on their actual edge and capture data as immutable value objects. Mark LSU request start versus accepted/completed transaction; a held request is one operation. Capture AW and W independently, join in AXI-Lite order and complete on B; pair AR/R similarly. Capture APB on `PSEL && PENABLE && PREADY` for the selected slot. Inactive-slot payloads are not valid observations. Four-state X/Z on valid control or compared data is a finding, not converted silently to zero.

**Output:** typed events, reset epoch, source, cycle/phase, local sequence number. **Evidence:** hand-built single-transfer, stalled-transfer, simultaneous read/write, reset-abort and same-address-repeat traces; exact count and payload comparison.

### C03 Configuration and scenario controller

**Goal:** a small explicit lifecycle: `build`, `connect`, `start`, `run`, `stop_stimulus`, `drain`, `check`, `report`. Constructor-injected typed configuration replaces a global config database. Select tests with a simple registry or explicit test-name dispatch, not a custom factory framework.

The controller schedules independent pin/reset actors from a precomputed scenario and observed checkpoint events. Global ordering is `(reset_epoch, cycle, sample_phase, source_id, local_sequence)`; replay does not rely on host-thread arrival order. Spawned threads have an explicit stop token and join policy. Every `randomize()` failure is fatal to the test; constraints never repair an illegal transaction after generation.

### C04 Firmware preparation and executor

**Goal:** execute system bus stimuli through the real core. The host prepares an operation table and firmware image before simulation. One compact C executor handles register operations, bounded polls, signature computation and checkpoint publication; dedicated assembly kernels handle trap-sensitive instruction sequences. The SV controller controls off-chip peers, not MMIO wires.

Generate one versioned scenario description with two projections: a C operation table and the SV expected external-device schedule. Actual register expectations remain in independently reviewed semantic models, not merely echoed from firmware PASS values. No live SV-to-firmware command server is required initially. A later live service is a new feature with its own coherency/ownership tests.

Mailbox protocol: firmware owns runtime writes; TB observes committed DSRAM writes and optionally passive memory reads. Reserve an aligned linker region, starting from the existing mailbox at `0x0002_0000`; reconcile every BSP/header against one reviewed definition. Never use `0x0002_8000` as writable mailbox storage: it is the exclusive DSRAM end. Publish payload first, sequence/status last, with compiler barriers and the required ordering instruction. Firmware tags test ID, scenario hash, firmware-local boot/start sequence, checkpoint sequence and terminal status. **TB owns the reset epoch:** it advances on each observed core-reset assertion and associates the next newly committed START/RUNNING record after release with that epoch. Firmware need not know the controller epoch. A reset before START leaves no active session. A retained PASS word, passive reread, old sequence or terminal record without a current START is ignored/reported as stale and cannot complete the test. Reset restarts the checkpoint-relative schedule for the new session; any absolute-time actor has an explicit cancel/restart policy. Final PASS requires matching observed activity, scoreboards and coverage obligations, not just a magic word.

### C05 Bus agents

**Goal:** CFG-F AXI agents generate independent AW/W/AR channel timing, legal stable VALID payloads, bounded READY delays, byte strobes, read/write mixes and response expectations. APB responders implement configurable waits, errors and reset abort. Agents expose `execute(item)` plus passive observed-event output. In CFG-S their monitors remain passive; drivers are absent.

Use typed request/response mailboxes where one producer/consumer exists. For multiple subscribers, the monitor creates one immutable snapshot and explicitly broadcasts copies or read-only handles through subscriber mailboxes. A single shared mailbox is a work queue, not a broadcast channel. Set finite queue capacities; overflow is reported and cannot silently drop scoreboard events.

### C06 Peripheral pin agents and device models

**Goal:** UART configurable frame generation/decoding; I2C EEPROM contents/ACK/NACK/stretch behavior; SPI command/address/data response and selected-peer behavior; GPIO loopback, independent input transitions and IRQ trigger modes. Drivers produce stimuli. Independent monitors decode what actually crossed the pins.

The reference model tracks expected bytes/device memory, FIFO-order effects and error/recovery behavior. Prove supported commands explicitly. Existing SPI BFM header claims are not a capability test: fast-read decoding and complete address assembly need qualification. Existing I2C model multi-byte reads and UART RX generation also need qualification. Use vendor models for realistic power-up/timing checks without overriding their time units; fast models earn only their declared functional scope.

### C07 Protocol and end-to-end path checking

**Goal:** SVA checks handshake stability, legal APB phases, response behavior, reset release and bounded liveness under stated assumptions. A queued path scoreboard joins native LSU → AXI request/response → APB transaction, including address, data, byte lanes, response, order and multiplicity. Native DSRAM operations bypass the MMIO join and go to the memory checker. Bootloader transactions carry a different origin and phase.

A positive error response is legal only when predicted for that access. Decoder holes may produce no APB transaction; expected error paths therefore terminate at the appropriate upstream boundary. Timeout checks distinguish a synthesized upstream error from late downstream completion/draining. On reset, explicitly classify outstanding requests as completed, legitimately aborted under the interface contract or lost; do not simply clear nonempty queues. At end, every expected and observed queue drains or has a checked terminal disposition.

**Instruction-to-effect ledger for trap tests:** a bus join alone cannot detect two duplicate native requests that both traverse correctly. Assign a TB token to each dynamic memory instruction at a qualified pipeline advance, using sampled instruction/PC/valid/stall/flush observations; propagate its stage identity until retirement, synchronous trap, squash or reset cancellation. A repeated PC in a loop is a new dynamic ordinal, not the same token. Associate native requests and permitted bus fragments with that token, and compare against an independent kernel/operation-table effect ledger (expected operation ordinal, address/width/value, permitted fragments and multiplicity). An unsplit aligned MMIO operation permits one effect; split memory accesses require an explicit fragment policy. Check older committed effects, suppressed younger effects and the precise trap/resume boundary. Do not assume that an accepted device side effect can be rolled back merely because an upstream instruction did not retire normally.

Qualify the token tracker with stall, flush, repeated-PC and simultaneous transfer/trap traces. Detect duplicate native requests for one instruction, an extra dynamic instruction/effect relative to the expected kernel, a missing effect, wrong fragment count and an effect from a squashed instruction. No production RTL tags are added. If available observation cannot unambiguously identify a required advance/squash, make that a named instrumentation blocker and use tightly bounded assembly checkpoints/effect expectations for the supported cases; do not claim general exactly-once trap closure until the ledger is qualified. This is a targeted memory-effect observer, not a promised general ISA lockstep model.

### C08 Register model and scoreboard

**Goal:** descriptor-driven, independently reviewed semantic checking of every integrated register, bank, alias and applicable field. It consumes completed APB operations, peripheral events and relevant resets. It neither predicts on request intent nor uses DUT readback as its expected state. Rejected-before-acceptance writes do not mutate state; timeout/late-completion behavior is tracked at both boundaries and is not assumed to roll back. See [03_REGISTER_VERIFICATION.md](03_REGISTER_VERIFICATION.md).

### C09 IRQ and trap scoreboard

**Goal:** model 13 source pending states, masks, global enable, threshold, class selection and commit-driven round robin; check source → gateway → service eligibility → trap commit → ISR observable effect → clear/reassert → mret. Compare the committed cause and PC, not just a transient winner. Model supported nesting separately from arbitration and check saved context/depth on return.

Use CSR write/commit observation as model inputs. The model must not use the DUT's chosen winner as its expectation. Raw peripheral events and independently predicted mask/priority state establish the expectation; internal pending/winner probes provide diagnostic comparisons. Verify one instruction boundary, defer window and reset case at a time before mixing all sources.

### C10 Memory and software-result checking

**Goal:** check actual DSRAM writes/readbacks, memory march signatures, guard regions, stack and ISR canaries. Define destructive regions disjoint from code, mailbox, operation table, stack and expected signatures. Full destructive SRAM testing runs from a safe execution/storage region or in a separate memory/fabric harness; a C loop cannot erase its own stack and claim full coverage. Preserve address/pattern/error detail, not just a compressed success signature.

### C11 Coverage collector

**Goal:** sample architectural coverage on observed completed events and checked outcomes. Publish attempted/observed/checked counters separately. Failed runs retain diagnostic coverage but do not contribute accepted candidate closure. Legal bins are generated from the reviewed inventory/configuration and retain requirement IDs. Functional, structural, assertion and code coverage stay separate. See [04_STIMULUS_AND_COVERAGE.md](04_STIMULUS_AND_COVERAGE.md).

### C12 Verdict, watchdog and evidence writer

**Goal:** one finding sink with check ID, classification, cycle, epoch, context and expected/actual values. Preserve first causal finding and subsequent dependent findings. Keep diagnostic ring-buffer freezing independent from lossless scoring/coverage ingestion; a ring wrap count is not permission to drop checker events.

Start an absolute simulation guard at time zero, then separate boot, runtime, transaction and drain deadlines. No unbounded `wait(boot_done)` before watchdog activation. Qualify retirement deadlines with actual core reset and legal boot phase. Publish expected-negative verdicts separately from clean positive verdicts. Writers produce machine-readable records and tool-native databases, with one final host-side gate evaluator. Simulator exit zero alone is never PASS.

## 4. Proposed implementation files

These names describe a future layout under `ips/Verification/`. Keep existing reusable module sources in place and reference them from the new manifests. Do not copy all existing monitors into a parallel tree.

```text
system_tb/
  top/soc_system_tb.sv                 C01, real full SoC
  top/soc_fabric_tb.sv                 C01/C05, declared F variants
  adapters/soc_observation_adapter.sv  C02, only hierarchy mapping
  interfaces/soc_observation_if.sv     C02, widths and sampled signals
  interfaces/pin_interfaces.sv         C01, UART/I2C/SPI/GPIO modports
  interfaces/reset_control_if.sv      C01, clock/reset ownership
  pkg/soc_tb_types_pkg.sv              events, enums, evidence IDs
  pkg/soc_tb_pkg.sv                    ordered class includes
  core/soc_tb_cfg.svh                  C03, explicit profiles/knobs
  core/soc_event.svh                   C02, immutable event contract
  core/soc_scenario.svh                C03/C04, scenario descriptor
  core/soc_env.svh                     build/connect/run/drain/check
  core/soc_test.svh                    small test base + explicit registry
  services/reset_boot_service.svh      C01/C12, deadlines/epochs
  services/firmware_service.svh        C04, image/checkpoint observation
  services/progress_watchdog.svh       C12, phase-aware bounded progress
  services/finding_sink.svh            C12, one verdict/finding stream
  agents/axi_lite_agent.svh            C05, F active / S passive
  agents/apb_response_agent.svh        C05, F responder
  agents/uart_agent.svh                C06, frame driver/monitor
  agents/i2c_peer_agent.svh             C06, electrical peer control
  agents/spi_peer_agent.svh             C06, CS0/CS1 response coordination
  agents/gpio_agent.svh                C06, loopback/injection modes
  models/register_model.svh            C08, reviewed semantic policies
  models/peripheral_models.svh         C06, device content/data expectations
  models/irq_model.svh                 C09, policy state independent of DUT
  scoreboards/path_scoreboard.svh      C07, exact ordered joins/drain
  scoreboards/instruction_effect_ledger.svh C07/C09, dynamic token/effect tracking
  scoreboards/register_scoreboard.svh  C08, event-driven expected values
  scoreboards/pin_scoreboard.svh       C06, bytes/commands/errors
  scoreboards/irq_trap_scoreboard.svh  C09, delivery/context/return
  scoreboards/memory_scoreboard.svh    C10, region/pattern/guard checking
  coverage/soc_coverage.svh            C11, family sampling dispatch
  coverage/{bus,register,pin,irq,reset,boot,trap}_coverage.svh
  assertions/soc_protocol_bind.sv      C07, wrappers around qualified SVA
  selftest/                            CFG-H driver/monitor/model negatives
  tests/{bringup,register,peripheral,mixed_stress,trap,reset}_test.svh
  filelists/{soc_system,soc_fabric,harness_selftest}.manifest
  uvm_adapter/                        absent initially; only if activated
spec/
  soc_registers.yaml                   reviewed register/field inventory
  soc_irq_map.yaml                     source/class/enable/trigger contract
  verification_requirements.yaml       requirement + original-plan/check IDs
  coverage_bins.yaml                  declared bins/legal predicates
  checker_catalog.yaml                check ID, binding, negative proof
  regression_suites.yaml               required tests/profiles/seeds/budgets
tests/
  bsp/                                 consolidate current test BSP in place
  suites/reg_semantics/main.c           C04 register operation executor
  suites/memory_patterns/main.c         C10 march/walking patterns
  suites/peripheral_duplex/main.c       C06 real pin paths
  suites/mixed_stress/main.c            C03/C06 combined workload
  suites/trap_load_stress/{main.c,kernels.S}
scripts/
  build_scenario.py                     schema validation + C/SV schedule
  generate_register_views.py            C/SV descriptors, addresses, inventory
  package_run.py                        hashes, commands, logs, counters
  evaluate_candidate.py                 typed verdict and gate aggregation
  report_traceability.py                requirement/check/test/result links
  report_coverage.py                    tool adapters + normalized hole list
artifacts/runs/<run_id>/                immutable execution evidence
artifacts/candidates/<candidate_id>/    selected runs/merge/closure decision
```

These logical components may share a physical file initially. Keep C01–C12 interfaces and ownership stable; split files when doing so makes review easier. Do not build a generic framework, an RPC service or a custom UVM clone before the first register suite runs.

## 5. Class communication contract

Every event contains `schema_version`, `run_id`, `profile`, `epoch`, `source_id`, `sequence`, `cycle`, `event_kind`, address/data/mask/response where applicable, and correlation context. Four-state payloads retain X information or an explicit unknown mask. Analysis transactions are not reused and mutated after publication. Separate request, completion, reset and architectural-commit event kinds prevent accidental intent-based coverage.

Analysis callbacks/typed subscriber queues call short zero-time functions. Blocking driver operations are tasks with timeouts. The environment processes same-cycle events in a declared order, with explicit pre-state/post-state policy for a simultaneous register clear and hardware set. No naked SV `event` is the sole record of a transaction: an event wakes a consumer, while a sequence-numbered queue retains the payload. Check reset epoch on every pending expectation.

## 6. Minimal UVM alternative

If activated, use UVM as an integration shell around the same interfaces, transactions and policy models. Pin the installed UVM version in the build manifest and qualify it with the selected simulator. Add only:

| UVM file/component | Responsibility |
|---|---|
| `soc_uvm_test.sv` / `soc_uvm_env.sv` | Test selection, build/connect lifecycle and one top-level run objection |
| `soc_uvm_cfg.sv` | One typed config object, passed once via config DB |
| `soc_item.sv` | Sequence item envelope around shared payload |
| `axi_uvm_agent.sv` | Active sequencer/driver/monitor in F; passive monitor in S |
| `pin_uvm_agents.sv` | Existing qualified pin-driver tasks plus sequencers and analysis ports |
| `soc_virtual_sequence.sv` | Coordinate firmware checkpoints, pins and reset; direct handles are sufficient initially |
| `soc_uvm_scoreboard.sv` | Adapt analysis events to the shared reference models and comparators |
| `soc_reg_adapter.sv` / `soc_reg_block.sv` | Optional generated RAL for F bus access; custom semantics remain explicit |

UVM sequences choose transactions; drivers apply electrical timing; monitors publish actual observations. UVM does not create the device's events automatically. `uvm_event` is not a lossless transaction FIFO; analysis FIFOs carry observations. Set drain completion explicitly before dropping the run objection. Avoid arbitrary objection delays, broad factory overrides, a separate virtual sequencer hierarchy and two parallel register mirrors. If RAL is adopted, select monitor-driven prediction as the authoritative update path; do not also auto-predict the same access.

In S, a RAL call cannot magically drive an internal bus: it needs a real firmware access backend or pre-generated firmware test. Therefore a full RAL rollout is deferred until it saves more work than it adds. The underlying agent/monitor/sequencer and register-adapter roles are described in the [Accellera UVM 1.2 User's Guide](https://accellera.org/images/downloads/standards/uvm/uvm_users_guide_1.2.pdf), chapters 3–5. This is a conceptual source, not a claim that UVM 1.2 is the required installed version.

**Decision:** implement pure OOP SV first. Add this shell only after a recorded need. Coverage and closure contracts do not change with the framework choice.

If literal checklist 6.1 acceptance requires an AXI UVM master emulating the CPU against **real peripherals**, add `soc_agent_integration_tb.sv` as optional **CFG-I**. It is a verification-only structural assembly of unchanged crossbar/bridge/timeout/peripheral RTL with the requester replaced by the UVM agent and real pin peers attached. It is distinct from the unchanged full-SoC top and from F's synthetic peripheral responders. Review and hash its wiring/parameters against the real integration; it cannot earn core execution, autonomous boot or real core-to-ISR bins. It needs its own topology/filelist and boundary report. Do not force internal nets or delete/modify the production core instance to create it. Implement CFG-I only when it resolves the specific accepted criterion or substantially accelerates real-peripheral register testing.
