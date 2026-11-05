#include "common.h"

.section .text.init
.globl _start
_start:
  li   a0, 0x7FFFFFFF
  li   a1, 1
  add  a2, a0, a1
  CHECK a2, 0x80000000, 1
  sub  a2, a1, a0
  CHECK a2, 0x80000002, 2
  addi a2, a0, -1
  CHECK a2, 0x7FFFFFFE, 3

  li   a0, 0xF0F0F0F0
  li   a1, 0x0FF00FF0
  and  a2, a0, a1
  CHECK a2, 0x00F000F0, 4
  or   a2, a0, a1
  CHECK a2, 0xFFF0FFF0, 5
  xor  a2, a0, a1
  CHECK a2, 0xFF00FF00, 6
  andi a2, a0, 0xFF
  CHECK a2, 0xF0, 7
  ori  a2, a0, 0x0F
  CHECK a2, 0xF0F0F0FF, 8
  xori a2, a0, -1
  CHECK a2, 0x0F0F0F0F, 9

  li   a0, 0x80000001
  li   a1, 4
  sll  a2, a0, a1
  CHECK a2, 0x00000010, 10
  srl  a2, a0, a1
  CHECK a2, 0x08000000, 11
  sra  a2, a0, a1
  CHECK a2, 0xF8000000, 12
  slli a2, a0, 31
  CHECK a2, 0x80000000, 13
  srli a2, a0, 31
  CHECK a2, 1, 14
  srai a2, a0, 31
  CHECK a2, 0xFFFFFFFF, 15

  li   a0, -1
  li   a1, 1
  slt  a2, a0, a1
  CHECK a2, 1, 16
  sltu a2, a0, a1
  CHECK a2, 0, 17
  slti a2, a0, 0
  CHECK a2, 1, 18
  sltiu a2, a1, 2
  CHECK a2, 1, 19
  sltiu a2, a0, 1
  CHECK a2, 0, 20

  lui  a2, 0x12345
  CHECK a2, 0x12345000, 21
here:
  auipc a2, 0
  la   a3, here
  CHECKR a2, a3, 22

  addi x0, x0, 5
  CHECK x0, 0, 23

  li   a0, -1
  li   a1, 1
  beq  a0, a1, bad_branch
  bne  a0, a1, b1
  j    bad_branch
b1:
  blt  a0, a1, b2
  j    bad_branch
b2:
  bge  a1, a0, b3
  j    bad_branch
b3:
  bltu a1, a0, b4
  j    bad_branch
b4:
  bgeu a0, a1, b5
  j    bad_branch
b5:
  bge  a0, a1, bad_branch
  bltu a0, a1, bad_branch
  j    jumps
bad_branch:
  FAIL 24

jumps:
  jal  ra, func
ret_here:
  la   a3, ret_here
  CHECKR ra, a3, 25
  CHECK s7, 0x55, 26
  la   t2, func2
  jalr ra, 4(t2)
ret_here2:
  la   a3, ret_here2
  CHECKR ra, a3, 27
  CHECK s7, 0x66, 28

  li   a0, 0x12345678
  csrw mscratch, a0
  csrr a2, mscratch
  CHECK a2, 0x12345678, 29
  li   a1, 0xF
  csrrs a2, mscratch, a1
  CHECK a2, 0x12345678, 30
  csrr a2, mscratch
  CHECK a2, 0x1234567F, 31
  li   a1, 0xF0
  csrrc a2, mscratch, a1
  csrr a2, mscratch
  CHECK a2, 0x1234560F, 32
  csrrwi a2, mscratch, 5
  CHECK a2, 0x1234560F, 33
  csrrsi a2, mscratch, 0x18
  csrr a2, mscratch
  CHECK a2, 0x1D, 34
  csrrci a2, mscratch, 0x5
  csrr a2, mscratch
  CHECK a2, 0x18, 35
  PASS

func:
  li   s7, 0x55
  ret
func2:
  li   s7, 0x11
  li   s7, 0x66
  ret
