const std = @import("std");
const sdk = @import("sdk");
const Wormhole = @import("Wormhole.zig");
const event = @import("event.zig");

var count: u8 = 0;

const Method = switch (@import("builtin").os.tag) {
    .windows => std.builtin.CallingConvention.Thiscall,
    else => std.builtin.CallingConvention.C,
};

fn readFuncPtr(comptime T: type, func: anytype, offset: usize) T {
    const raw = @intFromPtr(func);
    const diff = @as(*align(1) const usize, @ptrFromInt(raw + offset)).*;
    const addr = (raw + offset + @sizeOf(usize)) +% diff;
    return @ptrFromInt(addr);
}

IEngineVGuiInternal: struct {
    pub fn paint(self: *sdk.IEngineVGuiInternal, mode: sdk.PaintMode) callconv(Method) void {
        const orig = Wormhole.getInst().interface_manager.orig.IEngineVGuiInternal;
        var ret = orig.paint(self, mode);

        if (mode.ui_panels) {
            Wormhole.getInst().thud_manager.drawAll(0);
        }

        return ret;
    }
},

IServerGameDLL: struct {
    pub fn gameFrame(self: *sdk.IServerGameDLL, simulating: bool) callconv(Method) void {
        const orig = Wormhole.getInst().interface_manager.orig.IServerGameDLL;
        var sim1 = simulating;
        event.trigger(null, "pre_tick", &sim1);
        var ret = orig.gameFrame(self, simulating);
        event.trigger(null, "post_tick", &sim1);
        return ret;
    }
},
