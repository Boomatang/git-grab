const std = @import("std");

pub fn getTempDir(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");

    if (builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "TEMP") catch
            std.process.getEnvVarOwned(allocator, "TMP") catch
            try allocator.dupe(u8, "C:\\Temp");
    } else {
        return std.process.getEnvVarOwned(allocator, "TMPDIR") catch
            try allocator.dupe(u8, "/tmp");
    }
}
