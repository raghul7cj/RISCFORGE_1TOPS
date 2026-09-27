# RISCFORGE SoC — Software & Verification Roadmap

> **Current State:** The 5-stage RV32IM_Zicsr core and SoC peripheral subsystem RTL are integrated. RISCOF architectural compliance tests pass. However, **interrupt delivery has not yet been proven in an end-to-end testbench**, and **peripheral datapath integrity (MMIO read/write and IRQ loops)** remains to be verified.
>
> **Target:** RTL Interrupt Proof → Peripheral Datapath Verification → Toolchain & Linker Script Setup → Bare-Metal C Bring-up → FreeRTOS / RTOS.

---

## 1. Industry Perspective: Is "Proving Interrupts & Peripheral Datapaths" a Good Role / Path?

### **Yes, Absolutely. This is the Core of Silicon Pre-Silicon Verification & System Bring-Up.**

In top semiconductor firms (Qualcomm, Apple, Intel, Tenstorrent, SiFive, Western Digital), this exact domain sits at the intersection of:
- **Design Verification (DV) / Subsystem Verification Engineer**
- **Pre-Silicon / Post-Silicon Firmware & Bring-Up Engineer**
- **Embedded Systems & Silicon Validation Engineer**

### Why this is critical right now:
1. **The "Silent Hang" Trap:** If you try to run a full bare-metal C program or RTOS before proving the interrupt pipeline and APB register datapaths in RTL:
   - When a program hangs or drops into an unhandled exception loop, you won't know if the bug is in your C compiler's prologue/epilogue, the linker script layout, the AXI crossbar arbitration, an APB bridge handshake timeout, or a hazard unit pipeline stall.
2. **Interrupts are the Hardest Part of CPU Pipelines:**
   - Precise traps require killing instructions in IF/ID/EX, saving `mepc` to the exact non-committed PC, masking interrupts via `mstatus.MIE` → `MPIE`, saving `mcause`, vectoring through `mtvec`, executing the ISR, and resuming cleanly with `mret`.
   - Any corner-case bug in the writeback commit controller or hazard unit corrupts CPU architectural state.
3. **High Career Value:** Engineers who can bridge **RTL Verilog/SystemVerilog**, **bus interconnects (AXI/APB)**, and **low-level C / assembly / linker scripts** are significantly rarer and more sought-after than pure RTL coders or pure application software developers.

---

## 2. Interrupt Verification Plan (RTL Simulation Level)

Before running C, you must prove the interrupt path end-to-end using a minimal directed assembly testbench.

### 2.1 Interrupt Path in RISCFORGE SoC

```
Peripherals (Timer0, UART, SPI, I2C, GPIO)
        │ (irq lines)
        ▼
   top.v Inputs:
     ├── timer_irq_i    ──> mip[7]  (MTIP - Machine Timer Interrupt)
     └── fast_irq_i     ──> mip[19:16] (Fast Local Interrupts: UART=19, SPI=18, I2C=17, GPIO=16)
        │
        ▼
   csr_regfile.v (Evaluates (mip & mie) & mstatus.MIE)
        │
        ▼
   wb_trap_mret_commit_controller.v
        │ 1. Flushes IF, ID, EX pipeline stages
        │ 2. Captures mepc = PC of next uncommitted instruction
        │ 3. Sets mcause = [31]=1 (Interrupt), [4:0]=Interrupt ID (e.g. 7 or 19)
        │ 4. Shifts mstatus.MIE -> mstatus.MPIE, clears mstatus.MIE
        │ 5. Redirects PC to mtvec (Direct: mtvec[31:2]<<2, or Vectored: base + 4*cause)
        ▼
   Pipeline executes ISR routine -> issues 'mret'
        │
        ▼
   mret Restore:
     ├── PC <= mepc
     ├── mstatus.MIE <= mstatus.MPIE
     └── Resume interrupted execution cleanly
```

### 2.2 Directed Assembly Test: `test_timer_irq.S`

Write this minimal assembly test and run it in your testbench (`5_stage/tb/tb_sv_oop_csr_exc` or Verilator):

```asm
.section .text
.globl _start

_start:
    # 1. Setup trap vector address (Direct Mode: bottom 2 bits = 00)
    la   t0, isr_handler
    csrw mtvec, t0

    # 2. Enable Timer Interrupt in mie (Bit 7 = MTIE)
    li   t0, (1 << 7)
    csrw mie, t0

    # 3. Enable Global Interrupts in mstatus (Bit 3 = MIE)
    csrsi mstatus, 0x8

    # 4. Initialize signature registers
    li   s0, 0x11111111      # Background marker
    li   s1, 0x0             # Interrupt hit count

    # 5. Spin loop waiting for testbench to assert timer_irq_i
spin_loop:
    addi s0, s0, 1
    j    spin_loop

# ─────────────────────────────────────────────────────────────
# Trap / ISR Handler
# ─────────────────────────────────────────────────────────────
.align 4
isr_handler:
    # Read mcause and verify it is MTIP (0x80000007)
    csrr t1, mcause
    li   t2, 0x80000007
    bne  t1, t2, trap_fail

    # Increment hit counter
    addi s1, s1, 1

    # In a real system, clear peripheral IRQ or disable mie[7] so we don't re-trigger
    csrc mie, (1 << 7)

    # Return from interrupt
    mret

trap_fail:
    li   s1, 0xDEADDEAD
1:  j    1b
```

### 2.3 Verification Criteria
- [ ] **Trap Trigger:** Within 1-3 cycles of `timer_irq_i` asserting high, `PCSrcE1` fires and fetch jumps to `mtvec`.
- [ ] **Pipeline Flush:** In-flight instructions behind the interrupted PC do not commit to the register file.
- [ ] **Context Capture:** `mepc` precisely matches the address of the interrupted instruction in `spin_loop`.
- [ ] **MRET Return:** Upon `mret`, `PC` returns to `mepc`, `mstatus.MIE` is restored to `1`, and `s0` resumes incrementing.

---

## 3. Peripheral Datapath Proving Plan

Before bringing up complex drivers, prove each peripheral's bus path using single load/store instructions:

```
Core Load/Store (MEM Stage)
     │ (lsu_mem_*)
     ▼
hybrid_mem_interface.sv (Decodes addr >= 0x4000_0000 as MMIO)
     │ (AXI-Lite Master)
     ▼
axi_lite_xbar (2 Slaves -> 3 Masters)
     │ (Master 2: 0x4000_0000 - 0x5000_0000)
     ▼
axi_lite_to_apb Bridge
     │ (PSEL[0..5], PENABLE, PWRITE, PADDR, PWDATA)
     ▼
Target Peripheral (UART, Timer, GPIO, SPI, I2C)
```

### Datapath Verification Matrix

| Peripheral | APB Base | Quick Assembly / Verilog Test Sequence | Expected Result |
|---|---|---|---|
| **Timer 0** | `0x4000_1000` | Write `0x1` to `TIMER_CTRL` (`+0x04`). Read `TIMER_VAL` (`+0x00`) across 10 cycles. | Counter value increases from 0 to $>0$. Write `TIMER_CMP`, verify `timer0_irq_o[1]` fires. |
| **UART** | `0x4000_2000` | Write `0x83` to `LCR` (`+0x0C`), write divisor, write `0x03` to `LCR`. Write ASCII `'A'` (`0x41`) to `THR` (`+0x00`). | `uart_sout_o` transmits START bit, 8 data bits (`0x41`), and STOP bit at baud rate. |
| **GPIO** | `0x4000_3000` | Write `0x0000_FFFF` to `GPIO_EN` (`+0x10`). Write `0x0000_00AA` to `GPIO_OUT` (`+0x18`). | `gpio_out_o[7:0]` reflects `8'hAA`, `gpio_tx_en_o[15:0]` is high. |
| **SPI** | `0x4000_4000` | Set clock divider, write `0x12345678` to `TXFIFO` (`+0x18`). | `spi_csn0_o` pulls low, `spi_clk_o` pulses, `spi_sdo0_o` outputs serialized bits. |
| **I2C** | `0x4000_0000` | Set prescaler, write `CTR.EN=1` (`+0x04`), write slave addr to `TXR`, set `CR.STA | CR.WR`. | `i2c_scl_o` and `i2c_sda_o` generate I2C START condition. |

---

## 4. Step-by-Step: From RTL to Running Bare-Metal C

### Step 4.1: Toolchain Installation
Ensure you have the official RISC-V 32-bit bare-metal GCC toolchain installed.

**On Linux / WSL2:**
```bash
# Ubuntu / Debian package (includes 32-bit and 64-bit multi-lib support)
sudo apt update
sudo apt install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf

# Or download xPack prebuilt bare-metal toolchain:
# https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
```

**Compiler Triplet & Flags:**
```makefile
CC      = riscv64-unknown-elf-gcc   # or riscv-none-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump
SIZE    = riscv64-unknown-elf-size

# Crucial flags: RV32IM with Zicsr, bare-metal (nostdlib, freestanding)
CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -O2 -g \
          -ffreestanding -nostdlib -fno-builtin \
          -Wall -Wextra -I./include
LDFLAGS = -T ./bsp/link.ld -nostdlib -Wl,--gc-sections
```

---

### Step 4.2: The Linker Script (`bsp/link.ld`)
The linker script maps your compiled code and data directly to the RISCFORGE physical address map:
- **ISRAM:** `0x0001_0000` (32 KB instruction SRAM)
- **DSRAM:** `0x0002_0000` (32 KB data SRAM, stack top at `0x0002_8000`)

```ld
/* ========================================================================== */
/* RISCFORGE 1TOPS SoC — Bare-Metal Linker Script                             */
/* ========================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    /* 32 KB Instruction SRAM */
    ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
    /* 32 KB Data SRAM */
    DSRAM (rwx) : ORIGIN = 0x00020000, LENGTH = 32K
}

SECTIONS {
    /* Code Section located in ISRAM */
    .text : {
        . = ALIGN(4);
        KEEP(*(.text.init))         /* Startup crt0.S placed at very beginning */
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
        _etext = .;
    } > ISRAM

    /* Initialized data: LMA in ISRAM (loaded by bootloader), VMA in DSRAM */
    .data : AT(_etext) {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > DSRAM

    _sidata = LOADADDR(.data);

    /* Uninitialized data zero-filled at boot */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DSRAM

    /* Stack grows downwards from the very top of DSRAM */
    .stack (NOLOAD) : {
        . = ALIGN(16);
        _sstack = .;
        . = . + 4K;                 /* 4 KB stack reservation */
        . = ALIGN(16);
        _estack = .;
    } > DSRAM

    _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);
}
```

---

### Step 4.3: Startup Code (`bsp/crt0.S`)
Performs register clearing, stack pointer setup, `.data` section copying, `.bss` zeroing, trap vector installation, and branching to `main()`.

```asm
/* ========================================================================== */
/* RISCFORGE 1TOPS SoC — C Runtime Startup (crt0.S)                           */
/* ========================================================================== */

.section .text.init
.globl _start
.type  _start, @function

_start:
    /* 1. Clear all general-purpose registers to avoid uninitialized states */
    li  x1, 0
    li  x3, 0
    li  x4, 0
    li  x5, 0
    li  x6, 0
    li  x7, 0
    li  x8, 0
    li  x9, 0
    li  x10, 0
    li  x11, 0
    li  x12, 0
    li  x13, 0
    li  x14, 0
    li  x15, 0
    li  x16, 0
    li  x17, 0
    li  x18, 0
    li  x19, 0
    li  x20, 0
    li  x21, 0
    li  x22, 0
    li  x23, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0

    /* 2. Initialize Stack Pointer to top of DSRAM (0x00028000) */
    la  sp, _stack_top

    /* 3. Initialize Global Pointer */
    .option push
    .option norelax
    la  gp, __global_pointer$
    .option pop

    /* 4. Copy .data section from ISRAM load address to DSRAM runtime address */
    la  a0, _sdata
    la  a1, _edata
    la  a2, _sidata
    bge a0, a1, .L_zero_bss
.L_copy_data:
    lw   t0, 0(a2)
    sw   t0, 0(a0)
    addi a0, a0, 4
    addi a2, a2, 4
    blt  a0, a1, .L_copy_data

    /* 5. Zero-fill the .bss section in DSRAM */
.L_zero_bss:
    la  a0, _sbss
    la  a1, _ebss
    bge a0, a1, .L_setup_trap
.L_zero_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    blt  a0, a1, .L_zero_loop

    /* 6. Setup mtvec with trap entry point */
.L_setup_trap:
    la   t0, trap_entry
    csrw mtvec, t0

    /* 7. Call main() application */
    call main

    /* 8. Trap loop in case main() ever returns */
.L_exit_loop:
    wfi
    j .L_exit_loop

.size _start, . - _start
```

---

### Step 4.4: Trap Entry & Context Switch (`bsp/trap_entry.S`)

```asm
/* ========================================================================== */
/* RISCFORGE 1TOPS SoC — Interrupt & Exception Vector Entry                   */
/* ========================================================================== */

.section .text
.globl trap_entry
.align 4

trap_entry:
    /* Allocate stack frame for caller-saved registers (16 words = 64 bytes) */
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)

    /* Pass mcause and mepc to C handler: trap_handler(mcause, mepc) */
    csrr a0, mcause
    csrr a1, mepc
    call trap_handler

    /* Restore caller-saved registers */
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64

    /* Return to program */
    mret
```

---

### Step 4.5: Hardware Abstraction Layer (`include/rf_soc.h`)

```c
#ifndef RF_SOC_H
#define RF_SOC_H

#include <stdint.h>

/* ── Memory-Mapped Base Addresses ─────────────────────────────────────── */
#define I2C_BASE       0x40000000UL   /* APB[0] */
#define TIMER0_BASE    0x40001000UL   /* APB[1] */
#define UART_BASE      0x40002000UL   /* APB[2] */
#define GPIO_BASE      0x40003000UL   /* APB[3] */
#define SPI_BASE       0x40004000UL   /* APB[4] */
#define TIMER1_BASE    0x40005000UL   /* APB[5] */

/* ── Direct Register Access Macros ───────────────────────────────────── */
#define REG32(addr)                   (*(volatile uint32_t *)(addr))
#define MMIO_WRITE(base, offset, val) REG32((base) + (offset)) = (val)
#define MMIO_READ(base, offset)       REG32((base) + (offset))

/* ── UART (16550) Register Offsets ───────────────────────────────────── */
#define UART_RBR_THR   0x00
#define UART_IER       0x04
#define UART_FCR       0x08
#define UART_LCR       0x0C
#define UART_LSR       0x14
#define UART_LSR_THRE  (1 << 5)
#define UART_LSR_DR    (1 << 0)

/* ── Timer0 / Timer1 Register Offsets ────────────────────────────────── */
#define TIMER_VAL      0x00
#define TIMER_CTRL     0x04
#define TIMER_CMP      0x08
#define TIMER_CTRL_EN  (1 << 0)

/* ── GPIO Register Offsets ───────────────────────────────────────────── */
#define GPIO_EN        0x010
#define GPIO_IN        0x014
#define GPIO_OUT       0x018
#define GPIO_SET       0x01C
#define GPIO_CLR       0x020
#define GPIO_TOGGLE    0x024

/* ── RISC-V CSR Access Macros ────────────────────────────────────────── */
#define read_csr(reg) ({ uint32_t __val; \
    __asm__ volatile ("csrr %0, " #reg : "=r" (__val)); __val; })

#define write_csr(reg, val) ({ \
    __asm__ volatile ("csrw " #reg ", %0" :: "rK" ((uint32_t)(val))); })

#define set_csr(reg, bit) ({ \
    __asm__ volatile ("csrs " #reg ", %0" :: "rK" ((uint32_t)(bit))); })

#define clear_csr(reg, bit) ({ \
    __asm__ volatile ("csrc " #reg ", %0" :: "rK" ((uint32_t)(bit))); })

#define enable_irq()   set_csr(mstatus, 0x8)
#define disable_irq()  clear_csr(mstatus, 0x8)

#define MIE_MTIE       (1 << 7)    /* Timer Interrupt */
#define MIE_FLI_GPIO   (1 << 16)   /* Fast Local IRQ: GPIO */
#define MIE_FLI_I2C    (1 << 17)   /* Fast Local IRQ: I2C */
#define MIE_FLI_SPI    (1 << 18)   /* Fast Local IRQ: SPI */
#define MIE_FLI_UART   (1 << 19)   /* Fast Local IRQ: UART */

#endif /* RF_SOC_H */
```

---

### Step 4.6: The C Application (`app/main.c`)

```c
#include "rf_soc.h"

static volatile uint32_t timer_ticks = 0;

/* ── Minimal UART Driver ─────────────────────────────────────────────── */
void uart_init(uint32_t divisor) {
    MMIO_WRITE(UART_BASE, UART_LCR, 0x83); /* DLAB=1, 8N1 */
    MMIO_WRITE(UART_BASE, UART_RBR_THR, divisor & 0xFF);
    MMIO_WRITE(UART_BASE, UART_IER, (divisor >> 8) & 0xFF);
    MMIO_WRITE(UART_BASE, UART_LCR, 0x03); /* DLAB=0, 8N1 */
    MMIO_WRITE(UART_BASE, UART_FCR, 0x07); /* Enable & clear FIFOs */
}

void uart_putc(char c) {
    while (!(MMIO_READ(UART_BASE, UART_LSR) & UART_LSR_THRE));
    MMIO_WRITE(UART_BASE, UART_RBR_THR, (uint8_t)c);
}

void uart_puts(const char *str) {
    while (*str) uart_putc(*str++);
}

void print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex_chars[(val >> i) & 0xF]);
    }
}

/* ── Trap Dispatcher Called from trap_entry.S ────────────────────────── */
void trap_handler(uint32_t mcause, uint32_t mepc) {
    if (mcause & 0x80000000UL) {
        uint32_t irq_id = mcause & 0x7FFFFFFFUL;
        if (irq_id == 7) { /* MTIP - Timer Interrupt */
            timer_ticks++;
            /* Reset/Re-arm Timer 0 compare match */
            MMIO_WRITE(TIMER0_BASE, TIMER_VAL, 0);
        }
    } else {
        /* Synchronous exception */
        uart_puts("\r\n[TRAP] Exception at mepc: ");
        print_hex(mepc);
        uart_puts(" cause: ");
        print_hex(mcause);
        while (1);
    }
}

/* ── Main Application ────────────────────────────────────────────────── */
int main(void) {
    /* 1. Initialize UART (assume 50MHz clock, 115200 baud -> divisor ~27) */
    uart_init(27);
    uart_puts("\r\n========================================\r\n");
    uart_puts("   RISCFORGE RV32IM_Zicsr SoC Booting   \r\n");
    uart_puts("========================================\r\n");

    /* 2. Configure Timer 0 for 50,000 clock cycle ticks (~1ms) */
    MMIO_WRITE(TIMER0_BASE, TIMER_VAL, 0);
    MMIO_WRITE(TIMER0_BASE, TIMER_CMP, 50000);
    MMIO_WRITE(TIMER0_BASE, TIMER_CTRL, TIMER_CTRL_EN);

    /* 3. Enable GPIO pin 0 as output */
    MMIO_WRITE(GPIO_BASE, GPIO_EN, 0x1);

    /* 4. Enable Timer Interrupt in Core CSRs */
    write_csr(mie, MIE_MTIE);
    enable_irq();

    uart_puts("[INFO] Interrupts enabled. Entering event loop...\r\n");

    uint32_t last_tick = 0;
    while (1) {
        if (timer_ticks != last_tick) {
            last_tick = timer_ticks;

            /* Toggle GPIO[0] LED */
            MMIO_WRITE(GPIO_BASE, GPIO_TOGGLE, 0x1);

            /* Print heartbeat every 10 ticks */
            if (timer_ticks % 10 == 0) {
                uart_puts("Tick: ");
                print_hex(timer_ticks);
                uart_puts("\r\n");
            }
        }
    }

    return 0;
}
```

---

### Step 4.7: Binary to `$readmemh` Hex Converter (`tools/bin_to_memh.py`)

Simulation memories (`sram_sp.sv`) load 32-bit words via `$readmemh`:

```python
#!/usr/bin/env python3
import sys
import struct

def convert_bin_to_hex(bin_file, hex_file, total_words=8192):
    with open(bin_file, "rb") as f:
        raw_data = f.read()

    words = []
    for i in range(0, len(raw_data), 4):
        chunk = raw_data[i:i+4].ljust(4, b'\x00')
        words.append(struct.unpack("<I", chunk)[0])

    while len(words) < total_words:
        words.append(0)

    with open(hex_file, "w") as f:
        for word in words:
            f.write(f"{word:08x}\n")

    print(f"Generated {hex_file}: {len(words)} 32-bit words.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 bin_to_memh.py <input.bin> <output.hex> [total_words]")
        sys.exit(1)
    words = int(sys.argv[3]) if len(sys.argv) > 3 else 8192
    convert_bin_to_hex(sys.argv[1], sys.argv[2], words)
```

---

### Step 4.8: Automated Makefile (`Makefile`)

```makefile
CROSS_COMPILE ?= riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -O2 -g \
          -ffreestanding -nostdlib -fno-builtin \
          -Wall -Wextra -I./include

LDFLAGS = -T bsp/link.ld -nostdlib -Wl,--gc-sections

TARGET  = riscforge_app

SRCS_ASM = bsp/crt0.S bsp/trap_entry.S
SRCS_C   = app/main.c

all: $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).dis

$(TARGET).elf: $(SRCS_ASM) $(SRCS_C)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(SIZE) $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).bin
	python3 tools/bin_to_memh.py $< $@ 8192

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).dis

.PHONY: all clean
```

---

## 5. Critical RTL Bugs to Fix Before Running C Code

Before spending time debugging why bare-metal C fails, verify that the known critical bugs from `exception_bugs.md` are resolved:

1. **JALR bit-0 not cleared (`execute_cycle.v:254`):**
   - In RISC-V ISA, `JALR` target must have bit 0 set to 0 (`PCTargetE = {alu_r[31:1], 1'b0}`).
   - If not cleared, function returns (`ret` / `jalr ra`) jump to odd addresses, causing immediate instruction address misaligned exceptions.
2. **LHU Misalignment check missing funct3 (`memory_cycle.v:185`):**
   - Ensure `misaligned_load` includes `3'b101` (`LHU`).
3. **Illegal instruction firing on pipeline bubbles (`decode_cycle.v:380`):**
   - Must be guarded by `valid_D` so flushed pipeline bubbles do not spuriously trigger illegal instruction traps.
4. **CSR Write gate (`top.v:199`):**
   - Ensure `csr_write_en_W_gated` allows writes to `mtvec`, `mie`, and `mstatus` during initialization.

---

## 6. Execution Roadmap Summary

```
Phase 1: RTL Interrupt Verification (1-2 days)
  └─ Run test_timer_irq.S in Verilator / Vivado XSim
  └─ Verify mepc capture, pipeline flush, and mret restore

Phase 2: Peripheral Datapath Sanity Checks (2-3 days)
  └─ Assembly store/load to Timer 0, UART, GPIO via hybrid_mem_interface
  └─ Verify APB slave responses & interrupt pin reflections

Phase 3: Bare-Metal C Compilation & Bring-up (2-3 days)
  └─ Compile main.c using the provided Linker Script & crt0.S
  └─ Convert to riscforge_app.hex via tools/bin_to_memh.py
  └─ Load into ISRAM in simulation testbench (soc_timer0_boot_run_tb.sv)
  └─ Observe UART "RISCFORGE RV32IM_Zicsr SoC Booting" character stream
```