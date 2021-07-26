pub const CBaseEntity = opaque {};
pub const IServerUnknown = opaque {};
pub const IHandleEntity = opaque {};
pub const PVSInfo = opaque {};
pub const CreateInterfaceFn = fn (name: [*:0]const u8, ret: ?*c_int) callconv(.C) ?*align(@alignOf(*c_void)) c_void;
pub const ServerClass = opaque {};
pub const CBaseNetworkable = opaque {};
pub const CCommand = opaque {};
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};
pub const CvarDLLIdentifier = c_int;
pub const ConCommandBase = opaque {};
