const std = @import("std");
const classgen = @import("classgen.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-native-gnu",
        }) catch unreachable,
    });

    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("wormhole", "src/main.zig", .unversioned);
    lib.link_z_notext = true; // ziglang/zig#7935
    lib.addPackage(classgen.pkg(b, "sdk", "sdk"));
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkLibC();
    if (target.getOsTag() == .linux) {
        lib.linkSystemLibrary("fontconfig");
    }
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
