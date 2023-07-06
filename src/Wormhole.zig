//! This file contains the entire state of Wormhole. Every component should
//! contain a backlink to this main struct. The global accessor (getInst) should
//! be used only when absolutely necessary (on API boundaries).

const std = @import("std");
const sdk = @import("sdk");
const assert = std.debug.assert;

const Wormhole = @This();
const interface = @import("interface.zig");
const mods = @import("mods.zig");
const surface = @import("surface.zig");
const thud = @import("thud.zig");
const render_manager = @import("render_manager.zig");

/// Gets the global Wormhole instance. Use of this function is discouraged, and
/// should only occur on API boundaries where there is no other reference to the
/// instance.
pub fn getInst() *Wormhole {
    const S = struct {
        var inst: Wormhole = inst: {
            var wh: Wormhole = undefined;
            wh.load_state = .unloaded;
            break :inst wh;
        };
    };
    return &S.inst;
}

pub const LoadState = enum {
    /// Wormhole has not yet been loaded, has failed to load, or has been
    /// unloaded. It currently has no effect on the game.
    unloaded,
    /// Wormhole is in the process of attempting to load. That is, it is
    /// currently within its IServerPluginCallbacks::Load callback.
    loading,
    /// Wormhole has successfully loaded.
    loaded,
};

/// If this is `unloaded`, all other fields are invalid.
/// If it is `loading`, the fields are being initialized in declaration order.
/// If it is `loaded`, all fields are valid.
load_state: LoadState,
/// The root general-purpose allocator. In safe builds, this is a
/// std.heap.GeneralPurposeAllocator for leak detection. In unsafe builds, it is
/// a BinnedAllocator for performance.
gpa: std.mem.Allocator,

/// This is a random value create when Wormhole loads and persisted throughout
/// the game's lifetime. Named resources such as textures should incorporate
/// this value into their names. This prevents instance of Wormhole from
/// fighting with each other across reloads.
resource_prefix: u32,

// TODO: transition other global state here

var gpa_state: std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 8,
}) = undefined;

pub fn init(wh: *Wormhole) !void {
    assert(wh.load_state == .unloaded);
    wh.load_state = .loading;
    errdefer wh.load_state = .unloaded;

    gpa_state = .{};
    errdefer _ = gpa_state.deinit();
    wh.gpa = gpa_state.allocator();

    std.os.getrandom(std.mem.asBytes(&wh.resource_prefix)) catch return error.RandomInitFailed;

    const version = try @import("version.zig").getVersion(wh.gpa);
    // TODO: load offsets etc
    _ = version;

    if (!sdk.init()) return error.SdkInitError;

    try interface.init(wh.gpa);
    errdefer interface.deinit();

    surface.init(wh.gpa);

    try mods.init(wh.gpa);
    errdefer mods.deinit();

    try thud.init(wh.gpa);
    errdefer thud.deinit();

    try render_manager.init(wh.gpa);
    errdefer render_manager.deinit();

    wh.load_state = .loaded;
}

pub fn deinit(wh: *Wormhole) void {
    render_manager.deinit();
    thud.deinit();
    mods.deinit();
    interface.deinit();

    _ = gpa_state.deinit();

    wh.load_state = .unloaded;
}
