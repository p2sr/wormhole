const std = @import("std");
const sdk = @import("sdk");
const tier0 = @import("tier0.zig");
const interface = @import("interface.zig");
const mods = @import("mods.zig");
const log = @import("log.zig");
const surface = @import("surface.zig");

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const hud = @import("hud.zig");
const thud = @import("thud.zig");
pub var test_hud: hud.Hud(thud.THud) = undefined;

fn init() !void {
    gpa = .{};
    errdefer std.debug.assert(!gpa.deinit());

    {
        var arena = std.heap.ArenaAllocator.init(&gpa.allocator);
        var s = std.io.fixedBufferStream("testing {.color:FF0000}red{.color:reset} thud with {.align:base}{.align:50}alignment and {test.test} components");
        var p = thud.parser(arena, s.reader());
        const parts = try p.parse();
        var lines = try arena.allocator.alloc(thud.THud.Line, 1);
        lines[0] = .{
            .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .parts = parts,
        };
        test_hud = .{
            .ctx = .{
                .arena = arena,
                .font = {},
                .spacing = 5,
                .padding = 20,
                .lines = lines,
            },
            .screen_anchor = std.meta.Vector(2, f32){ 0.5, 0.5 },
            .hud_anchor = std.meta.Vector(2, f32){ 0.5, 0.5 },
            .pix_off = std.meta.Vector(2, i32){ 0, 0 },
            .scale = 1.0,
        };
    }

    try tier0.init();

    try interface.init(&gpa.allocator);
    errdefer interface.deinit();

    surface.init(&gpa.allocator);

    try mods.init(&gpa.allocator);
    errdefer mods.deinit();
}

fn deinit() void {
    mods.deinit();
    interface.deinit();
    test_hud.ctx.arena.deinit();
    std.debug.assert(!gpa.deinit());
}

// Plugin callbacks below

const Method = switch (@import("builtin").os.tag) {
    .windows => std.builtin.CallingConvention.Thiscall,
    else => std.builtin.CallingConvention.C,
};

// For some reason the game calls 'unload' if 'load' fails. We really don't
// want this, so we just ignore calls to 'unload' unless we're fully loaded
var loaded = false;

fn load(_: *sdk.IServerPluginCallbacks, interfaceFactory: sdk.CreateInterfaceFn, gameServerFactory: sdk.CreateInterfaceFn) callconv(Method) bool {
    _ = interfaceFactory;
    _ = gameServerFactory;

    init() catch return false;

    loaded = true;

    return true;
}

fn unload(_: *sdk.IServerPluginCallbacks) callconv(Method) void {
    if (!loaded) return;
    deinit();
}

fn pause(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn unpause(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn getPluginDescription(_: *sdk.IServerPluginCallbacks) callconv(Method) [*:0]const u8 {
    return "Wormhole: a mod loader for Portal 2";
}

fn levelInit(_: *sdk.IServerPluginCallbacks, map_name: [*:0]const u8) callconv(Method) void {
    _ = map_name;
}

fn serverActivate(_: *sdk.IServerPluginCallbacks, edict_list: [*]sdk.Edict, edict_count: c_int, client_max: c_int) callconv(Method) void {
    _ = edict_list;
    _ = edict_count;
    _ = client_max;
}

fn gameFrame(_: *sdk.IServerPluginCallbacks, simulating: bool) callconv(Method) void {
    _ = simulating;
}

fn levelShutdown(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn clientActive(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientFullyConnect(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientDisconnect(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientPutInServer(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict, player_name: [*:0]const u8) callconv(Method) void {
    _ = entity;
    _ = player_name;
}

fn setCommandClient(_: *sdk.IServerPluginCallbacks, index: c_int) callconv(Method) void {
    _ = index;
}

fn clientSettingsChanged(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientConnect(_: *sdk.IServerPluginCallbacks, allow: *bool, entity: *sdk.Edict, name: [*:0]const u8, addr: [*:0]const u8, reject: [*:0]u8, max_reject_len: c_int) callconv(Method) c_int {
    _ = allow;
    _ = entity;
    _ = name;
    _ = addr;
    _ = reject;
    _ = max_reject_len;
    return 0;
}

fn clientCommand(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict, args: *const sdk.CCommand) callconv(Method) c_int {
    _ = entity;
    _ = args;
    return 0;
}

fn networkIdValidated(_: *sdk.IServerPluginCallbacks, user_name: [*:0]const u8, network_id: [*:0]const u8) callconv(Method) c_int {
    _ = user_name;
    _ = network_id;
    return 0;
}

fn onQueryCvarValueFinished(_: *sdk.IServerPluginCallbacks, cookie: sdk.QueryCvarCookie, player: *sdk.Edict, status: sdk.QueryCvarValueStatus, name: [*:0]const u8, val: [*:0]const u8) callconv(Method) void {
    _ = cookie;
    _ = player;
    _ = status;
    _ = name;
    _ = val;
}

fn onEdictAllocated(_: *sdk.IServerPluginCallbacks, edict: *sdk.Edict) callconv(Method) void {
    _ = edict;
}

fn onEdictFreed(_: *sdk.IServerPluginCallbacks, edict: *const sdk.Edict) callconv(Method) void {
    _ = edict;
}

// Automatically generates the IServerPluginCallbacks vtable from the
// functions defined in this file
var callbacks = sdk.IServerPluginCallbacks{
    .vtable = &blk: {
        var vt: sdk.IServerPluginCallbacks.Vtable = undefined;
        for (std.meta.fieldNames(@TypeOf(vt))) |name| {
            @field(vt, name) = @field(@This(), name);
        }
        break :blk vt;
    },
};

// The function we expose to the game!
export fn CreateInterface(name: [*:0]u8, ret: ?*c_int) ?*c_void {
    if (!std.mem.eql(u8, std.mem.span(name), "ISERVERPLUGINCALLBACKS003")) {
        if (ret) |r| r.* = 0;
        return @ptrCast(*c_void, &callbacks);
    }

    if (ret) |r| r.* = 1;
    return null;
}
