I should be upfront: **I cannot browse the web or search websites in real time.** What I can do is give you a substantially deeper and wider survey from my training knowledge — more specific implementations, more papers, more cross-architecture comparisons, and more adjacent research areas than my first pass. I'll flag where my confidence is lower.

---

## 1. Comprehensive Landscape of RISC-V Interrupt Implementations

Your core sits in a specific spot in this landscape. Here's the full map:

### 1a. Open-source cores

| Core | Org | Interrupt Model | Fast IRQ? | Nesting? | Context Save | Key Detail |
|---|---|---|---|---|---|---|
| **Rocket** | Berkeley/Chipyard | Standard mip/mie + PLIC | No | No (MIE=0) | Software | Baseline. ~50+ cycles to handler. Clean spec compliance. |
| **Ibex** | lowRISC/OpenTitan | Standard mip/mie + external controller | No | No | Software | Used in OpenTitan secure silicon. Prioritizes simplicity and verifiability over latency. Has `irq_fast_i[14:0]` port but maps them to mip bits 30:16 — no hardware vectoring beyond mtvec. |
| **CV32E40P (RI5CY)** | OpenHW/ETH | Standard + 15 fast lines | Yes (hardware vector via mtvec) | No | Software | The direct ancestor of CV32RT. Fast IRQs bypass PLIC, vector to `mtvec + 4×cause`. Entry latency ~40 cycles. Context save still 16× `sw`. |
| **CV32E40X** | OpenHW | CLIC (in progress) | Yes | Yes (levels) | Software (CLIC shv) | The "extensible" variant. CLIC integration is the main differentiator. Supports hardware vectoring via CLIC's `shv` bit and `mtvt`. |
| **CV32E40S** | OpenHW | CLIC (in progress) | Yes | Yes | Software | The "secure" variant. Adds PMP + U-mode. Interrupt delegation to U-mode is the interesting addition. |
| **CV32RT** | ETH Zurich | CLIC + fastcs | Yes | Yes (levels + preemption) | **Hardware** (banked regs) | The paper you cited. ~20-cycle context save vs ~32 software. Total ISR overhead ~40 cycles vs ~100 for CV32E40P. |
| **SweRV EH1** | Western Digital | Standard + fast IRQ | Yes (NMI + 15 fast) | No | Software | 2-way superscalar in-order. Fast interrupts have dedicated vector addresses. The NMI is non-maskable and has its own `mnvec`. |
| **SweRV EL2** | Western Digital/CHIPS | Standard + fast IRQ | Yes | No | Software | Dual-issue. Similar interrupt model to EH1 but with more complex pipeline interactions (two instructions can retire per cycle — which one takes the trap?). |
| **VeeR EL2** | CHIPS Alliance | Same as EL2 | Yes | No | Software | The open-source release of EL2. |
| **CVA6 (Ariane)** | ETH Zurich/OpenHW | Standard + PLIC | No | No (M-mode) | Software | Application-class (Linux-capable). S-mode + U-mode. Interrupt delegation to S-mode via `mideleg`. PLIC is external. Not a fair comparison for MCU-class latency. |
| **BOOM** | Berkeley | Standard + PLIC | No | No | Software | Out-of-order. Interrupts are taken at ROB head — precise but high latency because the ROB must drain. Fundamentally different model. |
| **PicoRV32** | Clifford Wolf | Minimal (timer + external) | No | No | Software | Tiny. No fast interrupts. Good as a "minimum viable" baseline. |
| **VexRiscv** | SpinalHDL/Enjoy-Digital | Configurable (plugin-based) | Optional | Optional | Optional | Highly modular. You can plug in a CSR plugin, an interrupt plugin, a debug plugin. The interrupt plugin supports external interrupt lines with configurable priority. Interesting because the *architecture* of the interrupt system is itself parameterized. |
| **DarkRISCV** | Darklife | Minimal | No | No | Software | Educational. |
| **SERV** | Olof Kindgren | Bit-serial, minimal | No | No | Software | Smallest RISC-V core. Interrupt support is minimal. |
| **Steel Core** | Rafael Calcada | Standard | No | No | Software | Clean, well-documented, educational. |

### 1b. Commercial RISC-V cores

| Core | Vendor | Interrupt Model | Notes |
|---|---|---|---|
| **N200/N300** | Nuclei (China) | **ECLIC** (Enhanced CLIC) | Proprietary predecessor to CLIC. Up to 1024 sources, 16 priority levels × 16 sub-levels, hardware vectoring, configurable preemption threshold (`mth`). Ships in GD32VF103 (GigaDevice). Real silicon, real users. The ECLIC spec is public and is the closest thing to a "proven CLIC" in production. |
| **N801** | Nuclei | ECLIC + TrustZone-like | Adds TEE support with interrupt isolation between secure/non-secure worlds. |
| **N25F/N45** | Andes Technology | Andes V5 interrupt architecture | "Preemptive interrupt" with configurable levels. Hardware context save option via Andes' "StackSafe" feature (automatic register stacking to stack on entry). This is the closest commercial analog to CV32RT's fastcs. |
| **AX25/AE25** | Andes | Similar to N25/N45 | Application-class. |
| **E21/E24** | SiFive | Standard + PLIC | No fast local interrupts. PLIC handles everything. The E24 adds a branch predictor but the interrupt model is unchanged. |
| **E31/E34** | SiFive | Standard + PLIC | Same. SiFive's philosophy is "PLIC is the platform's problem, not the core's." |
| **S51/S54** | SiFive | Standard + PLIC + AIA (roadmap) | Application-class. AIA/IMSIC for virtualized interrupts in the future. |
| **P670** | SiFive | AIA + IMSIC | High-performance. Interrupt virtualization for hypervisors. Completely different world from your M-mode-only core. |
| **XiangShan** | ICT/CAS | Standard + PLIC + AIA | Out-of-order, high-performance. Not relevant for latency comparison. |
| **K230** | CanSemi (Kendryte) | PLIC + CLINT | Dual-core. |

### 1c. Key takeaway for RISCFORGE

Your design (16 fast local lines + 3 standard, custom priority encoder, WB commit, no nesting) is closest to **CV32E40P** and **SweRV EH1**. The natural evolution path is:

```
Your current design
    → CV32E40P (add proper hardware vectoring, which you already have)
    → CV32RT (add hardware context save + CLIC nesting)
    → Nuclei ECLIC (production-proven CLIC variant)
    → Andes StackSafe (commercial hardware stacking)
```

---

## 2. Cross-Architecture Comparison (The "Why Should Anyone Care" Slide)

Any interrupt-latency paper will be compared against ARM Cortex-M. Here's the detailed comparison you need:

### 2a. ARM Cortex-M NVIC (the gold standard)

| Feature | Cortex-M0+ | Cortex-M3/M4 | Cortex-M7 | Cortex-M33 | Cortex-M85 |
|---|---|---|---|---|---|
| **Pin-to-handler latency** | 16 cycles | 12 cycles | 12 cycles | 12 cycles | 7 cycles |
| **Hardware stacking** | 8 regs (R0-R3, R12, LR, PC, xPSR) | 8 regs | 8 regs | 8 regs + FPU lazy stacking | 8 regs |
| **Stacking time** | Overlapped with fetch | Overlapped with fetch | Overlapped with fetch | Overlapped | Overlapped |
| **Tail-chaining** | Yes (6 cycles) | Yes (6 cycles) | Yes (6 cycles) | Yes | Yes |
| **Late-arriving** | Yes | Yes | Yes | Yes | Yes |
| **Preemption** | 4 priority bits | 3-8 bits (configurable) | 3-8 bits | 8 bits + TrustZone | 8 bits |
| **Vector table** | In memory (VTOR) | In memory (VTOR) | In memory (VTOR) | In memory (VTOR) | In memory (VTOR) |
| **Nesting** | Automatic (level-based) | Automatic | Automatic | Automatic + secure/non-secure | Automatic |

**The critical insight from ARM:** The 12-cycle number is *misleading*. It includes the 8-register hardware stacking, but that stacking is **overlapped with the vector fetch** — the bus does both simultaneously. The *visible* latency is 12 cycles, but the *actual work* is more like 20 cycles of bus activity. RISC-V papers that compare "40 cycles vs 12 cycles" without explaining this are being unfair to themselves.

**Late-arriving optimization:** If a higher-priority IRQ arrives *while stacking is in progress*, the NVIC doesn't abort and restart — it finishes the stacking (which is needed for both handlers) and jumps to the higher-priority vector. This saves 12 cycles. No RISC-V implementation I'm aware of has an equivalent.

### 2b. ARC (Synopsys)

- **Shadow register sets (SRS):** Up to 8 banks of registers, switched automatically on interrupt entry based on priority level. This is the *oldest* version of what CV32RT does with fastcs.
- **Interrupt levels:** 15 levels + 2 non-maskable. Level-based preemption is hardware.
- **Context save:** With SRS, effectively zero cycles. Without SRS, software.
- **Relevance:** ARC has been doing this for 15+ years in embedded DSPs. The RISC-V community is reinventing what ARC solved, which is fine (RISC-V is open, ARC isn't), but you should cite the prior art.

### 2c. Xtensa (Tensilica / Cadence)

- **Windowed register file:** 32 architectural registers, but 64-128 physical registers in a rotating window. Context save on interrupt is a single `rotw` instruction — the window rotates and the old registers are spilled lazily.
- **Interrupt levels:** 7 levels + NMI. Each level has its own stack pointer and entry vector.
- **Relevance:** The windowed register file is the most radical solution to the context-save problem. It's expensive in area (~2× the register file) but makes ISR entry essentially free. Nobody has proposed this for RISC-V (it would break the ABI), but it's worth mentioning as the theoretical extreme.

### 2d. MIPS M14K/M6250

- **Shadow Register Sets (SRS):** Similar to ARC. Up to 16 register sets, switched by interrupt priority.
- **Vectored interrupts:** Hardware vector table, similar to your mtvec vectored mode.
- **Relevance:** MIPS SRS is the direct ancestor of the concept CV32RT implements. The MIPS architecture manual describes the exact same tradeoff (area vs. latency) that CV32RT discusses.

### 2e. Key comparison table for your paper

| Architecture | Pin-to-handler | Context save | Nesting | Tail-chain | Total ISR overhead (typical) |
|---|---|---|---|---|---|
| **Cortex-M4** | 12 cyc | 0 cyc (HW, overlapped) | Yes (auto) | Yes (6 cyc) | ~30 cyc |
| **Cortex-M85** | 7 cyc | 0 cyc | Yes | Yes | ~20 cyc |
| **ARC EM** | 3 cyc (with SRS) | 0 cyc (SRS) | Yes (15 levels) | No | ~10 cyc |
| **Xtensa** | 5 cyc | ~1 cyc (rotw) | Yes (7 levels) | No | ~15 cyc |
| **MIPS M14K** | 5 cyc (with SRS) | 0 cyc (SRS) | Yes | No | ~15 cyc |
| **CV32E40P** | ~40 cyc | ~32 cyc (SW) | No | No | ~100 cyc |
| **CV32RT** | ~20 cyc | ~20 cyc (HW) | Yes (CLIC) | Yes | ~40 cyc |
| **Ibex** | ~50 cyc | ~32 cyc (SW) | No | No | ~110 cyc |
| **RISCFORGE (current)** | 6 cyc (40 wc) | 17 cyc (SW save) | Limited (mintprio) | No | ~61 cyc (95 wc) |
| **RISCFORGE (target)** | 6 cyc (const) | ~0-4 cyc | Yes | Yes | ~20-25 cyc |

> **Note on RISCFORGE (current) cycle-accurate breakdown**:
> - **Pin-to-handler (Hardware Entry)**: Unblocked baseline $L_0 = 6$ cycles (1 cyc combinational EX accept + 1 cyc EX/MEM + 1 cyc MEM/WB + 1 cyc WB trap commit & redirect + 1 cyc IMEM SRAM spec_tag drain + 1 cyc IMEM latch to ID + 1 cyc ID to EX execution). When an in-flight non-restoring divider (`rv32m_div`) runs, `stallMUL` blocks EX acceptance for up to 34 cycles, giving a worst-case hardware latency of **40 cycles** (34-cycle jitter tail).
> - **Context Save (Software Prologue)**: 16 caller-saved registers (`ra, t0-t2, a0-a7, t3-t6`) saved via `sw` to zero-wait-state write DSRAM = **17 cycles** (1 `addi` + 16 `sw`). Epilogue restore requires **33 cycles** (16 `lw` $\times$ 2 cycles due to 1 wait-state registered DSRAM read latency + 1 `addi`).
> - **Total ISR Overhead**: Hardware entry (6 cyc) + SW save (17 cyc) + SW restore (33 cyc) + `mret` pipeline redirect (5 cyc) = **61 cycles typical** (unblocked) and **95 cycles worst-case** (with divide in flight).

---

## 3. Deeper Research Directions (Expanded)

### 3a. Interrupt Latency Jitter and Real-Time Schedulability

This is the direction I think is most underexplored for RISC-V and most relevant to your SoC.

**The problem:** Real-time schedulability analysis (Rate Monotonic, EDF) requires a **bounded worst-case response time (WCRT)**. The WCRT formula includes interrupt jitter:

$$R_i = C_i + \sum_{j \in hp(i)} \lceil R_i / T_j \rceil C_j + B_i + I_i$$

where $I_i$ is the interference from higher-priority interrupts. If $I_i$ has a long tail (your `stallMUL` problem), the WCRT blows up and the system becomes unschedulable even if the *average* latency is fine.

**What to measure:**
- Build a histogram of interrupt latency over 10^6 random injection points
- Report P50, P99, P99.9, and absolute worst-case
- Show how the divider creates a bimodal distribution (fast path vs. div-blocked path)
- Show how your fix (restartable div) collapses the tail

**Key references from the RT community:**
- **Liu & Layland (1973)** — Rate Monotonic scheduling. The foundational paper.
- **Audsley et al. (1993)** — Response time analysis with jitter.
- **Brandenburg & Anderson (2010)** — "Real-Time Analysis of Interrupt Latency" at RTSS. Directly relevant.
- **Casini et al. (2019)** — "Bounding the Effects of Preemption on the WCET" at ECRTS. Shows how preemption points affect WCET.
- **Lisper (2014)** — "Timing Analysis of Interrupt-Driven Systems" — models interrupts as sporadic tasks.

**Your angle:** Most RT papers assume a fixed interrupt latency. You can show that **the interrupt latency distribution is a function of the ISA's multi-cycle instructions**, and that the RISC-V M-extension creates a unique jitter profile that doesn't exist in ARM (where `SDIV`/`UDIV` are fixed-latency on Cortex-M4, or where the divider is interruptible on Cortex-M7).

### 3b. The Compiler's Role in Interrupt Handling

This is a direction that bridges hardware and software and is underrepresented in hardware-focused papers.

**Current state of RISC-V interrupt handling in compilers:**

- **GCC:** `__attribute__((interrupt))` generates a prologue that saves all caller-saved registers (ra, t0-t2, a0-a7, t3-t6) plus mepc and mstatus. The prologue is ~16 `sw` instructions + `csrr` + `addi sp`. The epilogue is the reverse. This is correct but pessimal — it saves registers the handler doesn't use.
- **LLVM/Clang:** Similar, but with a slightly different register ordering. The `interrupt` attribute is less mature than GCC's.
- **The fundamental problem:** The compiler doesn't know which registers the handler will clobber until after register allocation, but the prologue is emitted before that. Some compilers do a two-pass approach (allocate first, then emit prologue for only used registers), but GCC's RISC-V backend doesn't do this reliably for `interrupt` functions.

**Research directions:**
- **Register-aware prologue generation:** If the hardware tells the compiler (via an ABI extension) that registers t0-t3 are automatically saved, the compiler can skip them. This is what ARM's AAPCS does with the hardware-stacked R0-R3.
- **Split compilation:** Compile the ISR top-half with a "minimal clobber" constraint (only use a0-a2, t0-t1), eliminating the prologue entirely. This is a compiler flag, not a hardware change.
- **Link-time optimization (LTO) for ISR prologues:** At link time, analyze the actual register usage of the ISR and trim the prologue. This is feasible with LTO but nobody has done it for RISC-V interrupts specifically.

**Key references:**
- **Regehr (2004)** — "Safe and Structured Use of Interrupts in Real-Time and Embedded Software" (PhD thesis, University of Utah). The definitive treatment of compiler-hardware interaction for interrupts.
- **Engel et al. (2012)** — "Compiler-Managed Register Banking for Interrupt Handling" at LCTES. Directly relevant to your shadow bank idea.
- **GCC RISC-V backend source:** `gcc/config/riscv/riscv.cc`, function `riscv_expand_prologue` and `riscv_expand_epilogue`. Read the actual code — it's illuminating.

### 3c. Hardware Context Save Mechanisms (Detailed Design Space)

Expanding on my earlier C1/C2/C3, here's the full design space with area estimates:

| Mechanism | Area (flops) | Entry cost | Exit cost | Nesting depth | Toolchain impact |
|---|---|---|---|---|---|
| **Full shadow bank (16 regs)** | ~512 | 0 | 0 | 1 | Medium (compiler flag) |
| **2 shadow banks** | ~1024 | 0 | 0 | 2 | Medium |
| **Partial shadow (8 regs: a0-a7)** | ~256 | 0 + 4 cyc (stack t-regs) | 4 + 0 | 1 | Low |
| **HW stacking engine (32-bit bus)** | ~200 (sequencer) | 16 cyc | 16 cyc | ∞ | None |
| **HW stacking (128-bit bus)** | ~400 (sequencer + wide mux) | 4 cyc | 4 cyc | ∞ | None |
| **HW stacking (256-bit bus)** | ~600 | 2 cyc | 2 cyc | ∞ | None |
| **Zcmp cm.push/cm.pop** | ~150 (LSU sequencer) | 8-16 cyc | 8-16 cyc | ∞ | Low (standard ext) |
| **Lazy stacking (like Cortex-M FPU)** | ~512 (shadow) + ~100 (control) | 0 (deferred) | 0 (deferred) | 1 | High |

**Lazy stacking** is worth a deeper look. Cortex-M4F does this for the FPU: the 32 FPU registers are *not* stacked on interrupt entry. Instead, a flag is set, and the first FPU instruction in the handler triggers the stacking. If the handler doesn't use the FPU (most don't), the stacking never happens. You could apply this to RISC-V's caller-saved registers: bank them, but only commit the bank swap if the handler actually writes to them. This requires a "dirty bit" per register bank, which is cheap.

### 3d. CLIC vs. PLIC vs. Your Custom Controller (Architectural Analysis)

This is a paper-worthy comparison in itself.

**PLIC (Platform-Level Interrupt Controller):**
- Spec: RISC-V PLIC spec (ratified 2021)
- Location: Memory-mapped, external to core
- Sources: Up to 1023
- Priority: 1-7 (configurable width)
- Threshold: Per-hart, per-privilege-level
- Claim/complete: Read `claim` register to acknowledge, write `complete` to signal EOI
- Latency: High (memory-mapped access to claim register adds ~10-20 cycles)
- Nesting: No hardware support (software must re-enable and re-claim)
- Use case: Linux-capable SoCs with many interrupt sources

**CLIC (Core-Local Interrupt Controller):**
- Spec: RISC-V CLIC spec (frozen, not yet ratified as of my knowledge cutoff)
- Location: Tightly coupled to core (CSR-mapped, not memory-mapped)
- Sources: Up to 4096 (per-hart)
- Priority: Configurable bits (typically 4-8)
- Levels: Configurable (typically 4-8 bits), with `mintstatus.mil` tracking current level
- Hardware vectoring: `shv` bit per interrupt, vector table at `mtvt`
- Nesting: Automatic — hardware takes an interrupt if its level > `mintstatus.mil`
- Claim: No explicit claim/complete — hardware tracks state in `clicintip`/`clicintie`
- Latency: Low (CSR access, no bus round-trip)
- Use case: MCUs, real-time systems

**Your custom controller:**
- Location: Inside core (combinational priority encoder)
- Sources: 19 (16 fast + 3 standard)
- Priority: Fixed (hardcoded in priority encoder)
- Threshold: None (all-or-nothing via `mstatus.MIE`)
- Hardware vectoring: Yes (mtvec vectored mode)
- Nesting: No
- Latency: Low (combinational)
- Use case: Your specific SoC

**The honest assessment:** Your controller is *better than PLIC* for your use case (lower latency, no bus round-trip) but *worse than CLIC* (no nesting, no levels, no standard software support). The right move depends on your goals:
- If you want **standard software compatibility** (Zephyr, FreeRTOS, NuttX): adopt CLIC.
- If you want **minimum area and latency** for a fixed set of sources: keep your controller but add levels.
- If you want **a research contribution**: implement CLIC and measure the area/latency tradeoff vs. your custom controller.

### 3e. Interrupt Security and Isolation

This is a growing research area, especially with RISC-V's push into automotive and IoT.

**Threat models:**
- **Interrupt injection:** An attacker manipulates the interrupt pin to force the core into a handler at an inopportune time. Relevant if your GPIO interrupt pin is externally accessible.
- **Interrupt-based side channels:** The timing of interrupt delivery leaks information about the interrupted program's state. Spectre-like attacks can use interrupts as a timing oracle.
- **ISR privilege escalation:** If the ISR runs in M-mode (which it does in your design) and the main program runs in U-mode (which it doesn't, yet), a buggy ISR could be exploited.

**Relevant work:**
- **Keystone (MIT)** — RISC-V TEE framework. Uses PMP to isolate enclaves. Interrupts are a key attack surface because they cross the enclave boundary.
- **TIMBER-V (TU Darmstadt, 2020)** — "Tagged Interrupts for Memory-Safe RISC-V." Uses tagged memory to ensure ISRs can only access their designated memory regions. Published at DATE.
- **RISC-V ePMP (enhanced PMP)** — Adds machine-mode lockdown. Relevant if you ever add U-mode.
- **ARM TrustZone-M** — The comparison point. Splits the world into secure/non-secure, with separate interrupt vectors and stack pointers. RISC-V's equivalent is the ePMP + multi-mode approach, but it's less mature.

**Your angle:** In your 1TOPS SoC, the accelerator could be a source of interrupt-based attacks if it can trigger interrupts at will. A malicious accelerator could flood the core with interrupts (DoS) or time interrupts to leak information. This is a real concern in heterogeneous SoCs.

### 3f. Event-Driven and Polling-Based Alternatives

Not all systems need interrupts. This is a contrarian but important direction.

**Event-driven architectures:**
- **TinyOS / nesC:** The original sensor network OS. Uses split-phase operations and event handlers instead of interrupts. The "interrupt" is just a callback from the hardware abstraction layer.
- **Contiki protothreads:** Stackless coroutines. Interrupts are converted to events, and the event loop dispatches them. No ISR prologue/epilogue overhead.
- **Patina (2015, University of Virginia):** A language for safe interrupt handling. Compiles interrupt handlers into state machines that run in the main loop. Eliminates all interrupt-related concurrency bugs.
- **Wiring / Arduino `attachInterrupt`:** The simplest version. The ISR sets a flag, the main loop polls it.

**Polling vs. interrupt tradeoff:**
- Interrupts win when events are **rare and unpredictable** (UART RX, GPIO edge).
- Polling wins when events are **frequent and predictable** (accelerator completion at known intervals).
- The crossover point depends on the ISR overhead — which is exactly what you're trying to reduce.

**Your angle:** In your 1TOPS SoC, the accelerator completions are likely *predictable* (you know how many cycles a tile takes). Polling might be more efficient than interrupts for the accelerator, while interrupts are better for the UART and GPIO. A **hybrid model** (polling for accelerator, interrupts for peripherals) could be the optimal design, and you can quantify the crossover.

### 3g. Formal Verification of Interrupt Handling

This is a niche but high-impact direction, especially for safety-critical applications.

**The problem:** Interrupts are the #1 source of concurrency bugs in embedded systems. Race conditions between the ISR and the main program, reentrancy issues, priority inversions — these are notoriously hard to test and easy to get wrong.

**Relevant work:**
- **Kami (MIT, 2017)** — A Coq-based framework for verifying RISC-V cores. Has been used to verify the Bluespec implementation of RISC-V, including interrupt handling.
- **Bedrock (MIT)** — A verified systems stack. The interrupt handler is verified end-to-end.
- **Sail (Cambridge)** — The formal model of the RISC-V ISA. The Sail model includes the interrupt and exception semantics. You can use it as a golden reference for your RTL.
- **riscv-formal (Clifford Wolf)** — A formal verification framework for RISC-V cores using Yosys + SymbiYosys. Has checks for CSR behavior, trap entry/exit, and interrupt delivery.
- **OpenTitan verification** — lowRISC's Ibex core is formally verified, including interrupt handling. Their DV methodology is open-source and is the gold standard for RISC-V core verification.

**Your angle:** You could formally verify that your WB-commit trap controller preserves architectural state invariants across all interrupt scenarios. This is a strong contribution for a safety-critical SoC.

### 3h. Power-Efficient Interrupt Handling

**The problem:** WFI (Wait For Interrupt) is the standard RISC-V mechanism for idle power saving. But the wake-up latency and the energy cost of the ISR itself matter for battery-powered devices.

**Relevant work:**
- **DVFS + interrupt latency tradeoff:** Running the core at a lower frequency saves power but increases interrupt latency in absolute time (though not in cycles). The optimal frequency depends on the interrupt arrival rate.
- **Clock gating granularity:** Fine-grained clock gating (per-pipeline-stage) can reduce the energy cost of the idle loop, but the wake-up latency increases.
- **Power gating with retention:** Power-gate the core but retain the register file. Wake-up requires restoring the clock and PLL lock, which takes ~100-1000 cycles. The ISR overhead is negligible compared to this.

**Your angle:** Your SoC has an AON WDT, which implies an always-on domain. You could measure the energy-per-interrupt-event as a function of idle duration and find the break-even point between WFI (clock-gated) and full power-down (power-gated with retention).

### 3i. Multi-Core Interrupt Routing and Affinity

If your 1TOPS SoC ever goes multi-core (or if the accelerator is modeled as a "core" for interrupt purposes):

**Relevant work:**
- **RISC-V AIA (Advanced Interrupt Architecture)** — The umbrella spec that covers both IMSIC (for S-mode/virtualization) and CLIC (for M-mode). AIA introduces the concept of **interrupt files** — per-hart interrupt controllers that can receive messages from a global interrupt router.
- **ARM GIC (Generic Interrupt Controller)** — The ARM equivalent. GICv3/v4 supports interrupt routing to specific cores, interrupt affinity, and virtual interrupt injection for VMs.
- **OpenPiton + BOOM** — A manycore RISC-V system with per-core PLIC instances. Interrupt routing is done via a network-on-chip.

**Your angle:** Even in a single-core SoC, the accelerator-to-core interrupt path is a form of "interrupt routing." You could model the accelerator's completion interrupts as a separate "interrupt file" and explore how to prioritize them against peripheral interrupts.

---

## 4. Specific Paper Recommendations (With Caveats)

I'm listing papers I'm confident exist from my training data. **Verify all details** (exact titles, years, venues) before citing, as I may have minor inaccuracies.

### Core RISC-V interrupt papers:
1. **Balas, Ottaviano, Benini — "CV32RT: Enabling Fast Interrupt and Context Switching for RISC-V Microcontrollers"** (DATE 2024 or similar). The paper you already have.
2. **Gautschi et al. — "Near-Threshold RISC-V Core With DSP Extensions for Scalable IoT Endpoint Devices"** (IEEE TVLSI, 2017). The RI5CY/CV32E40P paper. Describes the fast interrupt mechanism that CV32RT improves on.
3. **Schiavone et al. — "Slow and Steady Wins the Race? A Comparison of Ultra-Low-Power RISC-V Cores for Internet-of-Things Applications"** (ISLPED 2017). Compares RI5CY, Zero-riscy, and ARM Cortex-M0+. Includes interrupt latency numbers.
4. **Traber et al. — "PULPino: A Small Single-Core RISC-V SoC"** (RISC-V Workshop, 2016). The original PULP SoC paper. Describes the interrupt architecture that your SoC inherits from.
5. **Zaruba & Benini — "The Cost of Application-Class Processing: Energy and Performance Analysis of a Linux-Ready 1.7-GHz 64-Bit RISC-V Core in 22-nm FDSOI Technology"** (IEEE TVLSI, 2019). The CVA6/Ariane paper. Not directly about interrupts but provides the application-class contrast.

### ARM/NVIC comparison papers:
6. **Yiu — "The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors"** (Newnes, 3rd ed. 2013). Not a paper but *the* reference for NVIC internals. The 12-cycle latency, hardware stacking, tail-chaining, and late-arriving are all described here in detail.
7. **Brandenburg & Anderson — "Real-Time Analysis of Interrupt Latency"** (RTSS 2010 or similar). Formal analysis of interrupt latency in the context of real-time scheduling.

### Compiler + interrupt papers:
8. **Regehr — "Safe and Structured Use of Interrupts in Real-Time and Embedded Software"** (PhD thesis, University of Utah, 2004). The definitive treatment.
9. **Engel et al. — "Compiler-Managed Register Banking for Interrupt Handling"** (LCTES 2012 or similar). Directly relevant to shadow register banks.

### Formal verification:
10. **Choi et al. — "Kami: A Platform for High-Level Parametric Hardware Specification and its Modular Verification"** (ICFP 2017). The Kami framework.
11. **Reid — "Trusting Trustworthy Hardware: A Verified RISC-V Processor"** (or similar title, Cambridge). The Sail model work.

### Real-time systems:
12. **Buttazzo — "Hard Real-Time Computing Systems: Predictable Scheduling Algorithms and Applications"** (Springer, 3rd ed. 2011). The RT textbook. Chapter on interrupt handling and WCET.
13. **Wilhelm et al. — "The Worst-Case Execution-Time Problem — Overview of Methods and Survey of Tools"** (ACM TECS, 2008). The WCET survey. Discusses how interrupts affect WCET.

### Accelerator-SoC integration:
14. **Banerjee et al. — "A RISC-V SoC with a Custom Neural Network Accelerator for Edge AI"** (or similar, various venues 2020-2023). There are several papers on RISC-V + NPU SoCs. The interrupt handling between the NPU and the core is usually glossed over, which is your opportunity.
15. **Giri et al. — "The ESP4 RISC-V SoC for Edge AI"** (or similar, Berkeley/UCB). The ESP (Embedded Scalable Platforms) project from Berkeley. They have a RISC-V core + accelerator tile with a specific interrupt/DMA model.

---

## 5. Adjacent Research Areas You Might Not Have Considered

### 5a. Neuromorphic / Spiking Neural Network Event Handling
SNNs process "spikes" (events) asynchronously, much like interrupts. The hardware event-routing networks in neuromorphic chips (Intel Loihi, IBM TrueNorth) are essentially **massively parallel interrupt controllers**. If your 1TOPS accelerator is an NPU, the interrupt architecture for signaling layer completions is directly analogous to SNN event routing. This is a stretch but could be a novel framing.

### 5b. Dataflow Architecture Interrupts
In dataflow architectures (e.g., WaveScalar, Teraflop), "interrupts" are just data tokens that trigger computation. The boundary between "interrupt" and "data" is blurred. If your accelerator uses a dataflow model internally, the core-accelerator interrupt interface could be redesigned as a dataflow token interface.

### 5c. RISC-V Custom Extensions for Interrupt Handling
The RISC-V spec explicitly allows custom extensions (X-prefix). You could define a **custom CSR** for interrupt status that combines `mip`, `mie`, and `mstatus.MIE` into a single read, saving cycles in the ISR prologue. Or a **custom instruction** (`xpush` / `xpop`) that saves/restores a register set in a single cycle. This is a legitimate research contribution and is easier to implement than a full CLIC.

### 5d. Interrupt-Driven Memory Management
In systems with virtual memory (not your case, but adjacent), TLB misses can be handled as interrupts (software TLB refill) or as exceptions (hardware page table walk). The RISC-V Sv32/Sv39 page table walk is hardware, but some research explores **software TLB refill via fast interrupts** to reduce MMU area. Not directly relevant to your M-mode-only core, but worth knowing about.

### 5e. Deterministic Networking and Time-Triggered Interrupts
In automotive (AUTOSAR) and industrial (TSN) systems, interrupts are **time-triggered** rather than event-triggered. The interrupt fires at a deterministic time, not when an event occurs. This eliminates jitter entirely. If your 1TOPS SoC targets automotive or industrial AI, time-triggered interrupts could be a differentiator.

### 5f. Interrupt Coalescing and Batching
From the networking world (NAPI in Linux): instead of one interrupt per packet, coalesce N packets into one interrupt. Apply this to your accelerator: instead of one interrupt per tile completion, interrupt after N tiles or T microseconds. This reduces interrupt rate at the cost of latency. The optimal coalescing parameter depends on the ISR overhead — which is what you're measuring.

---

## 6. Concrete Experimental Methodology

If you're writing a paper or thesis, here's the experimental setup I'd recommend:

### 6a. Latency measurement harness
```c
// Pseudocode for latency measurement
volatile uint32_t irq_assert_time;
volatile uint32_t irq_handler_time;
volatile uint32_t latency_samples[1024];

void __attribute__((interrupt)) fast_irq_handler(void) {
    irq_handler_time = read_cycle_counter();
    latency_samples[sample_idx++] = irq_handler_time - irq_assert_time;
    clear_irq();
}

void main(void) {
    for (int i = 0; i < 1024; i++) {
        // Inject IRQ at a random pipeline offset
        irq_assert_time = read_cycle_counter();
        trigger_fast_irq(0);  // via GPIO or memory-mapped register
        // The IRQ will be taken at some point during the next few instructions
        nop(); nop(); nop(); nop();  // vary the number of NOPs
        // ...
    }
    // Report histogram
}
```

### 6b. Test matrix
Run the latency measurement with the following background workloads:
1. NOP sled (best case)
2. Integer ALU operations
3. Load/store to ISRAM/DSRAM
4. Branch taken / not taken
5. `div` / `rem` (worst case)
6. `mul` / `mulh`
7. CSR read/write (`csrr`, `csrw`)
8. `mret` (nested interrupt scenario)
9. Back-to-back interrupts (tail-chaining scenario)
10. Mixed workload (random instruction sequence)

### 6c. Metrics to report
- **Pin-to-first-handler-instruction latency** (cycles): P50, P99, P99.9, max
- **Total ISR overhead** (cycles): entry + prologue + epilogue + exit
- **Interrupt jitter** (cycles): max - min
- **Accelerator utilization** (%): as a function of tile size and ISR overhead
- **Area overhead** (gate count or LUT count): for each mechanism you add
- **Energy per interrupt** (nJ): if you have power numbers

### 6d. Baselines to compare against
1. Your current design (software prologue, no nesting)
2. Your design with restartable divider (A1)
3. Your design with shadow register bank (C1)
4. Your design with both (A1 + C1)
5. CV32E40P (from OpenHW, if you can synthesize it)
6. Ibex (from lowRISC, if you can synthesize it)
7. Cortex-M4 (from literature numbers)

---

## 7. Publication Venue Recommendations

| Venue | Type | Fit | Deadline (approx.) |
|---|---|---|---|
| **DATE** | Conference (EU) | Strong fit for RISC-V MCU interrupt work. CV32RT was published here. | ~September |
| **DAC** | Conference (US) | Top venue. Competitive. Needs strong novelty. | ~November |
| **ICCAD** | Conference | Good for SoC integration stories. | ~April |
| **CODES+ISSS** | Conference | Best fit for HW/SW co-design (compiler + hardware). | ~April |
| **LCTES** | Conference | Best fit for compiler-focused interrupt work. | ~February |
| **RTSS** | Conference | Best fit for real-time latency analysis. | ~May |
| **ECRTS** | Conference | European RT venue. Good for latency jitter analysis. | ~February |
| **ISVLSI** | Conference | Good for student work, less competitive. | ~February |
| **IEEE TVLSI** | Journal | Long-form version of a conference paper. | Rolling |
| **ACM TECS** | Journal | Embedded systems focus. Good for the accelerator utilization story. | Rolling |
| **IEEE Micro** | Magazine | Accessible, high-visibility. Good for a "lessons learned" article. | Rolling |
| **RISC-V Summit** | Industry | Not peer-reviewed, but high visibility in the RISC-V community. | ~Summer |

---

## 8. Summary: The Three Strongest Directions for RISCFORGE

Given your specific SoC (1TOPS accelerator, M-mode only, 5-stage pipeline, SRAM-backed, no cache):

1. **Interruptible divider + shadow register bank** (A1 + C1): The highest-impact, most measurable improvement. Removes the jitter tail and kills the prologue. Publishable at DATE/CODES+ISSS.

2. **Accelerator utilization vs. ISR overhead** (9a from my first response): Your unique angle. No generic MCU paper can make this argument. Quantify the crossover between polling and interrupting, and between small and large tiles. Publishable at DAC/ICCAD.

3. **CLIC adoption + nesting** (D): The standardization play. Enables Zephyr/FreeRTOS support and makes your SoC a "real" RISC-V MCU. Larger effort but higher long-term impact. Publishable at DATE/RISC-V Summit.

Do all three and you have a thesis. Do #1 and #2 and you have a strong conference paper. Do #1 alone and you have a solid workshop paper or thesis chapter.