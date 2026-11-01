/* =============================================================================
 * RISCFORGE 1TOPS — Low-Level Trap Entry & Context Dispatcher (trap_entry.S)
 * =============================================================================
 * Direct-mode trap vector.
 * - Interrupts (mcause[31]=1): saves caller-saved context, dispatches to C ISR,
 *   restores frame, executes mret.
 * - Exceptions (mcause[31]=0): isolates fault, records signature, calls C
 *   exception handler, unconditionally halts (prevents infinite fault loop).
 * ============================================================================= */

  .section .text.trap, "ax"
  .align 4
  .global trap_entry
  .type trap_entry, @function

trap_entry:
  /* Allocate 64 bytes on stack (16 words, preserving 16-byte alignment) */
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

  /* Read trap cause and faulting program counter */
  csrr a0, mcause
  csrr a1, mepc

  /* Check Bit 31: 1 = Interrupt, 0 = Synchronous Exception */
  bgez a0, .Lhandle_sync_exception

  /* -------------------------------------------------------------------------
   * Asynchronous Interrupt Path
   * ------------------------------------------------------------------------- */
  /* Clear bit 31 to isolate cause ID (e.g. 7 for MTIP, 16..27 for peripherals) */
  slli a0, a0, 1
  srli a0, a0, 1

  /* Invoke C ISR dispatcher: void c_trap_handler(uint32_t cause, uint32_t epc) */
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

  /* Return from interrupt */
  mret

  /* -------------------------------------------------------------------------
   * Synchronous Exception Path (Fault / Error Isolation)
   * ------------------------------------------------------------------------- */
.Lhandle_sync_exception:
  /* Ensure interrupts are disabled */
  csrci mstatus, 0x8

  /* Record fault signatures to dedicated observation memory */
  la t0, _trap_sig_cause
  sw a0, 0(t0)
  la t0, _trap_sig_epc
  sw a1, 0(t0)

  /* Call C exception reporter: void c_exception_handler(uint32_t cause, uint32_t epc) */
  call c_exception_handler

  /* Unconditional deterministic halt: NEVER mret into faulting instruction */
.Lsync_halt:
  csrci mstatus, 0x8
  wfi
  j .Lsync_halt

  .size trap_entry, . - trap_entry
