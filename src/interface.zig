const std = @import("std");
const sdk = @import("sdk");
const hooks = @import("hooks.zig");

pub var ifaces: Ifaces = undefined;

pub var orig: Orig = undefined;

const locations = .{
    .IEngineVGuiInternal = "engine:VEngineVGui001",
    .IVEngineClient = "engine:VEngineClient015",
    .IServerTools = "server:VSERVERTOOLS001",
    .IServerGameDLL = "server:ServerGameDLL005",
    .IMaterialSystem = "materialsystem:VMaterialSystem080",
    .IInputSystem = "inputsystem:InputSystemVersion001",
};

var allocator: std.mem.Allocator = undefined;

const VtableEntry = ?*const opaque {};
var hooked_tables: std.ArrayList([]VtableEntry) = undefined;

pub fn init(allocator1: std.mem.Allocator) !void {
    allocator = allocator1;

    hooked_tables = @TypeOf(hooked_tables).init(allocator);
    errdefer hooked_tables.deinit();

    // TODO: on error remove hooks

    inline for (comptime getDescs()) |desc| {
        var library = if (std.mem.eql(u8, desc.module, "tier1"))
            switch (@import("builtin").os.tag) {
                .windows => "vstdlib.dll",
                .linux => "libvstdlib.so",
                .macos => "libvstdlib.dylib",
                else => @compileError("Unsupported OS"),
            }
        else
            desc.module ++ switch (@import("builtin").os.tag) {
                .windows => ".dll",
                .linux => ".so",
                .macos => ".dylib",
                else => @compileError("Unsupported OS"),
            };

        std.log.info("Opening {s}", .{library});
        if (std.mem.eql(u8, library, "server.so")) library = "portal2/bin/linux32/server.so";
        var lib = try std.DynLib.open(library);
        defer lib.close();

        const createInterface = lib.lookup(sdk.CreateInterfaceFn, "CreateInterface") orelse return error.SymbolNotFound;
        const iface = @ptrCast(
            @TypeOf(@field(ifaces, desc.name)),
            createInterface(desc.id.ptr, null) orelse return error.InterfaceNotFound,
        );
        @field(ifaces, desc.name) = iface;

        @field(orig, desc.name) = iface.data._vt;

        if (@typeInfo(desc.hooks).Struct.decls.len > 0) {
            const new_vtable = try copyVtable(@TypeOf(iface.data._vt.*), iface.data._vt);

            inline for (@typeInfo(desc.hooks).Struct.decls) |decl| {
                const hooked = @field(desc.hooks, decl.name);
                // TODO: assert type
                @field(new_vtable.*, decl.name) = hooked;
            }

            iface.data._vt = new_vtable;
        }

        std.log.debug("Initialized interface {s}:{s}\n", .{ desc.module, desc.id });
    }
}

pub fn deinit() void {
    inline for (comptime getDescs()) |desc| {
        var iface = @field(ifaces, desc.name);
        iface.data._vt = @field(orig, desc.name);
    }

    for (hooked_tables.items) |vtable| {
        allocator.free(vtable);
    }

    hooked_tables.deinit();
}

fn copyVtable(comptime T: type, vtable: *const T) !*T {
    // We don't necessarily know the full extent of vtables; not only could
    // our SDK definitions be incomplete, but also the subclass could
    // define extra virtual methods that we don't know about. That means
    // that in order to not completely fuck the vtable, we need to copy the
    // *whole* thing, including these extra bits. Luckily, there's a null
    // pointer at the end of the vtable, so we can use that as a sentinel!
    // Note that we also copy one pointer *before* the start of the vtable;
    // this is RTTI shit, I don't really understand it, but SAR does it and
    // I'm pretty sure it's a good idea.

    var vtable1 = std.mem.span(@ptrCast([*:null]const VtableEntry, vtable));

    // Include the preceding typeinfo shit and the terminator
    vtable1.len += 2;
    vtable1.ptr -= 1;

    var new_vtable = try allocator.alloc(VtableEntry, vtable1.len);
    std.mem.copy(VtableEntry, new_vtable, vtable1);

    try hooked_tables.append(new_vtable);

    return @ptrCast(*T, new_vtable.ptr + 1);
}

pub const Ifaces = blk: {
    var fields: [getDescs().len]std.builtin.Type.StructField = undefined;

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

pub const Orig = blk: {
    var fields: [getDescs().len]std.builtin.Type.StructField = undefined;

    for (getDescs()) |desc, i| {
        const T = @field(sdk, desc.name).Vtable;
        fields[i] = .{
            .name = desc.name,
            .field_type = *const T,
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
            .hooks = struct {},
        };

        for (std.meta.fields(hooks)) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                descs[i].hooks = field.field_type;
            }
        }
    }

    return &descs;
}
