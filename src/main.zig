const std = @import("std");
const clap = @import("clap");

// TODO: Need to set up some way to pull the version from the zon file.
const version = "x.y.z";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\<REPO>... Git repositrories to clone.
        \\-h, --help       show this help message and exit
        \\-p, --path <PATH>  Overrides the path set in the GRAB_PATH environment variable.
        \\-t, --temp       Download repositories to a temporary directory. This will be the OS default temporary directory.
        \\-r, --remote     Add remote to existing repo.
        \\--debug          Enable debug mode.
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
    if (res.args.version != 0)
        std.debug.print("grab: {s}\n", .{version});

    if (res.args.temp != 0 and res.args.path != null) {
        std.debug.print("Cannot specify both --temp and --path\n", .{});
        return error.noreturn; // FIXME: need better error value
    }

    if (res.positionals[0].len == 0) {
        std.debug.print("At least one repo must be provided\n", .{});
        return error.noreturn; // FIXME: need better error value
    }

    if (res.args.temp != 0) {
        std.debug.print("using temp as path\n", .{});
    } else if (res.args.path) |path| {
        std.debug.print("using {s} as path\n", .{path});
    } else {
        std.debug.print("try to get path from env\n", .{});
    }

    for (res.positionals[0]) |repo| {
        std.debug.print("working on repo: {s}\n", .{repo});
        if (res.args.remote != 0) {
            std.debug.print("adding repo as remote\n", .{});
        } else {
            std.debug.print("cloning repo\n", .{});
        }
    }
}
