const std = @import("std");
const log = @import("log.zig");

const ModSpec = struct {
    name: []const u8,
    version: std.SemanticVersion,
};

const Mod = struct {
    lib: std.DynLib,
    spec: ModSpec,
    deps: []ModSpec,
};

var mods: std.StringHashMap(Mod) = undefined;
var arena: std.heap.ArenaAllocator = undefined;

pub fn init(allocator: *std.mem.Allocator) !void {
    // This arena will be used for persistent allocations of mod info
    arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    // This is only used here, so don't allocate from the arena
    var mod_list = std.ArrayList(Mod).init(allocator);
    defer mod_list.deinit();

    var dir = std.fs.cwd().openDir("mods", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            log.info("mods directory not found; not loading any mods\n", .{});
            return;
        },
        else => |e| return e,
    };
    defer dir.close();

    var dir_it = dir.iterate();
    while (try dir_it.next()) |ent| {
        if (ent.kind != .File) continue;
        // Only used locally; don't allocate from the arena
        const path = try std.fs.path.join(allocator, &.{ "mods", ent.name });
        defer allocator.free(path);
        const mod_info = loadMod(path) catch |err| {
            switch (err) {
                error.MissingModInfo => log.err("Missing MOD_INFO in {s}\n", .{ent.name}),
                error.BadModName => log.err("Bad mod name in {s}\n", .{ent.name}),
                error.BadModVersion => log.err("Bad mod version in {s}\n", .{ent.name}),
                error.BadModDeps => log.err("Bad mod dependencies in {s}\n", .{ent.name}),
                else => |e| return e,
            }
            continue;
        };
        try mod_list.append(mod_info);
    }

    mods = std.StringHashMap(Mod).init(&arena.allocator);
    try validateMods(mod_list.items);
}

pub fn deinit() void {
    arena.deinit();
}

const ModInfoRaw = extern struct {
    name: ?[*:0]const u8,
    version: ?[*:0]const u8,
    deps: ?[*:null]?[*:0]const u8,
};

fn loadMod(path: []const u8) !Mod {
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
        .version = std.SemanticVersion.parse(std.mem.span(info_raw.version) orelse return error.BadModVersion) catch return error.BadModVersion,
    };

    if (spec.name.len == 0) return error.BadModName;

    // Validate mod name
    for (spec.name) |c| {
        if (c >= 'a' and c <= 'z') continue;
        if (c == '-') continue;
        return error.BadModName;
    }

    var dep_list = std.ArrayList(ModSpec).init(&arena.allocator);
    errdefer dep_list.deinit();

    for (std.mem.span(info_raw.deps) orelse return error.BadModDeps) |dep_str| {
        try dep_list.append(try parseDep(std.mem.span(dep_str orelse unreachable)));
    }

    return Mod{
        .lib = lib,
        .spec = spec,
        .deps = dep_list.toOwnedSlice(),
    };
}

fn getLibPtr(comptime T: type, lib: *std.DynLib, name: [:0]const u8) ?T {
    return (lib.lookup(*align(1) ?T, name) orelse return null).*;
}

fn parseDep(str: []const u8) !ModSpec {
    const idx = std.mem.lastIndexOfScalar(u8, str, '@') orelse return error.BadModDeps;
    return ModSpec{
        .name = str[0..idx],
        .version = try std.SemanticVersion.parse(str[idx + 1 ..]),
    };
}

fn validateMods(mod_list: []Mod) !void {
    var err = false;

    for (mod_list) |mod| {
        const res = try mods.getOrPut(mod.spec.name);
        if (res.found_existing) {
            log.err("Cannot load mod {s}; already loaded\n", .{
                mod.spec.name,
            });
            err = true;
            continue;
        } else {
            res.value_ptr.* = mod;
        }
    }

    if (err) {
        log.err("Error loading mods: duplicate mods\n", .{});
        return error.VersionConflicts;
    }

    for (mod_list) |mod| {
        for (mod.deps) |dep| {
            if (mods.get(dep.name)) |dep_loaded| {
                if (!compatibleWith(dep.version, dep_loaded.spec.version)) {
                    log.err("Incompatible version of dependency {s} for mod {s}\n", .{
                        dep.name,
                        mod.spec.name,
                    });
                    err = true;
                }
                break;
            } else {
                log.err("Missing dependency {s} for mod {s}\n", .{
                    dep.name,
                    mod.spec.name,
                });
                err = true;
            }
        }
    }

    if (err) {
        log.err("Error loading mods: missing dependencies\n", .{});
        return error.MissingDependencies;
    }

    log.info("{} mods loaded:\n", .{mods.count()});

    for (mod_list) |mod| {
        log.info("  {s}\n", .{mod.spec.name});
    }
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
