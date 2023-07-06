const std = @import("std");
const sdk = @import("sdk");
const render_manager = @import("render_manager.zig");
const Surface = @This();
const Wormhole = @import("Wormhole.zig");

wh: *Wormhole,
scale: f32 = 1.0, // TODO: this should affect text, but what else?
origin: [2]i32 = .{ 0, 0 },
units_per_pixel: f32 = 1.0,
color: sdk.Color = .{ .r = 255, .g = 255, .b = 255 },

pub const Font = struct {
    name: []const u8,
    size: f32,
};

fn translate(surf: Surface, coords: @Vector(2, f32)) @Vector(2, f32) {
    const scaled = coords * @splat(2, surf.scale / surf.units_per_pixel);
    return .{
        @as(f32, @floatFromInt(surf.origin[0])) + scaled[0],
        @as(f32, @floatFromInt(surf.origin[1])) + scaled[1],
    };
}

pub fn init(wh: *Wormhole) Surface {
    return .{ .wh = wh };
}

pub fn drawRect(surf: Surface, a: @Vector(2, f32), b: @Vector(2, f32)) void {
    const a1 = surf.translate(a);
    const b1 = surf.translate(b);
    render_manager.drawRect(@min(a1, b1), @max(a1, b1), surf.color);
}

pub fn fillRect(surf: Surface, a: @Vector(2, f32), b: @Vector(2, f32)) void {
    const a1 = surf.translate(a);
    const b1 = surf.translate(b);
    render_manager.fillRect(@min(a1, b1), @max(a1, b1), surf.color);
}

pub fn getFontHeight(surf: Surface, f: Font) f32 {
    const size: u32 = @intFromFloat(f.size * surf.scale / surf.units_per_pixel * 64.0);
    const info = render_manager.sizeInfo(f.name, size) catch unreachable;
    return @as(f32, @floatFromInt(info.line_height)) / surf.scale * surf.units_per_pixel / 64.0;
}

pub fn getTextLength(surf: Surface, f: Font, str: []const u8) f32 {
    const size: u32 = @intFromFloat(f.size * surf.scale / surf.units_per_pixel * 64.0);
    const len = render_manager.textLength(f.name, size, str) catch unreachable;
    return @as(f32, @floatFromInt(len)) / surf.scale * surf.units_per_pixel / 64.0;
}

pub fn drawText(surf: Surface, f: Font, pos: @Vector(2, f32), str: []const u8) void {
    const size: u32 = @intFromFloat(f.size * surf.scale / surf.units_per_pixel * 64.0);
    render_manager.drawText(surf.translate(pos), f.name, size, surf.color, str) catch unreachable;
}
