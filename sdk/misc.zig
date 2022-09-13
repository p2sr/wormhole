const std = @import("std");

pub const CBaseEntity = opaque {};
pub const IServerUnknown = opaque {};
pub const IHandleEntity = opaque {};
pub const PVSInfo = opaque {};
pub const CreateInterfaceFn = *const fn (name: [*:0]const u8, ret: ?*c_int) callconv(.C) ?*align(@alignOf(*anyopaque)) anyopaque;
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
pub const PaintMode = packed struct(c_int) {
    ui_panels: bool,
    in_game_panels: bool,
    _unused: u30,
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
pub const Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
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
pub const QAngle = extern struct {
    pitch: f32,
    yaw: f32,
    roll: f32,
};
pub const Model = opaque {}; // model_t
pub const SurfInfo = struct {
    verts: [16]Vector3D,
    nverts: c_ulong,
    plane: VPlane,
    engine_data: *anyopaque,
};
pub const VPlane = struct {
    normal: Vector3D,
    dist: f32,
};
pub const IClientEntity = opaque {};
pub const IServerEntity = opaque {};
pub const CEntityRespawnInfo = extern struct {
    hammer_id: c_int,
    ent_text: [*:0]const u8,
};
pub const CGlobalVars = opaque {};
pub const ImageFormat = enum(c_int) {
    default = -2,
    unkown = -1,
    rgba8888 = 0,
    abgr8888,
    rgb888,
    bgr888,
    rgb565,
    i8,
    ia88,
    p8,
    a8,
    rgb888_bluescreen,
    bgr888_bluescreen,
    argb8888,
    bgra8888,
    // TODO: more
};
pub const TextureFlags = packed struct(c_int) {
    point_sample: bool = false,
    trilinear: bool = false,
    clamp_s: bool = false,
    clamp_t: bool = false,
    anisotropic: bool = false,
    hint_dxt5: bool = false,
    pwl_corrected: bool = false,
    normal: bool = false,
    no_mip: bool = false,
    no_lod: bool = false,
    all_mips: bool = false,
    procedural: bool = false,
    one_bit_alpha: bool = false,
    eight_bit_alpha: bool = false,
    env_map: bool = false,
    render_target: bool = false,
    depth_render_target: bool = false,
    no_debug_override: bool = false,
    single_copy: bool = false,
    srgb: bool = false,
    default_pool: bool = false,
    _unused1: u2 = 0,
    no_depth_buffer: bool = false,
    _unused2: u1 = 0,
    clampu: bool = false,
    vertex_texture: bool = false,
    ssbump: bool = false,
    most_mips: bool = false,
    border: bool = false,
    _unused3: u2 = 0,
};
pub const MaterialRenderTargetDepth = c_int;
pub const ITextureRegenerator = opaque {};

pub const VertexCompressionType = enum(c_uint) {
    invalid = 0xFFFFFFFF,
    none = 0,
    on = 1,
};
pub const VertexDesc = extern struct {
    size: extern struct {
        position: c_int,
        bone_weight: c_int,
        bone_matrix_index: c_int,
        normal: c_int,
        color: c_int,
        specular: c_int,
        tex_coord: [8]c_int,
        tangent_s: c_int,
        tangent_t: c_int,
        wrinkle: c_int,
        user_data: c_int,
    },

    actual_size: c_int,
    compression_type: VertexCompressionType,
    num_bone_weights: c_int,

    data: extern struct {
        position: ?[*]f32,
        bone_weight: ?[*]f32,
        bone_matrix_index: ?[*]u8,
        normal: ?[*]f32,
        color: ?[*]u8,
        specular: ?[*]u8,
        tex_coord: [8]?[*]f32,
        tangent_s: ?[*]f32,
        tangent_t: ?[*]f32,
        wrinkle: ?[*]f32,
        user_data: ?[*]f32,
    },

    first: c_int,
    mem_offset: c_int,
};
pub const IndexDesc = extern struct {
    data: [*]u16,
    mem_offset: c_int,
    first: c_int,
    size: c_int,
};
pub const MeshDesc = extern struct {
    vertex: VertexDesc,
    index: IndexDesc,
};
pub const MeshBuffersAllocationSettings = opaque {};
pub const BaseMeshBuilder = opaque {};
pub const VertexFormat = enum(u64) { _ };
pub const PrimitiveType = enum(c_int) {
    points,
    lines,
    triangles,
    triangle_strip,
    line_strip,
    line_loop,
    polygon,
    quads,
};
pub const MaterialIndexFormat = enum(c_int) {
    unknown = -1,
    fmt_16bit = 0,
    fmt_32bit = 1,
};
pub const VMatrix = extern struct {
    mat: [4][4]f32,
    pub const identity: VMatrix = .{ .mat = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };
    pub fn scale(x: f32, y: f32, z: f32) VMatrix {
        return .{ .mat = .{
            .{ x, 0, 0, 0 },
            .{ 0, y, 0, 0 },
            .{ 0, 0, z, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }
};
pub const Matrix3x4 = opaque {};
pub const MaterialMatrixMode = enum(c_int) {
    view = 0,
    projection = 1,
    model = 10,
};
pub const PtrAlign16 = *align(16) anyopaque;
