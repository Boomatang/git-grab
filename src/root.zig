const std = @import("std");

const defaults = @import("defaults.zig");
const default_config_source = @embedFile("default_config.zon");

const _logging = @import("logging.zig");
pub const logging = _logging;

pub const Project = struct {
    site: []const u8,
    owner: []const u8,
    name: []const u8,
    clone: []const u8,
    root: ?std.Io.Dir = null,

    pub fn init(repo: []const u8) !Project {
        if (!std.mem.endsWith(u8, repo, ".git")) return error.parse;

        var split_on: []const u8 = undefined;
        var protocol_split: []const u8 = undefined;
        var min: usize = undefined;
        var max: usize = undefined;
        var site_offset: usize = undefined;

        const _clone = repo;

        const at_symbol_index = std.mem.find(u8, repo, "@");
        if (at_symbol_index) |_| {
            // "git@github.com:Boomatang/git-grab.git";
            // "ssh://git@codeberg.org/boomatang/boomatang.git";
            if (std.mem.startsWith(u8, repo, "git")) {
                std.log.debug("possible GitHub repo", .{});
                split_on = ":";
            } else if (std.mem.startsWith(u8, repo, "ssh://git")) {
                std.log.debug("possible Codeberg repo", .{});
                split_on = "/";
            } else {
                return error.parse;
            }
            protocol_split = "@";
            site_offset = 1;
        } else {
            // "https://github.com/Boomatang/git-grab.git";
            // "http://codeberg.org/boomatang/boomatang.git";
            if (!std.mem.startsWith(u8, repo, "http")) return error.parse;
            split_on = "/";
            protocol_split = "://";
            site_offset = 0;
        }

        min = std.mem.find(u8, repo, protocol_split) orelse return error.parse;
        if (protocol_split.len > 1) min += protocol_split.len;
        max = std.mem.findPos(u8, repo, min, split_on) orelse return error.parse;
        const _site = repo[min + site_offset .. max];

        min = max;
        max = std.mem.findPos(u8, repo, min + 1, "/") orelse return error.parse;
        const _owner = repo[min + 1 .. max];

        min = max;
        max = std.mem.findLast(u8, repo, ".git") orelse return error.parse;
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

pub const ConfigurationFile = struct {
    path: ?[]const u8 = null,
    action: ?Action = null,
    shallow: ?bool = null,
    log_level: ?logging.Level = null,

    pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
        std.zon.parse.free(gpa, self);
    }
};

pub const Configuration = struct {
    path: ?PathSource = .none,
    action: Action = defaults.action,
    shallow: bool = defaults.shallow,
    configFile: ?ConfigurationFile = null,

    pub fn init(io: std.Io, gpa: std.mem.Allocator, environ: std.process.Environ) !Configuration {
        std.log.debug("setting up configuration", .{});
        const config_file = load_config_file(io, gpa, environ) catch |err| switch (err) {
            error.NotFound => null,
            else => return err,
        };
        if (config_file) |config| {
            if (config.log_level) |v| logging.set_log_level(v);

            return Configuration{
                .path = if (config.path) |p| .{ .provided = p } else .none,
                .action = if (config.action) |v| v else defaults.action,
                .shallow = if (config.shallow) |v| v else defaults.shallow,
                .configFile = config,
            };
        }

        return .{};
    }

    pub fn deinit(self: *Configuration, gpa: std.mem.Allocator) void {
        if (self.path) |path| {
            switch (path) {
                .allocated => |p| gpa.free(p),
                .provided, .none => {},
            }
        }

        if (self.configFile) |configFile| configFile.deinit(gpa);
    }

    pub fn getPath(self: *const Configuration) ?[]const u8 {
        const path = self.path orelse return null;
        return switch (path) {
            .provided, .allocated => |p| p,
            .none => null,
        };
    }
};

fn load_config_file(io: std.Io, gpa: std.mem.Allocator, environ: std.process.Environ) !ConfigurationFile {
    const xdg_config_home = environ.getPosix("XDG_CONFIG_HOME") orelse "";
    const owns_path = xdg_config_home.len == 0;
    const path: []const u8 = if (xdg_config_home.len > 0) xdg_config_home else try userPath(gpa, environ);
    defer if (owns_path) gpa.free(path);

    const config_file_path = try std.fmt.allocPrint(gpa, "{s}/grab/config.zon", .{path});
    defer gpa.free(config_file_path);
    if (!pathIsFile(io, config_file_path)) {
        std.log.debug("No existing configuration file found at {s}", .{config_file_path});
        return error.NotFound;
    }

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, config_file_path, .{ .mode = .read_only });
    defer file.close(io);

    const size: usize = @intCast(try file.length(io));
    const buffer = try gpa.allocSentinel(u8, size, 0);
    defer gpa.free(buffer);

    _ = try file.readPositionalAll(io, buffer[0..size], 0);

    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    const config = std.zon.parse.fromSliceAlloc(ConfigurationFile, gpa, buffer, &diag, .{}) catch |err| {
        std.log.err("Failed to parse {s}: {}", .{ config_file_path, err });
        std.log.err("{f}", .{diag});
        return err;
    };

    return config;
}

pub fn init(io: std.Io, gpa: std.mem.Allocator, environ: std.process.Environ) !void {
    // set up root configuration path
    const xdg_config_home = environ.getPosix("XDG_CONFIG_HOME") orelse "";
    const owns_path = xdg_config_home.len == 0;
    const path: []const u8 = if (xdg_config_home.len > 0) xdg_config_home else try userPath(gpa, environ);
    defer if (owns_path) gpa.free(path);

    // Check if root configuration path exits
    if (!pathIsDir(io, path)) {
        std.log.err("Root configuration path does not exist. '{s}'", .{path});
        return error.PathNotFound;
    }
    std.log.debug("using root configuration path of '{s}'", .{path});

    // Create path to configuration file
    const config_path = try std.fmt.allocPrint(gpa, "{s}/grab", .{path});
    defer gpa.free(config_path);

    const config_file_path = try std.fmt.allocPrint(gpa, "{s}/config.zon", .{config_path});
    defer gpa.free(config_file_path);
    // Check if configuration file exist
    if (pathIsFile(io, config_file_path)) {
        std.log.warn("Existing configuration file found: {s}", .{config_file_path});
        return;
    }

    // Create the config directory
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, config_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const file = try cwd.createFile(io, config_file_path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, default_config_source, 0);

    std.log.info("Configuration file created, see {s} for configuration options", .{config_file_path});
}

fn userPath(gpa: std.mem.Allocator, environ: std.process.Environ) ![]const u8 {
    const home = environ.getPosix("HOME") orelse "";
    if (home.len > 0) return try std.fmt.allocPrint(gpa, "{s}/.config", .{home}) else return error.NoHomeFound;
}

fn pathIsDir(io: std.Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .directory;
}

fn pathIsFile(io: std.Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

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

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    if (std.mem.startsWith(u8, result.stderr, "fatal")) {
        if (std.mem.endsWith(
            u8,
            result.stderr,
            "already exists and is not an empty directory.\n",
        )) return error.exists;

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
            error.NotDir, error.FileNotFound => isRepo = false,
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
    while (output.next()) |value| {
        if (std.mem.eql(u8, value, project.owner)) {
            return error.RemoteExists;
        }
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

pub fn setLogAllRef(allocator: std.mem.Allocator, io: std.Io, path: std.Io.Dir) !void {
    const _path = try path.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(_path);
    std.log.debug("Configuring logAllRefUpdates", .{});
    const cmd = [_][]const u8{ "git", "-C", _path, "config", "core.logallrefupdates", "true" };
    const result = std.process.run(allocator, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run git config log all ref updates: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term.exited != 0) {
        std.log.err("{s}", .{result.stderr});
        return error.runtime;
    }
}

pub fn setAutoSetupMerge(allocator: std.mem.Allocator, io: std.Io, path: std.Io.Dir) !void {
    const _path = try path.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(_path);
    const cmd = [_][]const u8{ "git", "-C", _path, "config", "branch.autoSetupMerge", "true" };
    std.log.debug("Configuring autoSetupMerge", .{});
    const result = std.process.run(allocator, io, .{
        .argv = &cmd,
    }) catch |err| {
        std.log.err("Failed to run git config auto Setup Merge: {}", .{err});
        return err;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    if (result.term.exited != 0) {
        std.log.err("{s}", .{result.stderr});
        return error.runtime;
    }
}

pub fn setLocalTracking(allocator: std.mem.Allocator, io: std.Io, path: std.Io.Dir) !void {
    const _path = try path.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(_path);

    const branch_cmd = [_][]const u8{ "git", "-C", _path, "branch", "--format=%(refname:short)" };
    std.log.debug("Getting list of git branches", .{});
    const branch_result = std.process.run(allocator, io, .{
        .argv = &branch_cmd,
    }) catch |err| {
        std.log.err("Failed to run git branch: {}", .{err});
        return err;
    };

    defer {
        allocator.free(branch_result.stderr);
        allocator.free(branch_result.stdout);
    }
    if (branch_result.term.exited != 0) {
        std.log.err("{s}", .{branch_result.stderr});
        return error.runtime;
    }

    var iter = std.mem.splitScalar(u8, branch_result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        std.log.debug("Working with branch: {s}", .{line});

        const remote = try std.fmt.allocPrint(allocator, "branch.{s}.remote", .{line});
        defer allocator.free(remote);

        const merge = try std.fmt.allocPrint(allocator, "branch.{s}.merge", .{line});
        defer allocator.free(merge);

        const head = try std.fmt.allocPrint(allocator, "refs/heads/{s}", .{line});
        defer allocator.free(head);

        const remote_cmd = [_][]const u8{ "git", "-C", _path, "config", remote, "origin" };
        const merge_cmd = [_][]const u8{ "git", "-C", _path, "config", merge, head };

        std.log.debug("[{s}] Setting up remotes for origin", .{remote});
        const remote_result = std.process.run(allocator, io, .{ .argv = &remote_cmd }) catch |err| {
            std.log.err("Failed to run git config {s} origin", .{remote});
            return err;
        };
        defer {
            allocator.free(remote_result.stderr);
            allocator.free(remote_result.stdout);
        }
        if (remote_result.term.exited != 0) {
            std.log.err("{s}", .{remote_result.stderr});
            return error.runtime;
        }

        std.log.debug("[{s}] Setting up merge configuration", .{remote});
        const merge_result = std.process.run(allocator, io, .{ .argv = &merge_cmd }) catch |err| {
            std.log.err("Failed to run git config {s} {s}", .{ merge, head });
            return err;
        };
        defer {
            allocator.free(merge_result.stderr);
            allocator.free(merge_result.stdout);
        }
        if (merge_result.term.exited != 0) {
            std.log.err("{s}", .{merge_result.stderr});
            return error.runtime;
        }
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

test "input parsing GitHub http" {
    const input = "https://github.com/Boomatang/git-grab.git";
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

test "input parsing codeberg http" {
    const input = "http://codeberg.org/boomatang/boomatang.git";
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

test "input parsing short url" {
    const input = "ssh://git@gogs.io/user/repo.git";
    const expect = Project{
        .clone = input,
        .name = "repo",
        .owner = "user",
        .site = "gogs.io",
    };

    const project = try Project.init(input);

    try std.testing.expectEqualStrings(expect.site, project.site);
    try std.testing.expectEqualStrings(expect.owner, project.owner);
    try std.testing.expectEqualStrings(expect.name, project.name);
    try std.testing.expectEqualStrings(expect.clone, project.clone);
}

test "input parsing .git in project name" {
    const input = "https://github.com/user/.github.git";
    const expect = Project{
        .clone = input,
        .name = ".github",
        .owner = "user",
        .site = "github.com",
    };

    const project = try Project.init(input);

    try std.testing.expectEqualStrings(expect.site, project.site);
    try std.testing.expectEqualStrings(expect.owner, project.owner);
    try std.testing.expectEqualStrings(expect.name, project.name);
    try std.testing.expectEqualStrings(expect.clone, project.clone);
}
