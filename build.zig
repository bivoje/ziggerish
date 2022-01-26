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

    const exe = b.addExecutable("sigmund", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
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

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    const watch_step = b.step("watch-test", "Watch and test");
    watch_step.makeFn = watch_test;
}

fn watch_test(self: *std.build.Step) !void {
    _ = self;

    const cmd =
        \\pwd
        \\while inotifywait --quiet src/main.zig; do
        \\  echo -e "\x1b[34mTest Start ===================\x1b[0m"
        \\  sleep 0.1
        \\  zig build test
        \\done
        ;

    return std.os.execvpeZ(
        "/bin/bash",
        &[_:null]?[*:0]const u8{
            "/bin/bash", "-c", cmd, null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:~/bin",
            "HOME=/root",
            null,
        }
    );
}
