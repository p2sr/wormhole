const std = @import("std");
const classgen = @import("classgen.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("wormhole", "src/main.zig", .unversioned);
    lib.addPackage(classgen.pkg(b, "sdk", "sdk/"));
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
