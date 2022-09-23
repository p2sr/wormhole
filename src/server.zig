const ifaces = @import("interface.zig").ifaces;

pub const ServerEntity = opaque {};

pub fn getEntity(idx: usize) ?*ServerEntity {
    var ent = @ptrCast(?*ServerEntity, ifaces.IServerTools.firstEntity());

    var i: usize = 0;
    while (i < idx and ent != null) : (i += 1) {
        ent = @ptrCast(?*ServerEntity, ifaces.IServerTools.nextEntity(ent));
    }

    return ent;
}
