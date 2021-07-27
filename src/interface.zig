const std = @import("std");
const sdk = @import("sdk");
const log = @import("log.zig");

var ifaces_internal = blk: { // This is a workaround for a weird result location bug, will be fixed in stage2
    var i: Ifaces = undefined;
    break :blk i;
};
pub const ifaces = &ifaces_internal;

const locations = .{
    .ICvar = "tier1:VEngineCvar007",
};

pub fn init() !void {
    inline for (comptime getDescs()) |desc| {
        const library = if (std.mem.eql(u8, desc.module, "tier1"))
            switch (std.builtin.os.tag) {
                .windows => "vstdlib.dll",
                .linux => "libvstdlib.so",
                .macos => "libvstdlib.dylib",
                else => @compileError("Unsupported OS"),
            }
        else
            desc.module ++ switch (std.builtin.os.tag) {
                .windows => ".dll",
                .linux => ".so",
                .macos => ".dylib",
                else => @compileError("Unsupported OS"),
            };

        var lib = try std.DynLib.open(library);

        const createInterface = lib.lookup(sdk.CreateInterfaceFn, "CreateInterface") orelse return error.SymbolNotFound;
        const iface = createInterface(desc.id.ptr, null) orelse return error.InterfaceNotFound;
        @field(ifaces_internal, desc.name) = @ptrCast(@TypeOf(@field(ifaces, desc.name)), iface);

        log.devInfo("Initialized interface {s}:{s}\n", .{ desc.module, desc.id });
    }
}

pub const Ifaces = blk: {
    var fields: [getDescs().len]std.builtin.TypeInfo.StructField = undefined;

    for (getDescs()) |desc, i| {
        const T = @field(sdk, desc.name);
        fields[i] = .{
            .name = desc.name,
            .field_type = *T,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(*T),
        };
    }

    break :blk @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

const IfaceDesc = struct {
    name: []const u8,
    module: []const u8,
    id: [:0]const u8,
};

fn getDescs() []const IfaceDesc {
    comptime var descs: [std.meta.fields(@TypeOf(locations)).len]IfaceDesc = undefined;

    inline for (comptime std.meta.fieldNames(@TypeOf(locations))) |name, i| {
        const desc = @field(locations, name);
        const idx = comptime std.mem.lastIndexOfScalar(u8, desc, ':') orelse {
            @compileError(std.fmt.comptimePrint(
                "Malformed interface location string \"{}\"",
                .{std.zig.fmtEscapes(desc)},
            ));
        };
        descs[i] = .{
            .name = name,
            .module = desc[0..idx],
            .id = desc[idx + 1 ..],
        };
    }

    return &descs;
}
