const std = @import("std");

pub fn clone(allocator: std.mem.Allocator, repo: []const u8) !void {
    std.debug.print("cloning: {s}\n", .{repo});

    const cmd = [_][]const u8{ "git", "clone", repo };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd = null,
        .env_map = null,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.debug.print("Failed to run git clone: {}\n", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (std.mem.startsWith(u8, result.stderr, "fatal")) {
        if (std.mem.endsWith(u8, result.stderr, "already exists and is not an empty directory.\n")) {
            return error.exists;
        }
    }
}
