const std = @import("std");
const Wormhole = @import("Wormhole.zig");

fn trigger_i(wh: *Wormhole, ev_name: []const u8, data: ?*anyopaque) void {
    var it = wh.mod_manager.iterator();
    while (it.next()) |mod| {
        if (mod[1].event_handlers.get(ev_name)) |handlers| {
            for (handlers) |h| {
                // TODO: record that we're in that mod's code
                // otherwise, stuff like dispatching events from an
                // event callback will be super fucked up
                h.call(mod[0], data);
            }
        }
    }
}

pub fn trigger(wh: *Wormhole, mod: ?[]const u8, name: []const u8, data: ?*anyopaque) void {
    if (mod) |m| {
        const ev_name = wh.gpa.alloc(u8, name.len + m.len + 1) catch unreachable; // TODO
        defer wh.gpa.free(ev_name);

        std.mem.copy(u8, ev_name[0..name.len], m);
        ev_name[name.len] = '.';
        std.mem.copy(u8, ev_name[name.len + 1 ..], name);

        trigger_i(wh, ev_name, data);
    } else {
        trigger_i(wh, name, data);
    }
}
