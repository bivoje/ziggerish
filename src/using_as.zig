
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

    // NOTE for some reasone, inequality operators does not work correctly
    // cmp a b; jle L; jumps when a < b and in other program when a > b
    // maybe https://stackoverflow.com/a/29577037 is the reason but couldn't
    // make it work.
    // so i had to use ne/e series instead of l/le/g/ge/ae/b/be on
    // jumps, cmovs

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

    try w.writeAll(
        \\	.section	.note.GNU-stack,"",@progbits
        \\
    );

    // NOTE gcc would normally generate code using .comm directive
    // the difference is subtle, and negligible.
    // https://stackoverflow.com/a/13584185
    switch (options.alloc) {
        .StaticUnchecked, .Static => |size| try w.print(
            \\	.bss
            \\	.align 32
            \\buf:
            \\	.zero	{d}
        , .{ size }),
        .Dynamic => {},
    }

    try w.writeAll(
        \\
        \\	.text
        \\
    );

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
            \\intabort:
            \\	movl	$20, %eax	# sys_getpid
            \\	int	$0x80
            \\	movl	%eax, %ebx	# pid
            \\	movl	$37, %eax	# sys_kill
            \\	movl	$6, %ecx	# SIGABRT
            \\	int	$0x80
            \\
            ,
        .linux_x86_64 =>
            \\intabort:
            \\	movq	$39, %rax	# sys_getpid
            \\	syscall
            \\	movq	%rax, %rdi	# pid
            \\	movq	$62, %rax	# sys_kill
            \\	movq	$6, %rsi	# SIGABRT
            \\	syscall
            \\
            ,
        else => unreachable,
    });


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
            \\	movq	$1, %rax
            \\	movq	%rax, %rdi
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
            \\
            ,
        .linux_x86_64 =>
            \\intgetchar:
            \\	movq	$0, %rax
            \\	movq	%rax, %rdi
            \\	syscall
            \\	cmpq	$1, %rax
            \\	je	.Lreadend
            \\
            ,
        else => unreachable,
    });
    try w.writeAll(switch (options.target) {
        .linux_x86 => switch (options.eof_by) {
            .neg1 => "\tmovb\t$-1, (%ecx)\n",
            .noop => "",
            .zero => "\tmovb\t$0, (%ecx)\n",
        },
        .linux_x86_64 => switch (options.eof_by) {
            .neg1 => "\tmovb\t$-1, (%rsi)\n",
            .noop => "",
            .zero => "\tmovb\t$0, (%rsi)\n",
        },
        else => unreachable,
    });

    try w.writeAll(
        \\.Lreadend:
        \\	ret
        \\
    );

    // FIXME printing till ptr + 1 is dangerous
    switch (options.target) {
        .linux_x86 => {
            try w.writeAll(switch (options.alloc) {
                .StaticUnchecked, .Static =>
                    \\dump:
                    \\	addl	$1, %ecx		# dst = ptr+1
                    \\	pushl	%ecx			# store dst
                    \\	subl	$4, %esp		# (esp)=c, alingn frame
                    \\	leal	buf-1, %esi		# esi = p
                    \\	leal	(%esp), %ecx		# ecx = ptr (=&c)
                    \\
                    \\.Ldumploop:
                    \\	addl	$1, %esi
                    \\
                    ,
                .Dynamic =>
                    \\dump:
                    \\	subl	$1, %ecx		# dst = ptr+1
                    \\	push	%ecx			# store dst
                    \\	subl	$4, %esp		# (esp)=c, alingn frame
                    \\	leal	1(%ebp), %esi		# esi = p
                    \\	leal	(%esp), %ecx		# ecx = ptr (=&c)
                    \\
                    \\.Ldumploop:
                    \\	subl	$1, %esi
                    \\
                    ,
            });

            try w.writeAll(
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
                \\.Ldumpend:
                \\	movl	$0x0A, (%ecx)
                \\	call	intputchar
                \\
                \\	addl	$4, %esp
                \\	popl	%ecx
                \\
            );

            try w.writeAll(switch (options.alloc) {
                .StaticUnchecked, .Static =>
                    \\	subl	$1, %ecx
                    \\
                    ,
                .Dynamic =>
                    \\	addl	$1, %ecx
                    \\
                    ,
            });

            try w.writeAll(
                //\\	pop	%esi
                \\	ret
                \\
            );
        },

        .linux_x86_64 => {
            try w.writeAll(switch (options.alloc) {
                .StaticUnchecked, .Static =>
                    \\dump:
                    \\	addq	$1, %rsi		# dst = ptr+1
                    \\	pushq	%rsi			# store dst
                    \\	subq	$8, %rsp		# (rsp)=c, alingn frame
                    \\	leaq	buf-1(%rip), %rbx	# rbx = p
                    \\	leaq	(%rsp), %rsi		# rsi = ptr (=&c)
                    \\	xorq	%r8, %r8		# r8 = 0 for cmov
                    \\
                    \\.Ldumploop:
                    \\	addq	$1, %rbx
                    \\
                    ,
                .Dynamic =>
                    \\dump:
                    \\	subq	$1, %rsi		# dst = ptr+1
                    \\	pushq	%rsi			# store dst
                    \\	subq	$8, %rsp		# (rsp)=c, alingn frame
                    \\	leaq	1(%rbp), %rbx		# rbx = p
                    \\	leaq	(%rsp), %rsi		# rsi = ptr (=&c)
                    \\	xorq	%r8, %r8		# r8 = 0 for cmov
                    \\
                    \\.Ldumploop:
                    \\	subq	$1, %rbx
                    \\
            });

            try w.writeAll(
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
                \\
            );

            try w.writeAll(switch (options.alloc) {
                .StaticUnchecked, .Static =>
                    \\	subq	$1, %rsi
                    \\
                    ,
                .Dynamic =>
                    \\	addq	$1, %rsi
                    \\

            });
            try w.writeAll(
                //\\	popq	%rbx
                \\	ret
                \\
            );
        },

        else => unreachable,
    }

    try w.writeAll(switch (options.target) {
        .linux_x86 =>
            \\	.globl	_start
            \\_start:
            \\	movl	$1, %edx
            \\
            ,

        .linux_x86_64 =>
            \\	.globl	_start
            \\_start:
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

    switch (options.alloc) {
        .StaticUnchecked => try w.writeAll(switch (options.target) {
            .linux_x86 =>
                \\	leal	buf, %ecx
                ,
            .linux_x86_64 =>
                \\	leaq	buf(%rip), %rsi
                ,
            else => unreachable,
        }),

        .Static => |size| switch (options.target) {
            .linux_x86 => try w.print(
                \\	leal	buf, %ecx
                \\	leal	{d}(%ecx), %ebp	# use ebp as bufend
                , .{size}),
            .linux_x86_64 => try w.print(
                \\	leaq	buf(%rip), %rsi
                \\	leaq	{d}(%rsi), %rbp	# use rbp as bufend
                , .{size}),
            else => unreachable,
        },

        .Dynamic => try w.writeAll(switch (options.target) {
            .linux_x86 =>
                \\	pushl	$0		# initial buf 4 byte
                \\	leal	3(%esp), %ebp	# ebp is bufstart, esp is bufend
                \\	movl    %ebp, %ecx
                ,
            .linux_x86_64 =>
                \\	pushq	$0		# initial buf 8 byte
                \\	leaq	7(%rsp), %rbp	# rbp is bufstart
                \\	movq    %rbp, %rsi	# rsp is bufend
                ,
            else => unreachable,
        }),
    }
    try w.writeByte(@as(u8, '\n'));

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
                    .Left  => switch (options.alloc) { // <
                        .StaticUnchecked => w.writeAll(
                            \\	subq	$1, %rsi
                        ),
                        .Static => w.print(
                            \\	subq	$1, %rsi
                            \\	cmpq	buf(%rip), %rsi	# ??? is bufstart
                            //\\	jle	.Lleft{d}
                            \\	jne	.Lleft{d}
                            \\	call	intabort
                            \\.Lleft{d}:
                        , .{i, i}),
                        .Dynamic => w.print(
                            \\	addq	$1, %rsi	# stack grows to bottom
                            \\	cmpq	%rsi, %rbp	# rbp is bufstart
                            \\	jge	.Lleft{d}
                            \\	call	intabort
                            \\.Lleft{d}:
                        , .{i, i}),
                    },
                    .Right => switch (options.alloc) { // >
                        .StaticUnchecked => w.writeAll(
                            \\	addq	$1, %rsi
                        ),
                        .Static => w.print(
                            \\	addq	$1, %rsi
                            \\	cmpq	%rbp, %rsi	# rbp is bufend
                            \\	jne	.Lright{d}
                            \\	call	intabort	# abort if reached
                            \\.Lright{d}:
                        , .{i, i}),
                        .Dynamic => w.writeAll(
                            \\	subq	$1, %rsi	# stack grows to bottom
                            \\	cmpq	%rsp, %rsi	# rsp is bufend
                            \\	movq	$0, %rax
                            \\	cmove	%rdx, %rax	# rdx holds const 1
                            \\	subq	%rax, %rsp	# extend rsp if reached
                            \\	movb	$0, (%rsp)	# clear next new cell
                        ),
                    }, // TODO what if esp can't grow?
                    .Inc   => w.writeAll("\taddb\t$1, (%rsi)"), // +
                    .Dec   => w.writeAll("\tsubb\t$1, (%rsi)"), // -
                    .Get   => w.writeAll("\tcall\tintgetchar"), // ,
                    .Put   => w.writeAll("\tcall\tintputchar"), // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk w.print(
                        \\.Lfrom{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	je .Lto{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk w.print(
                        \\.Lto{d}:
                        \\	movb	(%rsi), %al
                        \\	testb	%al, %al
                        \\	jne	.Lfrom{d}
                        , .{i, jumprefs.items[jri]});
                    },
                },
                .linux_x86 => switch (token) {
                    .Dump  => w.writeAll("\tcall\tdump"),       // #
                    .Left  => switch (options.alloc) { // <
                        .StaticUnchecked => w.writeAll(
                            \\	subl	$1, %ecx
                        ),
                        .Static => w.print(
                            \\	subl	$1, %ecx
                            \\	cmpl	buf, %ecx	# buf is bufstart
                            //\\	jle	.Lleft{d}
                            \\	jne	.Lleft{d}
                            \\	call	intabort
                            \\.Lleft{d}:
                        , .{i, i}),
                        .Dynamic => w.print(
                            \\	addl	$1, %ecx	# stack grows to bottom
                            \\	cmpl	%ecx, %ebp	# ebp is bufstart
                            \\	jge	.Lleft{d}
                            \\	call	intabort
                            \\.Lleft{d}:
                        , .{i, i}),
                    },
                    .Right => switch (options.alloc) { // >
                        .StaticUnchecked => w.writeAll(
                            \\	addl	$1, %ecx
                        ),
                        .Static => w.print(
                            \\	addl	$1, %ecx
                            \\	cmpl	%ebp, %ecx	# ebp is bufend
                            \\	jne	.Lright{d}
                            \\	call	intabort	# abort if reached
                            \\.Lright{d}:
                        , .{i, i}),
                        .Dynamic => w.writeAll(
                            \\	subl	$1, %ecx	# stack grows to bottom
                            \\	cmpl	%esp, %ecx	# esp is bufend
                            \\	movl	$0, %eax
                            \\	cmove	%edx, %eax	# edx holds const 1
                            \\	subl	%eax, %esp	# extend esp if reached
                            \\	movb	$0, (%esp)	# clear next new cell
                        ),
                    }, // TODO what if esp can't grow?
                    .Inc   => w.writeAll("\taddb\t$1, (%ecx)"), // +
                    .Dec   => w.writeAll("\tsubb\t$1, (%ecx)"), // -
                    .Get   => w.writeAll("\tcall\tintgetchar"), // ,
                    .Put   => w.writeAll("\tcall\tintputchar"), // .
                    .From  => blk: { // [
                        defer jri += 1;
                        break :blk w.print(
                            \\.Lfrom{d}:
                            \\	movb	(%ecx), %al
                            \\	testb	%al, %al
                            \\	je .Lto{d}
                        , .{i, jumprefs.items[jri]});
                    },
                    .To    => blk: { // ]
                        defer jri += 1;
                        break :blk w.print(
                            \\.Lto{d}:
                            \\	movb	(%ecx), %al
                            \\	testb	%al, %al
                            \\	jne	.Lfrom{d}
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
