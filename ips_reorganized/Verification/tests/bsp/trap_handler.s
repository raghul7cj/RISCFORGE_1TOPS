/* =============================================================================
 * RISCFORGE 1TOPS — Machine-Mode Trap Entry and Context Switch (trap_handler.s)
 * ============================================================================= */

  .section .text.trap, "ax"
  .global trap_entry
  .type trap_entry, @function

trap_entry:
  /* Allocate 72 bytes on the stack for context */
  addi sp, sp, -72

  /* Save caller-saved registers */
  sw ra,   0(sp)
  sw t0,   4(sp)
  sw t1,   8(sp)
  sw t2,  12(sp)
  sw a0,  16(sp)
  sw a1,  20(sp)
  sw a2,  24(sp)
  sw a3,  28(sp)
  sw a4,  32(sp)
  sw a5,  36(sp)
  sw a6,  40(sp)
  sw a7,  44(sp)
  sw t3,  48(sp)
  sw t4,  52(sp)
  sw t5,  56(sp)
  sw t6,  60(sp)

  /* Save CSRs */
  csrr t0, mepc
  sw   t0, 64(sp)
  csrr t1, mcause
  sw   t1, 68(sp)

  /* Pass arguments to C dispatcher: a0 = mcause, a1 = mepc */
  mv a0, t1
  mv a1, t0
  call c_trap_handler

  /* Restore CSRs */
  lw   t0, 64(sp)
  csrw mepc, t0

  /* Restore caller-saved registers */
  lw ra,   0(sp)
  lw t0,   4(sp)
  lw t1,   8(sp)
  lw t2,  12(sp)
  lw a0,  16(sp)
  lw a1,  20(sp)
  lw a2,  24(sp)
  lw a3,  28(sp)
  lw a4,  32(sp)
  lw a5,  36(sp)
  lw a6,  40(sp)
  lw a7,  44(sp)
  lw t3,  48(sp)
  lw t4,  52(sp)
  lw t5,  56(sp)
  lw t6,  60(sp)

  /* Deallocate stack */
  addi sp, sp, 72

  /* Return from trap */
  mret

  .size trap_entry, . - trap_entry
