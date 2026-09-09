# ==============================================================================
# RISCFORGE Test 7: Full MRET Roundtrip & State Preservation
# ==============================================================================
.section .text
.globl _start

_start:
    la      t0, isr_handler
    csrw    mtvec, t0

    li      t0, 0x00000080             # Enable MTIE
    csrw    mie, t0
    csrsi   mstatus, 0x8               # Enable global MIE

    li      t0, 0x80001000             # DMEM Base

    # Load preloaded test vectors from DMEM[1..4]
    lw      s0, 4(t0)                  # s0 = 0x11111111 (from DMEM[1])
    lw      s1, 8(t0)                  # s1 = 0x22222222 (from DMEM[2])
    lw      s2, 12(t0)                 # s2 = 0x33333333 (from DMEM[3])
    lw      s4, 16(t0)                 # s4 = 0x44444444 (from DMEM[4])

    j       arith_thread

.org 0x50
arith_thread:
    # Arithmetic thread: IRQ injected during this sequence
    addi    s0, s0, 1                  # s0 = 0x11111112
    addi    s1, s1, 2                  # s1 = 0x22222224
    addi    s2, s2, 3                  # s2 = 0x33333336
    addi    s4, s4, 4                  # s4 = 0x44444448

    # Compute expected checksum:
    # 0x11111112 + 0x22222224 + 0x33333336 + 0x44444448 = 0xAAAAAAB4
    add     gp, s0, s1
    add     gp, gp, s2
    add     gp, gp, s4                 # gp = 0xAAAAAAB4

    sw      gp, 0(t0)                  # Store verified checksum to DMEM[0]
park:
    j       park

.org 0x100
isr_handler:
    csrr    t1, mcause                 # Read mcause (clobber temporary register only)
    csrr    t2, mepc                   # Read mepc
    csrci   mie, 0x80                  # Clear MTIE
    mret                               # Return cleanly without perturbing s0, s1, s2, s4

