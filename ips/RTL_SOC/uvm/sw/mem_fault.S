#include "common.h"

.macro EXPECT_TRAP n, cause, code
  CHECK s2, \n, \code
  CHECK s3, \cause, \code
  CHECKR s5, s4, \code
.endm

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s2, 0

  li   s4, DSRAM_BASE + 0x302
  lw   a0, 0(s4)
  EXPECT_TRAP 1, 4, 1

  sw   a0, 0(s4)
  EXPECT_TRAP 2, 6, 2

  li   s4, DSRAM_BASE + 0x301
  lh   a0, 0(s4)
  EXPECT_TRAP 3, 4, 3

  li   s4, 0x00010000
  lw   a0, 0(s4)
  EXPECT_TRAP 4, 5, 4

  li   s4, 0x30000000
  sw   a0, 0(s4)
  EXPECT_TRAP 5, 7, 5

  li   s4, 0x40006000
  lw   a0, 0(s4)
  EXPECT_TRAP 6, 5, 6

  li   s4, 0x00010000
  sw   a0, 0(s4)
  EXPECT_TRAP 7, 7, 7

  li   s4, DSRAM_BASE + 0x300
  li   a0, 0x5A5A1234
  sw   a0, 0(s4)
  lw   a1, 0(s4)
  CHECK a1, 0x5A5A1234, 8
  CHECK s2, 7, 9
  PASS

.align 2
handler:
  csrr s3, mcause
  csrr s5, mtval
  addi s2, s2, 1
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret
