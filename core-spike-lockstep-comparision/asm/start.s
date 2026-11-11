/* ========================================================================= */
/* File:    start.s                                                          */
/* Purpose: Bare-metal startup code, stack init, and reset entry point       */
/* ========================================================================= */

    .section .text.init, "ax", @progbits
    .align 2
    .globl _start
    .type  _start, @function

_start:
    /* Disable interrupts */
    .option push
    .option arch, +zicsr
    csrw mie, zero
    .option pop

    /* Setup stack pointer */
    la   sp, _stack_top

    /* Jump to C entry point */
    call main

    /* Write 1 to tohost: tells Spike ISS the test PASSED and stops simulation */
    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)

    /* Park CPU if main returns */
1:  wfi
    j 1b

    .size _start, . - _start

/* HTIF symbols required by Spike ISS for test completion signaling */
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0

    .align 6
    .globl fromhost
fromhost:
    .dword 0
