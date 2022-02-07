const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ziggerish", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.linkLibC();

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    const wt_cmd =
        \\pwd
        \\while inotifywait --quiet src; do
        \\  echo -e "\x1b[34mTest Start ===================\x1b[0m"
        \\  sleep 0.1
        \\  zig build test
        \\done
        ;

    const run_wt = b.addSystemCommand(&[_][]const u8{ "/bin/bash", "-c", wt_cmd });

    const wt_step = b.step("watch-test", "Watch and test");
    wt_step.dependOn(&run_wt.step);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const al = arena.allocator();

    var wr_cmd = std.ArrayList(u8).init(al);
    wr_cmd.appendSlice(
        \\pwd
        \\while inotifywait --quiet src; do
        \\  echo -e "\x1b[34mRuning Start ===================\x1b[0m"
        \\  sleep 0.1
        \\  zig build run --
    ) catch return;

    if (b.args) |args| {
        for (args) |arg| {
            wr_cmd.append(@as(u8, ' ')) catch return;
            wr_cmd.appendSlice(arg) catch return;
        }
    }

    wr_cmd.appendSlice(
        \\
        \\done
    ) catch return;

    const slice = wr_cmd.toOwnedSlice();
    //defer al.free(slice)

    const run_wr = b.addSystemCommand(&[_][]const u8{ "/bin/bash", "-c", slice });

    const wr_step = b.step("watch-run", "Watch and run");
    wr_step.dependOn(&run_wr.step);
}
