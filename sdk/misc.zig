const std = @import("std");

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
pub const FontDrawType = enum(c_int) {
    default,
    nonadditive,
    additive,
};
pub const wchar = switch (@import("std").builtin.os.tag) {
    .windows => u16,
    else => u32,
};
pub const HFont = i32;
pub const Vpanel = u32;
pub const InputContextHandle = ?*opaque {};
pub const VGuiPanel = enum(c_int) {
    root,
    gameui_dll,
    client_dll,
    tools,
    in_game_screens,
    game_dll,
    client_dll_tools,
    gameui_background,
    puzzlemaker,
    transition_effect,
    steam_overlay,
};
pub const InputEvent = opaque {};
pub const PaintMode = enum(c_int) {
    ui_panels = 1 << 0,
    in_game_panels = 1 << 1,
};
pub const LevelLoadingProgress = enum(c_int) {
    none,
    changelevel,
    spawnserver,
    loadworldmodel,
    crcmap,
    crcclientdll,
    createnetworkstringtables,
    precacheworld,
    clearworld,
    levelinit,
    precache,
    activateserver,
    beginconnect,
    signonchallenge,
    signonconnect,
    signonconnected,
    processserverinfo,
    processstringtable,
    signonnew,
    sendclientinfo,
    sendsignondata,
    createentities,
    fullyconnected,
    precachelighting,
    readytoplay,
};
pub const IntRect = extern struct {
    x0: c_int,
    y0: c_int,
    x1: c_int,
    y1: c_int,
};
pub const QueryCvarCookie = c_int;
pub const QueryCvarValueStatus = enum(c_int) {
    value_intact,
    cvar_not_found,
    not_a_cvar,
    cvar_protected,
};
