const std = @import("std");
const clap = @import("clap");
const grab = @import("grab");
const help = @import("help.zig");

pub const Level = enum { info, debug, @"error", warn };
pub const std_options: std.Options = .{
    // Keep compile-time logging permissive; runtime filter in `log`.
    .log_level = .debug,
    .logFn = log,
};

pub var log_level: std.log.Level = .info;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
    };

    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        std.debug.print(prefix ++ format ++ "\n", args);
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const params = comptime clap.parseParamsComptime(
        \\<REPO>... Git repositrories to clone.
        \\-h, --help       show this help message and exit
        \\-p, --path <PATH>  Overrides the path set in the GRAB_PATH environment variable.
        \\-t, --temp       Download repositories to a temporary directory. This will be the OS default temporary directory.
        \\-s, --standard Standard clone, normal clone is done using worktrees.
        \\-S, --shallow Create a shallow clone with a history of depth one
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
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});
    if (res.args.version != 0) {
        const build_options = @import("build_options");
        std.log.info("{s}: {s}", .{ build_options.name, build_options.version });
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
        std.process.exit(1);
    }

    if (res.args.standard != 0 and res.args.remote != 0) {
        std.log.err("Cannot specify both --standard and --remote", .{});
        std.process.exit(1);
    }
    if (res.positionals[0].len == 0) {
        std.log.err("At least one repo must be provided", .{});
        std.process.exit(1);
    }

    if (res.args.temp != 0) {
        const path = try help.getTempDir(allocator, init.minimal.environ);
        config.path = .{ .allocated = path };
        std.log.info("using temp as path", .{});
    } else if (res.args.path) |path| {
        config.path = .{ .provided = path };
        std.log.info("using {s} as path", .{path});
    } else {
        const path = init.minimal.environ.getPosix("GRAB_PATH") orelse {
            std.log.err("unable to get GRAB_PATH, please set or use --temp or --path", .{});
            std.process.exit(1);
        };

        if (path.len == 0) {
            std.log.err("unable to get GRAB_PATH, please set or use --temp or --path", .{});
            std.process.exit(1);
        }
        config.path = .{ .provided = path };
        std.log.debug("try to get path from env", .{});
    }
    if (res.args.remote != 0) {
        config.action = .remote;
    }

    if (res.args.standard != 0) {
        config.action = .standard;
    }

    if (res.args.shallow != 0) {
        config.shallow = true;
    }

    try grab.setLocation(init.io, config);

    var run_failure = false;
    for (res.positionals[0]) |repo| {
        std.log.info("working on repo: {s}", .{repo});

        const project = grab.Project.init(repo) catch |err| switch (err) {
            error.parse => {
                std.log.err("unable to parse: {s}", .{repo});
                run_failure = true;
                continue;
            },
        };

        std.log.debug("Project Data:\n\tSite: {s}\n\tOwner: {s}\n\tName: {s}\n\tClone: {s}", .{ project.site, project.owner, project.name, project.clone });

        switch (config.action) {
            .standard => clone(init.io, allocator, project, .{ .shallow = config.shallow }) catch {
                run_failure = true;
            },
            .worktree => worktree(allocator, init.io, project, .{ .shallow = config.shallow }) catch {
                run_failure = true;
            },
            .remote => addRemote(allocator, init.io, project) catch {
                run_failure = true;
            },
        }
    }
    std.log.info("Finished", .{});
    if (run_failure) std.process.exit(1);
}

const gitOpts = struct { shallow: bool = false };

fn clone(io: std.Io, allocator: std.mem.Allocator, project: grab.Project, opts: gitOpts) !void {
    var project_ = project;
    const cwd = std.Io.Dir.cwd();
    const path = grab.createPath(io, cwd, &[_][]const u8{ project_.site, project_.owner }) catch |err| {
        std.log.err("unhandled error: {any}", .{err});
        return err;
    };
    project_.root = path;
    grab.clone(allocator, io, project_, .{ .bare = false, .shallow = opts.shallow }) catch |err| switch (err) {
        error.exists => {
            std.log.err("Unable to clone: {s}, path not empty", .{project_.name});
            return error.clone;
        },
        else => {
            std.log.err("unhandled error: {any}", .{err});
            return err;
        },
    };
}

fn addRemote(allocator: std.mem.Allocator, io: std.Io, project: grab.Project) !void {
    var paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (paths.items) |i| {
            allocator.free(i);
        }
        paths.deinit(allocator);
    }
    grab.findPaths(allocator, io, &paths, project.name) catch |err| {
        std.log.err("unhandled error: {any}", .{err});
        return err;
    };
    std.log.info("Remote \"{s}\" is being added to the following projects:", .{project.owner});
    for (paths.items) |path| {
        std.log.info("\t{s}", .{path});
    }
    for (paths.items) |path| {
        grab.addRemote(allocator, io, project, path) catch |err| switch (err) {
            error.RemoteExists => std.log.warn("Skipping adding remote to {s}, as remote already exists", .{path}),
            else => return err,
        };
    }
    std.log.info("successfully added remotes", .{});
}

fn worktree(allocator: std.mem.Allocator, io: std.Io, project: grab.Project, opts: gitOpts) !void {
    std.log.debug("Config worktree deployment", .{});
    var project_ = project;
    const cwd = std.Io.Dir.cwd();
    const path = grab.createPath(io, cwd, &[_][]const u8{ project_.site, project_.owner, project_.name }) catch |err| {
        std.log.err("unhandled error: {any}", .{err});
        return err;
    };
    project_.root = path;
    grab.clone(allocator, io, project_, .{ .bare = true, .shallow = opts.shallow }) catch |err| switch (err) {
        error.exists => {
            std.log.err("Unable to clone: {s}, path not empty", .{project_.name});
            return error.clone;
        },
        else => {
            std.log.err("unhandled error: {any}", .{err});
            return err;
        },
    };

    if (project_.root) |root| {
        grab.linkGit(io, root) catch |err| {
            std.log.err("unhandled error: {any}", .{err});
            return err;
        };
        grab.setupOrigin(allocator, io, root) catch |err| {
            std.log.err("unhandled error: {any}", .{err});
            return err;
        };
        grab.fetchOrigin(allocator, io, root) catch |err| {
            std.log.err("unhandled error: {any}", .{err});
            return err;
        };
    }
}
