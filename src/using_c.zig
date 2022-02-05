
const std = @import("std");

const BFinstr        = @import("types.zig").BFinstr;
const CompileOptions = @import("types.zig").CompileOptions;

const system = @import("util.zig").system;

pub fn compile (
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {
    // REPORT zig does not let me use if as ternary expression <- with block body
    //const c_code = if (options.method.gcc.libc) {

    var c_code_header: [:0]const u8 = undefined;
    var c_code_footer: [:0]const u8 = undefined;

    if (options.method.gcc.libc) {
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
        c_code_header = if (! options.method.gcc.inlined)
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
        c_code_footer = if (!options.method.gcc.inlined) switch(options.target) {
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

    const temp_path: [:0]const u8 = options.method.gcc.temp_path;

    // create c tempfile
    {
        var file = try std.fs.cwd().createFile(temp_path, .{ .read = true, });
        defer file.close();

        try file.writeAll(c_code_header);

        for (tokens.items) |token| {
            try file.writeAll(translate(options, token));
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
            if (options.method.gcc.libc)
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

fn translate (options: CompileOptions, instr: BFinstr) []const u8 {
    return switch (instr) {
        .Left  => "--ptr;",         // <
        .Right => "++ptr;",         // >
        .Inc   => "++*ptr;",        // +
        .Dec   => "--*ptr;",        // -
        .From  => "while(*ptr) {",  // [
        .To    => "}",              // ]
        .Get   => // ,
            if (options.method.gcc.libc)
                "*ptr = getchar();"
            else if (! options.method.gcc.inlined)
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
            if (options.method.gcc.libc)
                "putchar(*ptr);"
            else if (! options.method.gcc.inlined)
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
