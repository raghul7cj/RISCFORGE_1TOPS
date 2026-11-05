#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, TIMER_BASE
  sw   zero, TIMER_CTRL(s1)
  sw   zero, TIMER_VAL(s1)
  li   t0, 100
  sw   t0, TIMER_CMP(s1)
  li   t0, 1
  sw   t0, TIMER_CTRL(s1)
  lw   s2, TIMER_VAL(s1)
  DELAY 20
  lw   s3, TIMER_VAL(s1)
  bgtu s3, s2, 3f
  FAIL 1
3:
  li   s1, TIMER1_BASE
  sw   zero, TIMER_CTRL(s1)
  sw   zero, TIMER_VAL(s1)
  li   t0, 80
  sw   t0, TIMER_CMP(s1)
  li   t0, 1
  sw   t0, TIMER_CTRL(s1)
  DELAY 300
  PASS
