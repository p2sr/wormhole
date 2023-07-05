const std = @import("std");
const sdk = @import("sdk");

var keyValuesSystem: *const fn () callconv(.C) *sdk.IKeyValuesSystem = undefined;

pub fn initSystem() !void {
    var lib = try std.DynLib.open(switch (@import("builtin").os.tag) {
        .windows => "vstdlib.dll",
        .linux => "libvstdlib.so",
        .macos => "libvstdlib.dylib",
        else => @compileError("Unsupported OS"),
    });
    defer lib.close();

    keyValuesSystem = lib.lookup(@TypeOf(keyValuesSystem), "KeyValuesSystem") orelse return error.SymbolNotFound;
}

pub const KeyValues = extern struct {
    key_name: packed struct(u32) {
        name: u24,
        case_sens_1: u8,
    },
    val_str: ?[*:0]u8 = null,
    val_wstr: ?[*:0]sdk.wchar = null,
    val: extern union {
        i: c_int,
        f: f32,
        p: *anyopaque,
        col: [4]u8,
    } = .{ .i = 0 },
    data_type: enum(u8) {
        none,
        string,
        int,
        float,
        ptr,
        wstring,
        color,
        uint64,
        compiled_int_byte,
        compiled_int_0,
        compiled_int_1,
    } = .none,
    has_escape_sequences: bool = false,
    key_name_case_sens_2: u16,
    peer: ?*KeyValues = null,
    sub: ?*KeyValues = null,
    chain: ?*KeyValues = null,
    expr_get_symbol_proc: ?*const fn (key: [*:0]const u8) callconv(.C) bool = null,

    pub fn init(name: [*:0]const u8) !*KeyValues {
        const mem = @as(?*KeyValues, @ptrCast(keyValuesSystem().allocKeyValuesMemory(@sizeOf(KeyValues)))) orelse return error.OutOfMemory;
        errdefer keyValuesSystem().freeKeyValuesMemory(mem);

        var case_insens_key: c_uint = std.math.maxInt(c_uint);
        const case_sens_key = keyValuesSystem().getSymbolForStringCaseSensitive(&case_insens_key, name, true);

        mem.* = KeyValues{
            .key_name = .{
                .name = @truncate(case_insens_key),
                .case_sens_1 = @truncate(case_sens_key),
            },
            .key_name_case_sens_2 = @truncate(case_sens_key >> 8),
        };

        return mem;
    }

    pub fn deinit(self: *KeyValues) void {
        var cur: ?*KeyValues = self.sub;
        var next: ?*KeyValues = undefined;

        while (cur) |ptr| : (cur = next) {
            next = ptr.peer;
            ptr.peer = null;
            ptr.deinit();
        }

        cur = self.peer;

        while (cur != null and cur != self) : (cur = next) {
            next = cur.?.peer;
            cur.?.peer = null;
            cur.?.deinit();
        }

        if (self.val_str) |ptr| keyValuesSystem().freeKeyValuesMemory(ptr);
        if (self.val_wstr) |ptr| keyValuesSystem().freeKeyValuesMemory(ptr);
        self.val_str = null;
        self.val_wstr = null;

        keyValuesSystem().freeKeyValuesMemory(self);
    }

    pub fn findKey(self: *KeyValues, name: [*:0]const u8, create: bool) error{OutOfMemory}!?*KeyValues {
        const sym = keyValuesSystem().getSymbolForString(name, create);
        if (sym == std.math.maxInt(c_uint)) return null;

        var prev: ?*KeyValues = null;
        var cur: ?*KeyValues = self.sub;
        while (cur) |ptr| : (cur = ptr.peer) {
            prev = ptr;
            if (ptr.key_name.name == sym) return ptr;
        }

        if (self.chain) |chain| {
            if (try chain.findKey(name, false)) |ptr| return ptr;
        }

        if (!create) return null;

        cur = try KeyValues.init(name);
        if (prev) |ptr| {
            ptr.peer = cur;
        } else {
            self.sub = cur;
        }

        self.data_type = .none;

        return cur;
    }

    pub fn setInt(self: *KeyValues, key: [*:0]const u8, val: c_int) !void {
        if (try self.findKey(key, true)) |kv| {
            kv.val.i = val;
            kv.data_type = .int;
        }
    }

    pub fn setString(self: *KeyValues, key: [*:0]const u8, val: []const u8) !void {
        if (try self.findKey(key, true)) |kv| {
            kv.val_str = @as(?[*:0]u8, @ptrCast(keyValuesSystem().allocKeyValuesMemory(val.len + 1))) orelse return error.OutOfMemory;
            std.mem.copy(u8, kv.val_str.?[0..val.len], val);
            kv.val_str.?[val.len] = 0;
            kv.data_type = .string;
        }
    }
};
