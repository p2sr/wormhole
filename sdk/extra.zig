const std = @import("std");

const key_values = @import("key_values.zig");

pub usingnamespace @import("edict.zig");
pub usingnamespace @import("misc.zig");
pub const KeyValues = key_values.KeyValues;

pub fn init() bool {
    key_values.initSystem() catch |err| {
        std.log.err("KeyValues init error: {}", .{err});
        return false;
    };

    return true;
}
