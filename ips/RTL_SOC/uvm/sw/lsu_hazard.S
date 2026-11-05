#include "common.h"

.section .text.init
.globl _start
_start:
  li   s0, TIMER1_BASE
  li   s1, DSRAM_BASE + 0x200
  sw   zero, TIMER_CTRL(s0)

  li   t1, 0x1234565A
  sw   t1, TIMER_CMP(s0)
  lw   t2, TIMER_CMP(s0)
  addi t2, t2, 1
  CHECK t2, 0x1234565B, 1

  li   t1, 0x00A5A5A5
  sw   t1, TIMER_CMP(s0)
  lw   t2, TIMER_CMP(s0)
  addi t2, t2, 1
  CHECK t2, 0x00A5A5A6, 2

  li   t1, 0x11223344
  sw   t1, 0(s1)
  lw   t2, 0(s1)
  addi t2, t2, 1
  CHECK t2, 0x11223345, 3

  li   t1, 0x3C
  sw   t1, TIMER_CMP(s0)
  addi t3, zero, 7
  CHECK t3, 7, 4
  PASS
