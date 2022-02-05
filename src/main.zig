const std = @import("std");
const dprint = std.debug.print;

const BFinstr        = @import("types.zig").BFinstr;
const CompileOptions = @import("types.zig").CompileOptions;
const system         = @import("util.zig").system;

const using_c = @import("using_c.zig");
const using_as = @import("using_as.zig");
const using_ll = @import("using_ll.zig");

pub fn main () anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // it allocates and copies each arg into a new memory,
    // we dont need it as only comparison & const refering is required.
    //var arg_it = std.process.args();
    //_ = arg_it.skip();
    //_ = arg_it.next(al);

    // so, instead, we acess os.argv directly.
    // REPORT this panics zig compiler
    // const options  = try parse_opt(allocator, argv);
    const argv: [][*:0]const u8 = std.os.argv;
    const options = try CompileOptions.parse_args(allocator, argv);
    options.dump();
    dprint("\n", .{});

    const tokens = load_and_parse(allocator, options.src_path) catch |e| {
        // TODO elaborate error messages
        dprint("could not load and parse, {}\n", .{e});
        return;
    };

    compile(allocator, tokens, options) catch |e| {
        // TODO elaborate error messages
        dprint("could not compile, {}\n", .{e});
        return;
    };
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
            if (BFinstr.token(c)) |token| {
                try tokens.append(token);
            } // ignore invalid characters
        }

        break :blk tokens;
    };

    return tokens;
}

fn compile (
    al : std.mem.Allocator,
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {
    return switch(options.method) {
        .gcc    => using_c.compile(al, tokens, options),
        .as     => using_as.copmile(al, tokens, options),
        .llvm   => using_ll.compile(tokens, options),
        .clang  => compile_cl(tokens, options),
    };
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

test "argparse" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // REPORT why in the hell can't i use const here?
    var argv = [_][*:0]const u8 {
        "ziggerish",
        "samples/hello.bf", ":",
        "?target=linux_x86", "?mem_size=200", "+verbose", "?warning=false", ":",
        "gcc", "+inlined", "-libc", "?temp_path=temp.c", ":",
        "hello",
    };

    const ret = try CompileOptions.parse_args(allocator, &argv);

    try std.testing.expect(std.mem.eql(u8, ret.src_path, "samples/hello.bf"));
    try std.testing.expect(std.mem.eql(u8, ret.dst_path, "hello"));
    try std.testing.expectEqual(ret.target, .linux_x86);
    try std.testing.expectEqual(ret.mem_size, 200);
    try std.testing.expectEqual(ret.verbose, true);
    try std.testing.expectEqual(ret.warning, false);
    try std.testing.expectEqual(ret.method.gcc.inlined, true);
    try std.testing.expectEqual(ret.method.gcc.libc, false);
    try std.testing.expect(std.mem.eql(u8, ret.method.gcc.temp_path, "temp.c"));
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
        .eof_by = .noop, // .zero TODO
        .src_path = integrated_tests[i].@"0",
        .dst_path = "main",
        .method = .{ .gcc = .{
            .libc = true, // false
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
    try test_for_gcc(al, i, tokens, options);
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
    libc: bool,
    inlined: bool,
) !void {
    options.*.method = .{ .gcc = .{
        .libc = libc,
        .inlined = inlined,
    }};
    dprint("testing ", .{});
    options.dump();
    dprint("\n", .{});
    try using_c.compile(al, tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn test_for_cl (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    _ = al;
    options.*.method = .{ .clang = .{
    }};
    dprint("testing ", .{});
    options.dump();
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
    options.*.method = .{ .as = .{
    }};
    dprint("testing ", .{});
    options.dump();
    dprint("\n", .{});
    try using_as.compile(al, tokens, options.*);
    try integrated_tests[i].@"1"();
}

fn test_for_ll (
    al: std.mem.Allocator,
    i: usize,
    tokens: std.ArrayList(BFinstr),
    options: *CompileOptions,
) !void {
    _ = al;
    options.*.method = .{ .llvm = .{
    }};
    dprint("testing ", .{});
    options.dump();
    dprint("\n", .{});
    try using_ll.compile(tokens, options.*);
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
