const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("sdk");

const InterfaceManager = @This();
const Wormhole = @import("Wormhole.zig");
const hooks = @import("hooks.zig");

const VtableEntry = ?*const opaque {};

wh: *Wormhole,
hooked_tables: std.ArrayListUnmanaged([]VtableEntry),
ifaces: Ifaces,
orig: Orig,

const locations = .{
    .IEngineVGuiInternal = "engine:VEngineVGui001",
    .IVEngineClient = "engine:VEngineClient015",
    .IServerTools = "server:VSERVERTOOLS001",
    .IServerGameDLL = "server:ServerGameDLL005",
    .IMaterialSystem = "materialsystem:VMaterialSystem080",
    .IInputSystem = "inputsystem:InputSystemVersion001",
};

pub fn init(wh: *Wormhole) !InterfaceManager {
    var hooked_tables: std.ArrayListUnmanaged([]VtableEntry) = .{};
    errdefer hooked_tables.deinit(wh.gpa);

    var ifaces: Ifaces = undefined;
    var orig: Orig = undefined;

    // TODO: on error remove hooks

    inline for (iface_descs) |desc| {
        const library = if (std.mem.eql(u8, desc.module, "tier1"))
            switch (builtin.os.tag) {
                .windows => "vstdlib.dll",
                .linux => "libvstdlib.so",
                .macos => "libvstdlib.dylib",
                else => @compileError("Unsupported OS"),
            }
        else if (builtin.os.tag == .linux and std.mem.eql(u8, desc.module, "server"))
            "portal2/bin/linux32/server.so" // TODO
        else
            desc.module ++ switch (builtin.os.tag) {
                .windows => ".dll",
                .linux => ".so",
                .macos => ".dylib",
                else => @compileError("Unsupported OS"),
            };

        std.log.info("Opening {s}", .{library});
        var lib = try std.DynLib.open(library);
        defer lib.close();

        const createInterface = lib.lookup(sdk.CreateInterfaceFn, "CreateInterface") orelse return error.SymbolNotFound;
        const iface: @TypeOf(@field(ifaces, desc.name)) = @ptrCast(
            createInterface(desc.id.ptr, null) orelse return error.InterfaceNotFound,
        );

        @field(ifaces, desc.name) = iface;
        @field(orig, desc.name) = iface.data._vt;

        if (@typeInfo(desc.hooks).Struct.decls.len > 0) {
            const new_vtable = try copyVtable(@TypeOf(iface.data._vt.*), iface.data._vt, wh.gpa, &hooked_tables);
            inline for (@typeInfo(desc.hooks).Struct.decls) |decl| {
                const hooked = @field(desc.hooks, decl.name);
                // TODO: assert type
                @field(new_vtable.*, decl.name) = hooked;
            }
            iface.data._vt = new_vtable;
        }

        std.log.debug("Initialized interface {s}:{s}", .{ desc.module, desc.id });
    }

    return .{
        .wh = wh,
        .hooked_tables = hooked_tables,
        .ifaces = ifaces,
        .orig = orig,
    };
}

pub fn deinit(im: *InterfaceManager) void {
    inline for (iface_descs) |desc| {
        var iface = @field(im.ifaces, desc.name);
        iface.data._vt = @field(im.orig, desc.name);
    }

    for (im.hooked_tables.items) |vtable| {
        im.wh.gpa.free(vtable);
    }

    im.hooked_tables.deinit(im.wh.gpa);

    im.* = undefined;
}

fn copyVtable(comptime T: type, vtable: *const T, gpa: std.mem.Allocator, hooked_tables: *std.ArrayListUnmanaged([]VtableEntry)) !*T {
    // We don't necessarily know the full extent of vtables; not only could
    // our SDK definitions be incomplete, but also the subclass could
    // define extra virtual methods that we don't know about. That means
    // that in order to not completely fuck the vtable, we need to copy the
    // *whole* thing, including these extra bits. Luckily, there's a null
    // pointer at the end of the vtable, so we can use that as a sentinel!
    // Note that we also copy one pointer *before* the start of the vtable;
    // this is RTTI shit, I don't really understand it, but SAR does it and
    // I'm pretty sure it's a good idea.

    var vtable1 = std.mem.span(@as([*:null]const VtableEntry, @ptrCast(vtable)));

    // Include the preceding typeinfo shit and the terminator
    vtable1.len += 2;
    vtable1.ptr -= 1;

    var new_vtable = try gpa.alloc(VtableEntry, vtable1.len);
    std.mem.copy(VtableEntry, new_vtable, vtable1);

    try hooked_tables.append(gpa, new_vtable);

    return @ptrCast(new_vtable.ptr + 1);
}

pub const Ifaces = blk: {
    var fields: [iface_descs.len]std.builtin.Type.StructField = undefined;

    for (iface_descs, 0..) |desc, i| {
        const T = @field(sdk, desc.name);
        fields[i] = .{
            .name = desc.name,
            .type = *T,
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

pub const Orig = blk: {
    var fields: [iface_descs.len]std.builtin.Type.StructField = undefined;

    for (iface_descs, 0..) |desc, i| {
        const T = @field(sdk, desc.name).Vtable;
        fields[i] = .{
            .name = desc.name,
            .type = *const T,
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
    hooks: type,
};

const iface_descs: []const IfaceDesc = blk: {
    comptime var descs: [std.meta.fields(@TypeOf(locations)).len]IfaceDesc = undefined;

    inline for (std.meta.fieldNames(@TypeOf(locations)), 0..) |name, i| {
        const desc = @field(locations, name);
        const idx = std.mem.lastIndexOfScalar(u8, desc, ':') orelse {
            @compileError(std.fmt.comptimePrint(
                "Malformed interface location string \"{}\"",
                .{std.zig.fmtEscapes(desc)},
            ));
        };

        descs[i] = .{
            .name = name,
            .module = desc[0..idx],
            .id = desc[idx + 1 ..],
            .hooks = struct {},
        };

        for (std.meta.fields(hooks)) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                descs[i].hooks = field.type;
            }
        }
    }

    break :blk &descs;
};
