    .option norvc
    .option norelax
    .section .text
    .globl _start, wrong_path, target, fault, resume, loop, done, handler, handler_end
_start:
    lui s0,0x80001
    addi t0,zero,5
    sw t0,0(s0)
    nop
    nop
    nop
    lw t1,0(s0)
    addi t2,zero,7
    lw t3,0(s0)
    nop
    addi t4,zero,9
    jal zero,target
wrong_path:
    addi s1,zero,99
    nop
target:
    la t0,handler
    csrw mtvec,t0
fault:
    ecall
resume:
    nop
    addi t5,zero,3
loop:
    addi t5,t5,-1
    bne t5,zero,loop
    nop
done:
    nop
    j done
handler:
    csrr t0,mepc
    addi t0,t0,4
    csrw mepc,t0
    mret
handler_end:
