const std = @import("std");
const Wormhole = @import("Wormhole.zig");
const surface = @import("surface.zig");

pub fn Hud(comptime Context: type) type {
    return struct {
        ctx: Context,
        screen_anchor: @Vector(2, f32),
        hud_anchor: @Vector(2, f32),
        pix_off: @Vector(2, i32),
        scale: f32,

        const Self = @This();

        pub fn position(self: *Self, slot: u8, screen_size: @Vector(2, i32), units_per_pixel: f32) @Vector(2, i32) {
            const hud_size = self.ctx.calcSize(slot) * @splat(2, self.scale / units_per_pixel);

            const screen_size_f: @Vector(2, f32) = .{
                @floatFromInt(screen_size[0]),
                @floatFromInt(screen_size[1]),
            };

            const screen_anchor = self.screen_anchor * screen_size_f;
            const hud_anchor = self.hud_anchor * hud_size;

            const diff: @Vector(2, i32) = .{
                @intFromFloat(screen_anchor[0] - hud_anchor[0]),
                @intFromFloat(screen_anchor[1] - hud_anchor[1]),
            };

            return diff + self.pix_off;
        }

        pub fn draw(self: *Self, slot: u8) void {
            // TODO: get the size for this slot's "sub-screen" if we're
            // in splitscreen
            const IVEngineClient = Wormhole.getInst().interface_manager.ifaces.IVEngineClient;
            const screen_size: @Vector(2, i32) = blk: {
                var x: c_int = undefined;
                var y: c_int = undefined;
                IVEngineClient.getScreenSize(&x, &y);
                break :blk .{ x, y };
            };

            surface.units_per_pixel.* = 1000.0 / @as(f32, @floatFromInt(screen_size[1]));

            const pos = self.position(slot, screen_size, surface.units_per_pixel.*);
            surface.origin.* = pos;
            surface.scale.* = self.scale;

            self.ctx.draw(slot);
        }
    };
}
