# Step 4 — Checkers, Protocol Assertions and Path Scoreboarding

**RISCFORGE SoC · Verification Infrastructure, `rtl/ips/Verification/step4_checkers/`**
Implements Step 4 of *SoC Verification Infrastructure: Integration Guide*
("Checkers and failure reporter").

| | |
|---|---|
| DUT | `RTL_SOC/riscforge_soc_subsystem.sv` (2 AXI-Lite slaves → xbar → 3 masters, `axi_lite_to_apb` → 6 APB slots) |
| Core | `riscv_core/rtl/top.v` · RV32IM_Zicsr, 5-stage |
| Layer | L1 protocol, L2 path (this step). L3+ belong to Steps 5–8 |
| Status | Implemented, compiles and elaborates in xsim. Self-proof Phase 1 green. **Phase 2 not yet green — see §10** |

---

## 1. What Step 4 owns, and what it does not

The guide's Step 4, verbatim:

> Bind protocol assertions on every fabric interface and add a path scoreboard:
> each core MMIO access must appear as one AXI transaction and one APB transfer
> on the slot given by the address map, with the same data, strobes and
> response. Add the reporter with first-fatal logic. Give every checker a
> fault-injection switch so you can prove it fires.
>
> **Proof:** each injected fault is named by the correct check ID in the report,
> and every assertion has a cover that is hit.

That decomposes into five deliverables:

| # | Deliverable | File |
|---|---|---|
| 4.1 | AXI4-Lite protocol assertions | `step4_axi_sva.sv` |
| 4.2 | APB4 protocol assertions | `step4_apb_sva.sv` |
| 4.3 | End-to-end MMIO path scoreboard | `step4_path_scoreboard.sv` |
| 4.4 | First-fatal failure reporter | `step4_hub.sv` + `step4_reporter.sv` + `step4_disasm.sv` |
| 4.5 | Fault-injection framework | `step4_fault_inject.sv` |

**Out of scope, and why.** Whether a peripheral should raise PSLVERR is a
register-layer question (L3), not a path question. The path scoreboard checks
only that PSLVERR survives the mapping into `RESP_SLVERR` and is not swallowed
into `RESP_OKAY` — swallowing an error is the worst thing a bridge can do, and
it belongs at L2. Deciding *which* writes are legal sub-word writes belongs to
the register predictor.

---

## 2. Design under test, and every observation point

```
  core_lsu_*  (top.lsu_mem_*)                 tap A ── the core issues an MMIO access
        │
        ▼
  hybrid_mem_interface  i_core_data_if
        │  m_axi_req_o.w.strb = mem_be              ← byte strobes enter here
        ▼
  axi_lite_timeout_monitor  i_axi_lite_timeout_monitor
        │
        ▼
  axi_lite_xbar  SLV[0]                      tap B ── the AXI4-Lite transaction
        │
        ▼
  axi_lite_xbar  MST[2]
        │
        ▼
  axi_lite_to_apb  i_axi_lite_to_apb               ← "AXI4-Lite Master 2"
        │
        ▼
  apb_req[i] / apb_resp[i]                  tap C ── the completed APB transfer
        │
        ├── APB[0] I2C     0x4000_0000 … 0x4000_0FFF
        ├── APB[1] Timer0  0x4000_1000 … 0x4000_1FFF
        ├── APB[2] UART    0x4000_2000 … 0x4000_2FFF
        ├── APB[3] GPIO    0x4000_3000 … 0x4000_37FF   ← 2 KB, see §11.1
        ├── APB[4] SPI     0x4000_4000 … 0x4000_4FFF   (bootloader during boot)
        └── APB[5] Timer1  0x4000_5000 … 0x4000_5FFF
```

Source of every constant: `riscforge_soc_subsystem.sv:678-690` (maps),
`:463-477` (timeouts), `:244` (`NUM_APB_SLAVES`). `addr_decode` semantics are
**start inclusive, end exclusive** (`addr_decode.sv:53-54`), which is why the
ranges above are written `[lo, hi)`.

### 2.1 Byte-enable path — the single most important chain

```
  core_lsu_be[3:0]                          top.v:lsu_mem_be
    → m_axi_req_o.w.strb = mem_be           hybrid_mem_interface.sv:349
      → apb_req.strb = axi_lite_req_i.w.strb   axi_lite_to_apb.sv:126
        → apb_req_o[..].pstrb = apb_req.strb  axi_lite_to_apb.sv:311, 339
```

Nothing in this chain aligns, reorders or masks anything. It is a straight wire,
which makes it exactly the kind of thing that breaks silently: a dropped byte
lane still completes, still returns OKAY, and lands in the wrong register. Only
a checker that compares the *same byte lane at both ends* sees it. That check is
`PATH_STRB`, and it is checked at both hops (§7.4).

`apb_req_t.pstrb` reaches only `gpio_apb_wrap` in the current peripheral set
(`riscforge_soc_subsystem.sv:1102-1118`); I2C, both timers, UART and the SPI
master take scalar ports and ignore it. The bridge still carries it, so the
scoreboard checks it end-to-end regardless of what a given peripheral does with
it.

### 2.2 Timing budgets

| Slot | `APB_TIMEOUT_CYCLES` | Source |
|---|---|---|
| 0 I2C, 1 Timer0, 2 UART, 3 GPIO, 5 Timer1 | 16 | `:463-470` |
| 4 SPI | 65536 | flash transactions are genuinely slow |

AXI-side: `AXI_TIMEOUT_SRAM = 64`, `AXI_TIMEOUT_APB = 131072` (`:476-477`). The
APB monitor always fires first — that ordering is load-bearing, because if the
AXI monitor answered first the APB error would be swallowed before the core ever
saw it. `step4_pkg::APB_BEFORE_AXI` records the invariant.

No path check is ever allowed to be tighter than these budgets. A path check
that fails on a transfer the timeout monitor would also have aborted is measuring
the wrong thing.

---

## 3. Layer model and the blame rule

Seven layers, lower number = more fundamental. Blame always walks down.

| Layer | What is observed | Expected behaviour comes from | Step |
|---|---|---|---|
| L1 `PROTOCOL` | AXI-Lite and APB handshakes | assertions | **4** |
| L2 `PATH` | core access → AXI transaction → APB transfer | scoreboard using the address map | **4** |
| L3 `REGISTER` | peripheral register reads and writes | register predictor | 6 |
| L4 `FUNCTIONAL` | UART/GPIO/I2C/SPI/timer at the pins | pin models | 6 |
| L5 `INTERRUPT` | raise, pending, grant, accept, acknowledge | interrupt predictor | 7 |
| L6 `CPU-STATE` | retired instructions, CSRs, traps | ISS (Spike) | 6 |
| L7 `FIRMWARE` | mailbox status, checksum | the test and host values | 8 |

The five levels named in the Step 4 request map to L1, L2, L3, L4, L7. L5 and L6
sit between them and are declared now so the ordering does not shift when those
steps land.

### 3.1 Blame algorithm

Implemented in `step4_reporter::absorb()`.

1. The **first** check to fire is the blame. Rings freeze immediately and the
   one-page report is emitted at once, not at end of simulation — a hang must
   still produce a report.
2. A later failure at a **strictly lower** layer is more fundamental, so blame
   moves to it (`F_REASSIGN`) and the page is re-emitted. This is not cosmetic:
   a protocol violation that the bus only reveals after the path has already
   complained should end up blaming the protocol.
3. Every later failure at the same or a higher layer is recorded and labelled
   `F_DOWNSTREAM`. It is printed, counted, and suppressed. All of them are kept —
   "no other check fired" is a claim a human has to be able to check.

### 3.2 The pass rule

A test passes only when **all** of:

- the mailbox reports PASS (Step 5+),
- no checker failed,
- **the checkers actually saw activity** — a suite that observed no MMIO traffic
  reports CLEAN and is flagged `VACUOUS PASS`,
- no predicted event is left unobserved (Step 8),
- no timeout occurred.

The vacuity clause is not decoration. During development of this step it caught a
testbench that held `lsu_stall` high from the first cycle, which meant the path
scoreboard's tap A never fired: 17 transactions, zero checks, a completely
misleading "0 findings". The counter exists so that failure cannot recur.

---

## 4. File map

```
step4_cfg.svh              compile-time sizing, included by everything
step4_pkg.sv               address map, layers, check IDs, records, FI config, bus types
step4_disasm.sv            RV32IM_Zicsr decoder for the report
step4_disasm_tb.sv         self-checking test for the decoder (31 cases)
step4_hub.sv               reporter state  — an INTERFACE, storage only, no functions
step4_reporter.sv          blame, rendering, one-page report, final verdict
step4_axi_sva.sv           AXI4-Lite assertions
step4_apb_sva.sv           APB4 assertions, all six slots in one instance
step4_path_scoreboard.sv   end-to-end MMIO path
step4_fault_inject.sv      fault injection
step4_bind.svh             attach everything to riscforge_soc_subsystem
step4_smoke_tb.sv          self-proof: clean traffic + fault matrix + bridge model
step4_sim.f                xsim compile list
run_step4.ps1              build / run / verdict
```

### 4.1 Two structural decisions, and why

**The reporter state is an interface; the reporter logic is a module.**
`step4_hub` holds only variables. Every string, every `$sformatf` and the whole
one-page emitter live in `step4_reporter`, an ordinary module that reads the
interface through a port. This is not stylistic. See §9.1 — xsim codegens every
function declared in an interface and crashes on anything non-trivial, and a
module cannot be a port type in xsim at all. The split is forced, and it happens
to be the better design: observers stay dumb, and one place owns blame.

**Checkers send numbers; the reporter renders the sentence.** A check ID is an
index (`CID_PATH_STRB`). `step4_reporter::render()` turns it into
`"PATH-3007  byte strobes survive the path unchanged: %04b"` plus the actual
value. A check ID therefore always reads the same way wherever it fires, and the
triage bucket keyed on that ID cannot drift from the prose. It also keeps the
SVA action blocks down to a single packed assignment.

---

## 5. AXI4-Lite assertions

Bound at `xbar_slv_req/resp[0]` (core master, **after** the timeout monitor —
post-monitor deliberately, so the abort path is visible) and `[1]` (bootloader).

| Check ID | Property | Why it matters here |
|---|---|---|
| `AXIL-1001` | AW addr/prot stable while `aw_valid && !aw_ready` | `hybrid_mem_interface.sv:345` drives `aw.addr` straight from `mem_addr`; correctness depends entirely on `core_lsu_stall` freezing the pipeline. Weaken that and the payload changes under the bridge and the access lands on the wrong slot — still completing, just somewhere else. Nothing else would notice. |
| `AXIL-1002` | W data/strb stable while stalled | same argument for the byte-enable hop |
| `AXIL-1003` | B resp stable while stalled | an error that changes mid-handshake is an error that is lost |
| `AXIL-1004` | AR addr/prot stable while stalled | |
| `AXIL-1005` | R data/resp stable while stalled | |
| `AXIL-1006` | VALID held until READY, all five channels | AXI4 removed the AXI3 allowance for withdrawing VALID. A master that does loses a transfer and the xbar demux latches the wrong target. |
| `AXIL-1007` | no X/Z on any payload while VALID | the SRAM models are 4 MB arrays gated by `` `ifndef SYNTHESIS ``; an uninitialised word arrives as X and would be written into a peripheral and read back as a plausible-looking value |
| `AXIL-1008` | response never EXOKAY | EXOKAY is AXI-full only; seeing it on AXI4-Lite means a full-AXI converter was wired up by mistake |
| `AXIL-1009` | B only after both AW and W handshaked | AXI4-Lite permits W before AW, so this does **not** order the two; it only forbids answering a write that was never issued |
| `AXIL-1010` | no channel stalled longer than `STEP4_STALL_BOUND` (64) | turns an unbounded hang into a named failure. Deliberately far below `AXI_TIMEOUT_APB`=131072 — an SVA range that wide is expensive, and by then the bus is long dead. |
| `AXIL-1011` | an accepted read is answered | without it, a request the fabric accepts and then loses shows up only as a watchdog timeout with no story |

Every assertion has a matching `cover property`. `AXIL-1010` is the reason the
coverage clause exists: the *bounded wait* path is only meaningful if some test
ever provokes a stall, and a cover that is never hit means the property was
never stressed.

---

## 6. APB4 assertions

One instance covers all six slots. That is not for brevity — the interesting
APB property here is fabric-wide. If the bridge ever drives two slots at once,
which is exactly what a mis-written `apb_addr_map` rule would do given that
GPIO's rule is 2 KB while its neighbours are 4 KB, then two peripherals both
commit the same access and neither is individually wrong. A per-slot checker
cannot see that.

| Check ID | APB4 rule | Why it matters here |
|---|---|---|
| `APB-2001` | PENABLE implies PSEL | APB4 removed the APB2 allowance for PENABLE high while PSEL low |
| `APB-2002` | setup is never more than one cycle | it must advance to access, or the master withdraws PSEL |
| `APB-2003` | PADDR/PWRITE/PWDATA/PSTRB stable from setup through access and through every wait state | `axi_lite_to_apb.sv:302-312` and `:330-340` rebuild the whole struct in both phases from `apb_req_q`; any bug in that register appears here |
| `APB-2004` | access completes within `STALL_BOUND`; PSEL held through the completing edge | |
| `APB-2005` | PRDATA meaningful only for a completed read | a slave driving PRDATA in setup, or on a write, is what makes a read-modify-write in firmware see stale data |
| `APB-2006` | PSLVERR only in the access phase | |
| `APB-2007` | PADDR word aligned | `aligned_addr()` at `:305` and `:333` means a sub-word MMIO access arrives word-aligned with the real lane in PSTRB. If `PADDR[1:0]!=0` the peripheral decodes the wrong register. |
| `APB-2008` | at most one PSEL across all six slots | §6 preamble |
| `APB-2009` | no X on PADDR or on PWDATA/PSTRB | |

---

## 7. The end-to-end MMIO path scoreboard

### 7.1 The claim

> Every core MMIO access appears as exactly one AXI4-Lite transaction and, if it
> decodes to an APB rule, exactly one APB transfer on the slot the address map
> gives — with the same direction, address, data, byte strobes and response,
> within the timing budgets.

### 7.2 Why a single record and not a queue

`axi_lite_to_apb` has one FSM and one spill-register pair (`Setup` / `Access` at
`:294-358`), so it retires exactly one AXI transaction at a time: the next
AW/W or AR is not accepted until `apb_req_ready` pops the current one. At most
one transaction is in flight across the bridge, so a single record plus a
claimed-by flag is exact. A queue would imply an ordering the fabric does not
have.

The same argument does **not** hold at the LSU tap: two core accesses could both
be in flight if the LSU ever stopped asserting `core_lsu_stall`. That case is
detected explicitly (`PATH-3013`) instead of being papered over by a queue that
would silently match the wrong pairs.

The bootloader is a second AXI master on a different xbar slave port, so it is
not ordered against the core. It claims the record itself when the core did not,
which keeps its APB[4] traffic accounted for instead of being read as a ghost
transfer.

### 7.3 The prediction is read off the RTL, not off what we would wish

`axi_lite_to_apb.sv:299` gates APB generation on

```systemverilog
apb_dec_valid && ((write && |strb) || !write)
```

so:

| Access | Decodes to a rule? | APB transfer? | Response |
|---|---|---|---|
| read | yes | yes | `OKAY`/`SLVERR` per `PSLVERR` |
| write, `WSTRB != 0` | yes | yes | `OKAY`/`SLVERR` per `PSLVERR` |
| write, `WSTRB == 0` | yes | **no** | `OKAY` (`:319`) |
| read | no | **no** | `DECERR` (`:322`) |
| write, `WSTRB == 0` | no | **no** | `OKAY` (`:319` — the ternary tests the strobes, not the decode) |

The last row is surprising enough to state plainly: a write with every strobe
clear to an unmapped address returns OKAY, not DECERR. The scoreboard predicts
that, because predicting anything else would make it fire on correct RTL, and a
checker that cries wolf on golden RTL is worse than no checker.

`PATH-3015` checks that the zero-strobe case stays a silent no-op; `PATH-3014`
checks that the unmapped hole still returns DECERR; `PATH-3003` checks that the
number of APB transfers matches the prediction in both directions.

### 7.4 Check list

| Check ID | Checks | `a`/`b`… meaning |
|---|---|---|
| `PATH-3001` | the core access reaches the fabric: AXI AW/AR address equals the LSU address | |
| `PATH-3002` | no AXI transaction without a core access | folded into 3001 |
| `PATH-3003` | exactly one APB transfer per AXI transaction, in both directions | expected vs actual |
| `PATH-3004` | the transfer lands on the slot the address map gives | |
| `PATH-3005` | `PADDR` equals the 4-byte-aligned AXI address | |
| `PATH-3006` | write data survives unchanged, LSU → AXI → APB | |
| `PATH-3007` | **byte strobes survive unchanged** | checked at the AXI hop (`LSU.be` vs `W.strb`) **and** the APB hop (`W.strb` vs `PSTRB`) |
| `PATH-3008` | AXI `RDATA` equals the APB `PRDATA` actually read | |
| `PATH-3009` | `PSLVERR` reaches the core as `RESP_SLVERR`, never swallowed into OKAY | |
| `PATH-3010` | read/write direction preserved | |
| `PATH-3011` | latency within the slot's own budget + fabric pipeline | |
| `PATH-3012` | timeout path behaves as specified (see §8.3) | |
| `PATH-3013` | one MMIO access outstanding at a time | |
| `PATH-3014` | an unmapped address returns `DECERR` | |
| `PATH-3015` | a write with all strobes clear is a no-op returning `OKAY` | |

`PATH-3004` deserves a note. In the self-proof bench both sides of the comparison
come from `step4_pkg`, so it cannot fail there; it is not a vacuous check in the
SoC, where the DUT side is the RTL's own `apb_addr_map` and the expected side is
this package's independent transcription of it. That is the whole point: it
catches the two drifting apart, which is exactly the GPIO 2 KB/4 KB discrepancy
in §11.1.

---

## 8. First-fatal failure reporter

### 8.1 What happens on a failure

1. The check fills a packed event and raises a flag. That is all an SVA action
   block does (§9.2).
2. A forwarder on the opposite clock edge posts it to the shared mailbox
   (`step4_hub.evt[]`).
3. `step4_reporter` drains the mailbox, applies the blame rule of §3.1, and on
   the first fatal sets `frozen`.
4. `frozen` makes every ring push a no-op, so the windows stop moving at the
   moment of the failure.
5. The one-page report is emitted immediately — to the console and to
   `step4_report.txt`.

### 8.2 The one page

```
================================================================================
  RISCFORGE SoC   STEP 4 CHECKERS   --  FIRST FATAL
================================================================================
  test            : <name>
  time / cycle    : <t> ps   /  <cycle>
  VERDICT         : *** BLAME = PATH  (check PATH-3007) ***
  blame check     : PATH-3007
  location        : core-MMIO-path/APB[3]/GPIO
  expected        : byte strobes survive the path unchanged: 1111
  actual          : byte strobes 1100, expected 1111 -- a byte lane was dropped
                    or duplicated
  findings        : 7 recorded, 5 downstream (suppressed), 1 reassignments
================================================================================
  LAYER STATUS
    PROTOCOL     BLAME   AXIL-1001
    PATH         FAIL    PATH-3007
    REGISTER     quiet   -
    FUNCTIONAL   quiet   -
    INTERRUPT    quiet   -
    CPU-STATE    quiet   -
    FIRMWARE     quiet   -
================================================================================
  LAST RETIRED INSTRUCTIONS  (32 of 32, oldest first)
    #28 0x000112a0  f8000213  addi    x4, x0, 520     ; mmio_write
    #29 0x000112a4  00b52023  sw      x4, 0(x5)
    ...
================================================================================
  FROZEN WINDOWS -- captured at the fatal cycle, not overwritten since
================================================================================
  CORE LSU  (hybrid_mem_interface mem_*)   (16 of 16 retained)
    #12  c1204  LSU  W  addr=0x40003040 wdata=0x0000ff00 strb=0100 slot=-  ok
  AXI4-LITE MASTER 2  (xbar slv[0])
    #12  c1207  AXI  W  addr=0x40003040 wdata=0x0000ff00 strb=0100 slot=-  ok
  APB BRIDGE  (axi_lite_to_apb)
    #12  c1210  APB  W  addr=0x40003040 wdata=0x0000ff00 strb=1100 slot=GPIO BAD
================================================================================
  COUNTERS  (vacuity evidence for the pass rule)
    lsu_reqs=...  axi_wrs=...  axi_rds=...  retired=...
    apb xfers [I2C T0 UART GPIO SPI T1] = ...
    apb_timeouts=...  RESP_SLVERR=...  RESP_DECERR=...
================================================================================
  NEXT: read the two lines above, in this order --
    1. disassemble the newest retired instruction and check access width,
       missing volatile, hidden reads and reordering
    2. compare the frozen AXI and APB windows row by row
    3. only then open waveforms
```

The three windows are side by side for the same transaction, which is the point:
row 12 differs only in `strb`, and that one column is the bug. Reading that takes
seconds instead of the twenty minutes it takes to find the same divergence by
eye in a waveform.

### 8.3 Disassembly

Two sources, in order of preference:

1. **The Step 1 PC map**, if `STEP4_PCMAP_FILE` names one — gives function name
   and source line.
2. **`step4_disasm.sv`**, a built-in RV32IM_Zicsr decoder: RV32I base, the M
   extension, CSR access, `ECALL`/`EBREAK`/`MRET`/`WFI`, and `FENCE`. Anything
   unrecognised renders as `.word 0x........` rather than being mis-decoded.

The built-in decoder exists because a hang is exactly the case where the PC map
has not helped yet — the fetch pipeline is full of words and nothing else is
running.

It has its own self-checking bench, `step4_disasm_tb` (31 cases, all passing),
and that bench exists because writing it found **five bugs that produced no
error anywhere**. A disassembler that prints plausible-looking wrong output is
worse than none, because the reader trusts it and then debugs the wrong
instruction:

| # | Bug | Symptom |
|---|---|---|
| 1 | sign extension took a **byte** width, so the 12-bit I/S/B immediates were never sign-extended | `addi x6, x0, -1` rendered as `4095` |
| 2 | the LOAD arm used `inst[31:25]` (the S-type field) instead of `inst[31:20]` | every load offset five too small |
| 3 | the B-type immediate put `inst[1]` in bit 0 | but B-type bit 0 is not encoded and is always zero, so every branch target one too high |
| 4 | the JAL sign-fill concatenation was one bit too wide | every JAL target shifted down by one |
| 5 | the shift/add decode compared the whole 7-bit `funct7` | `SRAI` decoded as `SRLI`, and on xsim the same expression crashed the kernel (§10.5) |

Fix 5 is worth stating as a rule: discriminate on `inst[30]` held in a plain
`logic`, not on a bit-select of a wider local. It is both clearer and portable.

### 8.4 The timeout sentinel

A read returning `32'hDEAD_BEEF` (`apb_timeout_psticky`, `riscforge_soc_subsystem.sv:1000`)
is a timeout, never peripheral data. `32'hDEAD_DEAD` is the AXI-side sentinel
(`:1318`). The register layer must never accept either as a register value; the
path layer flags the abort so the report says *timeout* rather than *data
mismatch*.

---

## 9. Fault-injection framework

### 9.1 The rule that makes injection work

**A path scoreboard compares two observation points. Corrupting both means it
sees a consistent world and reports nothing.**

Every injector therefore breaks exactly one hop and leaves the others intact. An
injector that spoils the whole chain proves only that the file compiles — which
is precisely the mistake the first version of this framework made, and why the
self-proof matrix was empty on the first run.

| Injector | Hop broken | Expected check |
|---|---|---|
| `FI_STROBE` | APB `PSTRB` only | `PATH-3007` |
| `FI_STROBE_AXI` | AXI `WSTRB` only | `PATH-3007` |
| `FI_WDATA` | APB `PWDATA` only | `PATH-3006` |
| `FI_AXI_WDATA` | AXI `W.data` only | `PATH-3006` |
| `FI_RDATA` | APB `PRDATA` only | `PATH-3008` |
| `FI_TIMEOUT` | APB `PRDATA` → the timeout sentinel | `PATH-3008` |
| `FI_PADDR` | APB `PADDR` only | `PATH-3005` |
| `FI_AXI_ADDR` | AXI AW/AR address only | `PATH-3001` |
| `FI_SLVERR` | APB `PSLVERR` only, response left as the bridge produced it | `PATH-3009` |
| `FI_RESP` | AXI response code only | `PATH-3014` when driven against the unmapped hole |
| `FI_WAIT` | APB `PREADY` | `APB-2004` |

The three the plan names explicitly:

- **strobe corruptor** — the guide's own example ("force one byte strobe").
  Implemented twice, once per hop, because the check has to catch a lane lost on
  either side of the bridge.
- **wait-state injector** — reports `PREADY` late. Must exceed
  `STEP4_STALL_BOUND` to trip `APB-2004`, and must stay below the slot's own
  `APB_TIMEOUT_CYCLES`, or the timeout monitor will convert it to SLVERR first
  and mask the protocol violation being observed.
- **parity / timeout trigger** — `FI_SLVERR` is the stand-in for a parity
  failure on an otherwise unprotected fabric; `FI_TIMEOUT` injects the sentinel.

### 9.2 Observation-side vs DUT-side

Injection is **observation-side** by default: the injector publishes a corrupted
view and the RTL is untouched. That proves the checker logic, which is what Step
4 owns, and it works on golden RTL with no RTL changes.

DUT-side injection (`force`/`release` on the real nets) is opt-in behind
`+define+STEP4_FORCE_FI`. It is the only way to prove the *timeout* path end to
end — a genuinely stuck `PREADY` has to make the design's own
`apb_timeout_monitor` fire. It is compiled out by default because a `force` that
is never released silently poisons everything downstream of it, and that risk
should be a deliberate choice.

---

## 10. Tool constraints found the hard way

These cost real time and will cost it again. All four are reproducible in
Vivado 2022.2 `xsim`; VCS and Xcelium are unaffected.

| # | Constraint | Workaround |
|---|---|---|
| 1 | **`xsim` codegens every function declared in an interface, called or not, and crashes (`EXCEPTION_ACCESS_VIOLATION`) on anything non-trivial** — array arguments, `string` outputs, `case` full of `$sformatf`. | Keep `step4_hub` function-free. All logic in `step4_reporter` (a module). |
| 2 | **A module cannot be used as a port type in `xsim`** — `"'m' is an unknown type"`, and with parameters `"unexpected parameter values in module port declaration"`. | Reporter handle is an interface; sizing comes from `step4_cfg.svh` macros, not parameters. |
| 3 | **`$past()` inside an SVA action block has no clocking event to infer from** and `xsim` refuses to elaborate it. | Explicit previous-cycle registers (`p_aw_addr`, `pp_paddr`, …). `$past` in *antecedents* is fine and is still used there. |
| 4 | **`axi_lite_to_apb` cannot be elaborated by `xsim`** — its APB ports are unpacked arrays of a parameter type (`:69-70`), and `xsim` rejects that port connection whatever the declaring scope. | The self-proof uses `step4_apb_bridge_model`, whose every decision is line-cited to the RTL it copies. The SoC regression binds the checkers to the **real** bridge under Xcelium/VCS. |

| 4 | **An undriven output floats X and poisons every checker downstream.** | The fault injector declared `o_penable` and never assigned it. Every APB check then saw X, no APB transfer was ever detected, and the scoreboard reported "0 findings" — indistinguishable from a pass until the vacuity counter was read. | Drive every output in the default branch, including the pass-throughs. |
| 5 | **xsim can mis-handle a bit-select of a function-local variable**, returning wrong bits and in one case killing the kernel outright. | Copy the bit into a plain `logic` at the top of the function and compare that. This is what fixed the `SRAI`/`SRLI` decode and the crash behind it. |

Also worth recording: an SVA action block may not call a function on an
interface carrying state (constraint 1's practical face), which is why action
blocks here only assign a packed record.

**A general lesson from items 1, 4 and 5.** Every one of these presented as
*silence*. None produced a warning; each produced plausible output that was
wrong. The defences are the three that exist in this package: the vacuity check
in the pass rule, the disassembler self-test, and the fault-injection matrix
whose entire purpose is to prove that a checker is not dead code.

---

## 11. Findings on the RTL

### 11.1 GPIO's APB window is 2 KB, not 4 KB

`riscforge_soc_subsystem.sv:688` maps APB[3] as `0x4000_3000 … 0x4000_3800`.
`rtl/ips/AGENTS.md` and `Sw/soc_spec.md` both say `0x4000_3000 – 0x4000_3FFF`.
The RTL is right — the register block decodes only 11 address bits, so a 4 KB
window would alias `0x4000_3800-0x4000_3FFF` onto real registers — and the
documentation is stale. `step4_pkg::SLOT_BASE/SLOT_END` follow the RTL;
`PATH-3004` will fail loudly if the two ever drift apart.

Consequence for firmware: accesses to `0x4000_3800…3FFF` return `DECERR`
(`PATH-3014`), not an aliased register.

### 11.2 A zero-strobe write to an unmapped address returns OKAY

`axi_lite_to_apb.sv:319` — the ternary tests `|strb`, not the decode, so a write
with all strobes clear short-circuits to `RESP_OKAY` whether or not the address
decoded. Harmless as specified, but it means "the write had no effect" and "the
address was garbage" are indistinguishable at the bus. Worth a comment in the
RTL at minimum.

### 11.3 A sub-word write to GPIO is answered with PSLVERR

`gpio_apb_wrap.sv` — `s_sub_word_wr` is `psel & penable & pwrite & ~(&pstrb)`,
and it answers `PSLVERR` without reaching the register block. So `strb != 4'hF` on
APB[3] is a guaranteed error, which is exactly what `REG-4001` will assert once
the register predictor lands. Until then the path layer correctly does *not*
judge it — it only checks that the SLVERR survives the mapping.

### 11.4 The timeout pulses are write-only

`apb_timeout_pulse[5:0]`, `axi_wr_timeout_pulse`, `axi_rd_timeout_pulse` are
declared, driven and never read (`riscforge_soc_subsystem.sv:549-551`, `:1326-1327`).
They exist as bind targets. `step4_bind.svh` uses them, which turns three dead
signals into live instrumentation for free.

---

## 12. Integration

### 12.1 In a SoC testbench

```systemverilog
riscforge_soc_subsystem u_dut ( .clk_i (clk), .rst_ni (hard_rst_ni), /* ... */ );
step4_hub               u_hub (.clk(clk), .rst_n(rst_n));
step4_reporter     u_step4_rep (.clk(clk), .rst_n(rst_n), .hub(u_hub));
step4_fault_inject u_step4_fi  ( /* ... */ );
`include "step4_bind.svh"
```

`u_dut` and `u_hub` are required names, or override `RF_DUT` / `RF_HUB`. A bind
statement's port connections resolve in the scope of the module containing the
bind, which is what lets `.hub(u_hub)` reach the interface while
`.apb_req[3].psel` reaches inside the SoC.

Add `step4_pkg.sv`, `step4_disasm.sv`, `step4_hub.sv`, `step4_reporter.sv`,
`step4_axi_sva.sv`, `step4_apb_sva.sv`, `step4_path_scoreboard.sv`,
`step4_fault_inject.sv` to the file list **in that order** — `xsim` does not make
packages visible across files.

### 12.2 Self-proof

```powershell
cd rtl\ips\Verification\step4_checkers
.\run_step4.ps1            # add -Coverage for a coverage report
```

### 12.3 Command-line options

| Plusarg / define | Effect |
|---|---|
| `+step4_halt=1` | stop at the first fatal instead of running on |
| `+define+STEP4_STALL_BOUND=<n>` | AXI/APB stall bound, default 64 |
| `+define+STEP4_RING_DEPTH=<n>` | transactions per window, default 16 |
| `+define+STEP4_RETIRE_DEPTH=<n>` | retired instructions kept, default 32 |
| `+define+STEP4_REPORT_FILE="<path>"` | report path |
| `+define+STEP4_PCMAP_FILE="<path>"` | Step 1 PC map |
| `+define+STEP4_FORCE_FI` | enable DUT-side `force`/`release` injection |

---

## 13. Exit criteria for Step 4

| # | Criterion | Status |
|---|---|---|
| 1 | Protocol assertions bound on every fabric interface | **done** — 3 AXI-Lite ports, 6 APB slots |
| 2 | Every assertion has a cover | **done** |
| 3 | Path scoreboard maps LSU → AXI M2 → APB slot 0–5 on address, data, byte enables, direction, response, latency | **done** |
| 4 | First-fatal reporter with hierarchical blame, ring freeze, one-page summary, disassembled retire window | **done**, and the report is produced and inspected |
| 5 | Reporter emits a VACUOUS PASS warning when no traffic was seen | **done** — and it has already caught one real bug |
| 6 | Failure-report disassembler is self-checking and correct | **done** — `step4_disasm_tb`, 31/31 |
| 7 | Path scoreboard proven against clean traffic with **zero** findings, non-vacuously | **done** — `lsu=17 axi_wr=16 axi_rd=9 apb=1` |
| 8 | Every injected fault is named by the correct check ID | **OPEN** — §14.1 |
| 9 | Path scoreboard proven against the real `axi_lite_to_apb` | **OPEN** — §14.1 |

## 14. Open items

### 14.1 The fault-injection matrix is not yet green, and the reason is the bench, not the checkers

`step4_smoke_tb` stands in for the real bridge because of §10 constraint 4, and
that stand-in model still deadlocks on some accesses: an AXI channel stays
stalled long enough to trip `AXIL-1010`, the run loses the transaction, and the
subsequent injections never reach a live transfer.

What is established:

- the checkers, reporter and scoreboard all compile and elaborate clean;
- the scoreboard agrees with the bridge model on clean traffic — **zero**
  findings, and non-vacuously, which is the part that matters;
- the disassembler is correct and self-checking;
- the reporter produces a correct one-page report with blame, layer status,
  disassembly and frozen windows;
- the fault-injection framework is implemented with hop-specific injectors and
  the expected check ID recorded for each case.

The right resolution is **not** to keep patching the model. Delete
`step4_apb_bridge_model` and run the matrix against the real `axi_lite_to_apb`
under Xcelium or VCS, which is where the SoC regression runs anyway and where
the array ports elaborate. Do not close criterion 8 on the model's word.

### 14.2 The timeout-ordering invariant is not yet asserted

`PATH-3012` is wired to `apb_tmo_pulse` and `axi_tmo_pulse` in the bind, but no
check yet asserts the ordering invariant from §2.2 — that the APB monitor must
always answer before the AXI monitor, or the APB error is swallowed upstream.
That belongs in the SoC regression as a directed test.

### 14.3 L3 register layer

`REG-4001` (sub-word write to GPIO must be answered with PSLVERR) is defined in
the check-ID table with no implementation. It belongs to Step 6, with the
register predictor.

### 14.4 Unbound fabric interfaces

`xbar_mst_req/resp[0..1]` (ISRAM, DSRAM) are not bound. Same protocol, different
map, and the core never uses them for MMIO — but they should be bound if the
SRAM agents ever go multi-transaction.

### 14.5 A real bound, not a proof

The `ev_q` queues in the checkers are 4–8 deep with free-running pointers. An
observer that fires more checks in one cycle than the forwarder drains loses the
oldest. `evt_overflow` counts it and it appears in the report counters, but it
has never been non-zero, and that is evidence rather than a guarantee.