#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, DSRAM_BASE

  li   t0, 0x12345678
  sw   t0, 0(s1)
  lw   t1, 0(s1)
  CHECK t1, 0x12345678, 1

  sw   zero, 4(s1)
  li   t0, 0xAB
  sb   t0, 5(s1)
  lw   t1, 4(s1)
  CHECK t1, 0x0000AB00, 2
  lb   t1, 5(s1)
  CHECK t1, 0xFFFFFFAB, 3
  lbu  t1, 5(s1)
  CHECK t1, 0xAB, 4

  sw   zero, 8(s1)
  li   t0, 0x8001
  sh   t0, 10(s1)
  lw   t1, 8(s1)
  CHECK t1, 0x80010000, 5
  lh   t1, 10(s1)
  CHECK t1, 0xFFFF8001, 6
  lhu  t1, 10(s1)
  CHECK t1, 0x8001, 7

  addi s2, s1, 0x100
  li   s3, 0
  li   s4, 64
3:
  slli t0, s3, 2
  add  t1, s2, t0
  sw   s3, 0(t1)
  addi s3, s3, 1
  bne  s3, s4, 3b

  li   s3, 0
  li   s5, 0
4:
  slli t0, s3, 2
  add  t1, s2, t0
  lw   t2, 0(t1)
  add  s5, s5, t2
  addi s3, s3, 1
  bne  s3, s4, 4b
  CHECK s5, 2016, 8
  PASS
