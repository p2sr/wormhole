const std = @import("std");
const sdk = @import("sdk");
const ifaces = @import("interface.zig").ifaces;
const font_manager = @import("font_manager.zig");

var scale_i: f32 = 1;
var origin_i = std.meta.Vector(2, i32){ 0, 0 };
var units_per_pixel_i: f32 = 1;

pub const scale = &scale_i; // TODO: this should affect text, but what else?
pub const origin = &origin_i;
pub const units_per_pixel = &units_per_pixel_i;

var allocator: std.mem.Allocator = undefined;

pub const Font = struct {
    name: [:0]const u8,
    tall: f32,
};

fn translate(coords: std.meta.Vector(2, f32)) std.meta.Vector(2, i32) {
    const scaled = coords * @splat(2, scale_i / units_per_pixel_i);
    return std.meta.Vector(2, i32){
        origin_i[0] + @floatToInt(i32, scaled[0]),
        origin_i[1] + @floatToInt(i32, scaled[1]),
    };
}

pub fn init(allocator1: std.mem.Allocator) void {
    allocator = allocator1;
}

pub fn setColor(col: sdk.Color) void {
    ifaces.ISurface.drawSetColor(col);
    ifaces.ISurface.drawSetTextColor(col);
}

pub fn drawRect(a: std.meta.Vector(2, f32), b: std.meta.Vector(2, f32)) void {
    const a1 = translate(a);
    const b1 = translate(b);
    const xmin = std.math.min(a1[0], b1[0]);
    const xmax = std.math.max(a1[0], b1[0]);
    const ymin = std.math.min(a1[1], b1[1]);
    const ymax = std.math.max(a1[1], b1[1]);
    ifaces.ISurface.drawOutlinedRect(xmin, ymin, xmax, ymax);
}

pub fn fillRect(a: std.meta.Vector(2, f32), b: std.meta.Vector(2, f32)) void {
    const a1 = translate(a);
    const b1 = translate(b);
    const xmin = std.math.min(a1[0], b1[0]);
    const xmax = std.math.max(a1[0], b1[0]);
    const ymin = std.math.min(a1[1], b1[1]);
    const ymax = std.math.max(a1[1], b1[1]);
    ifaces.ISurface.drawFilledRect(xmin, ymin, xmax, ymax);
}

pub fn getFontHeight(f: Font) f32 {
    const font_id = font_manager.findRawFont(f.name, @floatToInt(u32, f.tall / units_per_pixel_i)) orelse 12; // TODO: default
    const tall = ifaces.ISurface.getFontTall(font_id);
    return @intToFloat(f32, tall) * units_per_pixel_i;
}

pub fn getTextLength(f: Font, str: []const u8) f32 {
    var len: u32 = 0;

    const font_id = font_manager.findRawFont(f.name, @floatToInt(u32, f.tall / units_per_pixel_i)) orelse 12; // TODO: default

    for (str) |ch, i| {
        const prev: sdk.wchar = if (i == 0) 0 else str[i - 1];
        const next: sdk.wchar = if (i == str.len - 1) 0 else str[i + 1];
        var wide: f32 = undefined;
        var a: f32 = undefined;
        var c: f32 = undefined;
        ifaces.ISurface.getKernedCharWidth(font_id, ch, prev, next, &wide, &a, &c);
        len += @floatToInt(u32, wide + 0.6);
    }

    return @intToFloat(f32, len) * units_per_pixel_i;
}

pub fn drawText(f: Font, pos: std.meta.Vector(2, f32), str: []const u8) void {
    const font_id = font_manager.findRawFont(f.name, @floatToInt(u32, f.tall * scale_i / units_per_pixel_i)) orelse 12; // TODO: default

    const pos1 = translate(pos);
    ifaces.ISurface.drawSetTextPos(@intCast(c_int, pos1[0]), @intCast(c_int, pos1[1]));
    ifaces.ISurface.drawSetTextFont(font_id);

    if (str.len <= 64) {
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
