/* =============================================================================
 * RISCFORGE 1TOPS — Bare-Metal C Runtime Startup (crt0.s)
 * ============================================================================= */

  .section .text.init, "ax"
  .global _start
  .type _start, @function

_start:
  /* 1. Disable interrupts globally during boot */
  csrci mstatus, 0x8

  /* 2. Initialize Stack Pointer (sp) and Global Pointer (gp) */
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la sp, _stack_top

  /* 3. Zero General-Purpose Registers */
  li x1,  0
  li x4,  0
  li x5,  0
  li x6,  0
  li x7,  0
  li x8,  0
  li x9,  0
  li x10, 0
  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  /* 4. Zero .bss section in DSRAM */
  la a0, _sbss
  la a1, _ebss
  bge a0, a1, .Lzero_bss_done
.Lzero_bss_loop:
  sw zero, 0(a0)
  addi a0, a0, 4
  blt a0, a1, .Lzero_bss_loop
.Lzero_bss_done:

  /* 5. Set mtvec to default trap_entry */
  la a0, trap_entry
  csrw mtvec, a0

  /* 6. Clear mie. A stray reset-domain IRQ line that is already asserted at
   *    the first instruction boundary would otherwise trap us before main().
   *    Each stage enables the sources it wants explicitly.
   *    NOTE: the previous "csrw 0x7C0, zero" here was a boot-stopper — CSR
   *    0x7C0 (mintprio) is not implemented in csr_regfile.v, so the write
   *    took an illegal-instruction trap and no stage ever reached main(). */
  csrw mie, zero
  csrw mip, zero

  /* 7. Jump to main */
  call main

  /* 8. If main returns, handle exit code */
  beqz a0, .Lmain_pass
  /* Fail with error code in a0 */
  li a1, 0x00020000       /* Mailbox base */
  sw a0, 24(a1)           /* error_code */
  li a2, 2                /* CMD_FAIL */
  sw a2, 0(a1)
  j .Lhalt

.Lmain_pass:
  li a1, 0x00020000       /* Mailbox base */
  li a2, 1                /* CMD_PASS */
  sw a2, 0(a1)

.Lhalt:
  wfi
  j .Lhalt

  .size _start, . - _start
