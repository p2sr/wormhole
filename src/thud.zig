const std = @import("std");
const sdk = @import("sdk");
const surface = @import("surface.zig");
const mods = @import("mods.zig");

pub const THud = struct {
    pub const Part = union(enum) {
        text: []u8,
        component: struct {
            mod: []u8,
            name: []u8,
            format: [:0]u8,
        },
        color: ?sdk.Color,
        align_: ?u32,
    };

    pub const Line = struct {
        color: sdk.Color,
        parts: []Part,
    };

    arena: std.heap.ArenaAllocator,
    font: void, // TODO
    spacing: u32,
    padding: u32,
    lines: []Line,

    fn evalLine(self: *THud, slot: u8, line: Line, draw_pos: ?std.meta.Vector(2, i32)) !u32 {
        _ = self;

        var width: u32 = 0;
        var align_base: u32 = 0;

        if (draw_pos != null) surface.setColor(line.color);
        for (line.parts) |p| switch (p) {
            .text => |str| {
                if (draw_pos) |pos| surface.drawText(pos + std.meta.Vector(2, i32){ @intCast(i32, width), 0 }, str);
                width += surface.getTextLength(str);
            },
            .component => |info| {
                if (mods.getMod(info.mod)) |mod| {
                    if (mod.thud_components.get(info.name)) |comp| {
                        var buf: [64]u8 = undefined;
                        const size = comp.cbk(slot, info.format, &buf, buf.len);
                        var str: []u8 = undefined;
                        if (size <= 64) {
                            str = buf[0..size];
                        } else {
                            str = try self.arena.allocator.alloc(u8, size);
                            _ = comp.cbk(slot, info.format, str.ptr, buf.len);
                        }

                        if (draw_pos) |pos| surface.drawText(pos + std.meta.Vector(2, i32){ @intCast(i32, width), 0 }, str);
                        width += surface.getTextLength(str);

                        if (size > 64) self.arena.allocator.free(str);
                    }
                }
            },
            .color => |c| if (draw_pos != null) surface.setColor(c orelse line.color),
            .align_ => |x_opt| {
                if (x_opt) |x| {
                    width = std.math.max(width, x + align_base);
                } else {
                    align_base = width;
                }
            },
        };

        return width;
    }

    pub fn calcSize(self: *THud, slot: u8) std.meta.Vector(2, u32) {
        var width: u32 = 0;
        var height: u32 = 0;

        for (self.lines) |line, i| {
            if (i > 0) height += self.spacing;
            height += surface.getTextHeight();

            const w = self.evalLine(slot, line, null) catch 0; // TODO
            if (w > width) width = w;
        }

        return std.meta.Vector(2, u32){
            width + self.padding * 2,
            height + self.padding * 2,
        };
    }

    pub fn draw(self: *THud, slot: u8) void {
        const size = self.calcSize(slot);
        surface.setColor(.{ .r = 0, .g = 0, .b = 0, .a = 192 });
        surface.fillRect(std.meta.Vector(2, i32){ 0, 0 }, std.meta.Vector(2, i32){ @intCast(i32, size[0]), @intCast(i32, size[1]) });

        const x = self.padding;
        var y = self.padding;

        for (self.lines) |line, i| {
            _ = self.evalLine(slot, line, std.meta.Vector(2, i32){ @intCast(i32, x), @intCast(i32, y) }) catch {}; // TODO

            y += surface.getTextHeight();
            if (i > 0) y += self.spacing;
        }
    }
};

fn Parser(comptime Reader: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
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

        pub fn parse(self: *Self) ![]THud.Part {
            var parts = std.ArrayList(THud.Part).init(&self.arena.allocator);
            var str = std.ArrayList(u8).init(&self.arena.allocator);

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
                        if (str.items.len > 0) try parts.append(.{ .text = str.toOwnedSlice() });
                        try parts.append(try self.parseExpansion());
                    }
                } else {
                    try str.append(c);
                }
            }

            if (str.items.len > 0) try parts.append(.{ .text = str.toOwnedSlice() });

            return parts.toOwnedSlice();
        }

        fn parseExpansion(self: *Self) !THud.Part {
            var mod = std.ArrayList(u8).init(&self.arena.allocator);
            defer mod.deinit();

            var c = try self.next();
            while (c != '.') {
                if (c < 'a' and c > 'z' and c != '-') return error.BadModName;
                try mod.append(c);
                c = try self.next();
            }

            var component = std.ArrayList(u8).init(&self.arena.allocator);
            defer component.deinit();

            c = try self.next();
            while (c != ':' and c != '}') {
                if (c < 'a' and c > 'z' and c != '-') return error.BadComponentName;
                try component.append(c);
                c = try self.next();
            }

            var format = std.ArrayList(u8).init(&self.arena.allocator);
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
                return THud.Part{ .component = .{
                    .mod = mod.toOwnedSlice(),
                    .name = component.toOwnedSlice(),
                    .format = format1,
                } };
            }

            // Built-in expansion

            if (std.mem.eql(u8, component.items, "color")) {
                if (std.mem.eql(u8, format.items, "reset")) {
                    return THud.Part{ .color = null };
                }
                return THud.Part{ .color = try parseColor(format.items) };
            }

            if (std.mem.eql(u8, component.items, "align")) {
                if (std.mem.eql(u8, format.items, "base")) {
                    return THud.Part{ .align_ = null };
                }
                const x = parseUint(format.items) catch return error.BadAlign;
                return THud.Part{ .align_ = x };
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

pub fn parser(arena: std.heap.ArenaAllocator, r: anytype) Parser(@TypeOf(r)) {
    return .{ .arena = arena, .reader = r };
}
