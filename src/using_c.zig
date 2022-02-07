
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

    const a = switch (options.target) {
        .linux_x86_64 =>
            \\  asm volatile (
            \\    "syscall"//
            \\    : "=a"(ret)
            \\    : "a"(__NR_read), "D"(0), "S"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            ,
        .linux_x86 =>
            \\  asm volatile (
            \\    "int $0x80"
            \\    : "=a"(ret)
            \\    : "a"(__NR_read), "b"(0), "c"(ptr), "d"(1)
            \\    : "memory"
            \\  );
            ,
        else => unreachable,
    };
    var b = switch (options.eof_by) {
        .neg1 => "  if (ret!=1) *ptr = -1;",
        .noop => "  // place holder ------",
        .zero => "  if (ret!=1) *ptr = 0;;",
    };

    var getc_body_buf = [_]u8{undefined} ** 200;
    const getc_body: []const u8 = try std.fmt.bufPrint(&getc_body_buf, "{s}\n{s}", .{
        //REPORT only selects the first branch whatsoever
        //switch (options.target) {
        //    .linux_x86_64 =>
        //        \\  asm volatile (
        //        \\    "syscall"//
        //        \\    : "=a"(ret)
        //        \\    : "a"(__NR_read), "D"(0), "S"(ptr), "d"(1)
        //        \\    : "memory"
        //        ,
        //    .linux_x86 =>
        //        \\  asm volatile (
        //        \\    "int $0x80"
        //        \\    : "=a"(ret)
        //        \\    : "a"(__NR_read), "b"(0), "c"(ptr), "d"(1)
        //        \\    : "memory"
        //        ,
        //    else => unreachable,
        //},
        a, b
    });

    const getchar: []const u8 =
        if (gcc.inlined) getc_body
        else if (gcc.libc)
            switch (options.eof_by) {
                .neg1 => "  *ptr = getchar();",
                .noop =>
                    \\  ret = getchar();
                    \\  *ptr = ret==-1? *ptr: ret;
                    ,
                .zero =>
                    \\  ret = getchar();
                    \\  *ptr = ret==-1? 0: ret;
                    ,
            }
        else "  intgetchar(ptr);";

    const putchar: []const u8 =
        if (gcc.inlined) putc_body
        else if (gcc.libc) "  putchar(*ptr);"
        else "  intputchar(ptr);";

    var file = try std.fs.cwd().createFile(gcc.temp_path, .{ .read = true, });
    defer file.close();
    var w = file.writer();

    try w.print(
        \\char buf[{d}];
        \\
    , .{ options.mem_size });

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

    try w.print(
        \\void dump(char *p) {{
        \\ char c;
        \\ char* ptr = &c;
        \\ char *dst = p + 5; p = buf-1;
        \\ while(++p != dst) {{
        \\  c = ((*p >> 4) & 0x0F) + 0x30;
        \\  c += c<58? 0: 7;
        \\{s}
        \\  c = (*p & 0x0F) + 0x30;
        \\  c += c<58? 0: 7;
        \\{s}
        \\  c = 0x20;
        \\{s}
        \\ }}
        \\ c = 0x0A;
        \\{s}
        \\}}
        \\
    , .{ putchar, putchar, putchar, putchar});

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

    if (gcc.libc and options.eof_by != .neg1)
        try w.writeAll(
            \\  int ret; // temporary store of getchar result
            \\
        );


    // main body
    for (tokens.items) |token| {
        try w.writeAll(switch (token) {
            .Dump  => "  dump(ptr);",     // #
            .Left  => "  --ptr;",         // <
            .Right => "  ++ptr;",         // >
            .Inc   => "  ++*ptr;",        // +
            .Dec   => "  --*ptr;",        // -
            .From  => "  while(*ptr) {",  // [
            .To    => "  }",              // ]
            .Get   => getchar,            // ,
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
