	.file	"baremetal_helloworld.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zicsr2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.globl	sim_buffer
	.bss
	.align	2
	.type	sim_buffer, @object
	.size	sim_buffer, 64
sim_buffer:
	.zero	64
	.globl	idx
	.section	.sbss,"aw",@nobits
	.align	2
	.type	idx, @object
	.size	idx, 4
idx:
	.zero	4
	.text
	.align	2
	.globl	print_sim
	.type	print_sim, @function
print_sim:
	addi	sp,sp,-32
	sw	s0,28(sp)
	addi	s0,sp,32
	sw	a0,-20(s0)
	j	.L2
.L3:
	lw	a4,-20(s0)
	addi	a5,a4,1
	sw	a5,-20(s0)
	lui	a5,%hi(idx)
	lw	a5,%lo(idx)(a5)
	addi	a2,a5,1
	lui	a3,%hi(idx)
	sw	a2,%lo(idx)(a3)
	lbu	a4,0(a4)
	lui	a3,%hi(sim_buffer)
	addi	a3,a3,%lo(sim_buffer)
	add	a5,a3,a5
	sb	a4,0(a5)
.L2:
	lw	a5,-20(s0)
	lbu	a5,0(a5)
	bne	a5,zero,.L3
	nop
	nop
	lw	s0,28(sp)
	addi	sp,sp,32
	jr	ra
	.size	print_sim, .-print_sim
	.section	.rodata
	.align	2
.LC0:
	.string	"hello world !\n"
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	sw	s0,8(sp)
	addi	s0,sp,16
	lui	a5,%hi(.LC0)
	addi	a0,a5,%lo(.LC0)
	call	print_sim
	li	a5,0
	mv	a0,a5
	lw	ra,12(sp)
	lw	s0,8(sp)
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
