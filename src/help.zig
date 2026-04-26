const std = @import("std");

pub fn getTempDir(allocator: std.mem.Allocator, envVar: std.process.Environ) ![]const u8 {
    const builtin = @import("builtin");

    if (builtin.os.tag == .windows) {
        return error.Unsupported;
    } else {
        const dir = envVar.getPosix("TMPDIR");
        if (dir) |d| {
            return try allocator.dupe(u8, d);
        } else {
            return try allocator.dupe(u8, "/tmp");
        }
    }
}
