# ==============================================================================
# RISCFORGE Test 4: mintprio Priority Threshold Gate (CSR 0x7C0)
# ==============================================================================
.section .text
.globl _start

_start:
    la      t0, isr_handler
    csrw    mtvec, t0

    # Enable interrupts in mie
    li      t0, 0x000F0888
    csrw    mie, t0

    # Set priority threshold: mintprio = 16 (0x10)
    # Only IRQs with ID > 16 (i.e. UART=19, SPI=18, I2C=17) are accepted.
    # Sub-threshold IRQs (GPIO=16, MEIP=11, MTIP=7, MSIP=3) are blocked.
    li      t0, 16
    csrw    0x7C0, t0                  # CSR 0x7C0 (mintprio)

    csrsi   mstatus, 0x8               # Global MIE = 1

    li      t0, 0x80001000
    li      s0, 0
    li      s3, 0

    j       spin_loop

.org 0x40
spin_loop:
    addi    s0, s0, 1
    nop
    bnez    s3, finish_threshold
    j       spin_loop

finish_threshold:
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park

.org 0x100
isr_handler:
    csrr    s1, mcause                 # Expected: 0x8000_0013 (UART)
    csrr    s2, mepc
    sw      s1, 4(t0)                  # Log mcause to DMEM[1]
    sw      s2, 8(t0)                  # Log mepc to DMEM[2]
    csrci   mie, 0x80                  # Disable interrupts
    addi    s3, s3, 1                  # Signal background loop to complete
    mret

