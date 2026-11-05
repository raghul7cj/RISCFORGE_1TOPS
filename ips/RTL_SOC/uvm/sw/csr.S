#include "common.h"

.section .text.init
.globl _start
_start:
  la   t1, handler
  csrw mtvec, t1
  csrr t2, mtvec
  CHECKR t1, t2, 1

  li   t1, 0x12340
  csrw mepc, t1
  csrr t2, mepc
  CHECK t2, 0x12340, 2
  li   t1, 0x1F
  csrw mcause, t1
  csrr t2, mcause
  CHECK t2, 0x1F, 3
  li   t1, 0xDEADBEEF
  csrw mtval, t1
  csrr t2, mtval
  CHECK t2, 0xDEADBEEF, 4

  li   t1, 0x888
  csrw mie, t1
  csrr t2, mie
  CHECK t2, 0x888, 5
  csrw mie, zero

  csrsi mstatus, 8
  csrr t2, mstatus
  andi t2, t2, 8
  CHECK t2, 8, 6
  csrci mstatus, 8
  csrr t2, mstatus
  andi t2, t2, 8
  CHECK t2, 0, 7

  csrr t2, mip
  CHECK t2, 0, 8

  csrr s2, mcycle
  csrr s3, minstret
  nop
  nop
  nop
  csrr s4, mcycle
  csrr s5, minstret
  bleu s4, s2, bad_cnt
  bleu s5, s3, bad_cnt
  csrr t2, mcycleh
  csrr t2, minstreth

  li   t1, 0x80
  csrs mstatus, t1
  la   t1, after_mret
  csrw mepc, t1
  mret
  FAIL 10
after_mret:
  csrr t2, mstatus
  andi t2, t2, 8
  CHECK t2, 8, 11
  csrci mstatus, 8
  PASS

bad_cnt:
  FAIL 9

.align 2
handler:
  FAIL 12
