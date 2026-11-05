#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, GPIO_BASE
  li   t0, 0x55555555
  sw   t0, GPIO_MODE0(s1)
  sw   zero, GPIO_MODE1(s1)
  li   t0, -1
  sw   t0, GPIO_EN(s1)
  li   t0, 0xA5A5
  sw   t0, GPIO_OUT(s1)
  DELAY 50
  lw   t1, GPIO_IN(s1)
  srli t1, t1, 16
  CHECK t1, 0x5A5A, 1
  PASS
