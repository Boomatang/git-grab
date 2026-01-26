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

pub const Action = enum {
    worktree,
    remote,
    standard,
};

pub const CloneOptions = struct {
    bare: bool,
};

pub const PathSource = union(enum) {
    provided: []const u8,
    allocated: []const u8,
    none,
};

pub const Configuration = struct {
    path: ?PathSource = .none,
    action: Action = .worktree,

    pub fn init() Configuration {
        return Configuration{};
    }

    pub fn deinit(self: *Configuration, allocator: std.mem.Allocator) void {
        if (self.path) |path| {
            switch (path) {
                .allocated => |p| allocator.free(p),
                .provided, .none => {},
            }
        }
    }

    pub fn getPath(self: *const Configuration) ?[]const u8 {
        const path = self.path orelse return null;
        return switch (path) {
            .provided => |p| p,
            .allocated => |p| p,
            .none => null,
        };
    }
};

pub fn clone(allocator: std.mem.Allocator, project: Project, opts: CloneOptions) !void {
    std.log.debug("cloning: {s}", .{project.name});

    const cmd = if (opts.bare)
        &[_][]const u8{ "git", "clone", "--bare", project.clone, ".bare" }
    else
        &[_][]const u8{ "git", "clone", project.clone };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
        .cwd_dir = project.root,
        .max_output_bytes = 1024 * 1024, // 1MB max output
    }) catch |err| {
        std.log.err("Failed to run git clone: {}", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (std.mem.startsWith(u8, result.stderr, "fatal")) {
        if (std.mem.endsWith(u8, result.stderr, "already exists and is not an empty directory.\n")) {
            return error.exists;
        }
        std.log.err("{s}", .{result.stderr});
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
    std.log.debug("path: {s}", .{path});

    cwd.makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try cwd.openDir(path, .{});
}

pub fn setLocation(config: Configuration) !void {
    if (config.getPath()) |path| {
        std.log.debug("change path to: {s}", .{path});
        try std.posix.chdir(path);
    } else {
        std.log.warn("no path was set", .{});
    }
}

pub fn findPaths(allocator: std.mem.Allocator, paths: *std.ArrayList([]const u8), projectName: []const u8) !void {
    const cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch |err| {
            if (err == error.AccessDenied) continue;
            return err;
        } orelse break;

        if (entry.kind == .directory and std.mem.eql(u8, entry.basename, projectName)) {
            if (try isGitRepo(entry.path)) try paths.append(allocator, try allocator.dupe(u8, entry.path));
        }
    }
}

fn isGitRepo(path: []const u8) !bool {
    const temp = try std.fs.cwd().openDir(".", .{ .iterate = true });
    const cwd = try temp.openDir(path, .{ .iterate = true });
    const subPaths = [_][]const u8{ ".git", ".bare" };

    for (subPaths) |p| {
        var isRepo = true;
        _ = cwd.openDir(p, .{}) catch |err| switch (err) {
            error.NotDir => isRepo = false,
            error.FileNotFound => isRepo = false,
            else => return err,
        };
        if (isRepo) return isRepo;
    }

    return false;
}

pub fn addRemote(allocator: std.mem.Allocator, project: Project, path: []const u8) !void {
    const checkCmd = [_][]const u8{ "git", "remote" };
    const checkResult = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &checkCmd,
        .cwd = path,
    }) catch |err| {
        std.log.err("Failed to run git remote: {}", .{err});
        return err;
    };
    defer {
        allocator.free(checkResult.stdout);
        allocator.free(checkResult.stderr);
    }

    var output = std.mem.splitSequence(u8, checkResult.stdout, "\n");
    var value = output.first();
    while (true) {
        if (std.mem.eql(u8, value, project.owner)) {
            return error.RemoteExists;
        }
        value = output.next() orelse break;
    }

    const addCmd = [_][]const u8{ "git", "remote", "add", project.owner, project.clone };
    const addResult = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &addCmd,
        .cwd = path,
    }) catch |err| {
        std.log.err("Failed to run git remote: {}", .{err});
        return err;
    };
    defer {
        allocator.free(addResult.stdout);
        allocator.free(addResult.stderr);
    }
}

pub fn linkGit(path: std.fs.Dir) !void {
    std.log.debug("Creating .git file", .{});
    const file = path.createFile(".git", .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            std.log.err(".git file in path already", .{});
            std.process.exit(1);
        },
        else => return err,
    };
    defer file.close();
    try file.writeAll("gitdir: .bare");
}

pub fn setupOrigin(allocator: std.mem.Allocator, path: std.fs.Dir) !void {
    const cmd = [_][]const u8{
        "git",
        "config",
        "remote.origin.fetch",
        "+refs/heads/*:refs/remotes/origin/*",
    };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd_dir = path,
    }) catch |err| {
        std.log.err("Failed to run git config: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}

pub fn fetchOrigin(allocator: std.mem.Allocator, path: std.fs.Dir) !void {
    const cmd = [_][]const u8{ "git", "fetch", "-p", "origin" };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &cmd,
        .cwd_dir = path,
    }) catch |err| {
        std.log.err("Failed to run git fetch: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}
