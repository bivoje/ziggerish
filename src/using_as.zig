
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

    // FIXME more safe way?
    const as = options.method.as;

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

    var file = try std.fs.cwd().createFile(as.temp_path_s, .{ .read = true, });
    defer file.close();
    var w = file.writer();

    try w.print(
        \\	.file	"{s}"
        \\	.ident	"Ziggerish: ({s} {any}) {any} {s}"
        \\
    , meta_info);

    // NOTE gcc would normally generate code using .comm directive
    // the difference is subtle, and negligible.
    // https://stackoverflow.com/a/13584185
    try w.writeAll(
        \\	.section	.note.GNU-stack,"",@progbits
        \\
        \\	.bss
        \\	.align 32
        \\buf:
        \\	.zero	1000
        \\
        \\	.text
        \\
    );

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
            \\intputchar:
            \\	movl	$4, %eax
            \\	movl	$1, %ebx
            \\	int	$0x80
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
            ,
        else => unreachable,
    });

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
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
            ,
        .linux_x86_64 =>
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
            ,
        else => unreachable,
    });

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
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
            \\	xorl	%edi, %edi	# prepare 0 for cmov
            \\	movzbl	(%esi), %ebx
            \\	shrb	$4, %bl
            \\	orl	$0x30, %ebx	# faster than addl
            \\	cmpb	$0x3A, %bl
            \\	movl	$7, %eax
            \\	cmovl	%edi, %eax
            \\	addl	%eax, %ebx
            \\	movb	%bl, (%ecx)
            \\	call	intputchar
            \\
            \\	xorl	%edi, %edi	# prepare 0 for cmov
            \\	movzbl	(%esi), %ebx
            \\	andl	$0x0F, %ebx
            \\	orl	$0x30, %ebx	# faster than addl
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
            \\dump:
            \\	pushq	%rbp
            \\	addq	$5, %rsi		# dst = ptr+5
            \\	pushq	%rsi			# store dst
            \\	subq	$8, %rsp		# (rsp)=c, alingn frame
            \\	leaq	buf-1(%rip), %rbx	# rbx = p
            \\	leaq	(%rsp), %rsi		# rsi = ptr (=&c)
            \\	xorq	%r8, %r8		# r8 = 0 for cmov
            \\
            \\.Ldumploop:
            \\	addq	$1, %rbx
            \\	movq	8(%rsp), %rax
            \\	cmpq	%rbx, %rax
            \\	je	.Ldumpend
            \\
            \\	movzbl	(%rbx), %edi
            \\	shrb	$4, %dil
            \\	orl	$0x30, %edi	# fater than add
            \\	cmpb	$0x3A, %dil
            \\	movl	$7, %eax
            \\	cmovl	%r8d, %eax
            \\	addl	%eax, %edi
            \\	movb	%dil, (%rsi)
            \\	call	intputchar
            \\
            \\	movzbl	(%rbx), %edi
            \\	andl	$0x0F, %edi
            \\	orl	$0x30, %edi	# faster than add
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
    });

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
            \\	.globl	_start
            \\_start:
            \\	pushl	%ebp
            \\	leal	buf, %ecx
            \\	movl	$1, %edx
            \\
            ,

        .linux_x86_64 =>
            \\	.globl	_start
            \\_start:
            \\	pushq	%rbp
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
    });


    // write body
    {
        const jumprefs = (try collect_jumprefs(al, tokens)) orelse {
            return error.SytaxError;
        };

        var jri: usize = 0;
        for (tokens.items) |token, i| {
            try switch (options.target) {
                .linux_x86_64 => switch (token) {
                    .Dump  => w.writeAll("\tcall\tdump"),
                    .Left  => w.writeAll("\tsubq\t$1, %rsi"),   // <
                    .Right => w.writeAll("\taddq\t$1, %rsi"),   // >
                    .Inc   => w.writeAll("\taddb\t$1, (%rsi)"), // +
                    .Dec   => w.writeAll("\tsubb\t$1, (%rsi)"), // -
                    .Get   => w.writeAll("\tcall\tintgetchar"), // ,
                    .Put   => w.writeAll("\tcall\tintputchar"), // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk w.print(
                        \\.Lleft{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	je .Lright{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk w.print(
                        \\.Lright{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	jne	.Lleft{d}
                        , .{i, jumprefs.items[jri]});
                    },
                },
                .linux_x86 => switch (token) {
                    .Dump  => w.writeAll("\tcall\tdump"),       // #
                    .Left  => w.writeAll("\tsubl\t$1, %ecx"),   // <
                    .Right => w.writeAll("\taddl\t$1, %ecx"),   // >
                    .Inc   => w.writeAll("\taddb\t$1, (%ecx)"), // +
                    .Dec   => w.writeAll("\tsubb\t$1, (%ecx)"), // -
                    .Get   => w.writeAll("\tcall\tintgetchar"), // ,
                    .Put   => w.writeAll("\tcall\tintputchar"), // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk w.print(
                            \\.Lleft{d}:
                            \\	movb	(%ecx), %al
                            \\	testb	%al, %al
                            \\	je .Lright{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk w.print(
                            \\.Lright{d}:
                            \\	movb	(%ecx), %al
                            \\	testb	%al, %al
                            \\	jne	.Lleft{d}
                        , .{i, jumprefs.items[jri]});
                    },
                },
                else => unreachable,
            };

            try w.writeByte(@as(u8, '\n'));
        }
        std.debug.assert(jri == jumprefs.items.len); // FIXME detect first & fail gently?
    }

    try w.writeAll(switch (options.target) {
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
    });

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
