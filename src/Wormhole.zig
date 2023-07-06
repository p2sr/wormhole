//! This file contains the entire state of Wormhole. Every component should
//! contain a backlink to this main struct. The global accessor (getInst) should
//! be used only when absolutely necessary (on API boundaries).

const std = @import("std");
const sdk = @import("sdk");
const assert = std.debug.assert;

const Wormhole = @This();
const InterfaceManager = @import("InterfaceManager.zig");
const ModManager = @import("ModManager.zig");
const ThudManager = @import("ThudManager.zig");
const Surface = @import("Surface.zig");
const RenderManager = @import("RenderManager.zig");

/// Gets the global Wormhole instance. Use of this function is discouraged, and
/// should only occur on API boundaries where there is no other reference to the
/// instance. Asserts that Wormhole is loaded.
pub fn getInst() *Wormhole {
    const wh = getInstUnchecked();
    assert(wh.load_state == .loaded);
    return wh;
}

/// Like `getInst`, but does not assert that Wormhole is loaded.
pub fn getInstUnchecked() *Wormhole {
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

interface_manager: InterfaceManager,
mod_manager: ModManager,
surface: Surface,
thud_manager: ThudManager,
render_manager: RenderManager,
// TODO: transition other global state here

var gpa_state: std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 8,
}) = undefined;

pub fn load(wh: *Wormhole) !void {
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

    wh.interface_manager = try InterfaceManager.init(wh);
    errdefer wh.interface_manager.deinit();

    wh.mod_manager = try ModManager.init(wh);
    errdefer wh.mod_manager.deinit();

    wh.surface = Surface.init(wh);

    wh.thud_manager = try ThudManager.init(wh);
    errdefer wh.thud_manager.deinit();

    wh.render_manager = try RenderManager.init(wh);
    errdefer wh.render_manager.deinit();

    wh.load_state = .loaded;
}

pub fn unload(wh: *Wormhole) void {
    assert(wh.load_state == .loaded);

    wh.render_manager.deinit();
    wh.thud_manager.deinit();
    wh.mod_manager.deinit();
    wh.interface_manager.deinit();

    _ = gpa_state.deinit();

    wh.load_state = .unloaded;
}
