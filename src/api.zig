const std = @import("std");
const event = @import("event.zig");

// This file should deal with *all* calls between Wormhole and mods

// Should be set to the name of the mod whenever we call into one (e.g.
// for any callback etc).
var active_mod: ?[]const u8 = null;

pub fn callExternal(mod: []const u8, func: anytype, args: anytype) @typeInfo(@TypeOf(func)).Fn.return_type.? {
    const old_mod = active_mod;
    defer active_mod = old_mod;

    active_mod = mod;

    return @call(.{}, func, args);
}

export fn wh_trigger_event(name: [*:0]const u8, data: ?*c_void) void {
    if (active_mod) |m|
        event.trigger(m, std.mem.span(name), data)
    else
        @panic("wh_trigger_event without active mod");
}
