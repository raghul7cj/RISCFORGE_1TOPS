    .option norvc
    .option norelax
    .section .text
    .globl _start, done
_start:
    lui s0,0x80001
    la t0,handler
    csrw mtvec,t0
    ecall
    nop
    ebreak
    nop
    .word 0xffffffff
    nop
    lw t1,1(s0)
    nop
    sw t1,1(s0)
    nop
    addi t0,zero,11
    sw t0,0(s0)
    lw t2,0(s0)
done:
    nop
    j done
handler:
    csrr t0,mepc
    addi t0,t0,4
    csrw mepc,t0
    mret
