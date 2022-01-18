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

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // loading ===========
    const contents: []u8 = blk: {
        var file = try std.fs.cwd().openFile("hello.bf", .{ .read = true });
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

    // compile & store =========
    {
        const c_code_header =
            \\#include <stdio.h>
            \\char buf[1000];
            \\int main(void) {
            \\  char *ptr = buf;
            ;

        const c_code_footer =
            \\}
            ;

        var file = try std.fs.cwd().createFile("hello.c", .{ .read = true, });
        defer file.close();

        try file.writeAll(c_code_header);

        for (tokens.items) |token| {
            try file.writeAll(translate_c(token));
            try file.writeAll("\n");

        }

        try file.writeAll(c_code_footer);

        //compiler killer!
        //const x: [3:null] ?[*:0]const u8  = [_:null]?[*:0]u8{"hello.c", "-o", "hello"};

        _ = std.os.system.execve(
            "/usr/bin/gcc",
            &[_:null]?[*:0]const u8{
                "/usr/bin/gcc",
                "hello.c",
                "-o", "hello"
            }, &[_:null]?[*:0]const u8{
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin"
        });
    }
}

fn translate_c (instr :BFinstr) []const u8 {
    return switch (instr) {
        .Left  => "++ptr;",          // <
        .Right => "--ptr;",          // >
        .Inc   => "++*ptr;",         // +
        .Dec   => "--*ptr;",         // -
        .From  => "while(*ptr) {",   // [
        .To    => "}",               // ]
        .Get   => "getchar();",      // .
        .Put   => "putchar(*ptr);",  // ,
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

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}

