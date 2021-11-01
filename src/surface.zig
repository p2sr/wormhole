const std = @import("std");
const sdk = @import("sdk");
const ifaces = @import("interface.zig").ifaces;

var scale_i: f32 = 1;
var origin_i = std.meta.Vector(2, i32){ 0, 0 };

pub const scale = &scale_i; // TODO: this should affect text, but what else?
pub const origin = &origin_i;

var allocator: *std.mem.Allocator = undefined;

pub fn init(allocator1: *std.mem.Allocator) void {
    allocator = allocator1;
}

pub fn setColor(col: sdk.Color) void {
    ifaces.ISurface.drawSetColor(col);
    ifaces.ISurface.drawSetTextColor(col);
}

pub fn drawRect(a: std.meta.Vector(2, i32), b: std.meta.Vector(2, i32)) void {
    const xmin = std.math.min(a[0], b[0]) + origin_i[0];
    const xmax = std.math.max(a[0], b[0]) + origin_i[0];
    const ymin = std.math.min(a[1], b[1]) + origin_i[1];
    const ymax = std.math.max(a[1], b[1]) + origin_i[1];
    ifaces.ISurface.drawOutlinedRect(xmin, ymin, xmax, ymax);
}

pub fn fillRect(a: std.meta.Vector(2, i32), b: std.meta.Vector(2, i32)) void {
    const xmin = std.math.min(a[0], b[0]) + origin_i[0];
    const xmax = std.math.max(a[0], b[0]) + origin_i[0];
    const ymin = std.math.min(a[1], b[1]) + origin_i[1];
    const ymax = std.math.max(a[1], b[1]) + origin_i[1];
    ifaces.ISurface.drawFilledRect(xmin, ymin, xmax, ymax);
}

pub fn getTextHeight() u32 {
    return @intCast(u32, ifaces.ISurface.getFontTall(12));
}

pub fn getTextLength(str: []const u8) u32 {
    var len: u32 = 0;

    for (str) |ch, i| {
        const prev: sdk.wchar = if (i == 0) 0 else str[i - 1];
        const next: sdk.wchar = if (i == str.len - 1) 0 else str[i + 1];
        var wide: f32 = undefined;
        var a: f32 = undefined;
        var c: f32 = undefined;
        ifaces.ISurface.getKernedCharWidth(12, ch, prev, next, &wide, &a, &c);
        len += @floatToInt(u32, wide + 0.6);
    }

    return len;
}

pub fn drawText(pos: std.meta.Vector(2, i32), str: []const u8) void {
    ifaces.ISurface.drawSetTextPos(@intCast(c_int, pos[0] + origin_i[0]), @intCast(c_int, pos[1] + origin_i[1]));
    ifaces.ISurface.drawSetTextFont(12);
    if (str.len < 64) {
        var buf: [64]sdk.wchar = undefined;
        for (str) |c, i| buf[i] = c;
        ifaces.ISurface.drawPrintText(&buf, @intCast(c_int, str.len), .default);
    } else {
        var buf = allocator.alloc(sdk.wchar, str.len) catch return; // TODO: handle some other way?
        defer allocator.free(buf);
        for (str) |c, i| buf[i] = c;
        ifaces.ISurface.drawPrintText(buf.ptr, @intCast(c_int, str.len), .default);
    }
}
