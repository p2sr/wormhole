const std = @import("std");
const sdk = @import("sdk");
const Surface = @import("Surface.zig");
const hud = @import("hud.zig");
const Wormhole = @import("Wormhole.zig");
const ThudManager = @This();

wh: *Wormhole,
thuds: []hud.Hud(Thud),

const Thud = struct {
    pub const Part = union(enum) {
        text: []u8,
        component: struct {
            mod: []u8,
            name: []u8,
            format: [:0]u8,
        },
        color: ?sdk.Color,
        align_: u32,
    };

    pub const Line = struct {
        color: sdk.Color,
        parts: []Part,
    };

    arena: std.heap.ArenaAllocator.State,
    font: Surface.Font,
    spacing: f32,
    padding: f32,
    lines: []Line,

    fn evalLine(self: *Thud, wh: *Wormhole, slot: u8, line: Line, draw_pos: ?@Vector(2, f32)) !f32 {
        var width: f32 = 0;
        var align_base: f32 = 0;

        if (draw_pos != null) wh.surface.color = line.color;
        for (line.parts) |p| switch (p) {
            .text => |str| {
                if (draw_pos) |pos| wh.surface.drawText(self.font, pos + @Vector(2, f32){ width, 0 }, str);
                width += wh.surface.getTextLength(self.font, str);
            },
            .component => |info| {
                if (wh.mod_manager.get(info.mod)) |mod| {
                    if (mod.thud_components.get(info.name)) |comp| {
                        var buf: [64]u8 = undefined;
                        const size = comp.call(info.mod, slot, info.format, &buf, buf.len);
                        var str: []u8 = undefined;
                        if (size <= 64) {
                            str = buf[0..size];
                        } else {
                            str = try wh.gpa.alloc(u8, size);
                            _ = comp.call(info.mod, slot, info.format, str.ptr, buf.len);
                        }

                        if (draw_pos) |pos| wh.surface.drawText(self.font, pos + @Vector(2, f32){ width, 0 }, str);
                        width += wh.surface.getTextLength(self.font, str);

                        if (size > 64) wh.gpa.free(str);
                    }
                }
            },
            .color => |c| if (draw_pos != null) {
                wh.surface.color = c orelse line.color;
            },
            .align_ => |x| {
                width = @max(width, @as(f32, @floatFromInt(x)) + align_base);
                align_base = width;
            },
        };

        return width;
    }

    pub fn calcSize(self: *Thud, wh: *Wormhole, slot: u8) @Vector(2, f32) {
        var width: f32 = 0;
        var height: f32 = 0;

        for (self.lines, 0..) |line, i| {
            if (i > 0) height += self.spacing;
            height += wh.surface.getFontHeight(self.font);

            const w = self.evalLine(wh, slot, line, null) catch 0; // TODO
            if (w > width) width = w;
        }

        return .{
            width + self.padding * 2,
            height + self.padding * 2,
        };
    }

    pub fn draw(self: *Thud, wh: *Wormhole, slot: u8) void {
        const size = self.calcSize(wh, slot);
        wh.surface.color = .{ .r = 0, .g = 0, .b = 0, .a = 192 };
        wh.surface.fillRect(.{ 0, 0 }, size);

        const x = self.padding;
        var y = self.padding;

        for (self.lines, 0..) |line, i| {
            _ = self.evalLine(wh, slot, line, @Vector(2, f32){ x, y }) catch {}; // TODO

            y += wh.surface.getFontHeight(self.font);
            if (i > 0) y += self.spacing;
        }
    }
};

fn Parser(comptime Reader: type) type {
    return struct {
        allocator: std.mem.Allocator,
        reader: Reader,
        peeked: ?u8 = null,

        const Self = @This();

        fn peek(self: *Self) !u8 {
            if (self.peeked == null) self.peeked = try self.reader.readByte();
            return self.peeked.?;
        }

        fn next(self: *Self) !u8 {
            const c = self.peek();
            self.peeked = null;
            return c;
        }

        pub fn parse(self: *Self) ![]Thud.Part {
            var parts = std.ArrayList(Thud.Part).init(self.allocator);
            var str = std.ArrayList(u8).init(self.allocator);

            while (true) {
                const c = self.next() catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                };

                if (c == '{') {
                    if ((try self.peek()) == '{') {
                        _ = self.next() catch unreachable;
                        try str.append('{');
                    } else {
                        if (str.items.len > 0) try parts.append(.{ .text = try str.toOwnedSlice() });
                        try parts.append(try self.parseExpansion());
                    }
                } else {
                    try str.append(c);
                }
            }

            if (str.items.len > 0) try parts.append(.{ .text = try str.toOwnedSlice() });

            return parts.toOwnedSlice();
        }

        fn parseExpansion(self: *Self) !Thud.Part {
            var mod = std.ArrayList(u8).init(self.allocator);
            defer mod.deinit();

            var c = try self.next();
            while (c != '.') {
                if (c < 'a' and c > 'z' and c != '-') return error.BadModName;
                try mod.append(c);
                c = try self.next();
            }

            var component = std.ArrayList(u8).init(self.allocator);
            defer component.deinit();

            c = try self.next();
            while (c != ':' and c != '}') {
                if (c < 'a' and c > 'z' and c != '-') return error.BadComponentName;
                try component.append(c);
                c = try self.next();
            }

            var format = std.ArrayList(u8).init(self.allocator);
            defer format.deinit();

            if (c == ':') {
                c = try self.next();
                while (c != '}') {
                    try format.append(c);
                    c = try self.next();
                }
            }

            if (mod.items.len > 0) {
                const format1 = try format.toOwnedSliceSentinel(0);
                return Thud.Part{ .component = .{
                    .mod = try mod.toOwnedSlice(),
                    .name = try component.toOwnedSlice(),
                    .format = format1,
                } };
            }

            // Built-in expansion

            if (std.mem.eql(u8, component.items, "color")) {
                if (std.mem.eql(u8, format.items, "reset")) {
                    return Thud.Part{ .color = null };
                }
                return Thud.Part{ .color = try parseColor(format.items) };
            }

            if (std.mem.eql(u8, component.items, "align")) {
                const x = parseUint(format.items) catch return error.BadAlign;
                return Thud.Part{ .align_ = x };
            }

            return error.UnknownExpansion;
        }

        fn parseColor(col: []const u8) !sdk.Color {
            if (col.len == 3) {
                const r = (try parseColorChar(col[0])) * 17;
                const g = (try parseColorChar(col[1])) * 17;
                const b = (try parseColorChar(col[2])) * 17;
                return sdk.Color{ .r = r, .g = g, .b = b };
            } else if (col.len == 6) {
                const r = (try parseColorChar(col[0])) * 16 + (try parseColorChar(col[1]));
                const g = (try parseColorChar(col[2])) * 16 + (try parseColorChar(col[3]));
                const b = (try parseColorChar(col[4])) * 16 + (try parseColorChar(col[5]));
                return sdk.Color{ .r = r, .g = g, .b = b };
            } else {
                return error.BadColor;
            }
        }

        fn parseColorChar(c: u8) !u8 {
            if (c >= '0' and c <= '9') return c - '0';
            if (c >= 'a' and c <= 'f') return 10 + c - 'a';
            if (c >= 'A' and c <= 'F') return 10 + c - 'A';
            return error.BadColor;
        }

        fn parseUint(str: []const u8) !u32 {
            var x: u32 = 0;
            for (str) |c| {
                if (c < '0' and c > '9') return error.BadInt;
                x *= 10;
                x += c - '0';
            }
            return x;
        }
    };
}

fn parser(allocator: std.mem.Allocator, r: anytype) Parser(@TypeOf(r)) {
    return .{ .allocator = allocator, .reader = r };
}

pub fn init(wh: *Wormhole) !ThudManager {
    @setEvalBranchQuota(10000);

    const RawInfo = struct {
        font_name: []u8,
        font_size: f32,
        color: [4]u8,
        spacing: f32,
        padding: f32,
        screen_anchor: [2]f32,
        hud_anchor: [2]f32,
        pix_off: [2]i32,
        scale: f32,
        lines: [][]u8,
    };

    var file_contents = try std.fs.cwd().readFileAlloc(wh.gpa, "thud.json", std.math.maxInt(usize));
    defer wh.gpa.free(file_contents);

    const cfg = try std.json.parseFromSlice([]RawInfo, wh.gpa, file_contents, .{});
    defer cfg.deinit();

    var huds = std.ArrayList(hud.Hud(Thud)).init(wh.gpa);
    defer {
        for (huds.items) |h| h.ctx.arena.promote(wh.gpa).deinit();
        huds.deinit();
    }

    for (cfg.value) |raw| {
        var arena = std.heap.ArenaAllocator.init(wh.gpa);
        errdefer arena.deinit();

        var lines = std.ArrayList(Thud.Line).init(arena.allocator());

        for (raw.lines) |line| {
            var s = std.io.fixedBufferStream(line);
            var p = parser(arena.allocator(), s.reader());
            const parts = try p.parse();

            try lines.append(.{
                .color = .{
                    .r = raw.color[0],
                    .g = raw.color[1],
                    .b = raw.color[2],
                    .a = raw.color[3],
                },
                .parts = parts,
            });
        }

        const name = try arena.allocator().dupeZ(u8, raw.font_name);

        try huds.append(.{
            .ctx = .{
                .arena = arena.state,
                .font = .{
                    .name = name,
                    .size = raw.font_size,
                },
                .spacing = raw.spacing,
                .padding = raw.padding,
                .lines = try lines.toOwnedSlice(),
            },
            .screen_anchor = .{ raw.screen_anchor[0], raw.screen_anchor[1] },
            .hud_anchor = .{ raw.hud_anchor[0], raw.hud_anchor[1] },
            .pix_off = .{ raw.pix_off[0], raw.pix_off[1] },
            .scale = raw.scale,
        });
    }

    return .{
        .wh = wh,
        .thuds = try huds.toOwnedSlice(),
    };
}

pub fn deinit(tm: *ThudManager) void {
    for (tm.thuds) |*h| h.ctx.arena.promote(tm.wh.gpa).deinit();
    tm.wh.gpa.free(tm.thuds);
}

pub fn drawAll(tm: *ThudManager, slot: u8) void {
    for (tm.thuds) |*h| h.draw(tm.wh, slot);
}
