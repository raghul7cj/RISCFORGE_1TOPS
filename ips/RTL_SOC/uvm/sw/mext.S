#include "common.h"

.section .text.init
.globl _start
_start:
  li   a0, 7
  li   a1, -3
  mul  a2, a0, a1
  CHECK a2, -21, 1

  li   a0, 0x80000000
  li   a1, 2
  mulh a2, a0, a1
  CHECK a2, 0xFFFFFFFF, 2
  mulhu a2, a0, a1
  CHECK a2, 1, 3
  mulhsu a2, a0, a1
  CHECK a2, 0xFFFFFFFF, 4

  li   a0, -20
  li   a1, 3
  div  a2, a0, a1
  CHECK a2, -6, 5
  rem  a2, a0, a1
  CHECK a2, -2, 6
  divu a2, a0, a1
  CHECK a2, 0x5555554E, 7
  remu a2, a0, a1
  CHECK a2, 2, 8

  li   a1, 0
  div  a2, a0, a1
  CHECK a2, -1, 9
  rem  a2, a0, a1
  CHECK a2, -20, 10
  divu a2, a0, a1
  CHECK a2, 0xFFFFFFFF, 11
  remu a2, a0, a1
  CHECK a2, -20, 12

  li   a0, 0x80000000
  li   a1, -1
  div  a2, a0, a1
  CHECK a2, 0x80000000, 13
  rem  a2, a0, a1
  CHECK a2, 0, 14
  PASS
