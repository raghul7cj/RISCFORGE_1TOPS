# SPI Boot Controller — Implementation Plan (Concept Only)

## Goal

On external reset, the boot controller takes ownership of the bus, configures the SPI master to receive instructions from an external SPI flash/slave, drains those instructions from the SPI RX FIFO, and writes them into Instruction Memory via the AXI-Lite crossbar. Once complete, it releases control and the RISC-V core starts executing.

---

## System Constraints

- **Only one bus master at a time** — the boot controller OR the RISC-V core, never both simultaneously.
- **SPI master is shared** — used by the boot controller during boot, and available to the RISC-V core during normal runtime (via crossbar → bridge path).
- **Instruction Memory** is only accessible through the AXI-Lite crossbar.
---

## Design Decision: How Does the Boot Controller Read from SPI Master?

There are two possible approaches. **Both require a separate write to IMEM** — data never flows slave-to-slave through the crossbar automatically.

### Approach A: Direct APB 

Boot controller has its **own APB master** wired directly to the SPI master (via a small MUX).

```
Boot Controller ──APB read──► MUX ──► SPI Master RX FIFO
Boot Controller ◄──32-bit word returns──┘
       │
       │  (word is now inside the boot controller)
       │
Boot Controller ──AXI write──► Crossbar ──► IMEM
```

- **2 cycles** for the APB read (SPI master's `PREADY` is always 1)
- Requires an APB MUX (~50 gates) so the bridge can still access SPI at runtime
- Boot controller needs 2 bus interfaces: APB master + AXI-Lite master

### Approach B: Through Crossbar & Bridge

Boot controller uses **only** an AXI-Lite master, reads SPI master through the crossbar → bridge → APB path.

```
Boot Controller ──AXI read──► Crossbar ──► axi_lite_to_apb Bridge ──► SPI Master RX FIFO
Boot Controller ◄──32-bit word returns all the way back──────────────┘
       │
       │  (word is now inside the boot controller — NOT in IMEM)
       │
Boot Controller ──AXI write──► Crossbar ──► IMEM
```

- **Many more cycles** for the read (AXI handshake → crossbar arbitration → bridge Setup→Access → APB → response back)
- No MUX needed (bridge is the only APB master)
- Boot controller only needs 1 bus interface: AXI-Lite master

### Why We Chose Approach A

| | Approach A (Direct APB) | Approach B (Via Crossbar) |
|---|---|---|
| **Read latency** | 2 cycles | 6+ cycles (AXI + bridge + APB) |
| **Boot time (512 instr)** | ~6K cycles | ~15K+ cycles |
| **Extra hardware** | APB MUX (~50 gates) | None |
| **Boot controller ports** | APB master + AXI-Lite master | AXI-Lite master only |
| **Complexity** | Simple FSM, fast | Simpler interface, slower |

> [!NOTE]
> **Key insight both approaches share**: the crossbar routes responses **back to the requesting master**. A read from SPI returns data to the boot controller — it never automatically forwards to IMEM. You always need a separate write operation to store it. The boot controller is the middleman carrying data between two slaves, regardless of approach.



## Architecture Overview

```
                          ┌─────────────────────┐
         External Reset ──►  BOOT CONTROLLER    │
                          │                     │
                          │  ┌──── APB Master ──┼──► APB MUX ──► apb_spi_master ◄── SPI Flash
                          │  │                  │       ▲
                          │  │  AXI-Lite Master ┼──►    │
                          │  │       │          │   axi_lite_xbar
                          └──┘       │          │       │
                                     ▼          │       │
                              Instr Memory ◄────┘  axi_lite_to_apb bridge
                                                        ▲
                                                        │ (runtime only)
                                                   RISC-V Core
```

**Two interfaces on the boot controller:**
1. **APB master** — direct connection to the SPI master (through a simple MUX) for register configuration and FIFO reads
2. **AXI-Lite master** — connects to a slave port on the crossbar for writing instructions to IMEM

**APB MUX** — a tiny combinational mux that selects who drives the SPI master's APB port:
- During boot (`boot_busy=1`): boot controller's APB master
- During runtime (`boot_busy=0`): the `axi_lite_to_apb` bridge (so the core can access SPI normally)

---

## Boot Sequence — Step by Step

### Phase 0: Reset & Halt
1. External reset asserted → everything resets
2. Reset de-asserts → boot controller wakes up, sees a one-shot trigger
3. Boot controller asserts `core_halt` (keeps RISC-V core from fetching)
4. Boot controller asserts `boot_busy` (APB MUX routes to boot controller)

### Phase 1: Configure the SPI Master
The boot controller acts as an APB master and writes to the SPI master's registers in this order:

| Step | APB Write Target | What It Does |
|------|-----------------|--------------|
| 1 | `REG_STATUS` (0x00) bit[4] | Software reset (`spi_swrst`) — clears FIFOs and state |
| 2 | `REG_CLKDIV` (0x04) | Set SPI clock divider (e.g., `0x04` for a reasonable baud) |
| 3 | `REG_SPICMD` (0x08) | Flash read command (e.g., `0x03` for standard READ), or `0` if raw stream |
| 4 | `REG_SPIADR` (0x0C) | Flash start address (e.g., `0x00000000`), or `0` if raw stream |
| 5 | `REG_SPILEN` (0x10) | Set `cmd_len`, `addr_len`, `data_len` — data_len = `BATCH_SIZE × 32` bits |
| 6 | `REG_SPIDUM` (0x14) | Set dummy cycles (flash-dependent), or `0` if none |

> [!NOTE]
> Each APB write is a simple 2-cycle Setup→Access transaction. The SPI master's `PREADY` is always `1`, so no wait-states.

### Phase 2: Trigger SPI Read & Wait
7. APB write to `REG_STATUS` — set `spi_rd=1` and `spi_csreg=0001` → this triggers the SPI master to clock in data from the external flash
8. Wait for the SPI transfer to complete — either:
   - Poll `spi_eot` (end-of-transfer) signal wired directly from SPI master to boot controller, **or**
   - Poll the SPI status register via APB read

### Phase 3: Drain FIFO → Write to IMEM (the core loop)
For each instruction word sitting in the RX FIFO:

9. **APB read** `REG_RXFIFO` (0x20) — this pops one 32-bit word from the SPI RX FIFO into the boot controller
10. **AXI-Lite write** to `IMEM_BASE + (instr_count × 4)` — sends that word through the crossbar to instruction memory
11. Increment `instr_count`, repeat

### Phase 4: Batch Loop
Since the RX FIFO depth is limited (10 entries, use 8 as safe batch), we repeat the whole cycle:

12. If `instr_count < NUM_INSTR`: go back to Phase 1 Step 5 (reconfigure `data_len` for next batch) → Phase 2 → Phase 3
13. If `instr_count == NUM_INSTR`: all instructions loaded, proceed to release

> [!IMPORTANT]
> **Why batching?** The SPI master's RX FIFO is only 10 words deep. If we try to receive all 512 instructions in one shot, the FIFO overflows. So we do 64 batches of 8 words each (512 ÷ 8 = 64 SPI transactions).

### Phase 5: Release Core
14. De-assert `boot_busy` → APB MUX switches to bridge path (core can now use SPI master normally)
15. De-assert `core_halt` → RISC-V core starts fetching from IMEM address `0x0`
16. Pulse `boot_done` → boot controller returns to idle (never activates again until next reset)

---

## Boot FSM States (High-Level)

```
IDLE → HALT_CORE → SPI_RESET → CFG_CLKDIV → CFG_CMD → CFG_ADDR → CFG_LEN → CFG_DUMMY
                                                                                  │
           ┌──────────────────────────────────────────────────────────────────────┘
           ▼
     TRIGGER_READ → WAIT_EOT → DRAIN_FIFO → AXI_WRITE → CHECK_BATCH
                                                              │
                                          batch done? ────────┤
                                          yes ─► CHECK_DONE   │
                                          no  ─► DRAIN_FIFO ◄─┘
                                                 │
                                  all done? ─────┤
                                  yes ─► RELEASE_CORE → IDLE
                                  no  ─► CFG_LEN (next batch)
```

---

## APB MUX — Concept

The naming can be confusing because APB is **bidirectional** — signals flow in both directions. The component is actually doing two things at once:

```
                        COMMAND PATH (master → slave) = MUX (2:1)
                        ──────────────────────────────────────────

    ┌──────────────────┐
    │  Boot Controller │──► PADDR, PWDATA, PWRITE, ─┐
    │  (APB Master #1) │   PSEL, PENABLE, PSTRB     │
    └──────────────────┘                             │   boot_busy
                                                     ├──── sel ──►┌───────────────┐
    ┌──────────────────┐                             │            │  SPI Master   │
    │ AXI-Lite-to-APB  │──► PADDR, PWDATA, PWRITE, ─┘            │  (APB Slave)  │
    │  Bridge          │   PSEL, PENABLE, PSTRB                   └───────────────┘
    │  (APB Master #2) │
    └──────────────────┘

                        RESPONSE PATH (slave → master) = DEMUX (1:2)
                        ────────────────────────────────────────────

    ┌──────────────────┐                                ┌───────────────┐
    │  Boot Controller │◄── PRDATA, PREADY, PSLVERR ◄──┐│  SPI Master   │
    └──────────────────┘                                ├│  (APB Slave)  │
                                                        │└───────────────┘
    ┌──────────────────┐                                │
    │ AXI-Lite-to-APB  │◄── PRDATA, PREADY, PSLVERR ◄──┘
    │  Bridge          │          (only active master
    └──────────────────┘           sees valid response)
```

**In short:**
- **Command path** (PADDR, PWDATA, PWRITE, PSEL, PENABLE, PSTRB): Two masters, one slave → this is a **MUX** (many-to-one, selecting which master drives the slave)
- **Response path** (PRDATA, PREADY, PSLVERR): One slave, two masters → this is a **DEMUX** (one-to-many, routing the slave's response back to the correct master)

Industry convention calls the whole thing a **"MUX"** because the master→slave command direction is the primary/dominant one. But technically it's a bidirectional switch — a MUX on the way in and a DEMUX on the way out.

### Implementation Details

This is purely combinational — no state, no clock:

- When `boot_busy = 1` (boot time):
  - Route boot controller's `PADDR/PWDATA/PWRITE/PSEL/PENABLE/PSTRB` → SPI master
  - Route SPI master's `PRDATA/PREADY/PSLVERR` → boot controller
  - Bridge side sees `PSEL=0` (no spurious transactions)

- When `boot_busy = 0` (runtime):
  - Route bridge's `PADDR/PWDATA/PWRITE/PSEL/PENABLE/PSTRB` → SPI master
  - Route SPI master's `PRDATA/PREADY/PSLVERR` → bridge
  - Boot controller side sees `PSEL=0`

- The **inactive master always sees `PSEL=0`**, which prevents it from interpreting stale `PRDATA` as a valid response
- Total cost: ~50 gates (just a bank of 2:1 muxes on the command signals, no logic on response since both masters can safely see the response — only the one with `PSEL=1` will act on it)

---

## Summary of New Modules

| Module | Type | Purpose |
|--------|------|---------|
| `spi_boot_controller` | RTL | Main FSM + APB master + AXI-Lite master |
| `apb_spi_mux` | RTL | Combinational APB port mux (~50 gates) |

No changes needed to existing IPs — `apb_spi_master`, `axi_lite_to_apb`, and `axi_lite_xbar` are used as-is. The crossbar just needs one additional slave port for the boot controller.
