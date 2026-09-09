# RISCFORGE 1TOPS — SoC Datapath Verification Diagnostics & Fixes

This document records the architectural issues, root causes, requirements, and applied fixes identified during the integration and simulation of the **RISCFORGE 1TOPS SoC Subsystem** (Core + AXI-Lite Crossbar + APB Bridge + UART0 / Memories).

---

## 1. `sram_sp.sv` SystemVerilog `always_ff` Multi-Driver Conflict

### Reason
- `sram_sp.sv` declared synchronous memory writes using SystemVerilog `always_ff @(posedge clk_i)`.
- During simulation, the testbench (`tb_uart0.sv`) preloads memory using backdoor tasks (`$readmemh`).
- VCS strictly enforces single-process driver rules on `always_ff` blocks, producing an `ICPD` (Illegal Concurrent Procedural Driver) error.

### What is Needed
- The memory behavioral model must allow testbench initial-block backdoor preloading without compiler/elaborator driver conflicts.

### Fix
- Changed `always_ff @(posedge clk_i)` to standard Verilog `always @(posedge clk_i)` in `ips/RTL_SOC/sram_sp.sv`.

---

## 2. Bootloader Cold Reset Memory Wipe vs Testbench Preload

### Reason
- When asserting cold reset (`hard_rst_ni = 0 -> 1`), the hardware bootloader (`bootloader.sv`) enters state `S_CLEAR_SRAM`.
- It executes a 16,384-cycle loop writing `32'h0` to all ISRAM and DSRAM words to prepare for SPI flash fetching.
- In backdoor-preloaded simulation runs, this hardware clear overwrites the preloaded `imem.hex` and `dmem.hex`.

### What is Needed
- A mechanism to release the core from reset without triggering `S_CLEAR_SRAM` or SPI flash streaming when testing with preloaded hex files.

### Fix
- Used **Warm Boot** sequence in `tb_uart0.sv`:
  - Assert `hard_rst_ni = 1'b1` (disabled).
  - Pulse `soft_rst_ni = 1'b0 -> 1'b1`.
  - The bootloader skips `S_CLEAR_SRAM` and SPI fetching, transitioning through `S_CLEAN_ASSERT` -> `S_CLEAN_HOLD` -> `S_CLEAN_RELEASE` -> `S_DONE` in only 6 clock cycles while keeping preloaded SRAM contents intact.

---

## 3. `boot_rom.sv` Working Directory Dependency

### Reason
- `boot_rom.sv` originally relied purely on `$readmemh("boot_rom.hex", mem)`.
- Running simulations from varying working directories (`RTL_SOC/`, `datapath_verification/UART0/`, or remote scripts) caused relative path resolution failures for `boot_rom.hex`, resulting in `0x00000000` (NOPs) at the reset vector `0x0000_0000`.

### What is Needed
- The reset vector must reliably execute the trampoline jump regardless of simulation workdir.

### Fix
- Seeded hardcoded fallback instructions in `ips/RTL_SOC/boot_rom.sv` inside `initial begin`:
  - `mem[0] = 32'h0002_8137;` (`lui sp, 0x28000` — sets stack pointer to DSRAM top).
  - `mem[1] = 32'h7FD0_F06F;` (`jal x0, 0x10000` — jumps to ISRAM entry point `_start`).
  - Followed by `$readmemh` (which overrides if hex is provided).

---

## 4. 16550 UART DLAB Locking (Register Access Lockout)

### Reason
- The standard 16550 UART multiplexes register addresses based on the **DLAB** (Divisor Latch Access Bit, `LCR[7]`):
  - `DLAB = 1`: Address offset `0x00` maps to `DLL` (Divisor Latch Low), `0x04` maps to `DLM` (Divisor Latch High).
  - `DLAB = 0`: Address offset `0x00` maps to `RBR`/`THR` (Data FIFO), `0x04` maps to `IER`, and `0x14` maps to `LSR` (Line Status Register).
- `uart_init()` in `uart_min.h` set `DLAB = 1` to program the divisor but initially did not clear `DLAB` back to `0`.
- Subsequent reads from `UART_LSR` (`0x4000_2014`) returned `0x00` instead of `0x60` (`THRE | TEMT`), trapping the CPU in an infinite `while (!(UART_LSR & UART_LSR_THRE))` loop.

### What is Needed
- Software must clear `DLAB = 0` after divisor configuration before attempting FIFO writes (`THR`) or status checks (`LSR`).

### Fix
- Updated `uart_init()` in `ips/datapath_verification/UART0/uart_min.h`:
  ```c
  /* 1. Set DLAB=1 to access Baud Rate Divisor Latches */
  UART_LCR = UART_LCR_DLAB | UART_LCR_8BIT;
  /* 2. Configure Divisor */
  UART_DLL = 0x02;
  UART_DLM = 0x00;
  /* 3. Clear DLAB and configure 8N1 */
  UART_LCR = UART_LCR_8BIT;
  /* 4. Disable interrupts & configure FIFOs */
  UART_IER = 0x00;
  UART_FCR = 0x07;
  ```

---

## 5. `obi_uart_baudgen.sv` Zero-Divisor Calculation Bug

### Reason
- In `obi_uart_baudgen.sv` (Section 9 of SoC), the internal divisor logic is implemented as:
  ```systemverilog
  assign divisor = {reg_read_i.dlm, reg_read_i.dll} - 16'd1;
  assign divisor_valid = ~(divisor == 0);
  ```
- When software programmed `DLL = 1` (`{DLM, DLL} = 1`):
  - Hardware calculated `divisor = 1 - 1 = 0`.
  - Hardware evaluated `divisor_valid = ~(0 == 0) = 0` (FALSE).
  - The oversample counter enable `en_i = divisor_valid` was forced to `0`, completely halting baud rate generation and UART TX transmission.

### What is Needed
- The baud generator requires `divisor_valid` to be high for valid transmission.
- Software should use `DLL >= 2` (or hardware RTL updated to `divisor_valid = ~({dlm, dll} == 0)`).

### Fix
- Set `UART_DLL = 0x02` in `ips/datapath_verification/UART0/uart_min.h` (yielding `divisor = 1`, `divisor_valid = 1`).
- Configured baud timing:
  - Divisor = 2 $\rightarrow$ $16 \times 2 = 32\text{ clock cycles per baud bit}$.
  - At $T_{clk} = 10\text{ ns}$ (100 MHz), $T_{bit} = 320\text{ ns}$.
- Updated `tb_uart0.sv` receiver monitor `bit_time = 32.0 * CLK_PERIOD` (320 ns) to sample serial output accurately.

---

## Summary of Modified Files

| File | Modification Description |
|---|---|
| [`ips/RTL_SOC/sram_sp.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/sram_sp.sv) | Changed `always_ff` to `always @(posedge clk_i)` to allow backdoor preloading. |
| [`ips/RTL_SOC/boot_rom.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/boot_rom.sv) | Added default hardcoded reset vector trampoline before `$readmemh`. |
| [`ips/RTL_SOC/soc_subsystem_vcs.f`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/soc_subsystem_vcs.f) | Included AXI interfaces, fixed file typos, and added UART0 testbench. |
| [`ips/datapath_verification/UART0/uart_min.h`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/datapath_verification/UART0/uart_min.h) | Added DLAB clearance step and updated baud divisor `DLL = 2`. |
| [`ips/datapath_verification/UART0/tb_uart0.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/datapath_verification/UART0/tb_uart0.sv) | Configured Warm Reset, added `#1ns` initial delay, and calibrated UART bit period. |
| [`.agents/skills/soc-verification/SKILL.md`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/.agents/skills/soc-verification/SKILL.md) | Documented complete SoC memory map, interconnect, reset sequences, and tool flows. |

