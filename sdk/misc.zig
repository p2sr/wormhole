pub const CBaseEntity = opaque {};
pub const IServerUnknown = opaque {};
pub const IHandleEntity = opaque {};
pub const PVSInfo = opaque {};
pub const CreateInterfaceFn = fn (name: [*:0]const u8, ret: *c_int) callconv(.C) *c_void;
pub const ServerClass = opaque {};
pub const CBaseNetworkable = opaque {};
pub const CCommand = opaque {};
