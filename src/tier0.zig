const std = @import("std");

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
pub var devMsg: FmtFn = undefined;
pub var devWarning: FmtFn = undefined;

const names = switch (std.builtin.os.tag) {
    .windows => @compileError("Windows not yet supported"),
    else => .{
        .lib = "libtier0.so",
        .msg = "Msg",
        .warning = "Warning",
        .devMsg = "_Z6DevMsgPKcz",
        .devWarning = "_Z10DevWarningPKcz",
    },
};
