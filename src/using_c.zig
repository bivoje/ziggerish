
const std = @import("std");

const BFinstr        = @import("types.zig").BFinstr;
const CompileOptions = @import("types.zig").CompileOptions;

pub fn compile (
    al: std.mem.Allocator,
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {

    var gcc = options.method.gcc;

    if (gcc.inlined and gcc.libc) {
        // TODO warn the user
        gcc.inlined = false;
    }

    // TODO extract
    const exit_body = switch (options.target) {
        .linux_x86_64 =>
            \\  asm volatile (
            \\    "syscall"
            \\    :
            \\    : "a"(__NR_exit), "D"(0)
            \\    : "memory"
            \\  );
            ,
        .linux_x86 =>
            \\  asm volatile (
            \\    "int $0x80"
            \\    :
            \\    : "a"(__NR_exit), "b"(0)
            \\    : "memory"
            \\  );
            ,
        else => unreachable,
    };

    const putc_body = switch (options.target) {
        .linux_x86_64 =>
            \\  asm volatile (
            \\    "syscall"
            \\    :
            \\    : "a"(__NR_write), "D"(1), "S"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            ,
        .linux_x86 =>
            \\  asm volatile (
            \\    "int $0x80"
            \\    :
            \\    : "a"(__NR_write), "b"(1), "c"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            ,
        else => unreachable,
    };

    const getc_body  = switch (options.target) {
        .linux_x86_64 =>
            \\  asm volatile (
            \\    "syscall"//
            \\    : "=a"(ret)
            \\    : "a"(__NR_read), "D"(0), "S"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            \\  if (ret!=1) *ptr = -1;
            ,
        .linux_x86 =>
            \\  asm volatile (
            \\    "int $0x80"
            \\    : "=a"(ret)
            \\    : "a"(__NR_read), "b"(0), "c"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            \\  if (ret!=1) *ptr = -1;
            ,
        else => unreachable,
    };

    const getchar: []const u8 =
        if (gcc.inlined) getc_body
        else if (gcc.libc) "  *ptr = getchar();"
        else "  intgetchar(ptr);";

    const putchar: []const u8 =
        if (gcc.inlined) putc_body
        else if (gcc.libc) "  putchar(*ptr);"
        else "  intputchar(ptr);";

    var file = try std.fs.cwd().createFile(gcc.temp_path, .{ .read = true, });
    defer file.close();
    var w = file.writer();

    try w.writeAll(
        \\char buf[1000];
        \\
    );

    if (gcc.libc) {
        try w.writeAll(
            \\#include <stdio.h>
            \\#include <stdlib.h>
            \\
        );
    } else {
        try w.writeAll(
            \\#include <syscall.h>
            \\
        );
        if (! gcc.inlined) {
            try w.writeAll(
                \\void intputchar(char *ptr) {
                \\
            );

            try w.writeAll(putc_body);

            try w.writeAll(
                \\
                \\}
                \\
                \\void intgetchar(char *ptr) {
                \\  int ret;
                \\
            );

            try w.writeAll(getc_body);

            try w.writeAll(
                \\
                \\}
                \\
                \\void intexit() {
                \\
            );

            try w.writeAll(exit_body);

            try w.writeAll(
                \\
                \\}
                \\
            );
        } // not inlined
    } // not libc

    try w.writeAll(
        \\int main(void) {
        \\  char *ptr = buf;
        \\
    );

    if (gcc.inlined)
        try w.writeAll(
            \\  int ret; // used to store return value of read syscall
            \\
        );

    // main body
    for (tokens.items) |token| {
        try w.writeAll(switch (token) {
            .Left  => "  --ptr;",         // <
            .Right => "  ++ptr;",         // >
            .Inc   => "  ++*ptr;",        // +
            .Dec   => "  --*ptr;",        // -
            .From  => "  while(*ptr) {",  // [
            .To    => "  }",              // ]
            .Get   => getchar,            // ,
                // REPORT need explicit casting to invoke proper peer resol
            .Put   => putchar,            // .
        });

        try w.writeAll("\n");
    }

    try w.writeAll(
        if (gcc.inlined) exit_body
        else if (gcc.libc) "  exit(0);"
        else "  intexit();",
    );


    try w.writeAll("\n}\n");

    // REPORT execvpe does not hand over PATH var to the subproc if the path is absolute
    // furthermore, it is not get exported to child env (PATH only used to find the executable,
    // but the subproc doesn't get it). so we have to specify path anyway...
    const proc = try std.ChildProcess.init(
        &[_] []const u8{
            "gcc",
            "-o", options.dst_path,
            gcc.temp_path,
            if (gcc.libc)
                "-lc" // using it as a no-op option, needed place holder
            else switch (options.target) {
                .linux_x86 => "-m32",
                .linux_x86_64 => "-m64",
                else => unreachable,
            },
        },
        // NOTE to compile 32bit executable on 64bit system with gcc
        // you would need gcc-multilib package installed.
        // this is another dependency using gcc (with build-essentials)
        // https://stackoverflow.com/a/46564864
        // though, you cannot do so on Alpine Linux
        // https://stackoverflow.com/a/40574830
        al,
    );

    switch (try proc.spawnAndWait()) {
        .Exited => |e| if (e == 0) return else return error.GccError,
        else => return error.GccError,
    }
}
