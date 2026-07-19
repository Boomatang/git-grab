const builtin = @import("builtin");

pub const log_level = if (builtin.mode == .Debug) .debug else .info;
pub const shallow = false;
pub const action = .worktree;
