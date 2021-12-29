const ifaces = @import("interface.zig").ifaces;
const log = @import("log.zig");

pub const ServerEntity = opaque {};

pub fn getEntity(idx: usize) ?*ServerEntity {
    var ent = @ptrCast(?*ServerEntity, ifaces.IServerTools.firstEntity());

    var i: usize = 0;
    while (i < idx and ent != null) : (i += 1) {
        ent = @ptrCast(?*ServerEntity, ifaces.IServerTools.nextEntity(ent));
    }

    return ent;
}

pub fn outputThing() void {
    const player = getEntity(1);
    if (player) |p| {
        log.info("player at {}\n", .{player});
        const ptr = @ptrToInt(p);
        const beams = @intToPtr(*c_int, ptr + 5084 + 396).*;
        log.info("Player has tractor beam count {}\n", .{beams});
    } else {
        log.info("No player\n", .{});
    }
}
