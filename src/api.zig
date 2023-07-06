const std = @import("std");
const Wormhole = @import("Wormhole.zig");
const event = @import("event.zig");

// This file should deal with *all* calls between Wormhole and mods

// Should be set to the name of the mod whenever we call into one (e.g.
// for any callback etc).
var active_mod: ?[]const u8 = null;

pub fn callExternal(mod: []const u8, func: anytype, args: anytype) @typeInfo(std.meta.Child(@TypeOf(func))).Fn.return_type.? {
    const old_mod = active_mod;
    defer active_mod = old_mod;

    active_mod = mod;

    return @call(.auto, func, args);
}

export fn wh_trigger_event(name: [*:0]const u8, data: ?*anyopaque) void {
    const wh = Wormhole.getInst();
    if (active_mod) |m|
        event.trigger(wh, m, std.mem.span(name), data)
    else
        @panic("wh_trigger_event without active mod");
}
