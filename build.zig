const std = @import("std");
const classgen = @import("deps/zig-classgen/build.zig");
const fontmanager = @import("deps/zig-fontmanager/build.zig");
const fontconfig = @import("deps/zig-fontconfig/build.zig");
const freetype = @import("deps/mach-freetype/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget.parse(.{
            .arch_os_abi = "x86-native-gnu",
        }) catch unreachable,
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "wormhole",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.link_z_notext = true; // ziglang/zig#7935
    lib.linkLibC();
    classgen.addModule(b, lib, "sdk", "sdk");
    freetype.link(b, lib, .{ .harfbuzz = .{} });
    fontconfig.link(b, lib);
    lib.addModule("fontmanager", fontmanager.module(b, freetype));
    lib.addModule("fontconfig", fontconfig.module(b, freetype));
    lib.addModule("freetype", freetype.module(b));
    b.installArtifact(lib);
}
