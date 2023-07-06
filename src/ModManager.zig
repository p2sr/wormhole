const std = @import("std");
const api = @import("api.zig");

const ModManager = @This();
const Wormhole = @import("Wormhole.zig");

wh: *Wormhole,
mods: std.StringHashMapUnmanaged(Mod),

const ModSpec = struct {
    name: []const u8,
    version: std.SemanticVersion,
};

pub const Mod = struct {
    pub const THudComponent = struct {
        _cbk: *fn (slot: u8, fmt: [*:0]const u8, buf: [*]u8, size: usize) callconv(.C) usize,
        pub fn call(self: THudComponent, mod: []const u8, slot: u8, fmt: [*:0]const u8, buf: [*]u8, size: usize) usize {
            return api.callExternal(mod, self._cbk, .{ slot, fmt, buf, size });
        }
    };

    pub const EventHandler = struct {
        _cbk: *fn (data: ?*anyopaque) callconv(.C) void,
        pub fn call(self: EventHandler, mod: []const u8, data: ?*anyopaque) void {
            api.callExternal(mod, self._cbk, .{data});
        }
    };

    arena: std.heap.ArenaAllocator.State,

    lib: std.DynLib,
    spec: ModSpec,
    deps: []ModSpec,
    thud_components: std.StringHashMap(THudComponent),
    event_handlers: std.StringHashMap([]EventHandler),
};

pub fn get(mm: *ModManager, name: []const u8) ?Mod {
    return mm.mods.get(name);
}

pub const Iterator = struct {
    it: std.StringHashMap(Mod).Iterator,
    const Elem = struct { []const u8, Mod };
    pub fn next(self: *Iterator) ?Elem {
        if (self.it.next()) |ent| {
            return Elem{ ent.key_ptr.*, ent.value_ptr.* };
        } else {
            return null;
        }
    }
};

pub fn iterator(mm: *ModManager) Iterator {
    return .{ .it = mm.mods.iterator() };
}

pub fn init(wh: *Wormhole) !ModManager {
    var mod_list = std.ArrayList(Mod).init(wh.gpa);
    defer mod_list.deinit();

    var dir = std.fs.cwd().openIterableDir("mods", .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            std.log.err("mods directory not found", .{});
            return error.NoModDir;
        },
        else => |e| return e,
    };
    defer dir.close();

    var dir_it = dir.iterate();
    while (try dir_it.next()) |ent| {
        if (ent.kind != .file) continue;
        const path = try std.fs.path.join(wh.gpa, &.{ "mods", ent.name });
        defer wh.gpa.free(path);
        const mod_info = loadMod(path, wh) catch |err| {
            switch (err) {
                error.MissingModInfo => std.log.err("Missing MOD_INFO in {s}", .{ent.name}),
                error.BadModName => std.log.err("Bad name in {s}", .{ent.name}),
                error.BadModVersion => std.log.err("Bad version in {s}", .{ent.name}),
                error.BadModDeps => std.log.err("Bad dependencies in {s}", .{ent.name}),
                error.BadTHudComponents => std.log.err("Bad tHUD components in {s}", .{ent.name}),
                error.BadEventHandlers => std.log.err("Bad event handlers in {s}", .{ent.name}),
                else => |e| return e,
            }
            continue;
        };
        try mod_list.append(mod_info);
    }

    return .{
        .wh = wh,
        .mods = try validateMods(mod_list.items, wh),
    };
}

pub fn deinit(mm: *ModManager) void {
    var it = mm.mods.iterator();
    while (it.next()) |kv| {
        kv.value_ptr.lib.close();
        kv.value_ptr.arena.promote(mm.wh.gpa).deinit();
    }
    mm.mods.deinit(mm.wh.gpa);
    mm.* = undefined;
}

const ModInfoRaw = extern struct {
    const THudComponent = extern struct {
        name: ?[*:0]const u8,
        cbk: ?*fn (slot: u8, fmt: [*:0]const u8, buf: [*]u8, size: usize) callconv(.C) usize,
    };

    const EventHandler = extern struct {
        name: ?[*:0]const u8,
        cbk: ?*fn (data: ?*anyopaque) callconv(.C) void,
    };

    name: ?[*:0]const u8,
    version: ?[*:0]const u8,
    deps: ?[*:null]?[*:0]const u8,
    thud_components: ?[*:.{ .name = null, .cbk = null }]THudComponent,
    event_handlers: ?[*:.{ .name = null, .cbk = null }]EventHandler,
};

fn loadMod(path: []const u8, wh: *Wormhole) !Mod {
    var arena = std.heap.ArenaAllocator.init(wh.gpa);
    errdefer arena.deinit();

    var lib = try std.DynLib.open(path);
    errdefer lib.close();

    // std.mem.span wants deps to be aligned correctly, so we alignCast
    // this, returning an error if the alignment is incorrect
    const info_raw = std.math.alignCast(
        @alignOf(ModInfoRaw),
        lib.lookup(*align(1) ModInfoRaw, "MOD_INFO") orelse return error.MissingModInfo,
    ) catch return error.MissingModInfo;

    const spec = ModSpec{
        .name = std.mem.span(info_raw.name) orelse return error.BadModName,
        .version = std.SemanticVersion.parse(
            std.mem.span(info_raw.version) orelse return error.BadModVersion,
        ) catch return error.BadModVersion,
    };

    if (spec.name.len == 0) return error.BadModName;

    // Validate mod name
    for (spec.name) |c| {
        if (c >= 'a' and c <= 'z') continue;
        if (c == '-') continue;
        return error.BadModName;
    }

    var dep_list = std.ArrayList(ModSpec).init(arena.allocator());

    for (std.mem.span(info_raw.deps) orelse return error.BadModDeps) |dep_str| {
        try dep_list.append(try parseDep(std.mem.span(dep_str orelse unreachable)));
    }

    var thud_components = std.StringHashMap(Mod.THudComponent).init(arena.allocator());

    if (info_raw.thud_components) |raw| {
        var i: usize = 0;
        while (raw[i].name != null or raw[i].cbk != null) : (i += 1) {
            if (raw[i].name == null) return error.BadTHudComponents;
            if (raw[i].cbk == null) return error.BadTHudComponents;

            const name = std.mem.span(raw[i].name) orelse unreachable;

            const res = try thud_components.getOrPut(name);
            if (res.found_existing) {
                return error.BadTHudComponents;
            } else {
                res.value_ptr.* = .{
                    ._cbk = raw[i].cbk.?,
                };
            }
        }
    } else {
        return error.BadTHudComponents;
    }

    // This is temporary so we allocate it on the normal allocator
    var event_handlers_al = std.StringHashMap(std.ArrayList(Mod.EventHandler)).init(wh.gpa);
    defer {
        var it = event_handlers_al.iterator();
        while (it.next()) |kv| {
            kv.value_ptr.deinit();
        }
        event_handlers_al.deinit();
    }

    if (info_raw.event_handlers) |raw| {
        var i: usize = 0;
        while (raw[i].name != null or raw[i].cbk != null) : (i += 1) {
            if (raw[i].name == null) return error.BadEventHandlers;
            if (raw[i].cbk == null) return error.BadEventHandlers;

            const name = std.mem.span(raw[i].name) orelse unreachable;

            const res = try event_handlers_al.getOrPut(name);
            if (!res.found_existing) {
                // These are also temporary so we allocate them on the
                // normal allocator too
                res.value_ptr.* = std.ArrayList(Mod.EventHandler).init(wh.gpa);
            }
            try res.value_ptr.append(.{ ._cbk = raw[i].cbk.? });
        }
    }

    // Move them into a more efficient representation where each slice
    // is actually the right length
    var event_handlers = std.StringHashMap([]Mod.EventHandler).init(arena.allocator());

    {
        var it = event_handlers_al.iterator();
        while (it.next()) |kv| {
            const ptr = try arena.allocator().alloc(Mod.EventHandler, kv.value_ptr.items.len);
            std.mem.copy(Mod.EventHandler, ptr, kv.value_ptr.items);
            kv.value_ptr.clearAndFree();
            try event_handlers.put(kv.key_ptr.*, ptr);
        }
    }

    return .{
        .arena = arena.state,
        .lib = lib,
        .spec = spec,
        .deps = try dep_list.toOwnedSlice(),
        .thud_components = thud_components,
        .event_handlers = event_handlers,
    };
}

fn parseDep(str: []const u8) !ModSpec {
    const idx = std.mem.lastIndexOfScalar(u8, str, '@') orelse return error.BadModDeps;
    return ModSpec{
        .name = str[0..idx],
        .version = try std.SemanticVersion.parse(str[idx + 1 ..]),
    };
}

fn validateMods(mod_list: []Mod, wh: *Wormhole) !std.StringHashMapUnmanaged(Mod) {
    var err = false;

    var mods: std.StringHashMapUnmanaged(Mod) = .{};
    errdefer mods.deinit(wh.gpa);

    for (mod_list) |mod| {
        const res = try mods.getOrPut(wh.gpa, mod.spec.name);
        if (res.found_existing) {
            std.log.err("Cannot load mod {s}; already loaded", .{
                mod.spec.name,
            });
            err = true;
            continue;
        } else {
            res.value_ptr.* = mod;
        }
    }

    if (err) {
        std.log.err("Error loading mods: duplicate mods", .{});
        return error.VersionConflicts;
    }

    for (mod_list) |mod| {
        for (mod.deps) |dep| {
            if (mods.get(dep.name)) |dep_loaded| {
                if (!compatibleWith(dep.version, dep_loaded.spec.version)) {
                    std.log.err("Incompatible version of dependency {s} for mod {s}", .{
                        dep.name,
                        mod.spec.name,
                    });
                    err = true;
                }
                break;
            } else {
                std.log.err("Missing dependency {s} for mod {s}", .{
                    dep.name,
                    mod.spec.name,
                });
                err = true;
            }
        }
    }

    if (err) {
        std.log.err("Error loading mods: missing dependencies", .{});
        return error.MissingDependencies;
    }

    std.log.info("{} mods loaded:", .{mods.count()});

    for (mod_list) |mod| {
        std.log.info("  {s}", .{mod.spec.name});
    }

    return mods;
}

fn compatibleWith(version: std.SemanticVersion, desired: std.SemanticVersion) bool {
    if (version.major != desired.major) return false;

    if (version.major == 0) {
        // Major version 0 does not guarantee backwards compatability
        // for *any* change. Only allow the exact same version
        return std.SemanticVersion.order(version, desired) == .eq;
    }

    // We need minor and patch (and pre) to be at *least* the desired version, so
    // just order the versions, and check version is not below desired
    return std.SemanticVersion.order(version, desired) != .lt;
}
