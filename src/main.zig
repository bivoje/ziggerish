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

const GccOptions = struct {
    with_libc: bool = false,
};

const CompileOptions = struct {
    target: enum {
        linux_x86, linux_x86_64, windows,
    },

    compile_using: union(enum) {
        gcc: GccOptions,
        as: struct {
            quick: bool,
        },
    },
};


pub fn main () anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const tokens = try load_and_parse(allocator, "hello.bf");
    const options = CompileOptions { .target = .linux_x86, .compile_using = .{ .gcc = GccOptions { .with_libc = false, }, } };
    try compile_c(allocator, options, tokens, "main");
}

fn load_and_parse (allocator: std.mem.Allocator, src_path: [:0]const u8) !std.ArrayList(BFinstr) {
    // loading ===========
    const contents: []u8 = blk: {
        var file = try std.fs.cwd().openFile(src_path, .{ .read = true });
        defer file.close();

        break :blk try file.reader().readAllAlloc(allocator, std.math.inf_u64);
    };

    // parsing ==========
    var tokens = blk: {
        var tokens = std.ArrayList(BFinstr).init(allocator);
        //defer allocator.free(tokens);

        for (contents) |c| {
            if (tokenize(c)) |token| {
                try tokens.append(token);
            }
        }

        break :blk tokens;
    };

    return tokens;
}

fn compile_c (allocator: std.mem.Allocator, options: CompileOptions, tokens: std.ArrayList(BFinstr), dest_path: [:0]const u8) !void {
    // REPORT zig does not let me use if as ternary expression <- with block body
    //const c_code = if (options.compile_using.gcc.with_libc) {

    //var c_code_header: [:0]const u8 = undefined;
    var c_code_header: [:0]const u8 = undefined;
    var c_code_footer: [:0]const u8 = undefined;

    if (options.compile_using.gcc.with_libc) {
        const c_code = .{ .header = 
            \\#include <stdio.h>
            \\char buf[1000];
            \\int main(void) {
            \\  char *ptr = buf;

        , .footer =
            \\}
        };
        c_code_header = c_code.header;
        c_code_footer = c_code.footer;

    } else {
        // REPORT struct field initialization with switch does not work
        c_code_header =
            \\#include <syscall.h>
            \\#include <stdio.h> // for getchar
            \\char buf[1000];
            \\int intputchar(char c);
            \\int main(void) {
            \\  char *ptr = buf;
            ;

        c_code_footer = switch(options.target) {
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
                ,
            else => unreachable,
        };
    }

    // zig documentation page is still in experimental phase.
    // could find handy this function from the source.
    // go for the source rather than documentation, at least for now.
    const temp_path: [:0]u8 = try std.fmt.allocPrintZ(allocator, "{s}.c", .{dest_path});
    defer allocator.free(temp_path);

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

    //compiler killer!
    //const x: [3:null] ?[*:0]const u8  = [_:null]?[*:0]u8{"hello.c", "-o", "hello"};

    //Fault, no null added <- checked by strace
    //const e = std.os.execveZ(
    //    //"/usr/bin/gcc",
    //    "./dump_argv",
    //    &[_:null]?[*:0]const u8{
    //        "/usr/bin/gcc",
    //        //"-o", dest_path,
    //        "-o", "main",
    //        temp_path,
    //        //"main.c",
    //    }, &[_:null]?[*:0]const u8{
    //        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin",
    //});

    // REPORT execvpe does not hand over PATH var to the subproc if the path is absolute
    // furthermore, it is not get exported to child env (PATH only used to find the executable,
    // but the subproc doesn't get it). so we have to specify path anyway...
    const ret = try system(
        "gcc",
        &[_:null]?[*:0]const u8{
            "gcc",
            "-o", dest_path,
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
    );

    if (ret.status != 0) return error.GccError;
}

fn translate_c (options: CompileOptions, instr: BFinstr) []const u8 {
    return switch (instr) {
        .Left  => "++ptr;",         // <
        .Right => "--ptr;",         // >
        .Inc   => "++*ptr;",        // +
        .Dec   => "--*ptr;",        // -
        .From  => "while(*ptr) {",  // [
        .To    => "}",              // ]
        .Get   => "*ptr = getchar();", // ,
        .Put   => // .
            if (options.compile_using.gcc.with_libc)
                "putchar(*ptr);"
            else
                "intputchar(*ptr);"
            ,
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

test "c_hello" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const tokens = try load_and_parse(allocator, "hello.bf");
    const options = CompileOptions { .target = .linux_x86, .compile_using = .{ .gcc = GccOptions { .with_libc = true, }, } };
    try compile_c(allocator, options, tokens, "main");

    const ret = try system(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash", "-c", "diff <(./main) <(echo 'Hello World!')", null,
        }, &[_:null]?[*:0]const u8{null}
    );

    // REPORT this is a bug in zig, you can't just use '0'
    try std.testing.expectEqual(@as(u32, 0), ret.status);
}

test "c_linux_86_hello" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const tokens = try load_and_parse(allocator, "hello.bf");
    const options = CompileOptions { .target = .linux_x86, .compile_using = .{ .gcc = GccOptions { .with_libc = false, }, } };
    try compile_c(allocator, options, tokens, "main");

    const ret = try system(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash", "-c", "diff <(./main) <(echo 'Hello World!')", null,
        }, &[_:null]?[*:0]const u8{null}
    );

    // REPORT this is a bug in zig, you can't just use '0'
    try std.testing.expectEqual(@as(u32, 0), ret.status);
}

test "c_linux_86_64_rot13" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const tokens = try load_and_parse(allocator, "rot13.bf");
    const options = CompileOptions { .target = .linux_x86_64, .compile_using = .{ .gcc = GccOptions { .with_libc = false, }, } };
    try compile_c(allocator, options, tokens, "main");

    
    const ret = try system(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash",
            "-c", "[ \"`echo 'abcdefghijklmnopqrstuvwxyz' | ./main | ./main`\" == 'abcdefghijklmnopqrstuvwxyz' ]",
            null,
        }, &[_:null]?[*:0]const u8{null}
    );

    // REPORT this is a bug in zig, you can't just use '0'
    try std.testing.expectEqual(@as(u32, 0), ret.status);
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
