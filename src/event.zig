const std = @import("std");
const mods = @import("mods.zig");

var allocator: *std.mem.Allocator = undefined;

fn trigger_i(ev_name: []const u8, data: ?*c_void) void {
    var it = mods.iterator();
    while (it.next()) |mod| {
        if (mod[1].event_handlers.get(ev_name)) |handlers| {
            for (handlers) |h| {
                // TODO: record that we're in that mod's code
                // otherwise, stuff like dispatching events from an
                // event callback will be super fucked up
                h.cbk(data);
            }
        }
    }
}

pub fn trigger(mod: ?[]const u8, name: []const u8, data: ?*c_void) void {
    if (mod) |m| {
        const ev_name = allocator.alloc(u8, name.len + m.len + 1) catch unreachable; // TODO
        defer allocator.free(ev_name);

        std.mem.copy(u8, ev_name[0..name.len], m);
        ev_name[name.len] = '.';
        std.mem.copy(u8, ev_name[name.len + 1 ..], name);

        trigger_i(ev_name, data);
    } else {
        trigger_i(name, data);
    }
}
