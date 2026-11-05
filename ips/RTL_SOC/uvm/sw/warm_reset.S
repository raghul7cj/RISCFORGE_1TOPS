#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, DSRAM_BASE + 0x400
  li   s2, 0xC0FFEE11
  lw   t2, 0(s1)
  beq  t2, s2, second_run
  sw   s2, 0(s1)
  li   t2, 0x600DF00D
  sw   t2, 4(s1)
  PHASE 1
idle:
  j    idle

second_run:
  lw   t2, 4(s1)
  CHECK t2, 0x600DF00D, 1
  PASS
