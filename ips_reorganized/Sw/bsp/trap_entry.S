/* =============================================================================
 * RISCFORGE 1TOPS - Low-Level Trap & Context Save/Restore (trap_entry.S)
 * =============================================================================
 * In Direct Mode, all traps (interrupts & exceptions) vector directly here.
 * Saves caller-saved registers (ABI compliant), invokes C handler, executes mret.
 * ============================================================================= */

  .section .text.trap, "ax"
  .align 4
  .global trap_entry
  .type trap_entry, @function

trap_entry:
  /* Allocate 64 bytes on stack (16 words) for caller-saved registers */
  addi sp, sp, -64

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

  /* Pass mcause and mepc as arguments to c_trap_handler(mcause, mepc) */
  csrr a0, mcause
  csrr a1, mepc

  call c_trap_handler

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

  addi sp, sp, 64

  /* Return from trap and resume execution */
  mret

  .size trap_entry, . - trap_entry
