const std = @import("std");
const clap = @import("clap");
const grab = @import("grab");
const help = @import("help");

pub const Level = enum { info, debug, @"error", warn };
pub const std_options: std.Options = .{
    // Keep compile-time logging permissive; runtime filter in `log`.
    .log_level = .debug,
    .logFn = log,
};

pub var log_level: std.log.Level = .info;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
    };
    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        // Print the message to stderr, silently ignoring any errors
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.fs.File.stderr().deprecatedWriter();
        nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\<REPO>... Git repositrories to clone.
        \\-h, --help       show this help message and exit
        \\-p, --path <PATH>  Overrides the path set in the GRAB_PATH environment variable.
        \\-t, --temp       Download repositories to a temporary directory. This will be the OS default temporary directory.
        \\-s, --standard Standard clone, normal clone is done using worktrees.
        \\-r, --remote     Add remote to existing repo.
        \\--log-level <LEVEL> Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is info.
        \\--version        Show program's version number and exit
    );

    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .REPO = clap.parsers.string,
        .LEVEL = clap.parsers.enumeration(Level),
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    if (res.args.version != 0) {
        const build_options = @import("build_options");
        std.log.info("grab: {s}", .{build_options.version});
        std.process.exit(0);
    }

    var config = grab.Configuration.init();
    defer config.deinit(allocator);

    // Set up logger
    var level = Level.info;
    if (res.args.@"log-level") |l| {
        level = l;
    }

    switch (level) {
        .debug => log_level = std.log.Level.debug,
        .@"error" => log_level = std.log.Level.err,
        .info => log_level = std.log.Level.info,
        .warn => log_level = std.log.Level.warn,
    }

    if (res.args.temp != 0 and res.args.path != null) {
        std.log.err("Cannot specify both --temp and --path", .{});
        std.posix.exit(1);
    }

    if (res.args.standard != 0 and res.args.remote != 0) {
        std.log.err("Cannot specify both --standard and --remote", .{});
        std.posix.exit(1);
    }
    if (res.positionals[0].len == 0) {
        std.log.err("At least one repo must be provided", .{});
        std.posix.exit(1);
    }

    if (res.args.temp != 0) {
        const path = try help.getTempDir(allocator);
        config.path = .{ .allocated = path };
        std.log.info("using temp as path", .{});
    } else if (res.args.path) |path| {
        config.path = .{ .provided = path };
        std.log.info("using {s} as path", .{path});
    } else {
        const path = std.process.getEnvVarOwned(allocator, "GRAB_PATH") catch {
            std.log.err("unable to get GRAB_PATH, please set or use --temp or --path", .{});
            std.process.exit(1);
        };
        if (path.len == 0) {
            std.log.err("unable to get GRAB_PATH, please set or use --temp or --path", .{});
            std.process.exit(1);
        }
        config.path = .{ .allocated = path };
        std.log.debug("try to get path from env", .{});
    }
    if (res.args.remote != 0) {
        config.action = .remote;
    }

    if (res.args.standard != 0) {
        config.action = .standard;
    }

    try grab.setLocation(config);

    for (res.positionals[0]) |repo| {
        std.log.info("working on repo: {s}", .{repo});

        const project = grab.Project.init(repo) catch |err| switch (err) {
            error.parse => {
                std.log.err("unable to parse: {s}", .{repo});
                std.process.exit(1);
            },
            else => return err,
        };

        std.log.debug("Project Data:\n\tSite: {s}\n\tOwner: {s}\n\tName: {s}\n\tClone: {s}", .{ project.site, project.owner, project.name, project.clone });

        switch (config.action) {
            .standard => try clone(allocator, project),
            .worktree => try worktree(allocator, project),
            .remote => try addRemote(allocator, project),
        }
    }
    std.log.info("Finished", .{});
}

fn clone(allocator: std.mem.Allocator, project: grab.Project) !void {
    var project_ = project;
    const cwd = std.fs.cwd();
    const path = try grab.createPath(cwd, &[_][]const u8{ project_.site, project_.owner });
    project_.root = path;
    grab.clone(allocator, project_, .{ .bare = false }) catch |err| switch (err) {
        error.exists => {
            std.log.err("Unable to clone: {s}, path not empty", .{project_.name});
            std.process.exit(1);
        },
        else => {
            std.log.err("unhandled error: {any}", .{err});
            std.process.exit(1);
        },
    };
}

fn addRemote(allocator: std.mem.Allocator, project: grab.Project) !void {
    var paths = std.ArrayList([]const u8){};
    defer {
        for (paths.items) |i| {
            allocator.free(i);
        }
        paths.deinit(allocator);
    }
    try grab.findPaths(allocator, &paths, project.name);
    std.log.info("Remote \"{s}\" is being added to the following projects:", .{project.owner});
    for (paths.items) |path| {
        std.log.info("\t{s}", .{path});
    }
    for (paths.items) |path| {
        grab.addRemote(allocator, project, path) catch |err| switch (err) {
            error.RemoteExists => std.log.warn("Skipping adding remote to {s}, as remote already exists", .{path}),
            else => return err,
        };
    }
    std.log.info("successfully added remotes", .{});
}

fn worktree(allocator: std.mem.Allocator, project: grab.Project) !void {
    std.log.debug("Config worktree deployment", .{});
    var project_ = project;
    const cwd = std.fs.cwd();
    const path = try grab.createPath(cwd, &[_][]const u8{ project_.site, project_.owner, project_.name });
    project_.root = path;
    grab.clone(allocator, project_, .{ .bare = true }) catch |err| switch (err) {
        error.exists => {
            std.log.err("Unable to clone: {s}, path not empty", .{project_.name});
            std.process.exit(1);
        },
        else => {
            std.log.err("unhandled error: {any}", .{err});
            std.process.exit(1);
        },
    };

    if (project_.root) |root| {
        try grab.linkGit(root);
        try grab.setupOrigin(allocator, root);
        try grab.fetchOrigin(allocator, root);
    }
}
