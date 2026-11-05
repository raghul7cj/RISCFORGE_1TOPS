#include "common.h"

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   s2, 0

  ecall
  CHECK s2, 1, 1
  CHECK s3, 11, 2

  .word 0x00000000
  CHECK s2, 2, 3
  CHECK s3, 2, 4

  ebreak
  CHECK s2, 3, 5
  CHECK s3, 3, 6
  PASS

.align 2
handler:
  csrr s3, mcause
  addi s2, s2, 1
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret
