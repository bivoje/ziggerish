
const std = @import("std");

const BFinstr = @import("types.zig").BFinstr;

pub fn collect_jumprefs(allocator :std.mem.Allocator, instrs: std.ArrayList(BFinstr)) !?std.ArrayList(isize) {
    var loc_stack = std.ArrayList(isize).init(allocator);
    //defer allocator.free(loc_stack);

    for (instrs.items) |instr, i| {
        if (instr == .From) {
            // store negation of location of self
            // this will be overwritten with location of pairing ']'
            // note that 'loc of parinig' > 0 as it cannot be 0
            // also note that only unpaired '[' gets negative value
            try loc_stack.append(-@intCast(isize, i));
        } else if (instr == .To) {
            if (loc_stack.items.len == 0) return null; // unmatched ']' error
            var top = loc_stack.items.len - 1;

            // find top of the unpaired '['
            while (top < std.math.maxInt(usize)) : (top -%= 1) {
                if (loc_stack.items[top] < 0) break;
            } else { return null; } // unmatched ']' error

            // store the location of pairing '[' for current ']'
            try loc_stack.append(-loc_stack.items[top]);
            // update the value of '[' with the location of pairing ']'
            loc_stack.items[top] = @intCast(isize, i);
        } // otherwise, just skip it
    }

    if (loc_stack.items.len == 0) return null; // unmatched ']' error
    var top = loc_stack.items.len - 1;

    // find top of the unpaired '['
    while (top < std.math.maxInt(usize)) : (top -%= 1) {
        if (loc_stack.items[top] < 0) return null; // unmatched '[' error
    } else { return loc_stack; }
}

fn test_system () !void {
    const ret = try system("/bin/bash", &[_:null]?[*:0]u8{"/bin/bash", "-c", "sleep 5; date", null}, &[_:null]?[*:0]u8{null});
    std.testing.expect(0, ret.status);
}

// like subshell execution by `cmd args..` in bash
// run the command and waits for the result
pub fn system (
    file: [*:0]const u8,
    argv_ptr: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) (std.os.ExecveError || std.os.ForkError) ! std.os.WaitPidResult {
    const pid = try std.os.fork();
    return if (pid != 0) std.os.waitpid(pid, 0)
           else std.os.execvpeZ(file, argv_ptr, envp);
}
