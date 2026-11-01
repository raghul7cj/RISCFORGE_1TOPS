# ==============================================================================
# RISCFORGE Test 1: Basic Timer Interrupt (MTIP)
# ==============================================================================
.section .text
.globl _start

_start:
    # 1. Install Trap Vector to 0x8000_0100 (Direct Mode)
    la      t0, isr_handler
    csrw    mtvec, t0

    # 2. Enable Timer Interrupt (MTIE in mie, MIE in mstatus)
    li      t0, 0x00000080             # mie[7] = MTIE
    csrw    mie, t0
    csrsi   mstatus, 0x8               # mstatus[3] = MIE

    # 3. Setup base pointer and marker
    li      t0, 0x80001000             # DMEM Base Address
    li      s0, 0x100                  # Initial background counter

    # 4. Jump to trigger block at 0x8000_0040
    j       target_block

# ------------------------------------------------------------------------------
# Target Execution Block (located at 0x8000_0040)
# ------------------------------------------------------------------------------
.org 0x40
target_block:
    addi    s0, s0, 1                  # 0x8000_0040: Interrupted instruction (mepc)
    nop                                # 0x8000_0044
    nop                                # 0x8000_0048
    sw      s0, 4(t0)                  # Store s0 (0x101) to DMEM[1] (offset 4)

    # Write completion sentinel
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park                       # Park simulation

# ------------------------------------------------------------------------------
# Trap/ISR Handler (located at 0x8000_0100)
# ------------------------------------------------------------------------------
.org 0x100
isr_handler:
    csrr    s1, mcause                 # Expected: 0x8000_0007
    csrr    s2, mepc                   # Expected: 0x8000_0040
    sw      s1, 8(t0)                  # Log mcause to DMEM[2] (offset 8)
    sw      s2, 12(t0)                 # Log mepc to DMEM[3] (offset 12)
    csrci   mie, 0x80                  # Clear MTIE to prevent re-trigger
    mret                               # Return to target_block

