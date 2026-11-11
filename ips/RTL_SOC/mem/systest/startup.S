/* =============================================================================
 * RISCFORGE 1TOPS - start-up code for the system test (systest)
 * =============================================================================
 * _start: stack, mtvec, .bss clear, main. Same as mem/regtest/startup.S.
 *
 * trap_entry (mtvec, direct mode): unlike regtest, systest takes interrupts on
 * purpose, so the handler saves every caller-saved register and calls the C
 * handler trap_c(mcause, mepc, mtval) in systest.c. trap_c returns the address
 * to resume at:
 *   - interrupt : mepc unchanged (the interrupted instruction runs next); trap_c
 *                 also clears the cause's mie bit so it is not taken again
 *                 before the firmware removes the source.
 *   - exception : mepc + 4 (skip the faulting instruction; RV32I, no C ext.)
 *
 * Addresses are formed with lui/addi; main and trap_c are reached with jal.
 * ========================================================================== */

    .section .text.init, "ax"
    .globl  _start
_start:
    lui     sp, %hi(_stack_top)
    addi    sp, sp, %lo(_stack_top)

    lui     t0, %hi(trap_entry)
    addi    t0, t0, %lo(trap_entry)
    csrw    mtvec, t0                   /* direct mode: mtvec[1:0] = 00 */

    lui     t0, %hi(_bss_start)
    addi    t0, t0, %lo(_bss_start)
    lui     t1, %hi(_bss_end)
    addi    t1, t1, %lo(_bss_end)
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    jal     ra, main
3:  j       3b                          /* main returned: park */

/* -------------------------------------------------------------------------- */
    .text
    .balign 4
    .globl  trap_entry
trap_entry:
    addi    sp, sp, -64
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
    sw      a6, 40(sp)
    sw      a7, 44(sp)
    sw      t3, 48(sp)
    sw      t4, 52(sp)
    sw      t5, 56(sp)
    sw      t6, 60(sp)

    csrr    a0, mcause
    csrr    a1, mepc
    csrr    a2, mtval
    jal     ra, trap_c                  /* a0 = address to resume at */
    csrw    mepc, a0

    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    lw      a6, 40(sp)
    lw      a7, 44(sp)
    lw      t3, 48(sp)
    lw      t4, 52(sp)
    lw      t5, 56(sp)
    lw      t6, 60(sp)
    addi    sp, sp, 64
    mret
