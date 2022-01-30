const std = @import("std");
const dprint = std.debug.print;

const BFinstr = enum {
    Left,  // <
    Right, // >
    Inc,   // +
    Dec,   // -
    From,  // [
    To,    // ]
    Get,   // ,
    Put,   // .
};

const CompileOptions = struct {
    target: enum {
        linux_x86, linux_x86_64, windows,
    },

    src_path :[:0]const u8,
    dst_path :[:0]const u8,

    compile_using: union(enum) {
        gcc: struct {
            with_libc: bool = true,
            inlined: bool = false,
            temp_path: [:0]const u8 = "temp.c",
        },
        as: struct {
            temp_path_s: [:0]const u8 = "temp.s",
            temp_path_o: [:0]const u8 = "temp.o",
        },
        llvm: struct {
            temp_path_ll: [:0]const u8 = "temp.ll",
            temp_path_s: [:0]const u8 = "temp.s",
            temp_path_o: [:0]const u8 = "temp.o",
            use_clang:bool = true,
        },
        clang: struct {
        },
    },
};

pub fn main () anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const options = CompileOptions {
        .target = .linux_x86_64,
        //.src_path = "samples/rot25.bf",
        //.src_path = "samples/hello.bf",
        .src_path = "samples/rot13.bf",
        .dst_path = "main",
        //.compile_using = .{ .gcc = .{
        //    .with_libc = false,
        //    .quick = false,
        //}},
        //.compile_using = .{ .llvm = .{
        //}},
        .compile_using = .{ .as = .{
        }},
    };

    const allocator = arena.allocator();
    const tokens = load_and_parse(allocator, options.src_path) catch |e| {
        // TODO elaborate error messages
        dprint("could not load and parse, {}\n", .{e});
        return;
    };

    //compile_ll(tokens, options) catch |e| {
    //    // TODO elaborate error messages
    //    dprint("could not compile, {}\n", .{e});
    //    return;
    //};

    compile_cl(tokens, options) catch |e| {
        // TODO elaborate error messages
        dprint("could not compile, {}\n", .{e});
        return;
    };

    //compile_gcc(tokens, options) catch |e| {
    //    // TODO elaborate error messages
    //    dprint("could not compile, {}\n", .{e});
    //    return;
    //};
}

fn load_and_parse (
    allocator: std.mem.Allocator,
    src_path: [:0]const u8
) !std.ArrayList(BFinstr) {
    // loading ===========
    const contents: []u8 = blk: {
        var file = try std.fs.cwd().openFile(src_path, .{});
        defer file.close();

        const maxlen = std.math.inf_u64; // unlimited reading!
        break :blk try file.reader().readAllAlloc(allocator, maxlen);
    };

    // parsing ==========
    var tokens = blk: {
        var tokens = std.ArrayList(BFinstr).init(allocator);
        //defer allocator.free(tokens);

        for (contents) |c| {
            if (tokenize(c)) |token| {
                try tokens.append(token);
            } // ignore invalid characters
        }

        break :blk tokens;
    };

    return tokens;
}

fn compile_ll (
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {

    const ll_meta =
        \\source_filename = "{s}"
        \\target triple = "x86_64-pc-linux-gnu"
        \\
        ;

    const ll_header =
        \\@buf = internal global [1000 x i8] zeroinitializer, align 16
        \\define internal fastcc void @intgetchar(i8* nocapture %0) unnamed_addr #1 {
        \\  %2 = call i64 @read(i32 0, i8* %0, i64 1) #5
        \\  %3 = icmp eq i64 %2, 1
        \\  br i1 %3, label %readret, label %readeof
        \\readeof:
        \\  store i8 -1, i8* %0, align 1, !tbaa !2
        \\  br label %readret
        \\readret:
        \\  ret void
        \\}
        \\define internal fastcc void @intputchar(i8* nocapture readonly %0) unnamed_addr #1 {
        \\  %2 = call i64 @write(i32 1, i8* %0, i64 1) #5
        \\  ret void
        \\}
        \\define dso_local void @main() local_unnamed_addr #0 {
        \\loop0b0:
        \\  %l0p0 = getelementptr inbounds [1000 x i8], [1000 x i8]* @buf, i64 0, i64 0
        \\
        ;

    const ll_footer =
        \\  br label %mainret
        \\mainret:
        \\  call void @exit(i32 0) #4
        \\  unreachable
        \\}
        \\declare dso_local void @exit(i32) local_unnamed_addr #2
        \\declare dso_local i64 @write(i32, i8* nocapture readonly, i64) local_unnamed_addr #3
        \\declare dso_local i64 @read(i32, i8* nocapture, i64) local_unnamed_addr #3
        \\
        \\attributes #0 = { noreturn nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false"  "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87"}
        \\attributes #1 = { nofree nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
        \\attributes #2 = { noreturn nounwind "disable-tail-calls"="false" "frame-pointer"="none" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
        \\attributes #3 = { nofree "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "frame-pointer"="none" "less-precise-fpmad"="false" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
        \\attributes #4 = { noreturn nounwind }
        \\attributes #5 = { nounwind }
        \\
        \\!llvm.module.flags = !{!0}
        \\!llvm.ident = !{!1}
        \\
        \\!0 = !{i32 1, !"wchar_size", i32 4}
        \\!1 = !{!"clang version 10.0.0-4ubuntu1 "}
        \\!2 = !{!3, !3, i64 0}
        \\!3 = !{!"omnipotent char", !4, i64 0}
        \\!4 = !{!"Simple C/C++ TBAA"}
        \\
        ;

    var file = try std.fs.cwd().createFile(
        options.compile_using.llvm.temp_path_ll,
        .{ .read = true, }
    );
    defer file.close();

    try file.writer().print(ll_meta, .{options.src_path});
    try file.writeAll(ll_header);

    var w = file.writer();
    const tl = try translate_ll(w, 0, tokens, 0, 1, 0, 0, options);
    try file.writeAll(ll_footer);

    // TODO check more sophisticately
    try std.testing.expectEqual(tl.@"0", tokens.items.len);


    const ret_clang = try system(
        "clang",
        &[_:null]?[*:0]const u8{
            "clang",
            "-o", options.dst_path,
            options.compile_using.llvm.temp_path_ll,
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
    );

    if (ret_clang.status != 0) return error.ClangError;
}

fn translate_ll (
    w: std.fs.File.Writer,
    _ti: usize,
    tokens: std.ArrayList(BFinstr),
    ln: usize, // current level num
    _ln: usize, // level num of the block above
    _lx: usize, // level sub-num of the block above
    _px: usize, // ptr num of last loaded
    options: CompileOptions,
) std.fs.File.Writer.Error ! struct {@"0":usize,@"1":usize} { // returns the number of tokens read

    var ln_ = ln+1;       // next ln to allocate
    //dprint("translate(ti={}, ln={}, ln_={}, _lx={})\n", .{_ti, ln, ln_, _lx});

    var ti = _ti;
    _ = _px;

    // varnum of last updated value
    var vx: usize = 1;
    var px: usize = 0;
    var lx: usize = 0;

    blk: while (ti < tokens.items.len) : (ti += 1) {
        const token = tokens.items[ti];
        //dprint("tokens[{}]: {}\n", .{ti, token});
        switch (token) {
            .Left  => { // <
                try w.print("  %l{}p{} = getelementptr inbounds i8, i8* %l{}p{}, i64 -1", .{ln,px+1, ln,px});
                try w.print("\t\t;<", .{});
                px += 1;
            },
            .Right => { // >
                try w.print("  %l{}p{} = getelementptr inbounds i8, i8* %l{}p{}, i64 1", .{ln,px+1, ln,px});
                try w.print("\t\t;>", .{});
                px += 1;
            },
            .Inc   => { // +
                try w.print(
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = add i8 %l{}v{}, 1
                    \\  store i8 %l{}v{}, i8* %l{}p{}, align 16
                ,.{ ln,vx+1, ln,px,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, ln,px, });
                try w.print("\t\t\t;+", .{});
                vx += 2;
            },
            .Dec   => { // -
                try w.print(
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = sub i8 %l{}v{}, 1
                    \\  store i8 %l{}v{}, i8* %l{}p{}, align 16
                ,.{ ln,vx+1, ln,px,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, ln,px, });
                try w.print("\t\t\t;-", .{});
                vx += 2;
            },
            .Get   => { // ,
                try w.print("  call fastcc void @intgetchar(i8* nonnull %l{}p{})", .{ln,px});
                try w.print("\t\t;get", .{});
            },
            .Put   => { // .
                try w.print("  call fastcc void @intputchar(i8* nonnull %l{}p{})", .{ln,px});
                try w.print("\t\t;put", .{});
            },
            .From  => { // [
                try w.print("  br label %loop{}a\n", .{ln_});
                try w.print(
                    \\loop{}a:
                    \\  %l{}p{} = phi i8* [ %l{}p{}, %loop{}b{} ], [ %l{}p_, %loop{}c ]
                    //\\  call fastcc void @intputchar(i8* nonnull %l{}p{})
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = icmp eq i8 %l{}v{}, 0
                    \\  br i1 %l{}v{}, label %loop{}c, label %loop{}b{}
                    \\loop{}b{}:
                    \\
                ,.{ ln_,
                    ln_,0, ln,px, ln,lx, ln_, ln_,
                    //ln_,0,
                    ln_,0, ln_,0,
                    ln_,1, ln_,0,
                    ln_,1, ln_, ln_,0,
                    ln_,0
                });
                try w.print("\t\t\t\t\t;[\n", .{});
                const tl = try translate_ll(w, ti+1, tokens, ln_, ln, lx, px, options);
                try w.print(
                    \\loop{}b{}:
                    \\  %l{}p{} = getelementptr inbounds i8, i8* %l{}p_, i64 0
                ,.{ ln,lx+1,
                    ln,px+1, ln_,
                });
                ti += tl.@"0";
                ln_ = tl.@"1";
                lx += 1;
                px += 1;
            },
            .To => { // ]
                try w.print(
                    \\  br label %loop{}c
                    \\loop{}c:
                    \\  %l{}p_ = phi i8* [ %l{}p{}, %loop{}a ], [ %l{}p{}, %loop{}b{} ]
                    //\\  call fastcc void @intputchar(i8* nonnull %l{}p_)
                    \\  %l{}v{} = load i8, i8* %l{}p_, align 16
                    \\  %l{}v{} = icmp eq i8 %l{}v{}, 0
                    \\  br i1 %l{}v{}, label %loop{}b{}, label %loop{}a
                    \\
                ,.{ ln,
                    ln,
                    ln, ln,0, ln, ln,px, ln,lx,
                    //ln,
                    ln,vx+1, ln,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, _ln,_lx+1, ln
                });
                try w.print("\t\t\t\t\t;]\n", .{});
                vx += 2; // useless but justin-case
                ti += 1; // needed as 'continue expr' not executed
                break :blk;
            },
        } // switch
        try w.print("\n", .{});
    } // while

    //dprint("return(ln={}, ln_={}) {}\n", .{ln, ln_, ti-_ti});
    const vv = .{ .@"0"=ti-_ti, .@"1"=ln_ };
    return vv;
}

fn compile_as (
    allocator: std.mem.Allocator,
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
            options.compile_using.as.temp_path_s,
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

        const jumprefs = (try collect_jumprefs(allocator, tokens)) orelse {
            return error.SytaxError;
        };

        var jri: usize = 0;
        for (tokens.items) |token, i| {
            try switch (options.target) {
                .linux_x86_64 => switch (token) {
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
            "-o", options.compile_using.as.temp_path_o,
            options.compile_using.as.temp_path_s,
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
            options.compile_using.as.temp_path_o,
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
    );

    if (ret_ld.status != 0) return error.LdError;
}

fn collect_jumprefs(allocator :std.mem.Allocator, instrs: std.ArrayList(BFinstr)) !?std.ArrayList(isize) {
    var loc_stack = std.ArrayList(isize).init(allocator);
    //defer allocator.free(loc_stack);

    for (instrs.items) |instr, i| {
        if (instr == .From) {
            // store negation of location of self
            // this will be overwritten with location of pairing ']'
            // note that 'loc of parinig' > 0 as it cannot be 0
            // also note that only unpaired '[' gets negative value
            try loc_stack.append(-@intCast(isize, i));
        } else if (instr == .To) {
            if (loc_stack.items.len == 0) return null; // unmatched ']' error
            var top = loc_stack.items.len - 1;

            // find top of the unpaired '['
            while (top < std.math.maxInt(usize)) : (top -%= 1) {
                if (loc_stack.items[top] < 0) break;
            } else { return null; } // unmatched ']' error

            // store the location of pairing '[' for current ']'
            try loc_stack.append(-loc_stack.items[top]);
            // update the value of '[' with the location of pairing ']'
            loc_stack.items[top] = @intCast(isize, i);
        } // otherwise, just skip it
    }

    if (loc_stack.items.len == 0) return null; // unmatched ']' error
    var top = loc_stack.items.len - 1;

    // find top of the unpaired '['
    while (top < std.math.maxInt(usize)) : (top -%= 1) {
        if (loc_stack.items[top] < 0) return null; // unmatched '[' error
    } else { return loc_stack; }
}

fn compile_cl (
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {
    _ = tokens;
    _ = options;
    //TODO
    // use same c code as 'compile_gcc'
}

fn compile_gcc (
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {
    // REPORT zig does not let me use if as ternary expression <- with block body
    //const c_code = if (options.compile_using.gcc.with_libc) {

    var c_code_header: [:0]const u8 = undefined;
    var c_code_footer: [:0]const u8 = undefined;

    if (options.compile_using.gcc.with_libc) {
        c_code_header =
            \\#include <stdio.h>
            \\char buf[1000];
            \\int main(void) {
            \\  char *ptr = buf;
            ;

        c_code_footer =
            \\}
            ;

    } else {
        c_code_header = if (! options.compile_using.gcc.inlined)
            \\#include <syscall.h>
            \\char buf[1000];
            \\int intputchar(char c);
            \\int intgetchar();
            \\int main(void) {
            \\  char *ptr = buf;
        else
            \\#include <syscall.h>
            \\char buf[1000];
            \\int main(void) {
            \\  int ret; // used to store return value of read syscall
            \\  char *ptr = buf;
        ;

        // https://gcc.gnu.org/onlinedocs/gcc/Using-Assembly-Language-with-C.html
        c_code_footer = if (!options.compile_using.gcc.inlined) switch(options.target) {
            .linux_x86_64 =>
                \\}
                \\int intputchar(char c) {
                \\  asm volatile (
                \\    "syscall"
                \\    :
                \\    : "a"(__NR_write), "D"(1), "S"(&c), "d"(1)
                \\    : "memory"
                \\  );
                \\}
                \\int intgetchar() {
                \\  int ret;
                \\  char c;
                \\  asm volatile (
                \\    "syscall"
                \\    : "=a"(ret)
                \\    : "a"(__NR_read), "D"(0), "S"(&c), "d"(1)
                \\    : "memory"
                \\  );
                \\  return ret==1? c: -1; // -1 == EOF
                \\}
                ,

            .linux_x86 =>
                \\}
                \\int intputchar(char c) {
                \\  asm volatile (
                \\    "int $0x80"
                \\    :
                \\    : "a"(__NR_write), "b"(1), "c"(&c), "d"(1)
                \\    : "memory"
                \\  );
                \\}
                \\int intgetchar() {
                \\  int ret;
                \\  char c;
                \\  asm volatile (
                \\    "int $0x80"
                \\    : "=a"(ret)
                \\    : "a"(__NR_read), "b"(0), "c"(&c), "d"(1)
                \\    : "memory"
                \\  );
                \\  return ret==1? c: -1; // -1 == EOF
                \\}
                ,
            else => unreachable,
        } else
            \\}
        ;
    }

    const temp_path: [:0]const u8 = options.compile_using.gcc.temp_path;

    // create c tempfile
    {
        var file = try std.fs.cwd().createFile(temp_path, .{ .read = true, });
        defer file.close();

        try file.writeAll(c_code_header);

        for (tokens.items) |token| {
            try file.writeAll(translate_c(options, token));
            try file.writeAll("\n");
        }

        try file.writeAll(c_code_footer);
    }

    // REPORT execvpe does not hand over PATH var to the subproc if the path is absolute
    // furthermore, it is not get exported to child env (PATH only used to find the executable,
    // but the subproc doesn't get it). so we have to specify path anyway...
    const ret = try system(
        "gcc",
        &[_:null]?[*:0]const u8{
            "gcc",
            "-o", options.dst_path,
            temp_path,
            if (options.compile_using.gcc.with_libc)
                "-lc" // using it as a no-op option, needed place holder
            else switch (options.target) {
                .linux_x86 => "-m32",
                .linux_x86_64 => "-m64",
                else => unreachable,
            },
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
        // NOTE to compile 32bit executable on 64bit system with gcc
        // you would need gcc-multilib package installed.
        // this is another dependency using gcc (with build-essentials)
        // https://stackoverflow.com/a/46564864
        // though, you cannot do so on Alpine Linux
        // https://stackoverflow.com/a/40574830
    );

    if (ret.status != 0) return error.GccError;
}

fn translate_c (options: CompileOptions, instr: BFinstr) []const u8 {
    return switch (instr) {
        .Left  => "--ptr;",         // <
        .Right => "++ptr;",         // >
        .Inc   => "++*ptr;",        // +
        .Dec   => "--*ptr;",        // -
        .From  => "while(*ptr) {",  // [
        .To    => "}",              // ]
        .Get   => // ,
            if (options.compile_using.gcc.with_libc)
                "*ptr = getchar();"
            else if (! options.compile_using.gcc.inlined)
                "*ptr = intgetchar();"
            else switch (options.target) {
                .linux_x86_64 =>
                    \\asm volatile (
                    \\  "syscall"
                    \\  : "=a"(ret)
                    \\  : "a"(__NR_read), "D"(0), "S"(ptr), "d"(1)
                    \\  : "memory"
                    \\);
                    \\if(ret != 1) *ptr = -1; // -1 == EOF
                    ,
                .linux_x86 =>
                    \\asm volatile (
                    \\  "int $0x80"
                    \\  : "=a"(ret)
                    \\  : "a"(__NR_read), "b"(0), "c"(ptr), "d"(1)
                    \\  : "memory"
                    \\);
                    \\if(ret != 1) *ptr = -1; // -1 == EOF
                    ,
                else => unreachable,
            },
        .Put   => // .
            if (options.compile_using.gcc.with_libc)
                "putchar(*ptr);"
            else if (! options.compile_using.gcc.inlined)
                "intputchar(*ptr);"
            else switch (options.target) {
                .linux_x86_64 =>
                    \\asm volatile (
                    \\  "syscall"
                    \\  :
                    \\  : "a"(__NR_write), "D"(1), "S"(ptr), "d"(1)
                    \\  : "memory"
                    \\);
                    ,
                .linux_x86 =>
                    \\asm volatile (
                    \\  "int $0x80"
                    \\  :
                    \\  : "a"(__NR_write), "b"(1), "c"(ptr), "d"(1)
                    \\  : "memory"
                    \\);
                    ,
                else => unreachable,
            },
    };

}

fn tokenize (c: u8) ?BFinstr {
    return switch (c) {
        '<' => BFinstr.Left,
        '>' => BFinstr.Right,
        '+' => BFinstr.Inc,
        '-' => BFinstr.Dec,
        '[' => BFinstr.From,
        ']' => BFinstr.To,
        ',' => BFinstr.Get,
        '.' => BFinstr.Put,
        else => null,
        // need explicit type due to limitation of the compiler
        // https://stackoverflow.com/a/68424628
    };
}

const integrated_tests = blk: {
    // REPORT this makes the array to have same entry for all element
    //const TestPair = @TypeOf(.{ .@"0"="samples/hello.bf", .@"1"=integrated_test_hello, });
    // REPORT there's no way to express tuple type...
    const TestPair = struct {
        @"0": [:0]const u8,
        @"1": @TypeOf(integrated_test_hello),
    };
    break :blk [_]TestPair {
        .{ .@"0"="samples/hello.bf", .@"1"=integrated_test_hello, },
        .{ .@"0"="samples/rot13.bf", .@"1"=integrated_test_rot13, },
    };
};

test "integrated" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    dprint("\n", .{});
    for (integrated_tests) |_,i| {
        try test_for_all_options(allocator, i);
    }
}

fn test_for_all_options (
    al: std.mem.Allocator,
    i: usize,
) !void {
    const tokens = try load_and_parse(al, integrated_tests[i].@"0");

    var options = CompileOptions {
        .target = .linux_x86, // .linux_x86_64,
        .src_path = integrated_tests[i].@"0",
        .dst_path = "main",
        .compile_using = .{ .gcc = .{
            .with_libc = true, // false
            .inlined = false, //true
        }}, // .ass = { }
    };

    dprint("{} {s}\n", .{i, integrated_tests[i].@"0",});
    try test_for_target(al, i, tokens, &options, .linux_x86);
    try test_for_target(al, i, tokens, &options, .linux_x86_64);
}

fn test_for_target (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
    target: anytype,
) !void {
    options.*.target = target;
    //try test_for_gcc(al, i, tokens, options);
    //try test_for_cl( al, i, tokens, options);
    try test_for_as( al, i, tokens, options);
    try test_for_ll( al, i, tokens, options);
}

fn test_for_gcc (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    try test_for_gcc_options (al, i, tokens, options,  true,  true);
    try test_for_gcc_options (al, i, tokens, options,  true, false);
    try test_for_gcc_options (al, i, tokens, options, false,  true);
    try test_for_gcc_options (al, i, tokens, options, false, false);
}

fn test_for_gcc_options (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
    with_libc: bool,
    inlined: bool,
) !void {
    options.*.compile_using = .{ .gcc = .{
        .with_libc = with_libc,
        .inlined = inlined,
    }};
    _ = al;
    dprint("testing ", .{});
    dump_options(options.*);
    dprint("\n", .{});
    try compile_gcc(tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn test_for_cl (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    _ = al;
    options.*.compile_using = .{ .clang = .{
    }};
    dprint("testing ", .{});
    dump_options(options.*);
    dprint("\n", .{});
    try compile_cl(tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn test_for_as (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    options.*.compile_using = .{ .as = .{
    }};
    dprint("testing ", .{});
    dump_options(options.*);
    dprint("\n", .{});
    try compile_as(al, tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn test_for_ll (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    _ = al;
    options.*.compile_using = .{ .llvm = .{
    }};
    dprint("testing ", .{});
    dump_options(options.*);
    dprint("\n", .{});
    try compile_ll(tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn integrated_test_hello () !void {
    const ret = try system(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash", "-c", "diff <(./main) <(echo 'Hello World!')", null,
        }, &[_:null]?[*:0]const u8{null}
    );

    // REPORT this is a bug in zig, you can't just use '0'
    try std.testing.expectEqual(@as(u32, 0), ret.status);
}

fn integrated_test_rot13 () !void {
    const input = "abcdefghijklmnopqrstuvwxyz";
    const ret = try system(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash",
            "-c", "[ \"`echo '" ++ input ++ "' | ./main | ./main`\" == '" ++ input ++  "' ]",
            null,
        }, &[_:null]?[*:0]const u8{null}
    );

    // REPORT this is a bug in zig, you can't just use '0'
    try std.testing.expectEqual(@as(u32, 0), ret.status);
}

fn dump_options(options: CompileOptions) void {
    dprint("{s}:\t{s} => {s}\t| {s} - ", .{
        @tagName(options.target),
        options.src_path, options.dst_path,
        @tagName(options.compile_using),
    });

    //const none: [:0] const u8 = "";

    _ = switch (options.compile_using) {
        .gcc => |opts|
            // REPORT it does not even work...
            //dprint("{s} {s}", .{
            //    // REPORT, peer coercing does not happen between if branches
            //    // strictly coerced into the type of 'then' branch
            //    //if (opts.with_libc) "with_libc" else "",
            //    //if (opts.inlined) "inlined" else "",
            //    if (!opts.with_libc) none else "with_libc",
            //    if (!opts.inlined) none else "inlined",
            //}),
            dprint("{} {}", .{
                opts.with_libc,
                opts.inlined,
            }),
        .as => |_|
            //dprint("{s}", .{
            //    //if (opts.quick) "quick" else "",
            //    if (!opts.quick) none else "quick",
            //}),
            dprint("{s}", .{
                ".",
            }),
        .llvm => |_|
            dprint("{s}", .{
                ".",
            }),
        .clang => |_|
            dprint("{s}", .{
                ".",
            }),
    };
}

fn test_system () !void {
    const ret = try system("/bin/bash", &[_:null]?[*:0]u8{"/bin/bash", "-c", "sleep 5; date", null}, &[_:null]?[*:0]u8{null});
    std.testing.expect(0, ret.status);
}

// like subshell execution by `cmd args..` in bash
// run the command and waits for the result
fn system (
    file: [*:0]const u8,
    argv_ptr: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) (std.os.ExecveError || std.os.ForkError) ! std.os.WaitPidResult {
    const pid = try std.os.fork();
    return if (pid != 0) std.os.waitpid(pid, 0)
           else std.os.execvpeZ(file, argv_ptr, envp);
}
