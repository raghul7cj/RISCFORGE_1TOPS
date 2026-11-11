    .option norvc
    .option norelax
    .section .text
    .globl _start, done, poison0, poison1, poison2
_start:
    lui s0,0x80001
    addi t0,zero,21
    addi t1,zero,3
    add t2,t0,t1
    sub t3,t0,t1
    mul t4,t0,t1
    div t5,t0,t1
    nop
    sw t5,0(s0)
    lw s1,0(s0)
    nop
    addi s2,zero,7
    beq s1,s2,equal
poison0:
    .word 0xffffffff
equal:
    beq t0,t1,poison0
    bne t0,t1,unequal
poison1:
    .word 0xffffffff
unequal:
    bne s1,s2,poison1
    jal ra,jump_target
poison2:
    .word 0xffffffff
jump_target:
    la t0,indirect_target
    jalr ra,t0,0
    .word 0xffffffff
indirect_target:
    addi t0,zero,5
    csrrw t1,mscratch,t0
    csrrs t2,mscratch,t0
    csrrc t3,mscratch,t0
    csrrwi t4,mscratch,3
    csrrsi t5,mscratch,4
    csrrci t6,mscratch,1
    csrr s3,minstret
    sw s1,4(s0)
    nop
done:
    nop
    j done
