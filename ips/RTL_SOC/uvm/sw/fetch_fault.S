#include "common.h"

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s2, 0
  la   s4, back
  li   t1, 0x30000000
  jalr ra, 0(t1)
back:
  CHECK s2, 1, 1
  CHECK s3, 1, 2
  CHECK s5, 0x30000000, 3
  CHECK s6, 0x30000000, 4
  la   s4, back2
  li   t1, 0x00020000
  jr   t1
back2:
  CHECK s2, 2, 5
  CHECK s3, 1, 6
  CHECK s5, 0x00020000, 7
  PASS

.align 2
handler:
  csrr s3, mcause
  csrr s5, mtval
  csrr s6, mepc
  addi s2, s2, 1
  csrw mepc, s4
  mret
