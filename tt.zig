const os = @import("std").os;

const cInotify = @cImport({
    @cInclude("/usr/include/sys/inotify.h");
});

const dprint = @import("std").debug.print;

pub fn main() !void {
    const fd = try os.inotify_init1(0);
    const wd = try os.inotify_add_watch(fd, "tt.zig", cInotify.IN_ALL_EVENTS);
    dprint("fd {d}, wd: {d}, mask: {x}\n", .{fd, wd, cInotify.IN_ALL_EVENTS});

    dprint("{x} {x} {x} {x}\n", .{
        cInotify.IN_ACCESS, cInotify.IN_ATTRIB, cInotify.IN_CLOSE_WRITE, cInotify.IN_CLOSE_NOWRITE,
    });
    dprint("{x} {x} {x} {x}\n", .{
        cInotify.IN_CREATE, cInotify.IN_DELETE, cInotify.IN_DELETE_SELF, cInotify.IN_MODIFY,
    });
    dprint("{x} {x} {x} {x}\n", .{
        cInotify.IN_MOVE_SELF, cInotify.IN_MOVED_FROM, cInotify.IN_MOVED_TO, cInotify.IN_OPEN,
    });

    const sizeofIE = @sizeOf(cInotify.inotify_event);
    const alignofIEp = @alignOf([*]cInotify.inotify_event);
    dprint("{d} {d}\n", .{sizeofIE, alignofIEp});

    while (true) {
        var buf: [128]u8 = undefined;
        const n = (try os.read(@intCast(os.fd_t, fd), &buf)) / sizeofIE;
        dprint("n: {d}\n", .{n});

        const ptr = @ptrCast([*]cInotify.inotify_event, @alignCast(alignofIEp, &buf));
        //dprint("{s}\n", .{@typeName(@TypeOf(ptr[0].name))});
        // name is only used when watching for directory, to indicate file name

        for (range(n)) |_,i| {
            dprint("{d}| wd: {d}, mask: {x}, len: {d}, name: {d}\n",
                .{ i, ptr[i].wd, ptr[i].mask, ptr[i].len, ptr[i].name()[i], });
        }

        
    }
}

// stolen from https://github.com/nektro/zig-range/blob/master/src/lib.zig
pub fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}
