#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, DSRAM_BASE + 8
  li   s2, DSRAM_BASE + 0x8000

  mv   t2, s1
fill:
  sw   t2, 0(t2)
  addi t2, t2, 4
  bne  t2, s2, fill

  mv   t2, s1
check_addr:
  lw   t3, 0(t2)
  bne  t3, t2, bad_addr
  not  t4, t2
  sw   t4, 0(t2)
  addi t2, t2, 4
  bne  t2, s2, check_addr

  mv   t2, s1
check_inv:
  lw   t3, 0(t2)
  not  t4, t2
  bne  t3, t4, bad_inv
  addi t2, t2, 4
  bne  t2, s2, check_inv

  li   t2, 1
walk:
  sw   t2, 0(s1)
  lw   t3, 0(s1)
  bne  t2, t3, bad_walk
  slli t2, t2, 1
  bnez t2, walk
  PASS

bad_addr:
  FAIL 1
bad_inv:
  FAIL 2
bad_walk:
  FAIL 3
