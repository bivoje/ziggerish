
fn deep_equal(comptime T: type, ref: T, new: T) bool {
    return switch (@typeInfo(T)) {
        .Pointer    => |P| switch (P.size) {
            .One  => deep_equal(P.child, ref.*, new.*),
            .Many, .Slice  => blk: {
                if (ref.len != new.len) break :blk false;
                var i: usize = 0;
                break :blk while (i < ref.len) : (i += 1) {
                    if (! deep_equal(P.child, ref[i], new[i])) break false;
                } else
                    if (P.sentinel) |_| {
                        break :blk ref[ref.len] == new[new.len];
                    } else true
                ;
            },
            .C => @compileError("can't compare c_ptr"),
        },
        .Array  => |A| std.mem.eql(A.child, &ref, &new), // FIXME what if pointer?
        .Vector => @reduce(.And, ref == new), // FIXME what if pointer?
        .Optional   => |O| if     (ref == null and new == null) true
                           else if(ref == null and new != null) false
                           else if(ref != null and new == null) false
                           else deep_equal(O.child, ref.?, new.?),
        .Struct     =>
            inline for (@typeInfo(T).Struct.fields) |field| {
                const refval = @field(ref, field.name);
                const newval = @field(ref, field.name);
                if (! deep_equal(field.field_type, refval, newval))
                    break false;
            } else true,
        .Union       => |_| blk: {
            if (@enumToInt(ref) != @enumToInt(new)) break :blk false;
            // FIXME there's currently no way to access to unkown of union field
            // so, we need to check for each tag
            inline for (@typeInfo(T).Union.fields) |field| {
                const refval = @field(ref, field.name);
                const newval = @field(ref, field.name);
                if (std.mem.eql(u8, field.name, @tagName(ref))) {
                    if (! deep_equal(field.field_type, refval, newval))
                        break :blk false;
                }
            } else break :blk true;
        },
        else => ref == new,

        //ErrorUnion: ErrorUnion,
        //ErrorSet: ErrorSet,
        //Fn: Fn,
        //BoundFn: Fn,
        //Opaque: Opaque,
        //Frame: Frame,
        //AnyFrame: AnyFrame,
    };
}

const std = @import("std");
const expect = std.testing.expect;

test "primtive" {
    try expect( deep_equal(u8, 3, 3));
    try expect(!deep_equal(u8, 3, 4));
    try expect( deep_equal(bool, true,  true ));
    try expect( deep_equal(bool, false, false));
    try expect(!deep_equal(bool, true,  false));
    try expect(!deep_equal(bool, false, true ));
    try expect( deep_equal(f32, 3.14, 3.14));
    try expect(!deep_equal(f32, 3.14, 3.15));
}

const Vector = std.meta.Vector;

test "vector" {
    var v1: Vector(5,u8) = [_]u8{ 1,2,3,4,5 };
    var v2: Vector(5,u8) = [_]u8{ 1,2,3,4,6 };
    try expect(!deep_equal(Vector(5,u8), v1, v2));
    v2[4] = 5;
    try expect( deep_equal(Vector(5,u8), v1, v2));
}


test "array" {
    var a1: [5]u8 = [5]u8{ 1,2,3,4,5 };
    var a2: [5]u8 = [5]u8{ 1,2,3,4,6 };
    try expect(!deep_equal([5]u8, a1, a2));
    a2[4] = 5;
    try expect( deep_equal([5]u8, a1, a2));
}

test "array sentinel" {
    var a1: [5:8]u8 = [5:8]u8{ 1,2,3,4,5 };
    var a2: [5:8]u8 = [5:8]u8{ 1,2,3,4,6 };
    try expect(!deep_equal([5:8]u8, a1, a2));
    a2[4] = 5;
    try expect( deep_equal([5:8]u8, a1, a2));
}

test "pointer varlen1" {
    var a1: []const u8 = "abcde";
    var a2: []const u8 = "abcd";
    try expect(!deep_equal([]const u8, a1, a2));
}

test "pointer varlen2" {
    var a1: []const u8 = "abcde";
    var a2: []const u8 = "abcdf";
    try expect(!deep_equal([]const u8, a1, a2));
}

test "pointer varlen3" {
    var a1: []const u8 = "abcde";
    var a2: []const u8 = "abcde";
    try expect( deep_equal([]const u8, a1, a2));
}

//test "pointer constsen1" {
//    const a1: [*:0]const u8 = @ptrCast([*:0]const u8, "abcde");
//    const a2: [*:0]const u8 = @ptrCast([*:0]const u8, "abcd");
//    try expect(!deep_equal([*:0]const u8, a1, a2));
//}
//
//test "pointer constsen2" {
//    const a1: [*:0]const u8 = @ptrCast([*:0]const u8, "abcde");
//    const a2: [*:0]const u8 = @ptrCast([*:0]const u8, "abcdf");
//    try expect(!deep_equal([*:0]u8, a1, a2));
//}
//
//test "pointer constsen3" {
//    const a1: [*:0]const u8 = @ptrCast([*:0]const u8, "abcde");
//    const a2: [*:0]const u8 = @ptrCast([*:0]const u8, "abcde");
//    try expect( deep_equal([*:0]u8, a1, a2));
//}

test "optional prim" {
    var a = @as(?u8, 3);
    var b = @as(?u8, 4);
    var c = @as(?u8, 3);
    try expect( deep_equal(?u8, null, null));
    try expect(!deep_equal(?u8, a, null));
    try expect(!deep_equal(?u8, null, a));
    try expect( deep_equal(?u8, a, a));
    try expect(!deep_equal(?u8, a, b));
    try expect( deep_equal(?u8, a, c));
}

test "optional deep" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const al = arena.allocator();

    // REPORT zig panics!
    //var a = @as(?[:0]u8, try al.dupeZ(u8, "abcd"));
    //var b = @as(?[:0]u8, try al.dupeZ(u8, "abce"));
    //var c = @as(?[:0]u8, try al.dupeZ(u8, "abcd"));

    //try expect( deep_equal(?[:0]u8, null, null));
    //try expect(!deep_equal(?[:0]u8, a, null));
    //try expect(!deep_equal(?[:0]u8, null, a));
    //try expect( deep_equal(?[:0]u8, a, a));
    //try expect(!deep_equal(?[:0]u8, a, b));
    //try expect( deep_equal(?[:0]u8, a, c));

    var a = @as(?*[4:0]u8, @ptrCast(*[4:0]u8, try al.dupeZ(u8, "abcd")));
    var b = @as(?*[4:0]u8, @ptrCast(*[4:0]u8, try al.dupeZ(u8, "abce")));
    var c = @as(?*[4:0]u8, @ptrCast(*[4:0]u8, try al.dupeZ(u8, "abcd")));

    try expect( deep_equal(?*[4:0]u8, null, null));
    try expect(!deep_equal(?*[4:0]u8, a, null));
    try expect(!deep_equal(?*[4:0]u8, null, a));
    try expect( deep_equal(?*[4:0]u8, a, a));
    try expect(!deep_equal(?*[4:0]u8, a, b));
    try expect( deep_equal(?*[4:0]u8, a, c));
}

// REPORT this panics zig copmiler
//test "struct" {
//    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//    defer arena.deinit();
//    const allocator = arena.allocator();
//
//    const ut = struct {
//        aa: struct {
//            xx: [:0]u8,
//        },
//        bb: bool = true,
//    };
//
//    var str1 = try allocator.dupeZ(u8, "abc");
//    var str2 = try allocator.dupeZ(u8, "abd");
//    var str3 = try allocator.dupeZ(u8, "abc");
//
//    var ua = ut {.aa = .{.xx=str1}};
//    var ub = ut {.aa = .{.xx=str1}, .bb = false};
//    var uc = ut {.aa = .{.xx=str2}};
//    var ud = ut {.aa = .{.xx=str3}};
//
//    try expect( deep_equal(ut, ua, ua));
//    try expect(!deep_equal(ut, ua, ub));
//    try expect(!deep_equal(ut, ua, uc));
//    try expect( deep_equal(ut, ua, ud));
//}

// REPORT this segfaults zig compiler
//test "union" {
//    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//    defer arena.deinit();
//    const allocator = arena.allocator();
//
//    const ut = union(enum) {
//        aa: struct {
//            xx: [:0]u8,
//        },
//        bb: usize,
//    };
//
//    var str1 = try allocator.dupeZ(u8, "abc");
//    var str2 = try allocator.dupeZ(u8, "abd");
//    var str3 = try allocator.dupeZ(u8, "abc");
//
//    var ua = ut {.aa = .{.xx=str1}};
//    var ub = ut {.bb = 8 };
//    var uc = ut {.aa = .{.xx=str2}};
//    var ud = ut {.aa = .{.xx=str3}};
//
//    try expect( deep_equal(ut, ua, ua));
//    try expect(!deep_equal(ut, ua, ub));
//    try expect(!deep_equal(ut, ua, uc));
//    try expect( deep_equal(ut, ua, ud));
//}
