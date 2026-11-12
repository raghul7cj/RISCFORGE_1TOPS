# RISCFORGE RV32 Core - CSR and Trap Model (as implemented)

Sign-off items: 1.3 (privilege), 1.4 (CSR table), 1.5 (trap/interrupt model), 2.9 (nesting policy).
Scope: the active core in `ips/riscv_core/rtl/` (legacy `rv32im_zicsr_5stage_exc_nointr_old` NOT used).
Method: static reading of RTL only. No simulation was run for this document. Statements are
"as coded"; anything not directly confirmed in source is marked **UNVERIFIED**.
Paths below are relative to `ips/riscv_core/rtl/` unless noted. `top.v` signal `rst` is **active-low, asynchronous** (`csr_regfile.v:138`, `top.v:555`).

Abbreviations: `csr`=`csr_regfile.v`, `wb`=`wb_trap_mret_commit_controller.v`, `arb`=`irq_arbiter.v`, `gw`=`irq_gateway.v`, `exe`=`execute_cycle.v`, `dec`=`decode_cycle.v`, `mem`=`memory_cycle.v`, `fch`=`fetch_cycle.v`, `hz`=`hazard_unit.v`.

---

## 1. Implemented CSR table (item 1.4)

Access types: **RW** = all 32 bits read/write; **WARL(mask)** = only masked bits writable, other bits keep their old value (read-as-reset-value 0 in practice); **RO** = no software write path.
Software write path (all CSR instructions) = Port B, `csr:184-200`; writes are applied at WB (commit), not at EX. Read is combinational at EX (`csr:116-133`).
All reset values are 0 (async reset block `csr:138-150`).

| Addr | Name | Reset | Access | Writable-bit mask (as coded) | Side effects / notes | RTL ref |
|---|---|---|---|---|---|---|
| 0x300 | mstatus | 0x0000_0000 | WARL | `0x0000_188A` = bits 12,11,7,3,1 (MPP[1], MPP[0], MPIE, MIE, bit1). Other bits read 0 | Hardware-modified by trap entry (MIE<-0, MPIE<-old MIE, MPP<-11) and MRET (MIE<-MPIE, MPIE<-1, MPP<-11). Bits 12:11 are independently software-writable (MPP not hard-wired). Bit 1 is writable (see Obs. O1) | write `csr:186`; trap `csr:164-166`; mret `csr:173-178`; read `csr:118`; reset `csr:140` |
| 0x304 | mie | 0x0000_0000 | WARL | `0xFFFF_0888` = bits 31:16, 11 (MEIE), 7 (MTIE), 3 (MSIE) | Only bits 27:16 and bit 7 are consumed by the arbiter (`arb:20-21`); bits 31:28, 11, 3 are storage only (O2) | `csr:187`; read `csr:119`; use `arb:20` |
| 0x305 | mtvec | 0x0000_0000 | WARL | `0xFFFF_FFFC` (bits 31:2). MODE bits [1:0] always read 0 | Direct mode only reachable (see 3.1). Reset value 0 => trap goes to address 0 until software writes it | `csr:188`; read `csr:120`; use `wb:98-103` |
| 0x340 | mscratch | 0x0000_0000 | RW | none (32 bits) | none | `csr:189`; `csr:121` |
| 0x341 | mepc | 0x0000_0000 | RW | none (all 32 bits incl. [1:0]) | Written by trap entry with faulting/interrupted PC. MRET target masks [1:0] to 0 (`wb:103`) | `csr:190`; trap `csr:160`; `csr:122` |
| 0x342 | mcause | 0x0000_0000 | RW | none (all 32 bits; not WLRL-restricted) | Written by trap entry as `{is_interrupt, cause[30:0]}` | `csr:191`; trap `csr:161`; `csr:123` |
| 0x343 | mtval | 0x0000_0000 | RW | none | Written by trap entry: faulting value for exceptions, 0 for interrupts (3.3) | `csr:192`; trap `csr:162`; `csr:124` |
| 0x344 | mip | n/a (combinational; msip_r resets 0) | Mixed: bits [31:16],[11],[7] RO (live source/gateway state); bit 3 (MSIP) RW; all other bits RO 0 | Only bit 3 writable: `msip_r <= wdata[3]` | bit3 reads `msip_r \|\| msft_intr_i`; bit7 = `pend_gateway[0]` (gateway output); bit11 = `ext_irq_i` raw; bits [27:16] = `pend_gateway[12:1]`; bits [31:28] = 0 (`fast_intr_core[15:12]` tied 0). No clear-by-write for any pending bit | map `csr:217`; msip `csr:207-215`; read `csr:125`; top feed `top.v:550-551,574-577` |
| 0x7C0 | mintprio | 0x0 | RW (2 bits) / WARL | bits [1:0] only; [31:2] ignored on write, read 0 | Class threshold to arbiter. Not touched by trap entry or MRET (software-managed) | storage `csr:90`; write `csr:193`; read `csr:126`; reset `csr:149`; use `arb:99-100` |
| 0xB00 | mcycle | 0 | RW | none | Increments every clock; a CSR write at the same edge wins over the increment (later non-blocking assignment, `csr:153` vs `csr:194`) | `csr:153,194` |
| 0xB80 | mcycleh | 0 | RW | none | upper half of 64-bit counter | `csr:195`; `csr:128` |
| 0xB02 | minstret | 0 | RW | none | Increments when `instr_retired_i = valid_W & ~exc_valid_W` (`top.v:572`): MRET counts as retired; trapping instructions and interrupted instructions do not. CSR write wins over increment (`csr:154` vs `csr:196`) | `csr:154,196` |
| 0xB82 | minstreth | 0 | RW | none | upper half | `csr:197`; `csr:130` |

Notes on the table:
- Read-modify-write ordering for CSRRS/CSRRC: old value read at EX, new value computed at EX (`exe:333-337`), written at WB. Back-to-back CSR hazards stall decode (`hz:155-158`).
- CSRRS/CSRRC/CSRRSI/CSRRCI with rs1/uimm == 0 do not write (`exe:338-341`). CSRRW/CSRRWI always write.
- `mcause_out_o` is left unconnected in `top.v:583` (value is software-visible only through CSR read).

### 1.1 CSRs a reader might expect but that are NOT implemented

Not present in `csr:98-111` (address constants) or the read mux `csr:116-133`:

`misa` (0x301), `mhartid` (0xF14), `mvendorid` (0xF11), `marchid` (0xF12), `mimpid` (0xF13), `mconfigptr` (0xF15), `mcountinhibit` (0x320), `mcounteren` (0x306), `mstatush` (0x310), `medeleg`/`mideleg`, `mtinst`/`mtval2`, `mhpmcounter*`/`mhpmevent*`, user aliases `cycle`/`time`/`instret` (0xC00/0xC01/0xC02) and `cycleh`/`timeh`/`instreth` (0xC80/0xC81/0xC82), `mseccfg`, PMP CSRs, S-mode/U-mode CSRs, `fcsr`. Also the CSRs `mintlvl` (0x7C1) and `mintctl` (0x7C2) that appear in `documentation/RISCFORGE IRQ Architecture.html` (grep hit "mintlvl/mintctl" near the "Figure 4" text) are not in the RTL.
`mtvec` vectored mode (MODE=01) cannot be selected by software (mask excludes bits [1:0]) although the commit controller contains vectoring logic (3.1).

### 1.2 Behaviour on access to an unimplemented CSR address

Traced path:
1. `csr_valid_o` is defined at `csr:231-243` but **no consumer exists**: the instantiation at `top.v:553-586` does not connect `.csr_valid_o`, and a repo-wide grep of `riscv_core/rtl` for `csr_valid_o` finds only the declaration/assign in `csr_regfile.v`.
2. The `csr_valid` signals used by the pipeline (`Main_Decoder.v:239`, `top.v:276`) are simply `opcode == SYSTEM (7'b1110011)`; they do not test the CSR address.
3. `illegal_instr` is an opcode-only check (`opcode_check.v:30-43`).
4. Therefore: **read of an unimplemented CSR returns 0** (`csr:131`), **write is silently dropped** (`csr:198` `default: ;`), and **no illegal-instruction trap** is raised. rd (if not x0) is written with 0. Confirmed by static trace; the same conclusion is stated in `documentation/ARCHITECTURE_SUMMARY.md:278-281`.
5. Same behaviour for writes to architecturally read-only addresses (e.g. 0xC00, 0xF14): no trap, no effect.
6. Other SYSTEM-opcode encodings are also not trapped: only ECALL (`dec:151`), EBREAK (`dec:152`) and MRET (`Control_Unit_Top.v:165-166`) are specially decoded; WFI, SRET, SFENCE.VMA and reserved funct3 (000 with other immediates, 100) pass as `csr_op=00` (read only, no write) with RegWrite=1 (`Main_Decoder.v:105`). UNVERIFIED by simulation; derived from the decode logic.

---

## 2. Privilege modes (item 1.3)

- **Machine mode only.** No privilege-level state register exists in `csr_regfile.v`; there are no S/U CSRs, no delegation, no PMP. Consistent with `ARCHITECTURE_SUMMARY.md:16,43,158`.
- **mstatus.MPP** is a plain 2-bit storage field (`csr:67` comment; storage in `mstatus_r[12:11]`). Hardware sets it to `2'b11` on trap entry (`csr:166`) and on MRET (`csr:175`). It is **not hard-wired**: software can write any value to bits 12:11 via mask `0x188A` (`csr:186`), and the reset value is `2'b00`, not `2'b11` (`csr:140`). MRET does not read MPP and never changes privilege; it always returns to M-mode behaviour.
- No instruction other than MRET exists to change privilege; SRET/URET are not decoded (1.2 item 6).
- Result: every instruction executes with full machine privilege; CSR access is never privilege-checked.

---

## 3. Trap and interrupt model (item 1.5, 2.9)

### 3.1 mtvec behaviour

- Writable base: bits [31:2]; bits [1:0] always 0 (`csr:188`). Trap target = `{mtvec[31:2], 2'b00}` (`wb:99`).
- Direct mode is the only mode software can reach. The commit controller also implements vectored interrupts when `mtvec[1:0]==2'b01`: target = base + 4*cause[4:0], interrupts only; exceptions always go to base (`wb:98-101`). Because the MODE bits cannot be written, this branch is **unreachable from software** (O3).
- Reset value 0 (`csr:142`): a trap before mtvec is programmed redirects to address 0. In the SoC, address 0 is the BootROM base (`RTL_SOC/riscforge_soc_subsystem.sv:1245`, RESET_PC = 0x0000_0000; the core's own default `RESET_PC` is 0x8000_0000, `top.v:25`).

### 3.2 Trap boundary and redirect

- **Where a trap commits: the WB stage.** `trap_commit = valid_W & exc_valid_W` (`wb:64`). Exceptions/interrupts are tagged onto the instruction packet at IF/ID/EX/MEM and travel to WB (`fch:183-186`, `dec:415-426`, `exe:466-483`, `mem:132-147`); the first tag wins and is propagated (`dec:423-426`, `mem:144-147`).
- **Precision.** Older instructions (already in M/W) retire normally before the trap packet reaches WB. At commit: GPR write (`top.v:285`), CSR write (`top.v:286`) and counters (`top.v:572`) are suppressed for the trapping instruction; the E-to-M register also zeroes RegWrite/MemWrite/csr-write for a tagged instruction (`exe:411,412,420`) and `lsu_mem_req/we` are gated by `~exc_valid_M` (`mem:179-180`). On commit, `flush_pipeline_onehot = 4'b1111` (`wb:106`) and `wb_trap_redirect` flush FlushD/E/M/W (`hz:192,196,199,202`), killing all younger instructions in IF/ID/EX/MEM-WB registers. Younger instructions' CSR and GPR writes happen only at WB so are not committed. **Caveat on younger memory operations: see O8 (UNVERIFIED).**
- **Redirect priority** (`fch:119-121`): `wb_trap_redirect` (trap or MRET) > `PCSrcE` (branch/jump from EX) > `PC+4`. Stalls are overridden on redirect (`hz:170-175`, `fch:135`).
- **Trap target** (`wb:103`): trap -> `trap_target_addr` (3.1); MRET -> `{mepc[31:2], 2'b00}`.

### 3.3 Supported exceptions and mepc / mtval per cause

mepc rule: `mepc <= trap_pc_i = exc_pc_W` at trap entry (`csr:160`). mtval rule: `mtval <= exc_tval_W` if `trap_addr_valid_i`, else 0 (`csr:162`); `trap_addr_valid = trap_commit & ~exc_cause_W[5]` (`wb:76`), i.e. exceptions carry tval, **interrupts write mtval = 0**. mcause = `{trap_is_interrupt, 26'b0, cause[4:0]}` (`wb:71-72`, `csr:161`): bit 31 = interrupt flag (from `exc_cause_W[5]`), upper cause bits are 0, cause field is 5 bits.

| Code | Name | Raised by (RTL source) | mepc | mtval | Notes |
|---|---|---|---|---|---|
| 0 | Instruction address misaligned (taken branch/jump target) | `exe:480-483` (`branch_taken_raw & target[1:0]!=0`); PCSrcE suppressed `exe:290` | PC of the branch/jump (`PCE`, `exe:483`) | misaligned target (`PCTargetE`, `exe:482`) | Applies to JAL/JALR/Bxx taken. JALR target is `alu_r` with no bit-0 clearing (`exe:284`) so any nonzero [1:0] traps (O6) |
| 0 | Instruction address misaligned (fetch) | `fch:183-186` (`PC_next[1:0]!=0`) | `PC_next` (`fch:185`) | `PC_next` (`fch:186`) | Practically unreachable: trap/mepc targets are masked (`wb:99,103`) and misaligned branch targets are suppressed (`exe:290`). UNVERIFIED by simulation (O7) |
| 1 | Instruction access fault | NOT raised | - | - | No fault input in `fch`/`imem_controller`/`PC` (grep for fault/err found nothing); UNVERIFIED at SoC level |
| 2 | Illegal instruction | `dec:416` using `illegal_instr` from `opcode_check.v:30-43` | PC of instruction (`PCD`, `dec:421`) | the 32-bit instruction (`InstrD`, `dec:419`) | Opcode-only check (7 bits); funct3/funct7/CSR-address are not checked (O5) |
| 3 | Breakpoint (EBREAK) | `dec:152,418` (exact encoding 0x00100073) | PC of EBREAK | PC of EBREAK (`PCD`, `dec:420`) | |
| 4 | Load address misaligned | `mem:121-125,135` (LW needs [1:0]=0; LH/LHU need [0]=0) | PC_M (`mem:147`) | `ALU_ResultM` (`mem:141`) | misaligned beats access-fault; no request issued (`mem:179`) |
| 5 | Load access fault | `mem:132,137` from `lsu_core_err` = `hybrid_mem_interface.mem_err` (`ls_unit.v:51`) | PC_M | `ALU_ResultM` | Source (`hybrid_mem_interface.sv:72,387-389`): address outside SRAM and MMIO windows, or AXI resp != OKAY on completing cycle |
| 6 | Store/AMO address misaligned | `mem:127-130,136` (SW [1:0]; SH [0]) | PC_M | `ALU_ResultM` | |
| 7 | Store access fault | `mem:132,138` | PC_M | `ALU_ResultM` | same source as cause 5 |
| 11 | Environment call from M-mode | `dec:151,417` (exact encoding 0x00000073) | PC of ECALL itself (not +4) | 0 (`dec:419-420` default) | |
| others (8, 9, 10, 12-15 and >=16 for exceptions) | not raised | - | - | - | |

SoC address windows used by `hybrid_mem_interface` (instantiated at `RTL_SOC/riscforge_soc_subsystem.sv:1301-1305`): DMEM base 0x0002_0000 (size from `DSRAM_NUM_WORDS`), MMIO 0x4000_0000-0x4FFF_FFFF. The core-local default parameters in the .sv file are different (0x8000_1000 / 0x4000_FFFF), so access-fault boundaries depend on the instantiating SoC. Anything outside those windows (including the BootROM/IMEM region as a data target) gives a load/store access fault: **UNVERIFIED** against the full address map.

Exception priority within one instruction: fetch-tagged > decode-new (illegal vs ECALL vs EBREAK are mutually exclusive by encoding) (`dec:423-426`); EX misaligned-target only if no propagated exception (`exe:283`); MEM propagated exception first, then misaligned load, misaligned store, access fault (`mem:134-146`). An instruction carrying a synchronous exception is never also accepted as an interrupt (`exe:459`).

### 3.4 Interrupts: cause numbering, mip/mie map

Core inputs (`top.v:58-61`, SoC wiring `RTL_SOC/riscforge_soc_subsystem.sv:1275-1290`): `fast_irq_i[15:0]` (only [11:0] used), `timer_irq_i`, `ext_irq_i`, `sw_irq_i`. In the SoC `ext_irq_i` and `sw_irq_i` are tied 0.

| mip / mie bit | Source | Interrupt cause taken (mcause low bits) | In arbiter? | Gateway bit / mode (`top.v:207-209`) |
|---|---|---|---|---|
| 3 (MSIP / MSIE) | `msip_r \|\| sw_irq_i` | none (cause 3 is never generated) | **No** | not in gateway |
| 7 (MTIP / MTIE) | `timer_irq_i` via gateway bit 0 | 7 | Yes (class 2, highest) | bit 0, event mode |
| 11 (MEIP / MEIE) | `ext_irq_i` raw | none (cause 11 interrupt is never generated) | **No** | not in gateway |
| 16 | `fast_irq_i[0]` | 16 | class 0 (RR with 17) | bit 1, **edge** (rising) |
| 17 | `fast_irq_i[1]` | 17 | class 0 | bit 2, **level** |
| 18 | `fast_irq_i[2]` | 18 | class 1 (RR 19,18,27) | bit 3, event |
| 19 | `fast_irq_i[3]` | 19 | class 1 | bit 4, **level** |
| 20 | `fast_irq_i[4]` | 20 | class 2 fixed | bit 5, event |
| 21 | `fast_irq_i[5]` | 21 | class 2 fixed | bit 6, event |
| 22 | `fast_irq_i[6]` | 22 | class 2 fixed | bit 7, event |
| 23 | `fast_irq_i[7]` | 23 | class 2 fixed | bit 8, event |
| 24 | `fast_irq_i[8]` | 24 | class 2 fixed | bit 9, event |
| 25 | `fast_irq_i[9]` | 25 | class 2 fixed | bit 10, event |
| 26 | `fast_irq_i[10]` | 26 | class 2 fixed | bit 11, event |
| 27 | `fast_irq_i[11]` | 27 | class 1 (RR) | bit 12, event |
| 28-31 | `fast_irq_i[15:12]` | none | No (mie[31:28] storage only; mip[31:28] hard 0 because `fast_intr_core = {4'b0, pend_gateway[12:1]}`, `top.v:550`) | - |

Gateway mapping is `irq_raw = {fast_irq_i[11:0], timer_irq_i}` (`top.v:207`); gateway bit 0 = cause 7, bit k (1..12) = cause 15+k. Mode masks: `edge_mode = 13'h0002`, `event_mode = 13'h1fe9` (`top.v:208-209`); bits not in either mask pass through as level (`gw:29-30`). Event mode captures every asserted cycle, edge captures rising edge; capture wins over clear in the same cycle (`gw:16-26`). Gateway pending bits are cleared only on trap commit of that cause (`wb:80-92`: cause 7 -> bit 0; causes 16..27 -> bit cause-15). Level sources have no latch: they stay pending until the source deasserts.

Source names per SoC wiring comments (`riscforge_soc_subsystem.sv:1271-1287`): 7 = Timer0 compare; 16 = GPIO; 17 = I2C; 18 = SPI threshold; 19 = UART; 20-26 = timer overflow/compare events; 27 = SPI end of transfer. Class labels there are "Class 2 fixed / Class 1 RR / Class 0 RR". Whether the comment "SPI threshold" vs "SPI events[0]" is accurate for the peripheral is UNVERIFIED (outside the core).

**Arbiter** (`arb:20-100`):
- `active = pend & {mie[27:16], mie[7]} & {13{mstatus.MIE}}` (`arb:20-21`). mstatus.MIE therefore gates *all* interrupts; mie[3], mie[11], mie[31:28] are ignored.
- Class 2 (highest): fixed order 7, 22, 24, 26, 20, 21, 23, 25 (`arb:75-82`).
- Class 1: cyclic round-robin 19, 18, 27 (`arb:44-67`), pointer `rr_ptr_c1` reset 0 (first = 19); after a commit of cause 19 -> start at 18; 18 -> 27; 27 -> 19 (`arb:31-34`).
- Class 0: round-robin 17, 16 (`arb:86-91`); pointer `rr_ptr_c0` reset 0 (first = 17); after 17 -> start 16; after 16 -> start 17 (`arb:35-36`).
- RR pointers advance only when the selected interrupt *commits* at WB (`wb_commit_irq`, `top.v:238-239`; `wb:78`), not on selection.
- Class ordering: Class 2 > Class 1 > Class 0 (`arb:75-91`).
- `irq_pending_o = winner_valid && (class + 1) > mintprio` (`arb:99-100`): mintprio=0 -> all classes; 1 -> classes 1 and 2; 2 -> class 2 only; 3 -> none. Matches comment `csr:79-80`.
- A pending-but-masked or threshold-blocked interrupt is not lost: gateway pending state persists (event/edge) or the level source persists.

**Acceptance point.** The interrupt is accepted in EX: `irq_accept_E = valid_E & irq_pending & ~new_exc_valid_E & ~exc_valid_E` (`exe:459`). The instruction currently in EX is *converted* to an interrupt packet (cause `{1'b1, irq_id}`, tval 0, **mepc = PCE** of that instruction, `exe:466-478`), its RegWrite/MemWrite/CSR-write are cancelled (`exe:411-412,420`), and younger instructions are flushed by `irq_flush_frontend` (`top.v:309,327`). The interrupted instruction therefore re-executes after MRET (mepc points at it, not past it). The interrupt is architecturally taken when that packet commits at WB (`wb:64`).

### 3.5 Nested-interrupt policy (item 2.9)

- **Hardware auto-nesting/preemption is not implemented.** Trap entry clears `mstatus.MIE` (`csr:164`) and saves old MIE in MPIE (`csr:165`). Since `mstatus.MIE` gates the whole arbiter (`arb:20-21`), no interrupt is accepted inside a handler unless software sets MIE again.
- **mintprio** (0x7C0) is only an eligibility *class threshold* (3.4). Trap entry and MRET do **not** modify it (`csr:79-80,157,171`). There is no hardware stack/shadow of mepc, mcause, mstatus or mintprio in `csr_regfile.v` (only single `mepc_r`, `mcause_r`, `mtval_r`, single MPIE/MPP).
- **Software-managed nesting is possible**: a handler may save mepc/mcause/mstatus, raise mintprio to the desired threshold, and set MIE (CSRRS mstatus, bit 3). A later higher-class interrupt can then preempt. The ordering corner described in `csr:81-89` (an interrupt accepted in EX with the old mintprio while an older mintprio write is still in flight to WB) is documented as an unresolved *design option*, not implemented.
- Synchronous exceptions inside a handler are always taken (not gated by MIE, `wb:64`) and overwrite mepc/mcause/mtval (no stacking).
- Documentation inconsistency: `ARCHITECTURE_SUMMARY.md:294-305` and the `RISCFORGE IRQ Architecture.html` describe a hardware shadow-stack / nest_depth / NEST_EN / CUR_LVL-PREV_LVL scheme and a different mintprio layout (mask 0x0707); none of this exists in the current `csr_regfile.v` or `irq_arbiter.v` (O9).

### 3.6 In-flight multi-cycle operations at a trap

- **Load/store.** A faulting/misaligned load or store is detected in MEM and committed at WB; no bus request is issued for it (`mem:179-180`). A load/store in EX that is converted to an interrupt packet is cancelled (MemWrite zeroed, `exe:412`; request gated `mem:179`). A younger memory op in MEM at the instant an older instruction traps at WB: see O8.
- **MUL/DIV in EX when an interrupt is accepted.** `div_abort = irq_accept_E & stallMUL` (`exe:297`) resets the divider state machine (`rv32m_div.v:106-109`), clears the multiplier stall counter (`rv32m_unit.v:73-75`) and `m_started` (`exe:304`). The M instruction is the one replaced by the trap and is re-executed after MRET (mepc = its PC). Whether an in-flight multiplier result (3-cycle pipeline in `rv32m_mul.v`, no abort port; `rv32m_unit.v:36-47`) can complete after the abort and be written is **UNVERIFIED** (O10).
- **Trap while M-unit busy for an older exception:** M instruction stalls hold F/D (`hz:170-171`); bubbles are inserted into E/M while `stallMUL` (`hz:192,199`). Interaction with a synchronous exception tagged on an *older* instruction is UNVERIFIED.
- **Branch redirect vs trap in the same cycle:** trap (WB) wins (`fch:119-121`). A taken branch/jump in EX that is simultaneously converted to an interrupt packet still asserts `PCSrcE` (`exe:283,290` do not include `irq_accept_E`), so IF is redirected to the branch target for one cycle, then the packet commits at WB and the trap redirect plus flush override it; mepc holds the branch PC. Net architectural effect: none. Stated as observed structure; not simulated.

### 3.7 MRET

- Recognised by exact encoding `0x30200073` (`Control_Unit_Top.v:165-166`), carried as `is_mret` to WB. `mret_commit = valid_W & is_mret_W & ~exc_valid_W` (`wb:65`).
- Effects (same edge): PC <- `{mepc[31:2], 2'b00}` (`wb:103`), pipeline flush (`wb:106`), `mstatus.MIE <- MPIE`, `MPIE <- 1`, `MPP <- 2'b11` (`csr:172-175`; also `wb:116-126`). mstatus bit 1 is rewritten from the MRET port with its own previous value (`csr:176-178`, net no change). mintprio untouched (`csr:171`).
- MRET also increments minstret (`top.v:572`).

### 3.8 Collision of trap and CSR write in the same cycle

- Only one instruction is in WB per cycle; a trapping instruction has its CSR write cancelled twice: at E-to-M (`exe:420`) and at the register-file port gate (`top.v:286`, `~exc_valid_W & ~mret_commit`).
- Inside `csr_regfile` the single `always` block gives explicit priority **trap entry (`csr:159`) > MRET (`csr:172`) > Port B CSR write (`csr:184`)** via if/else-if. Trap entry also cannot coincide with MRET (`wb:65` includes `~exc_valid_W`).
- Exceptions to the else-if chain: `mcycle_r`/`minstret_r` increment (`csr:153-154`) is unconditional and is overridden only by a Port B counter write; `msip_r` is in a separate always block (`csr:208-215`) but is fed from the already-gated Port B write, so a trapping instruction cannot write MSIP.
- An older CSR write in M/W combined with an interrupt accepted in EX: the ordering corner in `csr:81-89` (UNVERIFIED, noted by the RTL author as not yet verified).

---

## 4. Observations (facts only; no diagnosis, no fix proposed)

| # | Observation | Ref |
|---|---|---|
| O1 | `mstatus` write mask `0x188A` includes bit 1 (SIE position) although the core is M-only; header comment lists only MIE/MPIE/MPP and says "rest read-as-zero". Bit 1 is a real storage bit settable by software and re-written from the MRET port. `ARCHITECTURE_SUMMARY.md:272-274` records this too. | `csr:67,186,176-178` |
| O2 | `mie` bits 3 (MSIE), 11 (MEIE), 31:28 are writable and read back, but the arbiter only uses `mie[27:16]` and `mie[7]`; no software (cause 3) or external (cause 11) interrupt can be taken even if pending. `mip[3]`/`mip[11]` are readable only. | `csr:187`, `arb:20` |
| O3 | `mtvec[1:0]` cannot be written, yet `wb_trap_mret_commit_controller` contains vectored-interrupt target logic keyed on `mtvec[1:0]==01`. That branch is dead unless the mask changes. | `csr:188`, `wb:98-101` |
| O4 | `csr_valid_o` is generated but unconnected; unimplemented CSR accesses neither trap nor are flagged (read 0, write dropped). Also `mstatus.MPP` resets to `00` and is software-writable although only `11` is meaningful for an M-only core. | `csr:231-243`, `top.v:553-586`, `csr:140,186` |
| O5 | `illegal_instr` is opcode-only; unsupported funct3/funct7 combinations, reserved SYSTEM encodings (WFI, SRET, SFENCE.VMA, funct3=100) and FENCE/FENCE.I are treated as valid opcodes. Not trapping. | `opcode_check.v:30-43`, `Main_Decoder.v:105` |
| O6 | JALR target is `alu_r` (rs1+imm) without clearing bit 0; any target with [1:0] != 0 raises cause 0 at the JALR's PC. | `exe:284-285,480-483` |
| O7 | Fetch-stage misalignment check on `PC_next` appears to be unreachable (trap/MRET targets are masked to 4-byte alignment; misaligned branch targets are suppressed before reaching `PC_next`). Not simulated. | `fch:119-121,183-186`, `wb:99,103`, `exe:290` |
| O8 | **UNVERIFIED (static reading).** Memory request gating in MEM uses only `valid_M` and the instruction's *own* exception/misalignment (`mem:179-180`). No term uses `wb_trap_redirect`/`FlushW`. Per the timing in `hz:192-202`, a younger instruction can be in MEM in the same cycle an older trapping instruction is in WB (younger flush applies at the end of that cycle). `hybrid_mem_interface` drives `sram_en/sram_we` combinationally from `mem_req` (`hybrid_mem_interface.sv:98-99`). So a younger store (or MMIO load) may issue a bus transaction in the trap-commit cycle. Not verified by simulation and not confirmed against the SoC fabric. | `mem:179-180`, `hz:192-202`, `hybrid_mem_interface.sv:74-75,98-99` |
| O9 | Documentation mismatches: `ARCHITECTURE_SUMMARY.md` (sections 3.5/3.6 around lines 294-305, plus csr line numbers such as `csr:183,207,218-227`) describe a nested-interrupt shadow stack (`mepc_stack`, `nest_depth`, `cur_class`) and `irq_arbiter.v:150` preemption gate that are absent in the current RTL. `RISCFORGE IRQ Architecture.html` describes mintprio PREV/CUR fields (mask 0x0707), `mintlvl` (0x7C1), `mintctl` (0x7C2), none implemented. `csr_regfile.v:38-40` port comments ("0-11 for exc", "Port C: exception controller") do not match actual use (Port C is the MRET write interface). | docs vs `csr:90,98-111`, `arb:1-103` |
| O10 | `rv32m_unit` passes `abort_i` to the divider and the multiplier stall counter, but `rv32m_mul` has no abort input and its `valid_out` is registered 3 cycles after `valid_in`. Whether a multiplier result can still emerge after an interrupt-abort is not established here. | `rv32m_unit.v:36-47,73-75`, `rv32m_mul.v:34,251-255`, `exe:297,304,329-331` |
| O11 | `mcause`, `mepc`, `mtval`, `mscratch` writes have no masking; `mepc[1:0]` are storable but ignored at MRET. `mcause` accepts arbitrary values. | `csr:189-192`, `wb:103` |
| O12 | `trap_class_o` / `exc_class` are carried through the pipeline but have no consumer in `csr_regfile` (no input port for it). `mcause_out_o` is unconnected at top. | `wb:73`, `top.v:583` |
| O13 | `top.v` comment near `edge_mode/event_mode` says "timers and both SPI events" are event mode; the event mask `0x1fe9` sets gateway bits 0,3,5-12 (causes 7,18,20-27). Cause 17 (I2C) and 19 (UART) are level, cause 16 (GPIO) edge. | `top.v:208-210` |
| O14 | `minstret` counts MRET as a retired instruction but not ECALL/EBREAK/illegal or interrupted instructions (those carry `exc_valid_W`). | `top.v:572` |
| O15 | `RESET_PC` default in the core is 0x8000_0000; the SoC overrides to 0x0000_0000 at the instantiation (comment says it must match another parameter at line 762-765). | `top.v:25`, `riscforge_soc_subsystem.sv:765,1245` |

---

## 5. Ambiguities for the owner (code cannot answer)

1. Is cause 3 (machine software interrupt) and cause 11 (machine external interrupt) meant to be deliverable? mie[3]/mie[11] are writable and mip shows them, but the arbiter ignores them (O2). SoC ties both sources to 0.
2. Is silent read-0/write-ignore on unimplemented CSRs the intended sign-off behaviour, or should accesses trap as illegal instructions (O4, 1.2)? `csr_valid_o` exists but is unused.
3. Should `mtvec` support vectored mode (the controller logic exists) or is Direct-only the intended release configuration (O3)?
4. Is `mstatus.MPP` expected to be hard-wired to `11` (summary doc says "hard-wired", code makes it writable with reset 00), and is writable bit 1 (SIE position) intentional (O1)?
5. Is hardware nested-interrupt preemption (documented in architecture docs) deliberately removed in favour of software-managed nesting with mintprio, i.e. which document is authoritative (O9)?
6. Is the intended trap-boundary contract "no younger memory-mapped side effect before an older trap commits"? If yes, O8 requires simulation evidence either way (e.g. `ecall` followed by `sw` to MMIO). The RTL cannot answer.
7. Is instruction-access-fault (cause 1) required for fetch from unmapped regions? No fetch error path exists in the core.
8. Should JALR clear target bit 0 (O6), or is trapping on any nonzero [1:0] intentional?
9. Behaviour after abort of an in-flight multiply (O10): is a stale multiplier completion guaranteed not to write rd? Needs a directed test.
10. Which SoC address map is authoritative for load/store access-fault boundaries (core .sv defaults vs `riscforge_soc_subsystem.sv:1301-1305`)? Also whether BootROM region as a load/store target is intended to fault.
11. Ordering corner in `csr:81-89` (IRQ accepted with stale `mintprio`/`mstatus.MIE`): is the documented "design option" to be implemented before tape-out, or accepted as a known limitation?
