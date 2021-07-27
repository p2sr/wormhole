const std = @import("std");
const sdk = @import("sdk");
const log = @import("log.zig");
const orig = @import("interface.zig").orig;

var count: u8 = 0;

const Method = switch (std.builtin.os.tag) {
    .windows => std.builtin.CallingConvention.Thiscall,
    else => std.builtin.CallingConvention.C,
};

IEngineVGui: struct {
    pub fn paint(self: *sdk.IEngineVGui, mode: sdk.PaintMode) callconv(Method) void {
        var ret = orig.IEngineVGui.paint(self, mode);
        count +%= 1;
        if (count == 0) {
            log.info("Paint!\n", .{});
        }
        return ret;
    }
},
