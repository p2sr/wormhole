const std = @import("std");
const sdk = @import("sdk");
const fc = @import("fontconfig");
const FontManager = @import("fontmanager").FontManager(FontTextureContext);
const MeshBuilder = @import("MeshBuilder.zig");
const Wormhole = @import("Wormhole.zig");

var allocator: std.mem.Allocator = undefined;
var texture_manager: TextureManager = undefined;
var font_manager: FontManager = undefined;
var default_font_name: []const u8 = undefined;

var mat_solid_depth: *sdk.IMaterial = undefined;
var mat_solid_no_depth: *sdk.IMaterial = undefined;

// TODO deinit
var font_names: std.StringHashMapUnmanaged(struct {
    file: [:0]const u8,
    id: ?FontManager.FontId,
}) = .{};

const xpix = 1.0 / 2560.0;
const ypix = 1.0 / 1080.0;

const FontTextureContext = struct {
    pub const RenderTexture = *const TextureManager.Texture;
    pub fn getRenderTexture(_: FontTextureContext, idx: u32) RenderTexture {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ Wormhole.getInst().resource_prefix, idx }) catch unreachable;

        for (texture_manager.textures.items) |*tex| {
            if (std.mem.eql(u8, tex.name, name)) {
                return tex;
            }
        }

        unreachable; // font texture not found
    }
    pub fn createTexture(_: FontTextureContext, idx: u32, w: u32, h: u32, data: []const u8) !void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ Wormhole.getInst().resource_prefix, idx }) catch unreachable;
        try texture_manager.createTexture(name, w, h, data, false);
    }
    pub fn destroyTexture(_: FontTextureContext, idx: u32) void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ Wormhole.getInst().resource_prefix, idx }) catch unreachable;
        texture_manager.destroyTexture(name);
    }
    pub fn updateTexture(_: FontTextureContext, idx: u32, x: u32, y: u32, w: u32, h: u32, data: []const u8) !void {
        var name_buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "_wh_{d}_font_page_{d}", .{ Wormhole.getInst().resource_prefix, idx }) catch unreachable;
        try texture_manager.updateTexture(name, x, y, w, h, null);
        _ = data; // We know it's the same buffer - TODO should this arg even really exist?
    }
};

const TextureManager = struct {
    textures: std.ArrayList(Texture),
    regenerator: Regenerator = .{},

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

        fn deinit(tex: Texture) void {
            switch (tex.buf) {
                .owned => |buf| allocator.free(buf),
                .external => {},
            }
            allocator.free(tex.name);
            // FIXME: the material sometimes has an extra reference, I suspect
            // because it's bound. TODO: unbind the material!!
            tex.mat_depth.decrementReferenceCount();
            tex.mat_no_depth.decrementReferenceCount();
            tex.matsys_tex.decrementReferenceCount();
        }
    };

    const Regenerator = struct {
        const Method = switch (@import("builtin").os.tag) {
            .windows => std.builtin.CallingConvention.Thiscall,
            else => std.builtin.CallingConvention.C,
        };

        vtable: *const struct {
            regenerateTextureBits: *const fn (*Regenerator, *sdk.ITexture, *sdk.IVtfTexture, *sdk.Rect) callconv(Method) void = &Regenerator.regenerateTextureBits,
            release: *const fn (*Regenerator) callconv(Method) void = &Regenerator.release,
            hasPreallocatedScratchTexture: *const fn (*const Regenerator) callconv(Method) bool = &Regenerator.hasPreallocatedScratchTexture,
            getPreallocatedScratchTexture: *const fn (*const Regenerator) callconv(Method) ?*sdk.IVtfTexture = &Regenerator.getPreallocatedScratchTexture,
        } = &.{},

        fn regenerateTextureBits(_: *Regenerator, matsys_tex: *sdk.ITexture, vtf_tex: *sdk.IVtfTexture, _: *sdk.Rect) callconv(Method) void {
            const tex = for (texture_manager.textures.items) |*tex| {
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

    fn init() TextureManager {
        return .{
            .textures = std.ArrayList(Texture).init(allocator),
        };
    }

    fn deinit(self: TextureManager) void {
        for (self.textures.items) |tex| {
            tex.deinit();
        }
        self.textures.deinit();
    }

    pub fn createTexture(self: *TextureManager, name: []const u8, w: u32, h: u32, init_data: []const u8, replicate_data: bool) !void {
        const name_owned = try allocator.dupeZ(u8, name);
        errdefer allocator.free(name_owned);

        const IMaterialSystem = Wormhole.getInst().interface_manager.ifaces.IMaterialSystem;
        const matsys_tex = IMaterialSystem.createProceduralTexture(name_owned.ptr, "Wormhole textures", @intCast(w), @intCast(h), .bgra8888, .{
            .clamp_s = true,
            .clamp_t = true,
            .no_mip = true,
            .no_lod = true,
            .single_copy = true,
        }) orelse return error.TextureInitError;
        errdefer matsys_tex.decrementReferenceCount();

        matsys_tex.setTextureRegenerator(@ptrCast(&self.regenerator), true);

        const mat_depth = try createTexMaterial(name, false);
        errdefer mat_depth.decrementReferenceCount();

        const mat_no_depth = try createTexMaterial(name, true);
        errdefer mat_no_depth.decrementReferenceCount();

        if (replicate_data) {
            const data = try allocator.dupe(u8, init_data);
            errdefer allocator.free(data);

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
                tex.deinit();
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

    fn createTexMaterial(tex_name: []const u8, no_depth: bool) !*sdk.IMaterial {
        const mat_name = try std.fmt.allocPrintZ(allocator, "{s}_mat_{s}", .{ tex_name, if (no_depth) "no_depth" else "depth" });
        defer allocator.free(mat_name);

        return createMaterial(mat_name, tex_name, no_depth);
    }
};

fn createMaterial(mat_name: [:0]const u8, tex_name: ?[]const u8, no_depth: bool) !*sdk.IMaterial {
    const kv = try sdk.KeyValues.init("UnlitGeneric");
    errdefer kv.deinit();
    try kv.setInt("$vertexcolor", 1);
    try kv.setInt("$vertexalpha", 1);
    try kv.setInt("$translucent", 1);
    if (no_depth) try kv.setInt("$ignorez", 1);
    if (tex_name) |tex| try kv.setString("$basetexture", tex);

    const IMaterialSystem = Wormhole.getInst().interface_manager.ifaces.IMaterialSystem;
    return IMaterialSystem.createMaterial(mat_name.ptr, kv) orelse error.MaterialInitError;
}

pub fn init(allocator1: std.mem.Allocator) !void {
    allocator = allocator1;

    texture_manager = TextureManager.init();
    errdefer texture_manager.deinit();

    const kv = try sdk.KeyValues.init("UnlitGeneric");
    errdefer kv.deinit();
    try kv.setInt("$vertexcolor", 1);
    try kv.setInt("$vertexalpha", 1);
    try kv.setInt("$translucent", 1);
    try kv.setInt("$ignorez", 1);
    mat_solid_depth = try createMaterial("_wh_solid_depth", null, false);
    mat_solid_no_depth = try createMaterial("_wh_solid_no_depth", null, true);

    font_manager = try FontManager.init(allocator, .{}, .{});
    errdefer font_manager.deinit();

    const conf = try fc.FontConfig.init();

    const pat = try fc.Pattern.init();
    defer pat.deinit();

    const obj_set = try fc.ObjectSet.build(&.{ .family, .file });
    defer obj_set.deinit();

    const font_set = try conf.fontList(pat, obj_set);
    defer font_set.deinit();

    var found_default: bool = false;
    for (font_set.fonts()) |font| {
        const family = font.getProperty(.family, 0) catch continue;
        const file = font.getProperty(.file, 0) catch continue;

        if (font_names.contains(family)) continue;

        const family_owned = try allocator.dupe(u8, family);
        const file_owned = try allocator.dupeZ(u8, file);
        try font_names.put(allocator, family_owned, .{
            .file = file_owned,
            .id = null,
        });

        if (!found_default) {
            for ([_][]const u8{
                "DejaVu Sans",
                "Segoe UI",
                "Roboto",
                "Ubuntu",
                "Helvetica Neue",
            }) |name| {
                if (std.mem.eql(u8, family, name)) {
                    found_default = true;
                    default_font_name = name;
                }
            }
        }
    }

    if (!found_default) return error.NoDefaultFont;

    std.log.debug("Initialized render manager", .{});
    std.log.debug("Using default font {s}", .{default_font_name});
}

pub fn deinit() void {
    font_manager.deinit();

    {
        var it = font_names.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.file);
        }
        font_names.deinit(allocator);
    }

    mat_solid_depth.decrementReferenceCount();
    mat_solid_depth.decrementReferenceCount(); // TODO
    mat_solid_depth.deleteIfUnreferenced();
    mat_solid_no_depth.decrementReferenceCount();
    mat_solid_no_depth.decrementReferenceCount(); // TODO
    mat_solid_no_depth.deleteIfUnreferenced();

    texture_manager.deinit();
}

fn getFont(name: []const u8) !FontManager.FontId {
    const ptr = font_names.getPtr(name) orelse font_names.getPtr(default_font_name).?;
    if (ptr.id) |id| return id;
    ptr.id = try font_manager.registerFont(ptr.file, 0);
    return ptr.id.?;
}

pub fn drawText(pos: [2]f32, font: []const u8, size: u32, col: sdk.Color, str: []const u8) !void {
    const font_id = try getFont(font);

    var x: f32 = pos[0] * xpix;
    var y: f32 = pos[1] * ypix;

    const size_info = try font_manager.sizeInfo(font_id, size, null);
    y += @as(f32, @floatFromInt(size_info.ascender)) * ypix / 64.0;

    var it = try font_manager.glyphIterator(font_id, size, null, str);
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

pub fn textLength(font: []const u8, size: u32, str: []const u8) !u32 {
    const font_id = try getFont(font);

    var it = try font_manager.glyphIterator(font_id, size, null, str);
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

pub fn sizeInfo(font: []const u8, size: u32) !@TypeOf(font_manager).SizeInfo {
    const font_id = try getFont(font);
    return font_manager.sizeInfo(font_id, size, null);
}

pub fn drawRect(a: [2]f32, b: [2]f32, col: sdk.Color) void {
    var mb = MeshBuilder.init(mat_solid_no_depth, true, 4, 8);
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

pub fn fillRect(a: [2]f32, b: [2]f32, col: sdk.Color) void {
    var mb = MeshBuilder.init(mat_solid_no_depth, false, 4, 6);
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
