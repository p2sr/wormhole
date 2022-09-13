const std = @import("std");

pub usingnamespace @import("edict.zig");
pub usingnamespace @import("misc.zig");
pub const KeyValues = @import("KeyValues.zig");

pub fn init() bool {
    KeyValues.initSystem() catch |err| {
        std.log.err("KeyValues init error: {}", .{err});
        return false;
    };

    return true;
}
