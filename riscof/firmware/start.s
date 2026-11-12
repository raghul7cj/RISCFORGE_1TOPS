# ==============================================================================
# File: start.s
# Description: Bare-metal startup code (crt0) for RV32I Processor Core
# ==============================================================================

.option nopic                  # Disable Position-Independent Code
.attribute arch, "rv32i"       # Target architecture: RV32I

.section .text.init            # Entry vector section
.globl _start
.type _start, @function

_start:
    # --------------------------------------------------------------------------
    # 1. Initialize Stack Pointer (sp) and Global Pointer (gp)
    # --------------------------------------------------------------------------
    .option push
    .option norelax
    la gp, __global_pointer$   # Set global pointer for small data optimization
    .option pop

    la sp, _stack_top          # Set stack pointer to top of RAM (DMEM)

    # --------------------------------------------------------------------------
    # 2. Copy .data section from IMEM to DMEM
    # --------------------------------------------------------------------------
    la t0, _sidata             # Source address (in IMEM)
    la t1, _sdata              # Destination start address (in DMEM)
    la t2, _edata              # Destination end address (in DMEM)
    bgeu t1, t2, .copy_data_end

.copy_data_loop:
    lw t3, 0(t0)               # Load word from IMEM
    sw t3, 0(t1)               # Store word into DMEM
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t1, t2, .copy_data_loop

.copy_data_end:

    # --------------------------------------------------------------------------
    # 3. Zero-out .bss section in DMEM
    # --------------------------------------------------------------------------
    la t0, _sbss               # BSS start address
    la t1, _ebss               # BSS end address
    bgeu t0, t1, .zero_bss_end

.zero_bss_loop:
    sw x0, 0(t0)               # Store 0 into BSS word
    addi t0, t0, 4
    bltu t0, t1, .zero_bss_loop

.zero_bss_end:

    # --------------------------------------------------------------------------
    # 4. Jump to C main() function
    # --------------------------------------------------------------------------
    jal ra, main               # Call main()

    # --------------------------------------------------------------------------
    # 5. Store return value (a0) into tohost and halt
    # --------------------------------------------------------------------------
    la t0, tohost
    sw a0, 0(t0)

_exit:
    j _exit                    # Infinite loop trap

.size _start, . - _start

.section .tohost, "aw", @progbits
.align 4
.globl tohost
tohost:
    .word 0
