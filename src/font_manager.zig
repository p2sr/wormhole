const std = @import("std");
const sdk = @import("sdk");
const log = @import("log.zig");
const ifaces = @import("interface.zig").ifaces;

const FontRecord = struct {
    name: [:0]const u8,
    tall: u32,

    const HashCtx = struct {
        pub fn eql(self: @This(), a: FontRecord, b: FontRecord) bool {
            _ = self;
            return a.tall == b.tall and std.mem.eql(u8, a.name, b.name);
        }
        pub fn hash(self: @This(), f: FontRecord) u64 {
            _ = self;
            return std.hash.Wyhash.hash(f.tall, f.name);
        }
    };
};

const FontMap = std.HashMap(FontRecord, sdk.HFont, FontRecord.HashCtx, std.hash_map.default_max_load_percentage);

var font_map: FontMap = undefined;
var handle_pool: std.ArrayList(sdk.HFont) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    font_map = FontMap.init(allocator);
    handle_pool = std.ArrayList(sdk.HFont).init(allocator);
}

pub fn deinit() void {
    font_map.deinit();
    handle_pool.deinit();
}

pub fn findRawFont(name: [:0]const u8, tall: u32) ?sdk.HFont {
    if (font_map.get(.{ .name = name, .tall = tall })) |handle| return handle;

    const handle = handle_pool.popOrNull() orelse ifaces.ISurface.createFont();

    if (ifaces.ISurface.setFontGlyphSet(handle, name, @intCast(c_int, tall), 80, 0, 0, 0, 0, 0)) {
        font_map.put(.{ .name = name, .tall = tall }, handle) catch {}; // TODO: make key persistent, i.e. owned memory. TODO: handle error
        return handle;
    }

    // We fucked up. Add the handle back to the pool
    handle_pool.append(handle) catch {}; // TODO: handle error

    return null;
}

const FcConfig = opaque {};
const FcPattern = opaque {};
const FcObjectSet = opaque {};
const FcFontSet = extern struct {
    nfont: c_int,
    sfont: c_int,
    fonts: [*]*FcPattern,
};
extern "fontconfig" fn FcConfigGetCurrent() *FcConfig;
extern "fontconfig" fn FcPatternCreate() *FcPattern;
extern "fontconfig" fn FcObjectSetBuild(first: ?[*:0]const u8, ...) *FcObjectSet;
extern "fontconfig" fn FcFontList(config: ?*FcConfig, p: *FcPattern, os: *FcObjectSet) *FcFontSet;
extern "fontconfig" fn FcPatternGetString(pat: *FcPattern, object: [*:0]const u8, n: c_int, s: *[*:0]const u8) c_int;
extern "fontconfig" fn FcPatternGetInteger(pat: *FcPattern, object: [*:0]const u8, n: c_int, i: *c_int) c_int;
extern "fontconfig" fn FcFontSetDestroy(s: *FcFontSet) void;

fn listFontsLinux() void {
    const config = FcConfigGetCurrent();
    const pat = FcPatternCreate();
    const os = FcObjectSetBuild("family", "file", "weight", @as(?[*:0]const u8, null));
    const fs = FcFontList(config, pat, os);
    for (fs.fonts[0..@intCast(usize, fs.nfont)]) |font| {
        var name: [*:0]const u8 = undefined;
        var file: [*:0]const u8 = undefined;
        var weight: c_int = undefined;
        if (FcPatternGetString(font, "family", 0, &name) != 0) continue;
        if (FcPatternGetString(font, "file", 0, &file) != 0) continue;
        if (FcPatternGetInteger(font, "weight", 0, &weight) != 0 or weight != 80) continue;
        log.info("{s}\n", .{name});
    }
    FcFontSetDestroy(fs);
}

const LOGFONT = extern struct {
    height: i32,
    width: i32,
    escapement: i32,
    orientation: i32,
    weight: i32,
    italic: u8,
    underline: u8,
    strikeout: u8,
    charset: u8,
    out_precision: u8,
    clip_precision: u8,
    quality: u8,
    pitch_and_family: u8,
    face_name: [32]u8,
};

const HDC = ?*opaque {};
const FONTENUMPROCA = fn (*const LOGFONT, *const TEXTMETRIC, u32, ?*anyopaque) callconv(.Stdcall) c_int;
const TEXTMETRIC = opaque {}; // don't care
const WND = opaque {};
extern "gdi32" fn EnumFontFamiliesExA(hfc: HDC, logfont: *LOGFONT, proc: FONTENUMPROCA, param: ?*anyopaque, flags: u32) callconv(.Stdcall) c_int;
extern "gdi32" fn GetDC(wnd: ?*WND) callconv(.Stdcall) HDC;
extern "gdi32" fn ReleaseDC(wnd: ?*WND, hdc: HDC) callconv(.Stdcall) c_int;

fn windowsEnumFontCbk(lf: *const LOGFONT, tm: *const TEXTMETRIC, font_type: u32, param: ?*anyopaque) callconv(.Stdcall) c_int {
    _ = tm;
    _ = font_type;
    _ = param;
    log.info("{s}\n", .{std.mem.sliceTo(&lf.face_name, 0)});
    return 1;
}

fn listFontsWindows() void {
    const hdc = GetDC(null) orelse return;
    var logfont: LOGFONT = undefined;
    logfont.charset = 1; // DEFAULT_CHARSET
    logfont.face_name[0] = 0;
    logfont.pitch_and_family = 0;
    _ = EnumFontFamiliesExA(hdc, &logfont, windowsEnumFontCbk, null, 0);
    _ = ReleaseDC(null, hdc);
}

pub const listFonts = switch (@import("builtin").os.tag) {
    .windows => listFontsWindows,
    .linux => listFontsLinux,
    else => @compileError("Platform not supported"),
};
