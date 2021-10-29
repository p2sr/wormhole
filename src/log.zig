const std = @import("std");
const sdk = @import("sdk");
const tier0 = @import("tier0.zig");

const Context = union(enum) {
    color: sdk.Color,
    dev: void,
};

fn writeFn(ctx: Context, bytes: []const u8) error{}!usize {
    switch (ctx) {
        .color => |c| tier0.colorMsg(&c, "%.*s", bytes.len, bytes.ptr),
        .dev => tier0.devMsg("%.*s", bytes.len, bytes.ptr),
    }
    return bytes.len;
}

fn mkWriter(ctx: Context) std.io.Writer(Context, void, writeFn) {
    return std.io.Writer(Context, void, writeFn){ .context = ctx };
}

// TODO: write info to a log file
fn write(ctx: Context, comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(
        std.io.Writer(Context, error{}, writeFn){ .context = ctx },
        fmt,
        args,
    ) catch unreachable;
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    write(.{ .color = .{ .r = 255, .g = 100, .b = 100 } }, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    write(.{ .color = .{ .r = 255, .g = 200, .b = 80 } }, fmt, args);
}

pub fn devInfo(comptime fmt: []const u8, args: anytype) void {
    write(.dev, fmt, args);
}
