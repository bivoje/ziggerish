	.file	"dull_rot25.c"
	# gen by `gcc -O1 -S dull_rot25.c -nostdlib -m64`
	# then manually edited, use followings to compile
	# as dull_rot25.s -o dull_rot25.o
	# ld dull_rot25.o -o dull_rot25

	.ident	"GCC: (Alpine 10.2.1_pre1) 10.2.1 20201203"
	# https://wiki.gentoo.org/wiki/Hardened/GNU_stack_quickstart
	.section	.note.GNU-stack,"",@progbits

	.bss
	.align 32
buf:
	.zero	1000

	.text

	.globl	_start
_start:
	jmp	main

intputchar:
	movl	$1, %eax
	movl	%eax, %edi
	syscall
	ret

intgetchar:
	movl	$0, %eax
	movl	%eax, %edi
	syscall
	cmpl	$1, %eax
	je	.L3
	movb	$-1, (%rsi)
.L3:
	ret

	.globl	main
main:
	pushq	%rbp
	subq	$8, %rsp

	#movl	$1, %ebp
	leaq	buf(%rip), %rsi
	movl	$1, %edx

	movzbl	(%rsi), %eax
	addl	$1, %eax
	movb	%al, (%rsi)	# ++*ptr

.Lleft:
	#testb	%al, %al
	movb	(%rsi), %al
	testb	%al, %al
	je .Lright		# [ // jump to ] if 0

	addq	$1, %rsi	# ++ptr;

	call	intgetchar	# intgetchar(ptr);

	subb	$1, (%rsi)	# --*ptr;

	call	intputchar	# intputchar(ptr);

	movzbl	(%rsi), %eax
	addl	$2, %eax
	movb	%al, (%rsi)	# ++*ptr; ++*ptr;

	#testb	%al, %al
	#jne .L6
.Lright:
	movb	(%rsi), %al
	testb	%al, %al
	jne	.Lleft		# ] // jump to [ if not 0

.Lexit:
	movl	$0, %edi
	movl	$60, %eax
	syscall			# exit(0);
