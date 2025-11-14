const std = @import("std");
const clap = @import("clap");
const grab = @import("grab");
const help = @import("help");

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
        \\--version        Show program's version number and exit
    );

    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .REPO = clap.parsers.string,
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
        std.debug.print("grab: {s}\n", .{build_options.version});
        std.process.exit(0);
    }

    var config = grab.Configuration.init();
    defer config.deinit(allocator);

    if (res.args.temp != 0 and res.args.path != null) {
        std.debug.print("Cannot specify both --temp and --path\n", .{});
        std.posix.exit(1);
    }

    if (res.args.standard != 0 and res.args.remote != 0) {
        std.debug.print("Cannot specify both --standard and --remote\n", .{});
        std.posix.exit(1);
    }
    if (res.positionals[0].len == 0) {
        std.debug.print("At least one repo must be provided\n", .{});
        std.posix.exit(1);
    }

    if (res.args.temp != 0) {
        const path = try help.getTempDir(allocator);
        config.path = .{ .allocated = path };
        std.debug.print("using temp as path\n", .{});
    } else if (res.args.path) |path| {
        config.path = .{ .provided = path };
        std.debug.print("using {s} as path\n", .{path});
    } else {
        const path = std.process.getEnvVarOwned(allocator, "GRAB_PATH") catch {
            std.debug.print("unable to get GRAB_PATH, please set or use --temp or --path\n", .{});
            std.process.exit(1);
        };
        if (path.len == 0) {
            std.debug.print("unable to get GRAB_PATH, please set or use --temp or --path\n", .{});
            std.process.exit(1);
        }
        config.path = .{ .allocated = path };
        std.debug.print("try to get path from env\n", .{});
    }
    if (res.args.remote != 0) {
        config.action = .remote;
    }

    if (res.args.standard != 0) {
        config.action = .standard;
    }

    try grab.setLocation(config);

    for (res.positionals[0]) |repo| {
        std.debug.print("working on repo: {s}\n", .{repo});

        const project = grab.Project.init(repo) catch |err| switch (err) {
            error.parse => {
                std.debug.print("unable to parse: {s}\n", .{repo});
                std.process.exit(1);
            },
            else => return err,
        };

        std.debug.print("Project Data:\n\tSite: {s}\n\tOwner: {s}\n\tName: {s}\n\tClone: {s}\n", .{ project.site, project.owner, project.name, project.clone });

        switch (config.action) {
            .standard => try clone(allocator, project),
            .worktree => try worktree(allocator, project),
            .remote => try addRemote(allocator, project),
        }
    }
}

fn clone(allocator: std.mem.Allocator, project: grab.Project) !void {
    var project_ = project;
    const cwd = std.fs.cwd();
    const path = try grab.createPath(cwd, &[_][]const u8{ project_.site, project_.owner });
    project_.root = path;
    grab.clone(allocator, project_, .{ .bare = false }) catch |err| switch (err) {
        error.exists => {
            std.debug.print("Unable to clone: {s}, path not empty\n", .{project_.name});
            std.process.exit(1);
        },
        else => {
            std.debug.print("unhandled error: {any}\n", .{err});
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
    std.debug.print("Remote \"{s}\" is being added to the following projects:\n", .{project.owner});
    for (paths.items) |path| {
        std.debug.print("\t{s}\n", .{path});
    }
    for (paths.items) |path| {
        grab.addRemote(allocator, project, path) catch |err| switch (err) {
            error.RemoteExists => std.debug.print("Skipping adding remote to {s}, as remote already exists\n", .{path}),
            else => return err,
        };
    }
    std.debug.print("Success\n", .{});
}

fn worktree(allocator: std.mem.Allocator, project: grab.Project) !void {
    std.debug.print("Config worktree deployment\n", .{});
    var project_ = project;
    const cwd = std.fs.cwd();
    const path = try grab.createPath(cwd, &[_][]const u8{ project_.site, project_.owner, project_.name });
    project_.root = path;
    grab.clone(allocator, project_, .{ .bare = true }) catch |err| switch (err) {
        error.exists => {
            std.debug.print("Unable to clone: {s}, path not empty\n", .{project_.name});
            std.process.exit(1);
        },
        else => {
            std.debug.print("unhandled error: {any}\n", .{err});
            std.process.exit(1);
        },
    };

    if (project_.root) |root| {
        try grab.linkGit(root);
        try grab.setupOrigin(allocator, root);
        try grab.fetchOrigin(allocator, root);
    }
}
