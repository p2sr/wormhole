const std = @import("std");
const sdk = @import("sdk");
const render_manager = @import("render_manager.zig");

var scale_i: f32 = 1;
var origin_i = @Vector(2, i32){ 0, 0 };
var units_per_pixel_i: f32 = 1;

pub const scale = &scale_i; // TODO: this should affect text, but what else?
pub const origin = &origin_i;
pub const units_per_pixel = &units_per_pixel_i;

var allocator: std.mem.Allocator = undefined;

var color: sdk.Color = .{ .r = 255, .g = 255, .b = 255 };

pub const Font = struct {
    name: []const u8,
    size: f32,
};

fn translate(coords: @Vector(2, f32)) @Vector(2, f32) {
    const scaled = coords * @splat(2, scale_i / units_per_pixel_i);
    return .{
        @as(f32, @floatFromInt(origin_i[0])) + scaled[0],
        @as(f32, @floatFromInt(origin_i[1])) + scaled[1],
    };
}

pub fn init(allocator1: std.mem.Allocator) void {
    allocator = allocator1;
}

pub fn setColor(col: sdk.Color) void {
    color = col;
}

pub fn drawRect(a: @Vector(2, f32), b: @Vector(2, f32)) void {
    const a1 = translate(a);
    const b1 = translate(b);
    const xmin = @min(a1[0], b1[0]);
    const xmax = @max(a1[0], b1[0]);
    const ymin = @min(a1[1], b1[1]);
    const ymax = @max(a1[1], b1[1]);
    render_manager.drawRect(.{ xmin, ymin }, .{ xmax, ymax }, color);
}

pub fn fillRect(a: @Vector(2, f32), b: @Vector(2, f32)) void {
    const a1 = translate(a);
    const b1 = translate(b);
    const xmin = @min(a1[0], b1[0]);
    const xmax = @max(a1[0], b1[0]);
    const ymin = @min(a1[1], b1[1]);
    const ymax = @max(a1[1], b1[1]);
    render_manager.fillRect(.{ xmin, ymin }, .{ xmax, ymax }, color);
}

pub fn getFontHeight(f: Font) f32 {
    const size: u32 = @intFromFloat(f.size * scale_i / units_per_pixel_i * 64.0);
    const info = render_manager.sizeInfo(f.name, size) catch unreachable;
    return @as(f32, @floatFromInt(info.line_height)) / scale_i * units_per_pixel_i / 64.0;
}

pub fn getTextLength(f: Font, str: []const u8) f32 {
    const size: u32 = @intFromFloat(f.size * scale_i / units_per_pixel_i * 64.0);
    const len = render_manager.textLength(f.name, size, str) catch unreachable;
    return @as(f32, @floatFromInt(len)) / scale_i * units_per_pixel_i / 64.0;
}

pub fn drawText(f: Font, pos: @Vector(2, f32), str: []const u8) void {
    const size: u32 = @intFromFloat(f.size * scale_i / units_per_pixel_i * 64.0);
    render_manager.drawText(translate(pos), f.name, size, color, str) catch unreachable;
}
