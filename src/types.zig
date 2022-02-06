const std = @import("std");
const C = @cImport({
    @cInclude("stdlib.h");
});

pub const BFinstr = enum {
    Left,  // <
    Right, // >
    Inc,   // +
    Dec,   // -
    From,  // [
    To,    // ]
    Get,   // ,
    Put,   // .
    Dump,  // #

    pub fn token (c: u8) ?BFinstr {
        return switch (c) {
            '<' => BFinstr.Left,
            '>' => BFinstr.Right,
            '+' => BFinstr.Inc,
            '-' => BFinstr.Dec,
            '[' => BFinstr.From,
            ']' => BFinstr.To,
            ',' => BFinstr.Get,
            '.' => BFinstr.Put,
            '#' => BFinstr.Dump,
            else => null,
            // need explicit type due to limitation of the compiler
            // https://stackoverflow.com/a/68424628
        };
    }
};

pub const CompileOptions = struct {
    src_path: [:0]const u8 = "-", // default to stdin
    dst_path: [:0]const u8 = "-", // default to stdout

    mem_size: usize = 100,
    verbose: bool = false,
    warning: bool = true,

    eof_by: EofBy,
    target: Target,
    method : CompileUsing,

    pub const Target = enum {
        linux_x86, linux_x86_64, windows,
    };

    pub const EofBy = enum {
        neg1, noop, zero,
    };

    pub const CompileUsing = union(enum) {
        gcc: struct {
            libc: bool = true,
            inlined: bool = false,
            temp_path: [:0]const u8 = "temp.c",
        },
        as: struct {
            temp_path_s: [:0]const u8 = "temp.s",
            temp_path_o: [:0]const u8 = "temp.o",
        },
        ll: struct {
            temp_path_ll: [:0]const u8 = "temp.ll",
            temp_path_s: [:0]const u8 = "temp.s",
            temp_path_o: [:0]const u8 = "temp.o",
            use_clang:bool = true,
        },
        clang: struct {
        },
    };

    pub const parse_args = parse_opt;
    pub const dump = dump_options;

};

fn parse_opt (al: std.mem.Allocator, argv: [][*:0]const u8) ArgError!CompileOptions {
    var options = CompileOptions {
         // FIXME get default target at compile time
        .target = .linux_x86_64,
        .method = .{ .as = .{}},
        .eof_by = .noop,
    };

    var i: usize = 0;
    //e.g: ziggerish hello.bf : ?target=linux_x86 ?mem_size=200 +verbose warning?=false : gcc +inlined -libc =temp_path?temp.c : hello

    // input file
    // TODO multi-source compile not supported, yet.
    i += 1; // skip progname
    while (i < argv.len) : (i+=1) {
        const arg = std.mem.sliceTo(argv[i], 0);
        if (std.mem.eql(u8, arg, ":")) break;
        options.src_path = std.mem.sliceTo(argv[i], 0);
    }

    // general options
    i += 1; // skip ':'
    i += try set_param_struct(CompileOptions, i, argv, &options, assign_struct_field, al);

    // compile method specific options
    i += 1; // skip ':'
    {
        const arg = if (i < argv.len) std.mem.sliceTo(argv[i], 0)
                    else return error.MalformedArg;
        i += 1;

        inline for (@typeInfo(CompileOptions.CompileUsing).Union.fields) |field| {
            if (std.mem.eql(u8, field.name, arg)) {
                var method_options = field.field_type {};
                i += try set_param_struct(field.field_type, i, argv, &method_options, assign_struct_field, al);
                options.method = @unionInit(CompileOptions.CompileUsing, field.name, method_options);
            }
        }
    }

    // output file
    // TODO correctly handle multiple files
    i += 1; // skip ':'
    while (i < argv.len) : (i+=1) {
        const arg = std.mem.sliceTo(argv[i], 0);
        if (std.mem.eql(u8, arg, ":")) break;
        options.dst_path = std.mem.sliceTo(argv[i], 0);
    }

    return options;
}

const ArgError = error {
    InvalidPrefix,
    NoAssignValue,
    UnknownOption,
    UnknownValue,
    MalformedArg,
} || error {OutOfMemory};

fn set_param_struct (
    comptime T: type,
    _i: usize,
    argv: [][*:0]const u8,
    options: *T,
    assign: fn (
        type,
        comptime std.builtin.TypeInfo.StructField,
        *T,
        []const u8,
        std.mem.Allocator
    ) ArgError!void,
    allocator: std.mem.Allocator,
) ArgError!usize { // returns # of args read
    var i = _i;
    while (i < argv.len) : (i+=1) {
        //convert [*:0]u8 (unknown len) to [:0]u8 (runtime-known len)
        const arg = std.mem.sliceTo(argv[i], 0);
        if (std.mem.eql(u8, arg, ":")) break;

        var key: []const u8 = undefined;
        var val: []const u8 = undefined;
        switch (arg[0]) {
            @as(u8,'?') => {
                const j = std.mem.indexOfScalar(u8, arg, @as(u8,'='))
                          orelse return error.NoAssignValue;
                {key=arg[1..j]; val=arg[j+1..];}
            },
            @as(u8,'+') => {key=arg[1..]; val="true"; },
            @as(u8,'-') => {key=arg[1..]; val="false"; },
            else => {
                //dprint("invalid prefix: {s}\n", .{arg});
                return error.InvalidPrefix;
            },
        }

//        const fields = switch (@typeInfo(T)) {
//            .Struct => |e| e.fields,
//            .Union  => |e| e.fields,
//            else => @compileError("container required for set_param_struct"),
//        };

        inline for (@typeInfo(T).Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                try assign(T, field, options, val, allocator);
                break;
            }
        } else return error.UnknownOption;
    }

    return i - _i;
}

fn assign_struct_field (
    comptime T: type,
    comptime field: std.builtin.TypeInfo.StructField,
    options: *T,
    val: []const u8,
    al: std.mem.Allocator
) ArgError!void {
    switch (field.field_type) {
        bool => {
            if (std.mem.eql(u8, val, "true")) {
                @field(options, field.name) = true;
            } else if (std.mem.eql(u8, val, "false")) {
                @field(options, field.name) = false;
            } else return error.UnknownValue;
        },
        [:0]const u8 => {
            // FIXME only valid in arena allocator,
            // it never frees allocated memory
            @field(options, field.name) = try al.dupeZ(u8,val);
        },
        usize => {
            // FIXME what if negative given?
            const ret: c_int = C.atoi(@ptrCast([*c]const u8, val));
            @field(options, field.name) = @intCast(usize, ret);
        },
        else => {
            switch (@typeInfo(field.field_type)) {
                .Enum => |E| {
                    inline for (E.fields) |efield| {
                        if (std.mem.eql(u8, efield.name, val)) {
                            @field(options, field.name) = @intToEnum(field.field_type, efield.value);
                            return;
                        }
                    } return error.UnknownValue;
                },
                else => {
                    dprint("{s} {} {s}\n", .{field.name, field.field_type, val});
                    //@compileError("assign_struct_field not implemented for " ++ @typeName(field.field_type));
                },
            }
        },
    }
}

// TODO remove???
const dprint = @import("std").debug.print;

fn dump_options(options: CompileOptions) void {
    dprint("{s}:{s}\t{s} => {s}\t| {s} - ", .{
        @tagName(options.target),
        @tagName(options.eof_by),
        options.src_path, options.dst_path,
        @tagName(options.method),
    });

    const none: [:0] const u8 = " ";

    _ = switch (options.method) {
        .gcc => |opts| {
            // REPORT it does not even work...
            const a = (if (!opts.libc) none else "libc");
            const b = (if (!opts.inlined) none else "inlined");
            dprint("{s} {s}", .{
                // REPORT, peer coercing does not happen between if branches
                // strictly coerced into the type of 'then' branch
                //if (opts.libc) "libc" else "",
                //if (opts.inlined) "inlined" else "",
                a, b
            });
            return;
        },
        .as => |_|
            dprint("{s}", .{
                ".",
            }),
        .ll => |_|
            dprint("{s}", .{
                ".",
            }),
        .clang => |_|
            dprint("{s}", .{
                ".",
            }),
    };

    dprint(" | {} {} {} ", .{
        options.mem_size,
        options.verbose,
        options.warning,
    });
}
