#include "common.h"

.macro BAD word, code
  li   s2, 0
  li   s3, 0
  li   s4, 0
  .word \word
  CHECK s2, 1, \code
  CHECK s3, 2, \code
  li   t6, \word
  CHECKR s4, t6, \code
.endm

.macro GOOD code
  CHECK s2, 0, \code
.endm

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0

  BAD  0x00029067, 1
  BAD  0x00002463, 2
  BAD  0x00003463, 3
  BAD  0x0002b283, 4
  BAD  0x0002e283, 5
  BAD  0x0052b023, 6
  BAD  0x0052c023, 7
  BAD  0x02029293, 8
  BAD  0x60105293, 9
  BAD  0x0402d293, 10
  BAD  0x4052e2b3, 11
  BAD  0x0852c2b3, 12
  BAD  0x0000200f, 13
  BAD  0x00004073, 14
  BAD  0x10200073, 15
  BAD  0x00200073, 16
  BAD  0x00000f73, 17

  li   s2, 0
  wfi
  fence
  fence.i
  csrrs x0, mstatus, x0
  add  t0, t1, t2
  sub  t0, t1, t2
  sra  t0, t1, t2
  mul  t0, t1, t2
  srai t0, t1, 3
  slli t0, t1, 31
  GOOD 18

  li   t0, 0x00010003
  csrw mepc, t0
  csrr t1, mepc
  CHECK t1, 0x00010000, 19
  PASS

.align 2
handler:
  addi s2, s2, 1
  csrr s3, mcause
  csrr s4, mtval
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret
