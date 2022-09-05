const std = @import("std");
const sdk = @import("sdk");
const log = @import("log.zig");
const event = @import("event.zig");
const ifaces = @import("interface.zig").ifaces;
const orig = @import("interface.zig").orig;

var count: u8 = 0;

const Method = switch (@import("builtin").os.tag) {
    .windows => std.builtin.CallingConvention.Thiscall,
    else => std.builtin.CallingConvention.C,
};

fn readFuncPtr(comptime T: type, func: anytype, offset: usize) T {
    const raw = @ptrToInt(func);
    const diff = @intToPtr(*align(1) const usize, raw + offset).*;
    const addr = (raw + offset + @sizeOf(usize)) +% diff;
    return @intToPtr(T, addr);
}

IEngineVGui: struct {
    pub fn paint(self: *sdk.IEngineVGui, _mode: c_int) callconv(Method) void {
        var ret = orig.IEngineVGui.paint(self, _mode);

        const mode = @bitCast(sdk.PaintMode, @intCast(u2, _mode));

        // TODO: proper system for getting non-exposed shit, cuz this is
        // gross
        const offsets = switch (@import("builtin").os.tag) {
            .linux => .{
                .startDrawing = 85,
                .finishDrawing = 204,
            },
            .windows => .{
                .startDrawing = 22,
                .finishDrawing = 117,
            },
            .macos => .{
                .startDrawing = 59,
                .finishDrawing = 217,
            },
            else => @compileError("OS not supported"),
        };
        const startDrawing = readFuncPtr(*const fn (*sdk.ISurface) callconv(Method) void, orig.ISurface.precacheFontCharacters, offsets.startDrawing);
        const finishDrawing = readFuncPtr(*const fn (*sdk.ISurface) callconv(Method) void, orig.ISurface.precacheFontCharacters, offsets.finishDrawing);

        startDrawing(ifaces.ISurface);

        if (mode.ui_panels) {
            @import("thud.zig").drawAll(0);
            //const str = "Hello from Wormhole!";

            // Seriously Valve, what the fuck is with the wchar strings?
            //var wstr: [str.len]sdk.wchar = undefined;
            //for (str) |c, i| {
            //    wstr[i] = @intCast(sdk.wchar, c);
            //}

            //ifaces.ISurface.drawSetTextPos(100, 100);
            //ifaces.ISurface.drawSetTextColor(sdk.Color{ .r = 0xCC, .g = 0x22, .b = 0xFF });
            //ifaces.ISurface.drawSetTextFont(13);
            //ifaces.ISurface.drawPrintText(&wstr, wstr.len, sdk.FontDrawType.default);
        }

        finishDrawing(ifaces.ISurface);

        return ret;
    }
},

IServerGameDLL: struct {
    pub fn gameFrame(self: *sdk.IServerGameDLL, simulating: bool) callconv(Method) void {
        var sim1 = simulating;
        event.trigger(null, "pre_tick", &sim1);
        var ret = orig.IServerGameDLL.gameFrame(self, simulating);
        event.trigger(null, "post_tick", &sim1);
        return ret;
    }
},
