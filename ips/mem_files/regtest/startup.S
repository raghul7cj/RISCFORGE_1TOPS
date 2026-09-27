/* =============================================================================
 * RISCFORGE 1TOPS - startup + trap handler for the register access test
 * =============================================================================
 * Entered at 0x0001_0000 from the BootROM (lui sp,0x28 ; jal 0x0001_0000).
 *
 * No .data copy: the bootloader already placed .rodata/.data in DSRAM.
 * .bss is zeroed here (the cold-boot SRAM clear already did it; this keeps a
 * warm-boot restart correct as well).
 *
 * trap_entry (mtvec, direct mode) exists for the NEGATIVE tests: a bus error
 * (SLVERR/DECERR) is turned by hybrid_mem_interface into mem_err, and the core
 * takes a load (mcause 5) or store (mcause 7) access fault with mepc = PC of
 * the faulting instruction (wb_trap_mret_commit_controller.v). The handler
 * records the trap in g_trap (regtest.c) and resumes at mepc + 4, i.e. the
 * faulting access is skipped. RV32I only - no compressed instructions, so +4
 * is always the next instruction.
 *
 * g_trap layout (must match trap_rec_t in regtest.c):
 *   +0 count  traps since the firmware last cleared it
 *   +4 cause  last mcause
 *   +8 tval   last mtval (faulting address)
 *   +12 epc   last mepc
 *   +16 total traps since reset (never cleared)
 *
 * Addresses are formed with lui/addi and main is reached with jal, so this file
 * does not depend on AUIPC.
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
    addi    sp, sp, -16
    sw      t0, 0(sp)
    sw      t1, 4(sp)

    lui     t1, %hi(g_trap)
    addi    t1, t1, %lo(g_trap)

    lw      t0, 0(t1)                   /* count++ */
    addi    t0, t0, 1
    sw      t0, 0(t1)
    lw      t0, 16(t1)                  /* total++ */
    addi    t0, t0, 1
    sw      t0, 16(t1)

    csrr    t0, mcause
    sw      t0, 4(t1)
    csrr    t0, mtval
    sw      t0, 8(t1)
    csrr    t0, mepc
    sw      t0, 12(t1)

    csrr    t0, mcause
    bltz    t0, 4f                      /* interrupt: do not skip an instruction */

    csrr    t0, mepc                    /* exception: resume after the access */
    addi    t0, t0, 4
    csrw    mepc, t0
    j       5f

4:  li      t0, 0x80                    /* interrupt (not expected: MIE stays 0) */
    csrc    mstatus, t0                 /* clear MPIE -> return with MIE = 0     */

5:  lw      t0, 0(sp)
    lw      t1, 4(sp)
    addi    sp, sp, 16
    mret
