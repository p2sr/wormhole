const Wormhole = @import("Wormhole.zig");

pub const ServerEntity = opaque {};

pub fn getEntity(idx: usize) ?*ServerEntity {
    const IServerTools = Wormhole.getInst().interface_manager.ifaces.IServerTools;

    var ent: ?*ServerEntity = @ptrCast(IServerTools.firstEntity());

    var i: usize = 0;
    while (i < idx and ent != null) : (i += 1) {
        ent = @ptrCast(IServerTools.nextEntity(ent));
    }

    return ent;
}
