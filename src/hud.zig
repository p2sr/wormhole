const std = @import("std");
const surface = @import("surface.zig");
const ifaces = @import("interface.zig").ifaces;

pub fn Hud(comptime Context: type) type {
    return struct {
        ctx: Context,
        screen_anchor: std.meta.Vector(2, f32),
        hud_anchor: std.meta.Vector(2, f32),
        pix_off: std.meta.Vector(2, i32),
        scale: f32,

        const Self = @This();

        pub fn position(self: *Self, slot: u8, screen_size: std.meta.Vector(2, i32)) std.meta.Vector(2, i32) {
            const hud_size = self.ctx.calcSize(slot);

            const screen_size_f = std.meta.Vector(2, f32){
                @intToFloat(f32, screen_size[0]),
                @intToFloat(f32, screen_size[1]),
            };

            const screen_anchor = self.screen_anchor * screen_size_f;
            const hud_anchor = self.hud_anchor * hud_size;

            const diff = std.meta.Vector(2, i32){
                @floatToInt(i32, screen_anchor[0] - hud_anchor[0]),
                @floatToInt(i32, screen_anchor[1] - hud_anchor[1]),
            };

            return diff + self.pix_off;
        }

        pub fn draw(self: *Self, slot: u8) void {
            // TODO: get the size for this slot's "sub-screen" if we're
            // in splitscreen
            const screen_size = blk: {
                var x: c_int = undefined;
                var y: c_int = undefined;
                ifaces.IVEngineClient.getScreenSize(&x, &y);
                break :blk std.meta.Vector(2, i32){ x, y };
            };

            surface.units_per_pixel.* = 1000.0 / @intToFloat(f32, screen_size[1]);

            const pos = self.position(slot, screen_size);
            surface.origin.* = pos;
            surface.scale.* = self.scale;

            self.ctx.draw(slot);
        }
    };
}
