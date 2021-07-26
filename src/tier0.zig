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

pub var devMsg: fn (fmt: [*:0]const u8, ...) callconv(.C) void = undefined;

const names = switch (std.builtin.os.tag) {
    .windows => @compileError("Windows not yet supported"),
    else => .{
        .lib = "libtier0.so",
        .devMsg = "_Z6DevMsgPKcz",
    },
};
