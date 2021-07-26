const std = @import("std");
const sdk = @import("sdk");

pub fn init() !void {
    var lib = try std.DynLib.open(names.lib);

    inline for (comptime std.meta.fieldNames(@TypeOf(names))) |field| {
        if (comptime std.mem.eql(u8, field, "lib")) continue;
        const func = &@field(@This(), field);
        const name = @field(names, field);
        func.* = lib.lookup(@TypeOf(func.*), name) orelse return error.SymbolNotFound;
    }
}

const FmtFn = fn (fmt: [*:0]const u8, ...) callconv(.C) void;
pub var msg: FmtFn = undefined;
pub var warning: FmtFn = undefined;
pub var colorMsg: fn (color: *const sdk.Color, fmt: [*:0]const u8, ...) callconv(.C) void = undefined;
pub var devMsg: FmtFn = undefined;
pub var devWarning: FmtFn = undefined;

const names = switch (std.builtin.os.tag) {
    .windows => .{
        .lib = "tier0.dll",
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "?ConColorMsg@@YAXABVColor@@PBDZZ",
        .devMsg = "?DevMsg@@YAXPBDZZ",
        .devWarning = "?DevWarning@@YAXPBDZZ",
    },
    .linux => .{
        .lib = "libtier0.so",
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "_Z11ConColorMsgRK5ColorPKcz",
        .devMsg = "_Z6DevMsgPKcz",
        .devWarning = "_Z10DevWarningPKcz",
    },
    .macos => @compileError("macOS not yet supported"),
    else => @compileError("Unsupported OS"),
};
