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

  li   t1, 1
  li   t3, 2
  li   t4, 3
  sw   t1, TIMER_CMP(s0)
  sw   t3, TIMER_VAL(s0)
  sw   t4, TIMER_CMP(s0)
  sw   t1, TIMER_VAL(s0)
  sw   t3, TIMER_CMP(s0)
  sw   t4, TIMER_VAL(s0)
  lw   t2, TIMER_CMP(s0)
  CHECK t2, 2, 5
  lw   t2, TIMER_VAL(s0)
  CHECK t2, 3, 6
  sw   t1, TIMER_CMP(s0)
  lw   t2, TIMER_CMP(s0)
  sw   t2, TIMER_VAL(s0)
  lw   t3, TIMER_VAL(s0)
  CHECK t3, 1, 7
  li   t1, 0x3C
  sw   t1, TIMER_CMP(s0)
  addi t3, zero, 7
  CHECK t3, 7, 4

  li   t1, 0x0A0A0A0A
  li   t3, 0x0B0B0B0B
  sw   t1, 8(s1)
  sw   t3, 12(s1)
  lw   a1, 8(s1)
  lw   a2, 12(s1)
  addi t5, zero, 12
  CHECK a1, 0x0A0A0A0A, 8
  CHECK a2, 0x0B0B0B0B, 9
  CHECK t5, 12, 10

  mv   s2, s1
  sw   t3, 16(s2)
  sw   t1, 20(s2)
  lw   s3, 20(s2)
  lw   s4, 16(s2)
  addi s2, s2, 20
  CHECK s3, 0x0A0A0A0A, 11
  CHECK s4, 0x0B0B0B0B, 12
  li   t6, DSRAM_BASE + 0x214
  CHECKR s2, t6, 13

  lw   a3, 8(s1)
  lw   a4, 12(s1)
  add  a5, a4, a3
  CHECK a5, 0x15151515, 14

  li   s5, 0
  sw   t1, TIMER_CMP(s0)
  jal  ra, bump
  CHECK s5, 1, 15
  lw   t2, TIMER_CMP(s0)
  jal  ra, bump
  CHECK s5, 2, 16
  lw   t2, 8(s1)
  jal  ra, bump
  CHECK s5, 3, 17
  sw   t1, 8(s1)
  jal  ra, bump
  CHECK s5, 4, 18
  lw   t2, 8(s1)
  la   t3, bump
  lw   t2, 8(s1)
  jalr ra, 0(t3)
  CHECK s5, 5, 19
  lw   t2, 8(s1)
  beq  zero, zero, 3f
  li   s5, 99
3:
  CHECK s5, 5, 20
  PASS

bump:
  addi s5, s5, 1
  ret
