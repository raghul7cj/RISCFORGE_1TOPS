/* =============================================================================
 * RISCFORGE 1TOPS — Assembly Datapath Smoke Test
 * ============================================================================= */

  .section .text.init, "ax"
  .global _start
  .type _start, @function

_start:
  /* Write signature into x10 and x11 */
  lui x10, 0xCAFEB
  addi x10, x10, -1346  /* 0xCAFE_BABE */
  li  x11, 1

  /* Store to DSRAM base */
  lui x12, 0x00020
  sw  x10, 0(x12)
  sw  x11, 4(x12)

.Ldone:
  wfi
  j .Ldone

  .size _start, . - _start
