#include "common.h"

.macro EXPECT_TRAP n, cause, addr, code
  CHECK s2, \n, \code
  CHECK s3, \cause, \code
  CHECK s5, \addr, \code
.endm

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s2, 0
  li   s1, TIMER_BASE
  li   s9, TIMER1_BASE

  PHASE 1
  DELAY 50
  lw   a0, TIMER_VAL(s1)
  EXPECT_TRAP 1, 5, TIMER_BASE, 1
  sw   a0, TIMER_CMP(s1)
  EXPECT_TRAP 2, 7, TIMER_BASE + 8, 2

  PHASE 2
  DELAY 50
  li   t1, 0x77
  sw   t1, TIMER_CMP(s1)
  lw   t2, TIMER_CMP(s1)
  CHECK t2, 0x77, 3
  CHECK s2, 2, 4

  PHASE 3
  DELAY 50
  lw   a0, TIMER_VAL(s9)
  EXPECT_TRAP 3, 5, TIMER1_BASE, 5

  PHASE 4
  DELAY 200
  li   t1, 0x99
  sw   t1, TIMER_CMP(s9)
  lw   t2, TIMER_CMP(s9)
  CHECK t2, 0x99, 6
  CHECK s2, 3, 7
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
