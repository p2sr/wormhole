const std = @import("std");
const sdk = @import("sdk");
const fc = @import("fontconfig");
const FontManager = @import("fontmanager").FontManager(FontTextureContext);
const MeshBuilder = @import("MeshBuilder.zig");
const Wormhole = @import("Wormhole.zig");
const RenderManager = @This();

wh: *Wormhole,
texture_manager: TextureManager,
font_manager: FontManager,
available_fonts: std.StringHashMapUnmanaged(FontState),
default_font_name: []const u8,

mat_solid_depth: *sdk.IMaterial,
mat_solid_no_depth: *sdk.IMaterial,

const FontState = struct {
    file: [:0]const u8,
    id: ?FontManager.FontId,
};

const xpix = 1.0 / 2560.0;
const ypix = 1.0 / 1080.0;

const FontTextureContext = struct {
    wh: *Wormhole,

    pub const RenderTexture = *const TextureManager.Texture;
    pub fn getRenderTexture(ctx: FontTextureContext, idx: u32) RenderTexture {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ ctx.wh.resource_prefix, idx }) catch unreachable;

        for (ctx.wh.render_manager.texture_manager.textures.items) |*tex| {
            if (std.mem.eql(u8, tex.name, name)) {
                return tex;
            }
        }

        unreachable; // font texture not found
    }
    pub fn createTexture(ctx: FontTextureContext, idx: u32, w: u32, h: u32, data: []const u8) !void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ ctx.wh.resource_prefix, idx }) catch unreachable;
        try ctx.wh.render_manager.texture_manager.createTexture(name, w, h, data, false);
    }
    pub fn destroyTexture(ctx: FontTextureContext, idx: u32) void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ ctx.wh.resource_prefix, idx }) catch unreachable;
        ctx.wh.render_manager.texture_manager.destroyTexture(name);
    }
    pub fn updateTexture(ctx: FontTextureContext, idx: u32, x: u32, y: u32, w: u32, h: u32, data: []const u8) !void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ ctx.wh.resource_prefix, idx }) catch unreachable;
        try ctx.wh.render_manager.texture_manager.updateTexture(name, x, y, w, h, null);
        _ = data; // We know it's the same buffer - TODO should this arg even really exist?
    }
};

const TextureManager = struct {
    wh: *Wormhole,
    textures: std.ArrayList(Texture),
    regenerator: Regenerator,

    const Texture = struct {
        name: [:0]u8,
        width: u32,
        height: u32,
        buf: union(enum) {
            owned: []u8,
            external: []const u8,
        },
        matsys_tex: *sdk.ITexture,
        mat_depth: *sdk.IMaterial,
        mat_no_depth: *sdk.IMaterial,

        fn deinit(tex: Texture, gpa: std.mem.Allocator) void {
            switch (tex.buf) {
                .owned => |buf| gpa.free(buf),
                .external => {},
            }
            gpa.free(tex.name);
            // FIXME: the material sometimes has an extra reference, I suspect
            // because it's bound. TODO: unbind the material!!
            tex.mat_depth.decrementReferenceCount();
            tex.mat_no_depth.decrementReferenceCount();
            tex.matsys_tex.decrementReferenceCount();
        }
    };

    const Regenerator = extern struct {
        const Method = switch (@import("builtin").os.tag) {
            .windows => std.builtin.CallingConvention.Thiscall,
            else => std.builtin.CallingConvention.C,
        };

        vtable: *const extern struct {
            regenerateTextureBits: *const fn (*Regenerator, *sdk.ITexture, *sdk.IVtfTexture, *sdk.Rect) callconv(Method) void = &Regenerator.regenerateTextureBits,
            release: *const fn (*Regenerator) callconv(Method) void = &Regenerator.release,
            hasPreallocatedScratchTexture: *const fn (*const Regenerator) callconv(Method) bool = &Regenerator.hasPreallocatedScratchTexture,
            getPreallocatedScratchTexture: *const fn (*const Regenerator) callconv(Method) ?*sdk.IVtfTexture = &Regenerator.getPreallocatedScratchTexture,
        } = &.{},

        wh: *Wormhole,

        fn regenerateTextureBits(ctx: *Regenerator, matsys_tex: *sdk.ITexture, vtf_tex: *sdk.IVtfTexture, _: *sdk.Rect) callconv(Method) void {
            const tex = for (ctx.wh.render_manager.texture_manager.textures.items) |*tex| {
                if (tex.matsys_tex == matsys_tex) {
                    break tex;
                }
            } else return;

            std.debug.assert(vtf_tex.format() == .bgra8888);

            const src: []const u8 = switch (tex.buf) {
                .owned => |buf| buf,
                .external => |buf| buf,
            };
            std.mem.copy(u8, vtf_tex.imageData()[0..src.len], src);
        }

        fn release(_: *Regenerator) callconv(Method) void {
            return;
        }

        fn hasPreallocatedScratchTexture(_: *const Regenerator) callconv(Method) bool {
            return false;
        }

        fn getPreallocatedScratchTexture(_: *const Regenerator) callconv(Method) ?*sdk.IVtfTexture {
            return null;
        }
    };

    fn init(wh: *Wormhole) TextureManager {
        return .{
            .wh = wh,
            .textures = std.ArrayList(Texture).init(wh.gpa),
            .regenerator = .{ .wh = wh },
        };
    }

    fn deinit(self: TextureManager) void {
        for (self.textures.items) |tex| {
            tex.deinit(self.wh.gpa);
        }
        self.textures.deinit();
    }

    pub fn createTexture(self: *TextureManager, name: []const u8, w: u32, h: u32, init_data: []const u8, replicate_data: bool) !void {
        const name_owned = try self.wh.gpa.dupeZ(u8, name);
        errdefer self.wh.gpa.free(name_owned);

        const IMaterialSystem = self.wh.interface_manager.ifaces.IMaterialSystem;
        const matsys_tex = IMaterialSystem.createProceduralTexture(name_owned.ptr, "Wormhole textures", @intCast(w), @intCast(h), .bgra8888, .{
            .clamp_s = true,
            .clamp_t = true,
            .no_mip = true,
            .no_lod = true,
            .single_copy = true,
        }) orelse return error.TextureInitError;
        errdefer matsys_tex.decrementReferenceCount();

        matsys_tex.setTextureRegenerator(@ptrCast(&self.regenerator), true);

        const mat_depth = try self.createTexMaterial(name, false);
        errdefer mat_depth.decrementReferenceCount();

        const mat_no_depth = try self.createTexMaterial(name, true);
        errdefer mat_no_depth.decrementReferenceCount();

        if (replicate_data) {
            const data = try self.wh.gpa.dupe(u8, init_data);
            errdefer self.wh.gpa.free(data);

            try self.textures.append(.{
                .name = name_owned,
                .width = w,
                .height = h,
                .buf = .{ .owned = data },
                .matsys_tex = matsys_tex,
                .mat_depth = mat_depth,
                .mat_no_depth = mat_no_depth,
            });
        } else {
            try self.textures.append(.{
                .name = name_owned,
                .width = w,
                .height = h,
                .buf = .{ .external = init_data },
                .matsys_tex = matsys_tex,
                .mat_depth = mat_depth,
                .mat_no_depth = mat_no_depth,
            });
        }

        matsys_tex.download(null, 0);
    }

    pub fn destroyTexture(self: *TextureManager, name: []const u8) void {
        for (self.textures.items, 0..) |tex, i| {
            if (std.mem.eql(u8, tex.name, name)) {
                tex.deinit(self.wh.gpa);
                _ = self.textures.swapRemove(i);
                return;
            }
        }
    }

    pub fn updateTexture(self: TextureManager, name: []const u8, x: u32, y: u32, w: u32, h: u32, data: ?[]const u8) !void {
        const tex = for (self.textures.items) |*tex| {
            if (std.mem.eql(u8, tex.name, name)) {
                break tex;
            }
        } else {
            return error.NoSuchTexture;
        };

        if (data) |d| {
            std.debug.assert(tex.buf == .owned);
            var dy: u32 = 0;
            while (dy < h) : (dy += 1) {
                const cur_y = y + dy;
                var dx: u32 = 0;
                while (dx < w) : (dx += 1) {
                    const cur_x = x + dx;
                    const i = cur_y * tex.width + cur_x;
                    tex.buf.owned[i * 4 + 0] = d[i * 4 + 0];
                    tex.buf.owned[i * 4 + 1] = d[i * 4 + 1];
                    tex.buf.owned[i * 4 + 2] = d[i * 4 + 2];
                    tex.buf.owned[i * 4 + 3] = d[i * 4 + 3];
                }
            }
        } else {
            std.debug.assert(tex.buf == .external);
        }

        // explicit arg type to allow known result type
        tex.matsys_tex.download(&sdk.Rect{
            .x = @intCast(x),
            .y = @intCast(y),
            .w = @intCast(w),
            .h = @intCast(h),
        }, 0);
    }

    fn createTexMaterial(tm: TextureManager, tex_name: []const u8, no_depth: bool) !*sdk.IMaterial {
        const mat_name = try std.fmt.allocPrintZ(tm.wh.gpa, "{s}_mat_{s}", .{ tex_name, if (no_depth) "no_depth" else "depth" });
        defer tm.wh.gpa.free(mat_name);

        return createMaterial(tm.wh, mat_name, tex_name, no_depth);
    }
};

fn createMaterial(wh: *Wormhole, mat_name: [:0]const u8, tex_name: ?[]const u8, no_depth: bool) !*sdk.IMaterial {
    const kv = try sdk.KeyValues.init("UnlitGeneric");
    errdefer kv.deinit();
    try kv.setInt("$vertexcolor", 1);
    try kv.setInt("$vertexalpha", 1);
    try kv.setInt("$translucent", 1);
    if (no_depth) try kv.setInt("$ignorez", 1);
    if (tex_name) |tex| try kv.setString("$basetexture", tex);

    const IMaterialSystem = wh.interface_manager.ifaces.IMaterialSystem;
    return IMaterialSystem.createMaterial(mat_name.ptr, kv) orelse error.MaterialInitError;
}

pub fn init(wh: *Wormhole) !RenderManager {
    var tm = TextureManager.init(wh);
    errdefer tm.deinit();

    const kv = try sdk.KeyValues.init("UnlitGeneric");
    errdefer kv.deinit();
    try kv.setInt("$vertexcolor", 1);
    try kv.setInt("$vertexalpha", 1);
    try kv.setInt("$translucent", 1);
    try kv.setInt("$ignorez", 1);
    const mat_solid_depth = try createMaterial(wh, "_wh_solid_depth", null, false);
    const mat_solid_no_depth = try createMaterial(wh, "_wh_solid_no_depth", null, true);

    var font_manager = try FontManager.init(wh.gpa, .{ .wh = wh }, .{});
    errdefer font_manager.deinit();

    var fonts: std.StringHashMapUnmanaged(FontState) = .{};
    errdefer fonts.deinit(wh.gpa);

    const conf = try fc.FontConfig.init();

    const pat = try fc.Pattern.init();
    defer pat.deinit();

    const obj_set = try fc.ObjectSet.build(&.{ .family, .file });
    defer obj_set.deinit();

    const font_set = try conf.fontList(pat, obj_set);
    defer font_set.deinit();

    var default_font_name: ?[]const u8 = null;
    for (font_set.fonts()) |font| {
        const family = font.getProperty(.family, 0) catch continue;
        const file = font.getProperty(.file, 0) catch continue;

        if (fonts.contains(family)) continue;

        const family_owned = try wh.gpa.dupe(u8, family);
        const file_owned = try wh.gpa.dupeZ(u8, file);
        try fonts.put(wh.gpa, family_owned, .{
            .file = file_owned,
            .id = null,
        });

        if (default_font_name == null) {
            for ([_][]const u8{
                "DejaVu Sans",
                "Segoe UI",
                "Roboto",
                "Ubuntu",
                "Helvetica Neue",
            }) |name| {
                if (std.mem.eql(u8, family, name)) {
                    default_font_name = name;
                }
            }
        }
    }

    const default = default_font_name orelse return error.NoDefaultFont;

    std.log.debug("Initialized render manager", .{});
    std.log.debug("Using default font {s}", .{default});

    return .{
        .wh = wh,
        .texture_manager = tm,
        .font_manager = font_manager,
        .available_fonts = fonts,
        .default_font_name = default,
        .mat_solid_depth = mat_solid_depth,
        .mat_solid_no_depth = mat_solid_no_depth,
    };
}

pub fn deinit(rm: *RenderManager) void {
    rm.font_manager.deinit();

    {
        var it = rm.available_fonts.iterator();
        while (it.next()) |kv| {
            rm.wh.gpa.free(kv.key_ptr.*);
            rm.wh.gpa.free(kv.value_ptr.file);
        }
        rm.available_fonts.deinit(rm.wh.gpa);
    }

    rm.mat_solid_depth.decrementReferenceCount();
    rm.mat_solid_depth.deleteIfUnreferenced();
    rm.mat_solid_no_depth.decrementReferenceCount();
    rm.mat_solid_no_depth.deleteIfUnreferenced();

    rm.texture_manager.deinit();

    rm.* = undefined;
}

fn getFont(rm: *RenderManager, name: []const u8) !FontManager.FontId {
    const ptr = rm.available_fonts.getPtr(name) orelse rm.available_fonts.getPtr(rm.default_font_name).?;
    if (ptr.id) |id| return id;
    ptr.id = try rm.font_manager.registerFont(ptr.file, 0);
    return ptr.id.?;
}

pub fn drawText(rm: *RenderManager, pos: [2]f32, font: []const u8, size: u32, col: sdk.Color, str: []const u8) !void {
    const font_id = try rm.getFont(font);

    var x: f32 = pos[0] * xpix;
    var y: f32 = pos[1] * ypix;

    const size_info = try rm.font_manager.sizeInfo(font_id, size, null);
    y += @as(f32, @floatFromInt(size_info.ascender)) * ypix / 64.0;

    var it = try rm.font_manager.glyphIterator(font_id, size, null, str);
    defer it.deinit();

    var cur_mat: ?*sdk.IMaterial = null;
    var mb: MeshBuilder = undefined;
    defer if (cur_mat != null and mb.num_indices > 0) mb.finish();

    while (try it.next()) |glyph| {
        const mat = glyph.render.texture.mat_no_depth;
        if (cur_mat != mat) {
            // Flush existing mesh and move onto next
            if (cur_mat != null) mb.finish();
            mb = MeshBuilder.init(mat, false, it.numGlyphs() * 4, it.numGlyphs() * 6);
            cur_mat = mat;
        }

        const w = @as(f32, @floatFromInt(glyph.layout.width)) * xpix / 64.0;
        const h = @as(f32, @floatFromInt(glyph.layout.height)) * ypix / 64.0;
        const first_vert: u16 = @intCast(mb.num_verts);

        const gx = x + @as(f32, @floatFromInt(glyph.layout.x_offset)) * xpix / 64.0;
        const gy = y - @as(f32, @floatFromInt(glyph.layout.y_offset)) * ypix / 64.0;

        mb.position(.{ .x = gx, .y = gy, .z = 0 });
        mb.color(col);
        mb.texCoord(0, glyph.render.left, glyph.render.top);
        mb.advanceVertex();

        mb.position(.{ .x = gx + w, .y = gy, .z = 0 });
        mb.color(col);
        mb.texCoord(0, glyph.render.right, glyph.render.top);
        mb.advanceVertex();

        mb.position(.{ .x = gx + w, .y = gy + h, .z = 0 });
        mb.color(col);
        mb.texCoord(0, glyph.render.right, glyph.render.bottom);
        mb.advanceVertex();

        mb.position(.{ .x = gx, .y = gy + h, .z = 0 });
        mb.color(col);
        mb.texCoord(0, glyph.render.left, glyph.render.bottom);
        mb.advanceVertex();

        mb.index(first_vert + 0);
        mb.index(first_vert + 1);
        mb.index(first_vert + 3);

        mb.index(first_vert + 1);
        mb.index(first_vert + 2);
        mb.index(first_vert + 3);

        x += @as(f32, @floatFromInt(glyph.layout.advance)) * xpix / 64.0;
    }
}

pub fn textLength(rm: *RenderManager, font: []const u8, size: u32, str: []const u8) !u32 {
    const font_id = try rm.getFont(font);

    var it = try rm.font_manager.glyphIterator(font_id, size, null, str);
    defer it.deinit();

    var cur: i32 = 0;
    var min: i32 = 0;
    var max: i32 = 0;
    while (try it.next()) |glyph| {
        cur += glyph.layout.advance;
        if (cur > max) max = cur;
        if (cur < min) min = cur;
    }

    return @intCast(max - min);
}

pub fn sizeInfo(rm: *RenderManager, font: []const u8, size: u32) !FontManager.SizeInfo {
    const font_id = try rm.getFont(font);
    return rm.font_manager.sizeInfo(font_id, size, null);
}

pub fn drawRect(rm: *RenderManager, a: [2]f32, b: [2]f32, col: sdk.Color) void {
    var mb = MeshBuilder.init(rm.mat_solid_no_depth, true, 4, 8);
    defer mb.finish();

    mb.position(.{ .x = a[0], .y = a[1], .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = b[0], .y = a[1], .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = b[0], .y = b[1], .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = a[0], .y = b[1], .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.index(0);
    mb.index(1);

    mb.index(1);
    mb.index(2);

    mb.index(2);
    mb.index(3);

    mb.index(3);
    mb.index(4);

    mb.index(4);
    mb.index(5);
}

pub fn fillRect(rm: *RenderManager, a: [2]f32, b: [2]f32, col: sdk.Color) void {
    var mb = MeshBuilder.init(rm.mat_solid_no_depth, false, 4, 6);
    defer mb.finish();

    mb.position(.{ .x = a[0] * xpix, .y = a[1] * ypix, .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = b[0] * xpix, .y = a[1] * ypix, .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = b[0] * xpix, .y = b[1] * ypix, .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.position(.{ .x = a[0] * xpix, .y = b[1] * ypix, .z = 0 });
    mb.color(col);
    mb.advanceVertex();

    mb.index(0);
    mb.index(1);
    mb.index(3);

    mb.index(1);
    mb.index(2);
    mb.index(3);
}
