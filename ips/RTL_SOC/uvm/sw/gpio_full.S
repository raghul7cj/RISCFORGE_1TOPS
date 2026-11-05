#include "common.h"

.section .text.init
.globl _start
_start:
  li   s1, GPIO_BASE
  lw   t2, GPIO_INFO(s1)
  andi t2, t2, 0x3FF
  CHECK t2, 32, 1
  li   t1, 0x55555555
  sw   t1, GPIO_MODE0(s1)
  li   t1, 0xFFFFAAAA
  sw   t1, GPIO_MODE1(s1)
  lw   t2, GPIO_MODE1(s1)
  CHECK t2, 0xFFFFAAAA, 2
  li   t1, -1
  sw   t1, GPIO_EN(s1)

  li   t1, 0x1234
  sw   t1, GPIO_OUT(s1)
  lw   t2, GPIO_OUT(s1)
  CHECK t2, 0x1234, 3
  li   t1, 0x00FF0000
  sw   t1, GPIO_SET(s1)
  lw   t2, GPIO_OUT(s1)
  CHECK t2, 0x00FF1234, 4
  li   t1, 0x4
  sw   t1, GPIO_CLEAR(s1)
  lw   t2, GPIO_OUT(s1)
  CHECK t2, 0x00FF1230, 5
  li   t1, 0xFF000001
  sw   t1, GPIO_TOGGLE(s1)
  lw   t2, GPIO_OUT(s1)
  CHECK t2, 0xFFFF1231, 6
  PHASE 1
  DELAY 200

  sw   zero, GPIO_MODE0(s1)
  sw   zero, GPIO_MODE1(s1)
  sw   zero, GPIO_OUT(s1)
  PHASE 2
  DELAY 200
  lw   t2, GPIO_IN(s1)
  CHECK t2, 0xA5C30F96, 7
  PHASE 3
  DELAY 200
  lw   t2, GPIO_IN(s1)
  CHECK t2, 0x5A3CF069, 8

  li   t1, 1
  sw   t1, GPIO_CFG(s1)
  PHASE 4
  DELAY 200
  li   t1, -1
  sw   t1, GPIO_RISE_STS(s1)
  sw   t1, GPIO_FALL_STS(s1)
  sw   t1, GPIO_INT_STS(s1)
  li   t1, 1
  sw   t1, GPIO_RISE_EN(s1)
  li   t1, 2
  sw   t1, GPIO_FALL_EN(s1)
  li   t1, 4
  sw   t1, GPIO_LVLH_EN(s1)
  li   t1, 8
  sw   t1, GPIO_LVLL_EN(s1)
  DELAY 20
  lw   t2, GPIO_LVLL_STS(s1)
  andi t2, t2, 8
  CHECK t2, 8, 9
  sw   zero, GPIO_LVLL_EN(s1)
  li   t1, -1
  sw   t1, GPIO_INT_STS(s1)

  PHASE 5
  DELAY 200
  lw   t2, GPIO_RISE_STS(s1)
  andi t2, t2, 1
  CHECK t2, 1, 10
  lw   t2, GPIO_FALL_STS(s1)
  andi t2, t2, 2
  CHECK t2, 2, 11
  lw   t2, GPIO_LVLH_STS(s1)
  andi t2, t2, 4
  CHECK t2, 4, 12
  lw   t2, GPIO_INT_STS(s1)
  andi t2, t2, 7
  CHECK t2, 7, 13
  sw   zero, GPIO_RISE_EN(s1)
  sw   zero, GPIO_FALL_EN(s1)
  sw   zero, GPIO_LVLH_EN(s1)
  li   t1, -1
  sw   t1, GPIO_RISE_STS(s1)
  sw   t1, GPIO_FALL_STS(s1)
  sw   t1, GPIO_INT_STS(s1)
  lw   t2, GPIO_INT_STS(s1)
  CHECK t2, 0, 14

  sw   zero, GPIO_CFG(s1)
  li   t1, -1
  sw   t1, GPIO_RISE_EN(s1)
  sw   t1, GPIO_FALL_EN(s1)
  PHASE 6
  DELAY 200
  lw   t2, GPIO_RISE_STS(s1)
  CHECK t2, 0xFFFFFFFA, 15
  li   t1, -1
  sw   t1, GPIO_RISE_STS(s1)
  sw   t1, GPIO_INT_STS(s1)
  sw   t1, GPIO_LVLH_EN(s1)
  DELAY 20
  lw   t2, GPIO_LVLH_STS(s1)
  CHECK t2, 0xFFFFFFFF, 16
  sw   zero, GPIO_LVLH_EN(s1)
  PHASE 7
  DELAY 200
  lw   t2, GPIO_FALL_STS(s1)
  CHECK t2, 0xFFFFFFFF, 17
  li   t1, -1
  sw   t1, GPIO_LVLL_EN(s1)
  DELAY 20
  lw   t2, GPIO_LVLL_STS(s1)
  CHECK t2, 0xFFFFFFFF, 18
  sw   zero, GPIO_RISE_EN(s1)
  sw   zero, GPIO_FALL_EN(s1)
  sw   zero, GPIO_LVLL_EN(s1)
  li   t1, -1
  sw   t1, GPIO_RISE_STS(s1)
  sw   t1, GPIO_FALL_STS(s1)
  sw   t1, GPIO_INT_STS(s1)
  lw   t2, GPIO_INT_STS(s1)
  CHECK t2, 0, 19
  PASS
