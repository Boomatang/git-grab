const std = @import("std");

pub const Project = struct {
    site: []const u8,
    owner: []const u8,
    name: []const u8,
    clone: []const u8,
    root: ?std.Io.Dir = null,

    pub fn init(repo: []const u8) !Project {
        if (!std.mem.endsWith(u8, repo, ".git")) {
            return error.parse;
        }
        var split_on = ":";
        var min: usize = undefined;
        var max: usize = undefined;
        if (std.mem.startsWith(u8, repo, "git")) {
            std.log.debug("possible GitHub repo", .{});
            split_on = ":";
        } else if (std.mem.startsWith(u8, repo, "ssh://git")) {
            std.log.debug("possible Codeberg repo", .{});
            split_on = "/";
        } else {
            return error.parse;
        }

        const _clone = repo;

        min = std.mem.indexOf(u8, repo, "@") orelse return error.parse;
        max = std.mem.indexOfPos(u8, repo, min, split_on) orelse return error.parse;
        const _site = repo[min + 1 .. max];

        min = max;
        max = std.mem.indexOfPos(u8, repo, min + 1, "/") orelse return error.parse;
        const _owner = repo[min + 1 .. max];

        min = max;
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
    shallow: bool = false,
};

pub const PathSource = union(enum) {
    provided: []const u8,
    allocated: []const u8,
    none,
};

pub const Configuration = struct {
    path: ?PathSource = .none,
    action: Action = .worktree,
    shallow: bool = false,

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

pub fn clone(allocator: std.mem.Allocator, io: std.Io, project: Project, opts: CloneOptions) !void {
    std.log.debug("cloning: {s}", .{project.name});

    const path = if (project.root) |root| try root.realPathFileAlloc(io, ".", allocator) else return error.noroot;
    defer allocator.free(path);

    var cmd: std.ArrayList([]const u8) = .empty;
    defer cmd.deinit(allocator);
    try cmd.appendSlice(allocator, &[_][]const u8{ "git", "-C", path, "clone" });

    if (opts.shallow) try cmd.append(allocator, "--depth=1");

    if (opts.bare) {
        try cmd.appendSlice(allocator, &[_][]const u8{ "--bare", project.clone, ".bare" });
    } else {
        try cmd.append(allocator, project.clone);
    }

    const result = std.process.run(allocator, io, .{
        .argv = cmd.items,
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

pub fn createPath(io: std.Io, cwd: std.Io.Dir, paths: []const []const u8) !std.Io.Dir {
    var current = cwd;

    for (paths) |path| {
        current = try _createPath(io, current, path);
    }
    return current;
}

fn _createPath(io: std.Io, cwd: std.Io.Dir, path: []const u8) !std.Io.Dir {
    std.log.debug("path: {s}", .{path});

    cwd.createDir(io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try cwd.openDir(io, path, .{});
}

pub fn setLocation(io: std.Io, config: Configuration) !void {
    if (config.getPath()) |path| {
        std.log.debug("change path to: {s}", .{path});
        const dir = try std.Io.Dir.cwd().openDir(io, path, .{});
        try std.process.setCurrentDir(io, dir);
    } else {
        std.log.warn("no path was set", .{});
    }
}

pub fn findPaths(allocator: std.mem.Allocator, io: std.Io, paths: *std.ArrayList([]const u8), projectName: []const u8) !void {
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    while (true) {
        const entry = walker.next(io) catch |err| {
            if (err == error.AccessDenied) continue;
            return err;
        } orelse break;

        if (entry.kind == .directory and std.mem.eql(u8, entry.basename, projectName)) {
            if (try isGitRepo(io, entry.path)) try paths.append(allocator, try allocator.dupe(u8, entry.path));
        }
    }
}

fn isGitRepo(io: std.Io, path: []const u8) !bool {
    const temp = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    const cwd = try temp.openDir(io, path, .{ .iterate = true });
    const subPaths = [_][]const u8{ ".git", ".bare" };

    for (subPaths) |p| {
        var isRepo = true;
        _ = cwd.openDir(io, p, .{}) catch |err| switch (err) {
            error.NotDir => isRepo = false,
            error.FileNotFound => isRepo = false,
            else => return err,
        };
        if (isRepo) return isRepo;
    }

    return false;
}

pub fn addRemote(allocator: std.mem.Allocator, io: std.Io, project: Project, path: []const u8) !void {
    const checkCmd = [_][]const u8{ "git", "-C", path, "remote" };
    const checkResult = std.process.run(allocator, io, .{
        .argv = &checkCmd,
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

    const addCmd = [_][]const u8{ "git", "-C", path, "remote", "add", project.owner, project.clone };
    const addResult = std.process.run(allocator, io, .{
        .argv = &addCmd,
    }) catch |err| {
        std.log.err("Failed to run git remote: {}", .{err});
        return err;
    };
    defer {
        allocator.free(addResult.stdout);
        allocator.free(addResult.stderr);
    }
}

pub fn linkGit(io: std.Io, path: std.Io.Dir) !void {
    std.log.debug("Creating .git file", .{});
    const file = path.createFile(io, ".git", .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            std.log.err(".git file in path already", .{});
            std.process.exit(1);
        },
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, "gitdir: .bare");
}

pub fn setupOrigin(allocator: std.mem.Allocator, io: std.Io, path: std.Io.Dir) !void {
    const _path = try path.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(_path);
    const cmd = [_][]const u8{
        "git",
        "-C",
        _path,
        "config",
        "remote.origin.fetch",
        "+refs/heads/*:refs/remotes/origin/*",
    };
    const result = std.process.run(allocator, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed toe run git config: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}

pub fn fetchOrigin(allocator: std.mem.Allocator, io: std.Io, path: std.Io.Dir) !void {
    const _path = try path.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(_path);
    const cmd = [_][]const u8{ "git", "-C", _path, "fetch", "-p", "origin" };
    const result = std.process.run(allocator, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run git fetch: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}

test "input parsing GitHub" {
    const input = "git@github.com:Boomatang/git-grab.git";
    const expect = Project{
        .clone = input,
        .name = "git-grab",
        .owner = "Boomatang",
        .site = "github.com",
    };

    const project = try Project.init(input);

    try std.testing.expectEqualStrings(expect.site, project.site);
    try std.testing.expectEqualStrings(expect.owner, project.owner);
    try std.testing.expectEqualStrings(expect.name, project.name);
    try std.testing.expectEqualStrings(expect.clone, project.clone);
}

test "input parsing codeberg" {
    const input = "ssh://git@codeberg.org/boomatang/boomatang.git";
    const expect = Project{
        .clone = input,
        .name = "boomatang",
        .owner = "boomatang",
        .site = "codeberg.org",
    };

    const project = try Project.init(input);

    try std.testing.expectEqualStrings(expect.site, project.site);
    try std.testing.expectEqualStrings(expect.owner, project.owner);
    try std.testing.expectEqualStrings(expect.name, project.name);
    try std.testing.expectEqualStrings(expect.clone, project.clone);
}

test "input parsing Bad Input" {
    const input = "@codeberg.org/boomatang/boomatang.git";

    try std.testing.expectError(error.parse, Project.init(input));
}
