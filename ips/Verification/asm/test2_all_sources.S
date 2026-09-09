# ==============================================================================
# RISCFORGE Test 2: All 7 Interrupt Sources Sequentially
# ==============================================================================
.section .text
.globl _start

_start:
    # 1. Install Trap Vector
    la      t0, isr_handler
    csrw    mtvec, t0

    # 2. Enable all 7 interrupt lines in mie (FLI[19:16], MEIE[11], MTIE[7], MSIE[3])
    li      t0, 0x000F0888
    csrw    mie, t0
    csrsi   mstatus, 0x8               # Global MIE = 1

    # 3. Setup registers
    li      t0, 0x80001000             # DMEM Base
    li      s0, 0                      # Background spin counter
    li      s3, 0                      # Interrupt hit counter
    li      a0, 7                      # Expected total hits = 7

    # 4. Jump to spin block at 0x8000_0040
    j       spin_loop

# ------------------------------------------------------------------------------
# Background Spin Loop (0x8000_0040)
# ------------------------------------------------------------------------------
.org 0x40
spin_loop:
    addi    s0, s0, 1
    nop
    beq     s3, a0, finish_all         # If hit count reaches 7, exit loop
    j       spin_loop

finish_all:
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park

# ------------------------------------------------------------------------------
# ISR Handler (0x8000_0100)
# ------------------------------------------------------------------------------
.org 0x100
isr_handler:
    csrr    s1, mcause                 # Read mcause
    slli    t1, s3, 2                  # offset = s3 * 4
    add     t2, t0, t1                 # t2 = DMEM_BASE + offset
    sw      s1, 16(t2)                 # Store mcause into DMEM table (from DMEM[4])
    addi    s3, s3, 1                  # Increment hit count
    mret

