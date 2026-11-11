    .option norvc
    .option norelax
    .section .text
    .globl _start, done, irq_trigger, irq_end, handler, handler_end
_start:
    la t0,handler
    csrw mtvec,t0
    addi t0,zero,128
    csrw mie,t0
    csrsi mstatus,8
    nop
    nop
irq_trigger:
    .rept 32
    nop
    .endr
irq_end:
    addi s0,zero,13
done:
    nop
    j done
handler:
    csrw mie,zero
    mret
handler_end:
