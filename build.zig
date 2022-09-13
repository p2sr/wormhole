const std = @import("std");
const classgen = @import("deps/zig-classgen/build.zig");
const fontmanager = @import("deps/zig-fontmanager/build.zig");
const fontconfig = @import("deps/zig-fontconfig/build.zig");
const freetype = @import("deps/mach-freetype/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-native-gnu",
        }) catch unreachable,
    });

    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("wormhole", "src/main.zig", .unversioned);
    lib.link_z_notext = true; // ziglang/zig#7935
    if (target.getOsTag() == .windows) {
        lib.want_lto = false; // ziglang/zig#8531
    }
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkLibC();
    classgen.addPackage(b, lib, "sdk", "sdk");
    freetype.link(b, lib, .{ .harfbuzz = .{} });
    fontconfig.link(b, lib);
    lib.addPackage(fontmanager.pkg(freetype));
    lib.addPackage(fontconfig.pkg(freetype));
    lib.addPackage(freetype.pkg);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
