#include "common.h"

.equ CH1, 0x10

.section .text.init
.globl _start
_start:
  li   s1, TIMER_BASE
  sw   zero, TIMER_CTRL(s1)

  li   t1, 0xCAFE0001
  sw   t1, TIMER_VAL(s1)
  lw   t2, TIMER_VAL(s1)
  CHECK t2, 0xCAFE0001, 1
  li   t1, 0x55AA
  sw   t1, TIMER_CMP(s1)
  lw   t2, TIMER_CMP(s1)
  CHECK t2, 0x55AA, 2
  li   t1, 0x28
  sw   t1, TIMER_CTRL(s1)
  lw   t2, TIMER_CTRL(s1)
  CHECK t2, 0x28, 3

  sw   zero, TIMER_VAL(s1)
  sw   zero, TIMER_CMP(s1)
  li   t1, 0x29
  sw   t1, TIMER_CTRL(s1)
  DELAY 60
  sw   zero, TIMER_CTRL(s1)
  lw   s2, TIMER_VAL(s1)
  beqz s2, bad_pre
  li   t1, 100
  bgeu s2, t1, bad_pre

  li   t1, 0xFFFFFFF0
  sw   t1, TIMER_VAL(s1)
  li   t1, 1
  sw   t1, TIMER_CTRL(s1)
  DELAY 20
  sw   zero, TIMER_CTRL(s1)
  lw   t2, TIMER_VAL(s1)
  li   t1, 0x100
  bgeu t2, t1, bad_wrap

  sw   zero, CH1+TIMER_CTRL(s1)
  sw   zero, CH1+TIMER_VAL(s1)
  li   t1, 50
  sw   t1, CH1+TIMER_CMP(s1)
  lw   t2, CH1+TIMER_CMP(s1)
  CHECK t2, 50, 6
  li   t1, 1
  sw   t1, CH1+TIMER_CTRL(s1)
  DELAY 100
  sw   zero, CH1+TIMER_CTRL(s1)
  PASS

bad_pre:
  FAIL 4
bad_wrap:
  FAIL 5
