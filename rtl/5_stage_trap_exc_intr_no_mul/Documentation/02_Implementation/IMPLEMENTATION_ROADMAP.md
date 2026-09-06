# Implementation Roadmap — Phased Build Plan

**Architecture Model**: Propagate-and-commit precise exceptions  
**Core Constraint**: M-Mode only. No user/supervisor mode. Direct Mode mtvec.

---

## Progress Overview

| Phase | Goal | Status |
|-------|------|--------|
| 0 | Synthesis-blocking bug fixes | ✅ Done |
| 1 | Pipeline infrastructure (valid, PC, flush, sideband) | ✅ Done |
| 2 | CSR Regfile cleanup | ✅ Done |
| 3 | Exception detection + side-effect gating + continuous flush | ✅ Done |
| 4 | Trap commit at WB (combinational) | ✅ Done |
| 5 | MRET | ✅ Done |
| 5b | Performance Counters (mcycle/minstret) | ✅ Done |
| 6 | External Interrupts (CLIC integration) | ❌ Pending |
| 7 | Memory system for bare-metal C | ❌ Pending |

---

## Phase 6: External Interrupts — CLIC Integration (Next Up)

**Goal**: Accept M-mode interrupts at instruction retirement boundary.  
**Pre-requisite**: Address decoder for MMIO.

### 6.1 Address Decoder (Prerequisite)
Add a simple address decoder in `core/top.v` to route LSU accesses:
```
0x0000_2000 – 0x0000_2FFF  →  Data RAM (DMEM)
0x0200_0000 – 0x0200_FFFF  →  CLIC MMIO registers
```
- Gate DMEM write enable: `DMEM.WE = dmem_wen & lsu_addr_is_dmem`
- Mux DMEM read data: `dmem_rdata = lsu_addr_is_clic ? clic_rdata : dmem_rdata_raw`

### 6.2 Instantiate CLIC (`clic.sv` from `clic-master/`)
- Expose MMIO read/write ports to LSU address decoder
- CLIC outputs: `irq_valid`, `irq_id[4:0]` (or wider per IP)
- Connect outputs to `wb_commit`: `.irq_valid_i(clic_irq_valid)`, `.irq_id_i(clic_irq_id)`
- **Direct Mode only** for now: all IRQs go to `mtvec.BASE`

### 6.3 Interrupt Pending Logic (`top.v`)
```verilog
wire mip_combined = csr_mip_out;  // From csr_regfile sideband
wire irq_pending  = csr_mstatus_mie_out &
                    ((mip_combined[3]  & csr_mie_out[3])  |   // MSIP
                     (mip_combined[7]  & csr_mie_out[7])  |   // MTIP
                     (mip_combined[11] & csr_mie_out[11]));   // MEIP
```

### 6.4 Interrupt Commit in WB Controller
Add to `wb_trap_mret_commit_controller.v`:
```verilog
wire wb_irq_commit = valid_W & ~exc_valid_W & ~is_mret_W & irq_valid_i;

wire [4:0] irq_cause = (irq_id_i[4:3] == 2'b01) ? 5'd11 :  // External
                       (irq_id_i[4:3] == 2'b00) ? 5'd7  :  // Timer
                                                   5'd3;    // Software
```
On `wb_irq_commit`:
- `mepc` ← `PC_W + 4` (return to NEXT instruction)
- `mcause` ← `{1'b1, irq_cause}` (bit 31 = interrupt)
- `mtval` ← `0`
- Update `mstatus`, redirect to `mtvec`, flush pipeline

### 6.5 Connect mip Inputs
- `timer_intr_i` → CLINT timer comparison logic (drive from MMIO `mtime >= mtimecmp`)
- `ext_intr_i` → CLIC `irq_valid` output
- `msft_intr_i` → MMIO MSIP register bit

**Acceptance**: Write `mtvec`, enable interrupts via `mstatus.MIE` and `mie`, trigger CLIC IRQ, verify core jumps to handler, executes MRET, resumes correctly.

---

## Phase 7: Memory System for Bare-Metal C

**Goal**: Enable the core to load and run a compiled C program from a `.hex` file.

### 7.1 `$readmemh` Program Loading
Replace hardcoded `initial begin mem[N] = ...` in `Instruction_Memory.v`:
```verilog
initial begin
    $readmemh("program.hex", mem);
end
```

### 7.2 Linker Script (`link.ld`)
```ld
ENTRY(_start)
MEMORY {
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    SRAM  (rwx) : ORIGIN = 0x00002000, LENGTH = 4K
}
SECTIONS {
    .text  : { *(.text.init) *(.text) } > FLASH
    .data  : { *(.data) }               > SRAM
    .bss   : { *(.bss) }                > SRAM
    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
}
```

### 7.3 Boot Code (`start.S`)
```asm
.section .text.init
.global _start
_start:
    la   sp, _stack_top         # Initialize stack pointer
    la   t0, _trap_handler
    csrw mtvec, t0              # Set trap vector
    call main
    j    .                      # Loop forever after main

_trap_handler:
    # Save registers to stack (minimal context save)
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    # ... save other caller-saved regs ...
    
    csrr t0, mcause             # Identify trap
    # ... dispatch based on mcause ...
    
    # Restore and return
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    addi sp, sp, 64
    mret
```

### 7.4 C Toolchain Commands
```bash
# Compile (requires RISC-V GCC cross-compiler)
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
    -T link.ld -o program.elf start.S main.c

# Convert to hex for $readmemh
riscv32-unknown-elf-objcopy -O verilog program.elf program.hex

# Disassemble for debugging
riscv32-unknown-elf-objdump -d program.elf
```

**Acceptance**: `mcycle` counter increments, `minstret` counts retired instructions, bare-metal C reads both counters successfully.

---

## Future Extensions (Post-Bare-Metal)

### Vectored Interrupt Mode
- Check `mtvec[1:0]`: if `2'b01`, compute `trap_target = {mtvec[31:2], 2'b00} + (4 * cause)`
- Required for efficient multi-source interrupt dispatch

### Access Fault Detection  
- Out-of-range address check in memory decoder
- Inject cause 5 (load) or 7 (store) into exception sideband

### Full Illegal Instruction Detection
- Extend `opcode_check.v` with funct3/funct7 validation for R-type and shift ops
- Validate CSR address privilege level (read-only CSR write = illegal)

### Timer Peripheral (CLINT-compatible)
- Add simple `mtime` (64-bit) and `mtimecmp` (64-bit) registers at MMIO
- Drive `timer_intr_i` when `mtime >= mtimecmp`
