const std = @import("std");
const log = @import("log.zig");

const ModInfo = struct {
    name: []const u8,
    version: std.SemanticVersion,
};

const Mod = struct {
    lib: std.DynLib,
    info: ModInfo,
    deps: []ModInfo,
};

var mods: std.ArrayList(Mod) = undefined;
var allocator: *std.mem.Allocator = undefined;

pub fn init(allocator1: *std.mem.Allocator) !void {
    allocator = allocator1;

    mods = std.ArrayList(Mod).init(allocator);
    errdefer deinit();

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
        const path = try std.fs.path.join(allocator, &.{ "mods", ent.name });
        defer allocator.free(path);
        loadMod(path) catch |err| switch (err) {
            error.InvalidModName => log.err("Invalid MOD_NAME in {s}\n", .{ent.name}),
            error.InvalidModVersion => log.err("Invalid MOD_VERSION in {s}\n", .{ent.name}),
            error.InvalidModDeps => log.err("Invalid MOD_DEPS in {s}\n", .{ent.name}),
            else => |e| return e,
        };
    }

    try checkMods();

    log.info("Loaded {} mods\n", .{mods.items.len});
}

pub fn deinit() void {
    for (mods.items) |*mod| {
        allocator.free(mod.deps);
        mod.lib.close();
    }

    mods.deinit();
}

fn loadMod(path: []const u8) !void {
    var lib = try std.DynLib.open(path);
    errdefer lib.close();

    const name = getLibPtr([*:0]const u8, &lib, "MOD_NAME") orelse return error.InvalidModName;
    const version = getLibPtr([*:0]const u8, &lib, "MOD_VERSION") orelse return error.InvalidModVersion;

    // std.mem.span wants deps to be aligned correctly, so we alignCast
    // this, returning an error if the alignment is incorrect
    const deps = std.math.alignCast(
        @alignOf(?[*:0]const u8),
        lib.lookup([*:null]align(1) const ?[*:0]const u8, "MOD_DEPS") orelse return error.InvalidModDeps,
    ) catch return error.InvalidModDeps;

    const info = ModInfo{
        .name = std.mem.span(name),
        .version = try std.SemanticVersion.parse(std.mem.span(version)),
    };

    var dep_list = std.ArrayList(ModInfo).init(allocator);
    errdefer dep_list.deinit();

    for (std.mem.span(deps)) |dep_str| {
        if (dep_str) |dep_str1| {
            try dep_list.append(try parseDep(std.mem.span(dep_str1)));
        } else {
            return error.InvalidModDeps;
        }
    }

    try mods.append(.{
        .lib = lib,
        .info = info,
        .deps = dep_list.toOwnedSlice(),
    });

    log.info("Loaded mod {s}\n", .{info.name});

    return;
}

fn getLibPtr(comptime T: type, lib: *std.DynLib, name: [:0]const u8) ?T {
    return (lib.lookup(*align(1) ?T, name) orelse return null).*;
}

fn parseDep(str: []const u8) !ModInfo {
    const idx = std.mem.lastIndexOfScalar(u8, str, '@') orelse return error.InvalidModVersion;
    return ModInfo{
        .name = str[0..idx],
        .version = try std.SemanticVersion.parse(str[idx + 1 ..]),
    };
}

fn checkMods() !void {
    for (mods.items) |*mod| {
        for (mods.items) |*mod1| {
            if (mod == mod1) continue;
            if (std.mem.eql(u8, mod.info.name, mod1.info.name)) {
                log.err("Multiple versions of mod {s}\n", .{mod.info.name});
                return error.MultipleModVersions;
            }
        }
        for (mod.deps) |dep| {
            for (mods.items) |mod1| {
                if (std.mem.eql(u8, dep.name, mod1.info.name)) {
                    if (compatibleWith(dep.version, mod1.info.version)) {
                        break;
                    } else {
                        log.err("Incompatible version of dependency {s} for mod {s}\n", .{ dep.name, mod.info.name });
                        return error.BadDependencyVersion;
                    }
                }
            } else {
                log.err("Missing dependency {s} for mod {s}\n", .{ dep.name, mod.info.name });
                return error.MissingDependency;
            }
        }
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
