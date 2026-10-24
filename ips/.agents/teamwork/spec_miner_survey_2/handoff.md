# Specification Mining Report: Peripheral Registers, Semantics & Interrupt Architecture

**Working Directory**: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\spec_miner_survey_2`  
**Milestone**: Survey & Specification Mining Phase 2  
**Author**: `spec_miner_survey_2`  
**Target Recipient**: `f600a31f-7502-4e6a-baf5-5e32a55d3d3e`  

---

## 1. Observation

Authoritative sources inspected:
1. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/Sw/soc_spec.md` (lines 100–370: Memory Map, Peripheral Registers, Interrupt Mapping, Reset Topology).
2. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv` (lines 40–180: Memory Map; lines 680–691: Address Decoder Rules; lines 1205–1252: Core Instantiation & Interrupt Routing).
3. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/top.v` (lines 204–245: `irq_gateway` and `irq_arbiter` instantiation; lines 246–270: Trap commit interface).
4. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/irq_gateway.v` (lines 1–68: Hardware pulse-to-level capture with pulse-wins latch precedence).
5. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/irq_arbiter.v` (lines 1–155: Two-Level Priority Class Arbiter, Intra-Class Round-Robin, and Preemption Gating).
6. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/csr_regfile.v` (lines 68–90, 163–236: 2-deep hardware shadow stack, trap commit push, MRET commit pop, CSR address decoding).
7. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/wb_trap_mret_commit_controller.v` (lines 60–138: Trap commit, gateway auto-clear, direct vs vectored `mtvec` target generation, MRET CSR update).
8. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/gpio-master/gpio_reg_pkg.sv` (lines 166–186: Register offsets; lines 220–240: Access permits).
9. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/gpio-master/gpio.sv` (lines 168–215: `GPIO_SET`, `GPIO_CLEAR`, `GPIO_TOGGLE` atomic semantics; lines 217–255: `INTRPT_STATUS` W1C & pulse-wins logic).
10. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/gpio-master/gpio_apb_wrap.sv` (lines 51–79: Sub-word write blocker raising `PSLVERR`).
11. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/apb_i2c-master/apb_i2c.sv` (lines 1–130: Register offsets; lines 130–215: Command auto-clearing and interrupt acknowledgment).
12. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/apb_timer-master/rtl/apb_timer.sv` & `timer.sv` (lines 1–154: Dual-timer channel offsets, CMP-write-zeroes-timer, IRQ generation).
13. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/apb_uart-main/rtl/apb_uart.sv` & `apb_uart_wrap.sv` (16550 UART register set, DLAB multiplexing).
14. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/spi_master_ip/spi_master/spi_master_apb_if.sv` (lines 13–23: Register definitions; lines 79–93: FIFO backpressure via `PREADY`; lines 134–194: Auto-clearing command bits).
15. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/aon_timer/rtl/aon_timer_reg_pkg.sv` & `aon_timer_reg_top.sv` (OpenTitan reggen-based TL-UL AON timer/watchdog registers).
16. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/documentation/RISCFORGE IRQ Architecture.html` (Complete architecture review, failure analyses F1–F5, phased evolution A/B1/B2/C/D).
17. `c:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/Verification/tb1_interrupts.sv` (Test suite executing tests IRQ01 through IRQ07).

---

## 2. Logic Chain

1. **System Memory Map & Bus Routing**:
   - `riscforge_soc_subsystem.sv` allocates address space `0x4000_0000 – 0x4FFF_FFFF` to MMIO.
   - Core fetches via `instr_fetch_demux` (BootROM `0x0000_0000–0x0000_003F`, ISRAM `0x0001_0000–0x0001_7FFF`).
   - Core LSU direct access to DSRAM (`0x0002_0000–0x0002_7FFF`).
   - AXI Crossbar MST[2] routes to `axi_lite_to_apb` with 6 slots:
     - APB[0] (0x4000_0000 – 0x4000_0FFF): I2C Master
     - APB[1] (0x4000_1000 – 0x4000_1FFF): Timer 0 (Dual 32-bit timers)
     - APB[2] (0x4000_2000 – 0x4000_2FFF): UART 16550
     - APB[3] (0x4000_3000 – 0x4000_37FF): GPIO (2 KB window decoded)
     - APB[4] (0x4000_4000 – 0x4000_4FFF): SPI Master (via Bootloader multiplexer)
     - APB[5] (0x4000_5000 – 0x4000_5FFF): Timer 1 (Dual 32-bit timers)
2. **Peripheral Register Semantics & Special Behaviors**:
   - **GPIO (`gpio_master`)**:
     - Auto-generated with lowRISC `reggen` (BlockAw=11, 2 KB aperture).
     - Standard registers: `INFO` (0x000, RO), `CFG` (0x004, RW), `GPIO_MODE_0` (0x008, RW), `GPIO_MODE_1` (0x00C, RW), `GPIO_EN` (0x080, RW), `GPIO_IN` (0x100, RO), `GPIO_OUT` (0x180, RW).
     - **Atomic Output Aliases**:
       - `GPIO_SET` (0x200, WO): Writing 1 to bit $k$ asserts `gpio_out[k] <= 1'b1`. Writing 0 does nothing. Read returns 0.
       - `GPIO_CLEAR` (0x280, WO): Writing 1 to bit $k$ deasserts `gpio_out[k] <= 1'b0`. Writing 0 does nothing. Read returns 0.
       - `GPIO_TOGGLE` (0x300, WO): Writing 1 to bit $k$ inverts `gpio_out[k] <= ~gpio_out[k]`. Writing 0 does nothing. Read returns 0.
     - **Sub-word Write Guard**: `gpio_apb_wrap.sv` checks `~(&apb_req_i.pstrb)`. If true on a write, it withholds access from `gpio_reg_top` and immediately returns `pslverr = 1'b1` and `pready = 1'b1`. All writes must be 32-bit full-word aligned (`pstrb = 4'b1111`).
     - **Interrupt Status & W1C**: `INTRPT_STATUS` (0x580, W1C aggregate), `INTRPT_RISE_STATUS` (0x600, W1C), `INTRPT_FALL_STATUS` (0x680, W1C), `INTRPT_LVL_HIGH_STATUS` (0x700, RO), `INTRPT_LVL_LOW_STATUS` (0x780, RO). An incoming interrupt edge coincident with software clear is preserved ("hardware-set-wins").
   - **I2C Master (`apb_i2c`)**:
     - Registers: `PRE` (0x00, 16-bit RW), `CTR` (0x04, 8-bit RW: [7]=EN, [6]=IEN), `RXR` (0x08, 8-bit RO), `SR` (0x0C, 8-bit RO: [7]=RxACK, [6]=Busy, [5]=AL, [1]=TIP, [0]=IF), `TXR` (0x10, 8-bit RW/WO), `CR` (0x14, 8-bit WO: [7]=STA, [6]=STO, [5]=RD, [4]=WR, [3]=ACK, [0]=IACK).
     - Command bits [7:4] auto-clear on `s_done | i2c_al`. `IACK` (bit 0) auto-clears on next cycle and deasserts `irq_flag`.
   - **Timer 0 & Timer 1 (`apb_timer`)**:
     - Each block instantiates 2 identical 32-bit timers: Timer 0 (0x00) and Timer 1 (0x10).
     - Per-timer registers: `TIMER_VAL` (0x00 / 0x10, 32-bit RW), `TIMER_CTRL` (0x04 / 0x14, 32-bit RW: [0]=EN, [5:3]=PRESCALER), `TIMER_CMP` (0x08 / 0x18, 32-bit RW).
     - Side Effect: Writing `TIMER_CMP` automatically resets `TIMER_VAL <= 32'h0`.
     - When `TIMER_VAL == TIMER_CMP` or `TIMER_VAL == 0xFFFF_FFFF`, the corresponding IRQ pulses high for 1 cycle and `TIMER_VAL <= 32'h0`.
   - **UART (`apb_uart`)**:
     - 16550-compatible 8-bit registers at byte offsets 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C (accessed via word addresses `PADDR[4:2]`).
     - DLAB (bit 7 of LCR, offset 0x0C) multiplexes 0x00 (`RBR`/`THR` vs `DLL`) and 0x04 (`IER` vs `DLM`).
   - **SPI Master (`apb_spi_master`)**:
     - Registers: `STATUS` (0x00, Read: FIFO flags [0]=TX_FULL, [1]=TX_EMPTY, [4]=RX_FULL, [5]=RX_EMPTY; Write: strobes [0]=RD, [1]=WR, [2]=QRD, [3]=QWR, [4]=SWRST, [11:8]=CS), `CLKDIV` (0x04, RW), `SPICMD` (0x08, RW), `SPIADR` (0x0C, RW), `SPILEN` (0x10, RW), `SPIDUM` (0x14, RW), `TXFIFO` (0x18, WO), `RXFIFO` (0x20, RO), `INTCFG` (0x24, RW), `INTSTA` (0x28, RO, reading clears status).
     - **Backpressure**: APB `PREADY` is driven low if software attempts to write `TXFIFO` when full or read `RXFIFO` when empty.
   - **AON Timer & Watchdog (`aon_timer`)**:
     - OpenTitan reggen-based module with 14 registers (offsets 0x00 to 0x34): `ALERT_TEST`, `WKUP_CTRL`, `WKUP_THOLD_HI/LO`, `WKUP_COUNT_HI/LO`, `WDOG_REGWEN`, `WDOG_CTRL`, `WDOG_BARK_THOLD`, `WDOG_BITE_THOLD`, `WDOG_COUNT`, `INTR_STATE`, `INTR_TEST`, `WKUP_CAUSE`.
     - `WDOG_REGWEN` (0x18, RO): reset 1, write 0 locks out further writes to watchdog configuration until reset.
3. **Interrupt Architecture & Two-Level Priority Class Arbitration**:
   - Total of 6 qualified interrupt channels in core arbiter:
     - Channel 5: SPI EOT / Watchdog (`fast_irq_i[11]`, cause 27, Class 2)
     - Channel 4: Timer 0 compare match (`timer_irq_i`, cause 7, Class 2)
     - Channel 3: UART (`fast_irq_i[3]`, cause 19, Class 1)
     - Channel 2: SPI transfer event (`fast_irq_i[2]`, cause 18, Class 1)
     - Channel 1: I2C master byte complete (`fast_irq_i[1]`, cause 17, Class 0)
     - Channel 0: GPIO global interrupt (`fast_irq_i[0]`, cause 16, Class 0)
   - Additional mapped lines in SoC top (`riscforge_soc_subsystem.sv`):
     - `fast_irq_i[4]` (cause 20): Timer 0 ch0 overflow
     - `fast_irq_i[5]` (cause 21): Timer 0 ch1 overflow
     - `fast_irq_i[6]` (cause 22): Timer 0 ch1 compare
     - `fast_irq_i[7]` (cause 23): Timer 1 ch0 overflow
     - `fast_irq_i[8]` (cause 24): Timer 1 ch0 compare
     - `fast_irq_i[9]` (cause 25): Timer 1 ch1 overflow
     - `fast_irq_i[10]` (cause 26): Timer 1 ch1 compare
     - `ext_irq_i` (cause 11, MEIP) and `sw_irq_i` (cause 3, MSIP) are tied to `1'b0`.
   - **`irq_gateway` (Pulse Capture)**:
     - `edge_mode_i = 6'b110101`: WD (ch5), Timer0 (ch4), SPI (ch2), GPIO (ch0) are edge-mode; UART (ch3), I2C (ch1) are level-mode.
     - Positive edge sets `pend_q`.
     - Output is combinational OR: `pend_o = edge_mode_i ? pend_q : irq_raw_i`. Zero latency cycles added.
     - Trap commit generates one-hot clear strobe from WB stage. Rising edge strictly wins over clear ("pulse-wins").
   - **`irq_arbiter` (Two-Level Priority Class Arbitration)**:
     - **Inter-Class**: Class 2 (Real-Time) > Class 1 (Stream) > Class 0 (Background).
     - **Intra-Class Round-Robin**:
       - Class 2: Strict Fixed Priority (WD cause 27 > Timer0 cause 7).
       - Class 1: Round-Robin between UART (cause 19) and SPI (cause 18) via `rr_ptr_c1`.
       - Class 0: Round-Robin between I2C (cause 17) and GPIO (cause 16) via `rr_ptr_c0`.
       - Pointers advance strictly upon Writeback commit of the winning interrupt, preventing speculative drift during branch mispredicts or flushes.
     - **Preemption Gating**:
       - `preempt_allowed = (nest_depth_i == 2'd0) || (raw_winner_class > cur_class_i);`
       - Interrupt is asserted to EX stage if `mstatus.MIE == 1` and `preempt_allowed` is true.
   - **Hardware Shadow Stack & Nesting (csr_regfile.v)**:
     - 2-deep shadow stack: `mepc_stack[1:0]`, `mcause_stack[1:0]`, `mpie_stack[1:0]`, `class_stack[1:0]`.
     - Depth tracked by `nest_depth` (0, 1, 2). Maximum depth = 2.
     - On trap entry: pushes old context to stack, increments `nest_depth`, updates `cur_class_r <= trap_class_i`, clears `mstatus.MIE <= 0`, saves `MPIE <= MIE`.
     - On MRET commit: decrements `nest_depth`, restores previous context from stack, restores `MIE <= MPIE`, sets `MPIE <= 1`.
     - Trap Target:
       - Direct mode (`mtvec[1:0] == 2'b00`): `{mtvec[31:2], 2'b00}`.
       - Vectored mode (`mtvec[1:0] == 2'b01`): `{mtvec[31:2], 2'b00} + (cause << 2)` for interrupts; exceptions stay at base.
4. **Reference Model Architecture Requirements**:
   - **Peripheral Register Predictor**:
     - Maintains mirrored C++/SystemVerilog struct of all peripheral registers across APB[0..5] and AON timer.
     - Models write masks, read-only bits, W1C clearing, atomic SET/CLEAR/TOGGLE side-effects on `GPIO_OUT`, and sub-word write `SLVERR` generation.
     - Compares actual MMIO read transactions on LSU/AXI against predicted values; logs mismatch with expected vs actual, address, and source instruction PC.
   - **Interrupt Predictor**:
     - Mirrors `irq_gateway` sticky latches and `irq_arbiter` state (including `rr_ptr_c1`, `rr_ptr_c0`).
     - Tracks 2-level preemption rules and 2-deep shadow stack state (`nest_depth`, `cur_class`).
     - Predicts the exact winning interrupt ID, class, and pipeline trap cycle.
     - Flags out-of-order grants, illegal preemption (same-class or lower-class interrupting active ISR), and shadow stack overflow (`nest_depth > 2`).

---

## 3. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | APB[0] I2C | Clock Prescaler (`PRE`) | 16-bit clock divider: $f_{SCL} = f_{PCLK} / (5 \times (PRE + 1))$ | Offset 0x00, 16-bit write | `r_pre` | Upper 16-bit write ignored | `apb_i2c.sv:88` |
| 2 | APB[0] I2C | Control Register (`CTR`) | Enable core [7] and interrupt enable [6] | Offset 0x04, 8-bit write | `r_ctrl` | Reserved bits [5:0] read 0 | `apb_i2c.sv:90` |
| 3 | APB[0] I2C | Command Register (`CR`) | Initiate STA, STO, RD, WR, ACK, IACK | Offset 0x14, 8-bit write | `r_cmd` | Ignored if `s_core_en=0`; bits [7:4] auto-clear on completion | `apb_i2c.sv:96` |
| 4 | APB[0] I2C | Interrupt Ack (`IACK`) | Writing bit 0 of CR clears `irq_flag` and `interrupt_o` | CR[0] write 1 | `irq_flag <= 0` | Auto-clears to 0 on subsequent clock cycle | `apb_i2c.sv:193` |
| 5 | APB[1,5] Timer | Dual 32-bit Timers | Two 32-bit timers per block (Timer 0 at 0x00, Timer 1 at 0x10) | PADDR[4]=timer select | `PRDATA` | Unselected addresses read 0 | `apb_timer.sv:38` |
| 6 | APB[1,5] Timer | Compare Match Auto-Reset | Writing `TIMER_CMP` resets `TIMER_VAL` to 0 | Offset 0x08 / 0x18 write | `regs_n[REG_TIMER] = 0` | None | `timer.sv:107` |
| 7 | APB[1,5] Timer | Dual IRQ Outputs | Per timer: [2*k] = overflow IRQ, [2*k+1] = compare IRQ | Timer value / CMP match | `irq_o[1:0]` | Inactive if `TIMER_CTRL[0]=0` | `timer.sv:63` |
| 8 | APB[2] UART | 16550 DLAB Multiplexing | Bit 7 of LCR (0x0C) switches 0x00 between RBR/THR and DLL, and 0x04 between IER and DLM | LCR[7] | Reg decode | Accessing wrong bank when DLAB set corrupts baud divisor | `soc_spec.md:273`, `obi_uart` |
| 9 | APB[3] GPIO | Atomic Pin SET (`GPIO_SET`) | Writing 1 to bit $k$ sets output pin $k$; writing 0 has no effect | Offset 0x200, 32-bit write | `gpio_out[k] <= 1` | Reading returns 0 | `gpio.sv:199` |
| 10 | APB[3] GPIO | Atomic Pin CLEAR (`GPIO_CLEAR`) | Writing 1 to bit $k$ clears output pin $k$; writing 0 has no effect | Offset 0x280, 32-bit write | `gpio_out[k] <= 0` | Reading returns 0 | `gpio.sv:203` |
| 11 | APB[3] GPIO | Atomic Pin TOGGLE (`GPIO_TOGGLE`) | Writing 1 to bit $k$ inverts output pin $k$; writing 0 has no effect | Offset 0x300, 32-bit write | `gpio_out[k] <= ~gpio_out[k]` | Reading returns 0 | `gpio.sv:207` |
| 12 | APB[3] GPIO | Sub-word Write Guard | Requires full 32-bit writes (`pstrb = 4'b1111`) | APB `pstrb` | `pslverr = 1` | Sub-word write generates immediate `PSLVERR` and suppresses register write | `gpio_apb_wrap.sv:75` |
| 13 | APB[3] GPIO | Aggregated W1C Interrupt Status | Writing 1 to bit $k$ in `INTRPT_STATUS` clears all edge/level flags for pin $k$ | Offset 0x580, 32-bit write | `intrpt_status` | Coincident hardware edge wins over clear | `gpio.sv:231` |
| 14 | APB[4] SPI | FIFO Backpressure | APB `PREADY` pulled low when writing full TX FIFO or reading empty RX FIFO | `PSEL`, `PENABLE`, `PADDR` | `PREADY <= 0` | Triggers bus wait states until FIFO ready | `spi_master_apb_if.sv:90` |
| 15 | APB[4] SPI | Auto-Clearing Control Strobes | Writing bits [4:0] of `REG_STATUS` (0x00) pulses RD, WR, QRD, QWR, SWRST | Offset 0x00 write | `spi_rd/wr/etc.` | Strobes auto-deassert after 1 clock cycle | `spi_master_apb_if.sv:138` |
| 16 | AON Timer | Watchdog Write Lockout | `WDOG_REGWEN` (0x18) bit 0 clears to 0 to lock all watchdog thresholds | Offset 0x18 write 0 | `wdog_regwen` | Writes to `WDOG_CTRL/BARK/BITE` ignored when locked | `aon_timer_reg_top.sv` |
| 17 | Core IRQ | Pulse-to-Level Gateway (`irq_gateway`) | Latches 1-cycle edge pulses into sticky pending flip-flops (`pend_q`) | `irq_raw_i[5:0]`, `edge_mode_i` | `pend_o[5:0]` | Edge pulses never lost during ISR execution or MIE=0 | `irq_gateway.v:51` |
| 18 | Core IRQ | Latch Precedence: Pulse-Wins | Coincident rising edge on raw input strictly wins over clear strobe | `edge_detect[k] & clear_i[k]` | `pend_q[k] <= 1` | Never drops back-to-back incoming interrupts | `irq_gateway.v:51` |
| 19 | Core IRQ | 2-Level Priority Class Arbitration | Class 2 (Fixed: WD > Timer0) > Class 1 (RR: UART <-> SPI) > Class 0 (RR: I2C <-> GPIO) | `pend_i[5:0]`, `mie_i` | `irq_pending_o`, `irq_id_o` | Evaluated combinatorially in 0 added cycles | `irq_arbiter.v:126` |
| 20 | Core IRQ | Non-Speculative RR Pointer Update | `rr_ptr_c1` and `rr_ptr_c0` rotate strictly on WB commit of winning cause | `wb_commit_i`, `wb_trap_cause_i` | `rr_ptr_c1`, `rr_ptr_c0` | Prevents pointer corruption on speculative pipeline flushes | `irq_arbiter.v:71` |
| 21 | Core IRQ | Hardware Preemption Gating | Interrupt allowed if in main thread (`nest_depth == 0`) or winning class > `cur_class` | `cur_class_i`, `nest_depth_i` | `irq_pending_o` | Same-class or lower-class interrupts blocked during ISR | `irq_arbiter.v:150` |
| 22 | Core IRQ | 2-Deep Hardware Shadow Stack | Automatically pushes `mepc`, `mcause`, `MIE`, `cur_class` on trap; pops on MRET | Trap commit / MRET commit | `mepc_stack`, `class_stack` | Supports up to 2 nested ISR levels without software save overhead | `csr_regfile.v:170` |
| 23 | Core IRQ | Vectored vs Direct Redirection | `mtvec[1:0]=01` branches to `base + (cause << 2)` for interrupts; `00` branches to `base` | `mtvec_i`, `trap_is_interrupt_o` | `trap_target_o` | Exceptions always branch to `base` regardless of mode | `wb_trap_mret_commit_controller.v:101` |
| 24 | Core IRQ | MRET Atomic Restore | Restores `MIE <= MPIE`, `MPIE <= 1`, pops shadow stack, redirects to `mepc` | `mret_commit` | `wb_trap_redirect_o` | Pipeline flushed via `flush_pipeline_onehot = 4'b1111` | `wb_trap_mret_commit_controller.v:116` |

---

## 4. Edge Cases

| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | GPIO Sub-word Write | Store Byte (`sb`) or Store Halfword (`sh`) to `GPIO_OUT` (`pstrb != 4'b1111`) | `gpio_apb_wrap.sv` suppresses write to register file and asserts `pslverr = 1'b1`, generating Load/Store Access Fault (`mcause = 7`). |
| 2 | GPIO Atomic SET/CLEAR Collision | Simultaneous write of 1 to bit $k$ via SET vs write of 0 | Writing 1 sets the bit; writing 0 leaves current state unchanged. SET only touches bits with 1. |
| 3 | GPIO Interrupt Clear vs New Event | Software writes 1 to clear `INTRPT_STATUS[k]` in the exact cycle a new edge pulse arrives on GPIO pin $k$ | Hardware-set-wins logic records the incoming event; the new interrupt is NOT lost (`gpio.sv:231`). |
| 4 | SPI FIFO Full Write | Core writes `TXFIFO` (0x18) while internal TX FIFO is completely full | APB wrapper deasserts `PREADY = 1'b0`. Core LSU stalls until FIFO space frees or AXI timeout monitor trips. |
| 5 | SPI FIFO Empty Read | Core reads `RXFIFO` (0x20) while internal RX FIFO is empty | APB wrapper deasserts `PREADY = 1'b0`. Core LSU stalls until byte is received from SPI bus or timeout trips. |
| 6 | Timer CMP Match during Write | Core writes `TIMER_CMP` at the exact cycle `TIMER_VAL` equals old `CMP` | Bus write has priority (`timer.sv:94`). `TIMER_CMP` receives new value, and `TIMER_VAL` is reset to 0. |
| 7 | Interrupt during MIE=0 | Pulse interrupt arrives on SPI (`spi_events_o[0]`) while `mstatus.MIE = 0` | Gateway latches pulse in `pend_q`. Pending bit remains asserted indefinitely until `mstatus.MIE` is enabled, whereupon trap vectors immediately. |
| 8 | Simultaneous Contention (Class 1) | UART and SPI both assert interrupt requests simultaneously with `rr_ptr_c1 = 0` | UART (cause 19) is granted first. Upon WB commit, `rr_ptr_c1` toggles to 1. On subsequent cycle, SPI (cause 18) is granted next, ensuring exact 1:1 fairness. |
| 9 | Preemption Attempt by Equal Class | Class 1 interrupt arrives while processor is actively executing another Class 1 ISR (`cur_class = 1`) | Preemption gating blocks assertion (`preempt_allowed = 0`). The new interrupt is held pending until MRET commits. |
| 10 | Real-Time Preemption of Stream ISR | Class 2 interrupt (Timer 0 compare, cause 7) arrives while processor is executing Class 1 ISR (`cur_class = 1`) | Preemption allowed (`raw_winner_class (2) > cur_class (1)`). Pipeline flushes, shadow stack pushes context, and Timer 0 ISR vectors within $\le 4$ cycles. |
| 11 | Shadow Stack Overflow Boundary | Third interrupt arrives while two nested ISRs are already active (`nest_depth = 2`) | `nest_depth` saturates at 2. Further preemption is blocked by `preempt_allowed` because no class exceeds Class 2 (`raw_winner_class > cur_class_i` evaluates to false). |
| 12 | CSR Write to `mepc` inside Nested ISR | Application writes `csrw mepc, t0` while `nest_depth > 0` | Hardware intercepts write and updates both `mepc_r` and `mepc_stack[nest_depth - 1]`, ensuring return address integrity across nested MRETs. |

---

## 5. Caveats

1. **AON Timer Bus Adapter**: The AON Timer RTL uses OpenTitan TL-UL interfaces (`tl_i`, `tl_o`). In the current SoC subsystem (`riscforge_soc_subsystem.sv`), the 6 APB slots are dedicated to I2C, Timer0, UART, GPIO, SPI, and Timer1. Connecting the AON Timer into an APB slot requires an APB-to-TL-UL protocol shim.
2. **CLIC vs In-Core Arbiter**: While `clic-master/` is present in the repository, the active SoC integration uses the native, lightweight in-core `irq_gateway` and `irq_arbiter` (Option B architecture from `RISCFORGE IRQ Architecture.html`). CLIC is not hooked up to the top-level core.
3. **Timer IRQ Line Mapping**: In `riscforge_soc_subsystem.sv`, Timer 0 Compare is routed directly to `timer_irq_i` (MTIP, cause 7), while secondary Timer 0 and Timer 1 compare/overflow channels are mapped to fast local interrupts `fast_irq_i[4..10]` (causes 20..26).

---

## 6. Conclusion

1. **Peripheral Register Architecture**:
   - RISCFORGE APB peripherals decode standard 32-bit aligned addresses with clean peripheral base separations: I2C (0x4000_0000), Timer 0 (0x4000_1000), UART (0x4000_2000), GPIO (0x4000_3000), SPI (0x4000_4000), Timer 1 (0x4000_5000).
   - GPIO supports atomic bit manipulation (`GPIO_SET` at 0x200, `GPIO_CLEAR` at 0x280, `GPIO_TOGGLE` at 0x300) and strictly forbids sub-word writes via `PSLVERR`.
   - SPI Master implements hardware backpressure via `PREADY = 0` on FIFO overflow/underflow conditions.
2. **Interrupt & Arbitration Architecture**:
   - The SoC features an in-core Two-Level Priority Class interrupt controller with pulse-to-level edge capture (`irq_gateway`), zero-bubble combinational arbitration (`irq_arbiter`), and a 2-deep hardware shadow stack for single-cycle preemption context saving.
   - Arbitration enforces: Class 2 (Real-Time, Fixed) > Class 1 (Stream, RR) > Class 0 (Background, RR).
   - Starvation is eliminated through non-speculative round-robin pointer rotation that updates only on instruction commit in the Writeback stage.
3. **Predictor Requirements for Reference Model**:
   - The Peripheral Register Predictor must maintain exact shadow register state, enforce atomic alias side-effects, mirror FIFO levels, and forecast `PREADY` backpressure.
   - The Interrupt Predictor must replicate gateway latch states, arbiter class evaluations, round-robin token rotations, preemption decisions, and shadow stack push/pop events to achieve 100% Blame Engine determinism.

---

## 7. Verification Method

To independently verify these findings:
1. **Inspect Peripheral RTLs**:
   - View `gpio-master/gpio_apb_wrap.sv:74–79` to verify sub-word write gating.
   - View `gpio-master/gpio.sv:198–210` to verify atomic SET/CLEAR/TOGGLE logic.
   - View `spi_master_ip/spi_master/spi_master_apb_if.sv:90–93` to verify FIFO backpressure logic.
2. **Inspect Interrupt Datapath**:
   - View `riscv_core/rtl/irq_gateway.v:40–66` to verify pulse capture and pulse-wins latch logic.
   - View `riscv_core/rtl/irq_arbiter.v:50–155` to verify 2-level priority classes, round-robin pointers, and preemption thresholding.
   - View `riscv_core/rtl/csr_regfile.v:163–215` to verify the 2-deep shadow stack push/pop operations.
3. **Run Regression Proofs**:
   - Inspect `Verification/tb1_interrupts.sv` and run `Verification/run_tb1.ps1` to verify testcases IRQ01 through IRQ07 on both XSim and Synopsys VCS / Cadence Xcelium.
