# RISCFORGE 1TOPS — SPI Master Datapath Diagnostics & Integration Fixes

---

## 1. Executive Summary

This document captures the hardware and software design nuances, integration challenges, and engineering fixes implemented during the datapath verification of the **APB SPI Master IP (`apb_spi_master` @ `0x4000_4000`)** integrated into the complete **RISCFORGE 1TOPS SoC Subsystem** (`riscforge_soc_subsystem.sv`) running under the RV32IM 5-stage RISC-V core and the **Infineon S25FS512S QSPI Vendor Flash Model** (`s25fs512s.sv`).

---

## 2. Hardware Architecture & Pin Mapping Nuances

### 2.1 SPI SDO / SDI Pin Assignments in Standard SPI Mode
* **Hardware Shift Logic**:
  - `spi_master_tx.sv` shifts standard SPI command and data bits MSB-first out of `spi_sdo0_o` (IO0 / MOSI).
  - `spi_master_rx.sv` (line 84) samples standard SPI data from `spi_sdi1_i` (IO1 / MISO) on the rising edge of `spi_clk_o`:
    ```systemverilog
    if (en_quad_in)
      data_int_next = {data_int[27:0], sdi3, sdi2, sdi1, sdi0};
    else
      data_int_next = {data_int[30:0], sdi1};
    ```
* **Integration Rule**:
  In the top-level testbench (`tb_spi0.sv`), the Flash model `SO` output MUST be wired to `spi_sdi1_i` (IO1), while the SoC `spi_sdo0_o` (IO0) connects to Flash `SI`. Connecting Flash `SO` to `spi_sdi0_i` results in zero/erased bytes read by the RX FIFO.

---

### 2.2 Infineon S25FS512S Inout Net Ambiguity & Isolation
* **The Challenge**:
  The Infineon `s25fs512s.sv` vendor behavioral model declares its interface pins as bidirectional `inout SI, SO, WPNeg, RESETNeg;`.
* **Resolution**:
  Explicit unidirectional driver nets must bridge the SoC and the model to prevent Verilog multi-driver resolution from generating `X` (unknown) states during clock transitions:
  ```systemverilog
  wire flash_si;
  wire flash_so;
  wire flash_wpn;
  wire flash_resetn;

  assign flash_si     = spi_sdo0_o;   // Master MOSI -> Flash SI
  assign spi_sdi1_i   = flash_so;     // Flash SO -> Master MISO (IO1)
  assign flash_wpn    = 1'b1;         // Write protect disabled
  assign flash_resetn = 1'b1;         // Flash reset deasserted
  ```

---

### 2.3 Left-Justified Command (`SPICMD`) & Address (`SPIADR`) Registers
* **Register Architecture**:
  The SPI Master IP transmitter shifts out bits starting from bit 31 downwards regardless of the configured bit length (`cmd_len` / `addr_len`).
* **Software Alignment Requirement**:
  - 8-bit Command opcodes must be left-aligned by 24 bits: `SPI_SPICMD = ((uint32_t)opcode) << 24;`.
  - 24-bit Flash addresses must be left-aligned by 8 bits: `SPI_SPIADR = (addr & 0x00FFFFFF) << 8;`.
  - Failing to shift left causes the IP to shift out leading zeros, transmitting garbage opcodes to the Flash device.

---

## 3. SoC Subsystem & Memory Preload Fixes

### 3.1 Time-0 Race Condition Guard (`#1` Delay)
* **The Root Cause**:
  `Instruction_Memory.v` contains an `initial begin for (...) mem_array[i] = 32'h0000_0013; end` block that initializes all memory words to NOP (`0x0000_0013`) at time 0.
* **The Failure**:
  If the testbench `$readmemh` executes in a parallel `initial` block at time 0, it may execute before the NOP loop, wiping out the preloaded firmware binary.
* **Fix**:
  Add an explicit `#1;` delta delay in the testbench initialization block before loading `imem.hex` and `dmem.hex`:
  ```systemverilog
  initial begin
    #1;
    $readmemh(imem_hex, dut.i_isram.u_imem.mem_array);
    $readmemh(dmem_hex, dut.i_dsram.mem);
  end
  ```

---

### 3.2 16550 UART Baud Rate Divisor Calibration
* **Clocking Ratio**:
  In `obi_uart_baudgen.sv`, the baud pulse generator divides the system clock (100 MHz / 10 ns) by $(D \times 16)$.
  - `DLL = 0x01`: $1 \times 16 = 16$ clocks per bit (160 ns bit-period).
  - `DLL = 0x02`: $2 \times 16 = 32$ clocks per bit (320 ns bit-period).
* **Testbench Receiver Calibration**:
  `tb_spi0.sv` serial monitor task must set `bit_time = (DLL_VAL * 16.0) * CLK_PERIOD` (`320 ns`) to sample exactly at the mid-point of each serial bit without drift.

---

### 3.3 Pure-ALU Hex Formatter (`uart_puthex`)
* **Optimization**:
  To prevent any potential data segment misalignment or stack copy overhead during early initialization, `uart_puthex()` uses pure register arithmetic rather than character lookup tables:
  ```c
  static inline void uart_puthex(uint32_t val) {
      uart_putc('0');
      uart_putc('x');
      for (int i = 7; i >= 0; i--) {
          uint8_t nibble = (val >> (i * 4)) & 0xF;
          char c = (nibble < 10) ? ('0' + nibble) : ('A' + (nibble - 10));
          uart_putc(c);
      }
  }
  ```

---

## 4. Verification Test Matrix Summary

| Test ID | Flash Opcode | Description | Hardware Validation Criteria | Result |
|:---:|:---:|---|---|:---:|
| **T01** | `0x9F` | JEDEC ID Read | Winbond (`0xEF4018`) / Spansion (`0x010219`) ID match | **PASS** |
| **T02** | `0x06` / `0x05` | Write Enable & Status | Status Register 1 `WEL` bit 1 asserts high | **PASS** |
| **T03** | `0x02` | Page Program | 32-bit payload `0x55AA1234` written to Flash `0x001000` | **PASS** |
| **T04** | `0x03` | Standard Read Data | Read data from `0x001000` matches `0x55AA1234` | **PASS** |
| **T05** | `0x0B` | Fast Read (Dummy Clocks) | 8 dummy clock cycles counted; data matches `0x55AA1234` | **PASS** |

