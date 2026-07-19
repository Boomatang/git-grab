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
            break :blk "[" ++ level.asText() ++ "] ";
        break :blk "[" ++ level.asText() ++ "][" ++ @tagName(scope) ++ "] ";
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
