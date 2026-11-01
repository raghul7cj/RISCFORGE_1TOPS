# ==============================================================================
# RISCFORGE Test 3: Priority Resolution (Simultaneous IRQ Assertion)
# ==============================================================================
.section .text
.globl _start

_start:
    la      t0, isr_handler
    csrw    mtvec, t0

    # Enable all 7 interrupt lines
    li      t0, 0x000F0888
    csrw    mie, t0
    csrsi   mstatus, 0x8

    li      t0, 0x80001000
    li      s0, 0
    li      s3, 0
    li      a0, 7

    j       spin_loop

.org 0x40
spin_loop:
    addi    s0, s0, 1
    nop
    beq     s3, a0, finish_prio
    j       spin_loop

finish_prio:
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park

.org 0x100
isr_handler:
    csrr    s1, mcause                 # Read mcause
    slli    t1, s3, 2
    add     t2, t0, t1
    sw      s1, 16(t2)                 # Store mcause into table (DMEM[4 + s3])

    # Dynamic IRQ clear to allow next priority line to fire:
    # UART (19) -> clear mie[19], SPI (18) -> clear mie[18], etc.
    andi    t3, s1, 0x1F               # Extract cause ID (bits [4:0])
    li      t4, 1
    sll     t4, t4, t3                 # t4 = 1 << cause_id
    csrc    mie, t4                    # Clear the serviced IRQ bit in mie

    addi    s3, s3, 1
    mret

