const std = @import("std");

const defaults = @import("defaults.zig");

pub const Level = enum { info, debug, @"error", warn };
pub var log_level: std.log.Level = defaults.log_level;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime blk: {
        if (scope == .default)
            break :blk levelColor(level);
        break :blk levelColor(level) ++ "[" ++ @tagName(scope) ++ "] ";
    };

    if (@intFromEnum(level) <= @intFromEnum(log_level)) {
        std.debug.print(prefix ++ format ++ "\n", args);
    }
}

pub fn set_log_level(level: Level) void {
    switch (level) {
        .debug => log_level = .debug,
        .@"error" => log_level = .err,
        .info => log_level = .info,
        .warn => log_level = .warn,
    }
}

fn levelColor(level: std.log.Level) []const u8 {
    const csi = "\x1b[";
    const end = csi ++ "0m";
    const yellow = csi ++ "33m";
    const red = csi ++ "31m";
    const blue = csi ++ "34m";
    return switch (level) {
        .debug => blue ++ "[" ++ level.asText() ++ "]" ++ end ++ " ",
        .warn => yellow ++ "[" ++ level.asText() ++ "]" ++ end ++ " ",
        .err => red ++ "[" ++ level.asText() ++ "]" ++ end ++ " ",
        .info => "[" ++ level.asText() ++ "] ",
    };
}
