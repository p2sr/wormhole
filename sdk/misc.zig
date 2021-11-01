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
pub const wchar = switch (@import("builtin").os.tag) {
    .windows => u16,
    else => u32,
};
pub const HFont = u32;
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
pub const PaintMode = packed struct {
    ui_panels: bool,
    in_game_panels: bool,
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
pub const SurfaceFeature = enum(c_int) {
    antialiased_fonts = 1,
    dropshadow_fonts = 2,
    escape_key = 3,
    opening_new_html_windows = 4,
    frame_minimize_maximize = 5,
    outline_fonts = 6,
    direct_hwnd_render = 7,
};
pub const IHTMLEvents = opaque {};
pub const IHTML = opaque {};
pub const HCursor = u32;
pub const HTexture = u32;
pub const Vertex = extern struct {
    position: Vector2D,
    tex_coord: Vector2D,
};
pub const Vector2D = extern struct {
    x: f32,
    y: f32,
};
pub const FontCharRenderInfo = opaque {};
pub const IVguiMatInfo = opaque {};
pub const ImageFormat = c_int; // TODO: this is really an enum but it's fucking huge
pub const IImage = opaque {};
pub const DrawTexturedRectParms = extern struct {
    x0: c_int,
    y0: c_int,
    x1: c_int,
    y1: c_int,

    s0: f32,
    t0: f32,
    s1: f32,
    t1: f32,

    alpha_ul: u8,
    alpha_ur: u8,
    alpha_lr: u8,
    alpha_ll: u8,

    angle: f32,
};
pub const Vector3D = extern struct {
    x: f32,
    y: f32,
    z: f32,
};
pub const Model = opaque {}; // model_t
pub const SurfInfo = struct {
    verts: [16]Vector3D,
    nverts: c_ulong,
    plane: VPlane,
    engine_data: *c_void,
};
pub const VPlane = struct {
    normal: Vector3D,
    dist: f32,
};
pub const IMaterial = opaque {};
