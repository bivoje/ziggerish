
const std = @import("std");

const BFinstr        = @import("types.zig").BFinstr;
const CompileOptions = @import("types.zig").CompileOptions;

const collect_jumprefs = @import("util.zig").collect_jumprefs;
const system           = @import("util.zig").system;

pub fn compile (
    al: std.mem.Allocator,
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {

    const asm_meta = //TODO
        \\	.file	"{s}"
        \\	.ident	"Ziggerish: ({s} {any}) {any} {s}"
        \\
        ;

    const asm_header =
        \\	.section	.note.GNU-stack,"",@progbits
        \\
        \\	.bss
        \\	.align 32
        \\buf:
        \\	.zero	1000
        \\
        \\	.text
        \\
        ;
    // NOTE gcc would normally generate code using .comm directive
    // the difference is subtle, and negligible.
    // https://stackoverflow.com/a/13584185

    // TODO opt like this?
    //%7 = lshr i8 %6, 4
    //%8 = or i8 %7, 48
    //%9 = icmp ult i8 %8, 58
    //%10 = select i1 %9, i8 0, i8 7
    //%11 = add nuw nsw i8 %10, %8
    //%12 = zext i8 %11 to i32
    //%13 = call i32 @putchar(i32 %12)
    const asm_routines = switch (options.target) {
        .linux_x86 =>
            \\intputchar:
            \\	movl	$4, %eax
            \\	movl	$1, %ebx
            \\	int	$0x80
            \\	ret
            \\
            \\intgetchar:
            \\	movl	$3, %eax
            \\	movl	$0, %ebx
            \\	int	$0x80
            \\	cmpl	$1, %eax
            \\	je	.Lreadend
            \\	movb	$-1, (%ecx)
            \\.Lreadend:
            \\	ret
            \\
            \\dump:
            \\	push	%ebp
            \\	add	$5, %ecx		# dst = ptr+5
            \\	push	%ecx			# store dst
            \\	sub	$4, %esp		# (esp)=c, alingn frame
            \\	lea	buf-1, %esi		# esi = p
            \\	lea	(%esp), %ecx		# ecx = ptr (=&c)
            \\
            \\.Ldumploop:
            \\	add	$1, %esi
            \\	mov	4(%esp), %eax
            \\	cmp	%esi, %eax
            \\	je	.Ldumpend
            \\
            \\	xorl	%edi, %edi
            \\	movzbl	(%esi), %ebx
            \\	shrb	$4, %bl
            \\	addl	$0x30, %ebx
            \\	cmpb	$0x3A, %bl
            \\	movl	$7, %eax
            \\	cmovl	%edi, %eax
            \\	addl	%eax, %ebx
            \\	movb	%bl, (%ecx)
            \\	call	intputchar
            \\
            \\	xorl	%edi, %edi
            \\	movzbl	(%esi), %ebx
            \\	andl	$0x0F, %ebx
            \\	addl	$0x30, %ebx
            \\	cmpb	$0x3A, %bl
            \\	movl	$7, %eax
            \\	cmovl	%edi, %eax
            \\	addl	%eax, %ebx
            \\	movb	%bl, (%ecx)
            \\	call	intputchar
            \\
            \\	movl	$0x20, (%ecx)
            \\	call	intputchar
            \\
            \\	jmp	.Ldumploop
            \\
            \\.Ldumpend:
            \\	movl	$0x0A, (%ecx)
            \\	call	intputchar
            \\
            \\	add	$4, %esp
            \\	pop	%ecx
            \\	sub	$5, %ecx
            \\	pop	%esi
            \\	ret
            \\
            ,
        .linux_x86_64 =>
            \\intputchar:
            \\	movl	$1, %eax
            \\	movl	%eax, %edi
            \\	syscall
            \\	ret
            \\
            \\intgetchar:
            \\	movl	$0, %eax
            \\	movl	%eax, %edi
            \\	syscall
            \\	cmpl	$1, %eax
            \\	je	.Lreadend
            \\	movb	$-1, (%rsi)
            \\.Lreadend:
            \\	ret
            \\
            \\dump:
            \\	pushq	%rbp
            \\	addq	$5, %rsi		# dst = ptr+5
            \\	pushq	%rsi			# store dst
            \\	subq	$8, %rsp		# (rsp)=c, alingn frame
            \\	leaq	buf-1(%rip), %rbx	# rbx = p
            \\	leaq	(%rsp), %rsi		# rsi = ptr (=&c)
            \\	xorq	%r8, %r8		# r8 = 0 for convenience
            \\
            \\.Ldumploop:
            \\	addq	$1, %rbx
            \\	movq	8(%rsp), %rax
            \\	cmpq	%rbx, %rax
            \\	je	.Ldumpend
            \\
            \\	movzbl	(%rbx), %edi
            \\	shrb	$4, %dil
            \\	addl	$0x30, %edi
            \\	cmpb	$0x3A, %dil
            \\	movl	$7, %eax
            \\	cmovl	%r8d, %eax
            \\	addl	%eax, %edi
            \\	movb	%dil, (%rsi)
            \\	call	intputchar
            \\
            \\	movzbl	(%rbx), %edi
            \\	andl	$0x0F, %edi
            \\	addl	$0x30, %edi
            \\	cmpb	$0x3A, %dil
            \\	movl	$7, %eax
            \\	cmovl	%r8d, %eax
            \\	addl	%eax, %edi
            \\	movb	%dil, (%rsi)
            \\	call	intputchar
            \\
            \\	movl	$0x20, (%rsi)
            \\	call	intputchar
            \\
            \\	jmp	.Ldumploop
            \\
            \\.Ldumpend:
            \\	movl	$0x0A, (%rsi)
            \\	call	intputchar
            \\
            \\	addq	$8, %rsp
            \\	popq	%rsi
            \\	subq	$5, %rsi
            \\	popq	%rbx
            \\	ret
            \\
            ,
        else => unreachable,
    };

    const asm_main_prol = switch (options.target) {
        .linux_x86 =>
            \\	.globl	_start
            \\_start:
            \\	pushl	%ebp
            \\	subl	$8, %esp
            \\
            \\	leal	buf, %ecx
            \\	movl	$1, %edx
            \\
            ,

        .linux_x86_64 =>
            \\	.globl	_start
            \\_start:
            \\	pushq	%rbp
            \\	subq	$8, %rsp
            \\
            \\	leaq	buf(%rip), %rsi
            \\	movl	$1, %edx
            \\
            , // FIXME use of %rip register in this code is placed by gcc
              // in attempt to make PIE (position independent executable)
              // thus, not needed in this case (except you want to load
              // brackfuck code as shared library?)
              // given -fno-pie option to gcc would prevent this behavior.
              // https://stackoverflow.com/a/45422495
        else => unreachable,
    };

    const asm_footer = switch (options.target) {
        .linux_x86 =>
            \\.Lexit:
            \\	movl	$0, %ebx
            \\	movl	$1, %eax
            \\	int	$0x80
            \\
            ,
        .linux_x86_64 =>
            \\.Lexit:
            \\	movl	$0, %edi
            \\	movl	$60, %eax
            \\	syscall
            \\
            ,
        else => unreachable,
    };


    // create *.s tempfile
    {
        var file = try std.fs.cwd().createFile(
            options.method.as.temp_path_s,
            .{ .read = true, }
        );
        defer file.close();

        const meta_info = blk: {
            const build_os = @import("builtin").os;

            const os_name = switch (build_os.tag) {
                .linux => "Linux",
                else => unreachable,
            };

            const os_ver = switch (build_os.tag) {
                .linux => build_os.version_range.linux.range.min,
                else => unreachable,
            };

            const version = std.builtin.Version {
                .major = 0, .minor = 0, .patch = 0,
            };

            const date = "20220124"; // FIXME how to use pragmatically?

            break :blk .{ options.src_path, os_name, os_ver, version, date, };
        };

        try file.writer().print(asm_meta, meta_info);
        try file.writeAll(asm_header);
        try file.writeAll(asm_routines);
        try file.writeAll(asm_main_prol);

        const jumprefs = (try collect_jumprefs(al, tokens)) orelse {
            return error.SytaxError;
        };

        var jri: usize = 0;
        for (tokens.items) |token, i| {
            try switch (options.target) {
                .linux_x86_64 => switch (token) {
                    .Dump  => file.writeAll("\tcall\tdump"),
                    .Left  => file.writeAll("\tsubq\t$1, %rsi"),     // <
                    .Right => file.writeAll("\taddq\t$1, %rsi"),     // >
                    .Inc   => file.writeAll("\taddb\t$1, (%rsi)"),  // +
                    .Dec   => file.writeAll("\tsubb\t$1, (%rsi)"),  // -
                    .Get   => file.writeAll("\tcall\tintgetchar"),   // ,
                    .Put   => file.writeAll("\tcall\tintputchar"),   // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk file.writer().print(
                        \\.Lleft{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	je .Lright{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk file.writer().print(
                        \\.Lright{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	jne	.Lleft{d}
                        , .{i, jumprefs.items[jri]});
                    },
                },
                .linux_x86 => switch (token) {
                    .Dump  => file.writeAll("\tcall\tdump"),        // #
                    .Left  => file.writeAll("\tsubl\t$1, %ecx"),     // <
                    .Right => file.writeAll("\taddl\t$1, %ecx"),     // >
                    .Inc   => file.writeAll("\taddb\t$1, (%ecx)"),  // +
                    .Dec   => file.writeAll("\tsubb\t$1, (%ecx)"),  // -
                    .Get   => file.writeAll("\tcall\tintgetchar"),   // ,
                    .Put   => file.writeAll("\tcall\tintputchar"),   // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk file.writer().print(
                        \\.Lleft{d}:
                        \\	movb	(%ecx), %al
                        \\	testb	%al, %al
                        \\	je .Lright{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk file.writer().print(
                        \\.Lright{d}:
                        \\	movb	(%ecx), %al
                        \\	testb	%al, %al
                        \\	jne	.Lleft{d}
                        , .{i, jumprefs.items[jri]});
                    },
                },
                else => unreachable,
            };

            try file.writer().writeByte(0x0a); // newline
        }
        std.debug.assert(jri == jumprefs.items.len);

        try file.writeAll(asm_footer);
    }

    const ret_as = try system(
        "as",
        &[_:null]?[*:0]const u8{
            "as",
            "-o", options.method.as.temp_path_o,
            options.method.as.temp_path_s,
            switch (options.target) {
                .linux_x86 => "--32",
                .linux_x86_64 => "--64",
                else => unreachable,
            },
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
    );

    if (ret_as.status != 0) return error.AsError;

    const ret_ld = try system(
        "ld",
        &[_:null]?[*:0]const u8{
            "ld",
            // NOTE we need to explicitly specify target architecture
            // for ld if it is different from current system archi.
            // https://stackoverflow.com/a/16004418
            "-m", switch (options.target) {
                .linux_x86 => "elf_i386",
                .linux_x86_64 => "elf_x86_64",
                else => unreachable,
            },
            // NOTE -e <symbol> sets the entry point
            // we can use other symbol than '_start'!
            // https://sourceware.org/binutils/docs/ld/Entry-Point.html
            "-o", options.dst_path,
            options.method.as.temp_path_o,
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
    );

    if (ret_ld.status != 0) return error.LdError;
}
