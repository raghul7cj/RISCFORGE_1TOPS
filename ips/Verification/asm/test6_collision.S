# ==============================================================================
# RISCFORGE Test 6: Synchronous Exception vs Asynchronous Interrupt Collision
# ==============================================================================
.section .text
.globl _start

_start:
    la      t0, trap_handler
    csrw    mtvec, t0

    li      t0, 0x00000080             # Enable MTIE
    csrw    mie, t0
    csrsi   mstatus, 0x8               # Enable global MIE

    li      t0, 0x80001000             # DMEM Base

    j       misalign_block

.org 0x40
misalign_block:
    # 2 Continuous branch misalign instructions at EX and ID:
    # Target address 0x8000_0042 is NOT 4-byte aligned on RV32I -> raises Cause 0.
    jal     ra, 2                      # 0x8000_0040: Instruction 1 (misaligned target)
    jal     ra, 2                      # 0x8000_0044: Instruction 2 (continuous misaligned)
    nop
    nop

.org 0x100
trap_handler:
    csrr    s1, mcause                 # Must be 0x0000_0000 (Exception, MSB=0, Cause=0)
    csrr    s2, mepc                   # Expected: 0x8000_0040
    sw      s1, 4(t0)                  # Store mcause to DMEM[1]
    sw      s2, 8(t0)                  # Store mepc to DMEM[2]

    # Write completion sentinel indicating exception handler committed successfully
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park

