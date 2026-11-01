/* =============================================================================
 * RISCFORGE 1TOPS — Canonical C Runtime Startup (crt0.S)
 * =============================================================================
 * Executed at ISRAM base (0x0001_0000) after BootROM jump.
 * Hardware bootloader / testbench preloader has populated ISRAM & DSRAM.
 * ============================================================================= */

  .section .text.init, "ax"
  .global _start
  .type _start, @function

_start:
  /* 1. Disable interrupts globally during boot sequence */
  csrci mstatus, 0x8

  /* 2. Initialize Global Pointer (gp) with relaxation explicitly disabled */
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop

  /* 3. Initialize Stack Pointer (sp) to 16-byte aligned DSRAM top */
  la sp, _stack_top

  /* 4. Zero General-Purpose Registers */
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

  /* 5. Zero .bss and .sbss section in DSRAM */
  la a0, _sbss
  la a1, _ebss
  bge a0, a1, .Lzero_bss_done
.Lzero_bss_loop:
  sw zero, 0(a0)
  addi a0, a0, 4
  blt a0, a1, .Lzero_bss_loop
.Lzero_bss_done:

  /* 6. Install direct-mode trap vector (mtvec[1:0] = 00) */
  la a0, trap_entry
  csrw mtvec, a0

  /* 7. Initialize custom priority threshold CSR mintprio (0x7C0) to 0 (allow all) */
  csrw 0x7C0, zero

  /* 8. Call main() */
  call main

  /* 9. Clean halt on return from main() */
_exit:
  csrci mstatus, 0x8
.Lhalt_loop:
  wfi
  j .Lhalt_loop

  .size _start, . - _start
