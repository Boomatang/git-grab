const std = @import("std");

pub const Project = struct {
    site: []const u8,
    owner: []const u8,
    name: []const u8,
    clone: []const u8,
    root: ?std.fs.Dir = null,

    pub fn init(repo: []const u8) !Project {
        if (!std.mem.startsWith(u8, repo, "git") or !std.mem.endsWith(u8, repo, "git")) {
            return error.parse;
        }
        const _clone = repo;

        var min = std.mem.indexOf(u8, repo, "@") orelse return error.parse;
        var max = std.mem.indexOf(u8, repo, ":") orelse return error.parse;
        const _site = repo[min + 1 .. max];

        min = std.mem.indexOf(u8, repo, ":") orelse return error.parse;
        max = std.mem.indexOf(u8, repo, "/") orelse return error.parse;
        const _owner = repo[min + 1 .. max];

        min = std.mem.indexOf(u8, repo, "/") orelse return error.parse;
        max = std.mem.indexOf(u8, repo, ".git") orelse return error.parse;
        const _name = repo[min + 1 .. max];

        return Project{ .site = _site, .owner = _owner, .name = _name, .clone = _clone };
    }
};

pub fn clone(allocator: std.mem.Allocator, project: Project) !void {
    std.debug.print("cloning: {s}\n", .{project.name});

    const cmd = [_][]const u8{ "git", "clone", project.clone };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd_dir = project.root,
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
        std.debug.print("error: {s}", .{result.stderr});
        return error.unknown;
    }
}

pub fn createPath(cwd: std.fs.Dir, paths: []const []const u8) !std.fs.Dir {
    var current = cwd;

    for (paths) |path| {
        current = try _createPath(current, path);
    }
    return current;
}

fn _createPath(cwd: std.fs.Dir, path: []const u8) !std.fs.Dir {
    std.debug.print("path: {s}\n", .{path});

    cwd.makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try cwd.openDir(path, .{});
}
