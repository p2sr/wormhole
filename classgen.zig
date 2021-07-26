const std = @import("std");

pub fn pkg(b: *std.build.Builder, pkg_name: []const u8, dir: []const u8) std.build.Pkg {
    const step = ClassGenStep.init(b, pkg_name, dir);
    return .{
        .name = pkg_name,
        .path = .{ .generated = &step.out_file },
    };
}

const ClassGenStep = struct {
    b: *std.build.Builder,
    step: std.build.Step,
    dir: []const u8,
    out_file: std.build.GeneratedFile,

    pub fn init(b: *std.build.Builder, pkg_name: []const u8, dir: []const u8) *ClassGenStep {
        const self = b.allocator.create(ClassGenStep) catch unreachable;
        const out_path = b.fmt("{s}/{s}.zig", .{ b.cache_root, pkg_name });
        self.* = .{
            .b = b,
            .step = std.build.Step.init(.custom, b.fmt("ClassGen {s}", .{dir}), b.allocator, make),
            .dir = dir,
            .out_file = .{ .step = &self.step, .path = out_path },
        };
        return self;
    }

    pub fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ClassGenStep, "step", step);

        var gen = try ClassGenerator.init(self.b.allocator);
        const dir = try std.fs.cwd().openDir(self.dir, .{
            .access_sub_paths = false,
            .iterate = true,
        });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .File) continue;
            if (std.mem.startsWith(u8, entry.name, ".")) continue;
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                try gen.zigFile(entry.name);
            } else {
                try gen.classFromFilename(entry.name);
            }
        }
        const code = try gen.finish();

        const f = try std.fs.cwd().createFile(self.out_file.path orelse unreachable, .{});
        defer f.close();
        try f.writeAll(code);
    }
};

const ClassGenerator = struct {
    allocator: *std.mem.Allocator,
    buf: std.ArrayList(u8),

    pub fn init(arena_allocator: *std.mem.Allocator) !ClassGenerator {
        var self = ClassGenerator{
            .allocator = arena_allocator,
            .buf = std.ArrayList(u8).init(arena_allocator),
        };
        errdefer self.deinit();
        try self.write(
            \\const std = @import("std");
        );
        try self.sep();
        return self;
    }
    pub fn deinit(self: ClassGenerator) void {
        self.buf.deinit();
    }

    /// Return the generated source code as an owned slice.
    /// The ClassGenerator is reset and can be reused.
    pub fn finish(self: *ClassGenerator) ![]u8 {
        const source = try self.buf.toOwnedSliceSentinel(0);
        var tree = try std.zig.parse(self.allocator, source);
        defer tree.deinit(self.allocator);
        if (tree.errors.len != 0) {
            for (tree.errors) |err| {
                tree.renderError(err, std.io.getStdErr().writer()) catch unreachable;
                std.debug.print("\n", .{});
            }
            unreachable;
        }

        return tree.render(self.allocator);
    }

    pub fn zigFile(self: *ClassGenerator, filename: []const u8) !void {
        try self.print("pub usingnamespace @import(\"{}\");\n", .{
            std.zig.fmtEscapes(filename),
        });
    }

    pub fn classFromFilename(self: *ClassGenerator, filename: []const u8) !void {
        const f = try std.fs.cwd().openFile(filename, .{});
        defer f.close();

        const class_name = std.fs.path.basename(filename);
        var cls = self.class(class_name);

        var line_no: u32 = 0;
        while (try f.reader().readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1 << 20)) |line| {
            line_no += 1;
            var toks = std.mem.split(line, "\t");

            const zig_name = toks.next() orelse continue;
            if (zig_name[0] == '#') continue;

            const dispatch_group = toks.next() orelse {
                std.debug.print("Missing dispatch group on line {}\n", .{line_no});
                return error.InvalidFormat;
            };

            const signature_s = toks.next() orelse {
                std.debug.print("Missing method signature on line {}\n", .{line_no});
                return error.InvalidFormat;
            };

            if (toks.next() != null) {
                std.debug.print("Unexpected extra fields on line {}\n", .{line_no});
                return error.InvalidFormat;
            }

            const signature_z = try self.allocator.dupeZ(u8, signature_s);
            const signature = (try TypeDesc.parse(self.allocator, signature_z)) orelse {
                std.debug.print("Invalid signature type on line {}\n", .{line_no});
                return error.InvalidFormat;
            };

            if (signature != .func) {
                std.debug.print("Invalid signature type on line {}\n", .{line_no});
                return error.InvalidFormat;
            }

            try cls.vmethod(.{
                .zig_name = zig_name,
                .dispatch_group = dispatch_group,
                .signature = signature.func,
            });
        }

        try cls.finish();
    }

    fn print(self: *ClassGenerator, comptime fmt: []const u8, args: anytype) !void {
        try self.buf.writer().print(fmt, args);
    }
    fn write(self: *ClassGenerator, str: []const u8) !void {
        try self.buf.writer().writeAll(str);
    }

    pub fn class(self: *ClassGenerator, class_name: []const u8) Class {
        return Class{ .gen = self, .name = class_name };
    }

    pub const Class = struct {
        gen: *ClassGenerator,
        name: []const u8,
        vmethods: std.ArrayListUnmanaged(Method) = .{},

        pub fn finish(self: Class) !void {
            try self.gen.print("pub const {} = extern struct {{\n", .{std.zig.fmtId(self.name)});

            try self.gen.vtable(self.name, self.vmethods.items);
            try self.gen.sep();

            for (self.vmethods.items) |m| {
                try self.gen.wrapper(m.zig_name, self.name, m.signature);
            }

            try self.gen.write("};");
            try self.gen.sep();
        }

        pub fn vmethod(self: *Class, m: Method) !void {
            try self.vmethods.append(self.gen.allocator, m);
        }
    };

    pub const Method = struct {
        zig_name: []const u8,
        dispatch_group: []const u8,
        signature: TypeDesc.Fn,
    };

    fn vtable(self: *ClassGenerator, class_name: []const u8, methods: []const Method) !void {
        try self.write("vtable: *const Vtable,");
        try self.sep();

        try self.write(
            \\pub const Vtable = switch (std.builtin.os.tag) {
            \\    .windows => extern struct {
            \\
        );
        // Generate msvc vtable
        var groups = std.StringArrayHashMap(std.ArrayListUnmanaged(Method)).init(self.allocator);
        for (methods) |m| {
            const res = try groups.getOrPutValue(m.dispatch_group, .{});
            try res.value_ptr.append(self.allocator, m);
        }
        for (groups.values()) |group| {
            var i = group.items.len;
            while (i > 0) {
                i -= 1;
                var m = group.items[i];
                if (std.mem.eql(u8, m.zig_name, "~")) {
                    m.signature.args = &.{.{ .named = "u16" }};
                }
                try self.vmethod(m.zig_name, class_name, m.signature, if (m.signature.variadic) .C else .Thiscall);
            }
        }

        try self.write(
            \\    },
            \\    else => extern struct {
            \\
        );
        // Generate gcc vtable
        for (methods) |m| {
            if (std.mem.eql(u8, m.zig_name, "~")) {
                try self.vmethod("~DUMMY", class_name, .{
                    .args = &.{},
                    .return_type = &.{ .named = "void" },
                    .variadic = false,
                }, .C);
            }
            try self.vmethod(m.zig_name, class_name, m.signature, .C);
        }

        try self.write(
            \\    },
            \\};
        );
    }

    fn vmethod(
        self: *ClassGenerator,
        name: []const u8,
        class_name: []const u8,
        sig: TypeDesc.Fn,
        call_conv: std.builtin.CallingConvention,
    ) !void {
        try self.print("{}: fn (*{}", .{ std.zig.fmtId(name), std.zig.fmtId(class_name) });
        for (sig.args) |arg| {
            try self.print(", {}", .{arg});
        }
        if (sig.variadic) {
            try self.write(", ...");
        }
        try self.print(") callconv(.{}) {},\n", .{ std.zig.fmtId(@tagName(call_conv)), sig.return_type });
    }

    fn wrapper(self: *ClassGenerator, name: []const u8, class_name: []const u8, sig: TypeDesc.Fn) !void {
        try self.print("pub inline fn {}(self: *{}", .{ std.zig.fmtId(name), std.zig.fmtId(class_name) });
        for (sig.args) |arg, i| {
            try self.print(", arg{}: {}", .{ i, arg });
        }
        if (sig.variadic) {
            try self.write(", rest: anytype");
        }
        try self.print(") {} {{\n", .{sig.return_type});

        if (std.mem.eql(u8, name, "~")) {
            try self.write(
                \\return switch (std.builtin.os.tag) {
                \\    .windows => self.vtable.@"~"(self, 0),
                \\    else => self.vtable.@"~"(self),
                \\};
            );
        } else if (sig.variadic) {
            try self.print("return @call(.{{}}, self.vtable.{}, .{{self", .{std.zig.fmtId(name)});
            for (sig.args) |_, i| {
                try self.print(", arg{}", .{i});
            }
            try self.write("} ++ rest);");
        } else {
            try self.print("return self.vtable.{}(self", .{std.zig.fmtId(name)});
            for (sig.args) |_, i| {
                try self.print(", arg{}", .{i});
            }
            try self.write(");");
        }
        try self.write("}\n");
    }

    fn sep(self: *ClassGenerator) !void {
        try self.write("\n\n");
    }
};

// Has no deinit function because we use an arena for everything
const TypeDesc = union(enum) {
    named: []const u8,
    ptr: Pointer,
    array: Array,
    func: Fn,

    pub const Pointer = struct {
        size: Size,
        is_const: bool,
        child: *const TypeDesc,
        sentinel: ?[]const u8,

        pub const Size = enum {
            one,
            many,
        };
    };

    pub const Array = struct {
        len: usize,
        child: *const TypeDesc,
        sentinel: ?[]const u8,
    };

    pub const Fn = struct {
        args: []const TypeDesc,
        return_type: *const TypeDesc,
        variadic: bool,
    };

    pub fn format(value: TypeDesc, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (value) {
            .named => |name| try writer.writeAll(name),

            .ptr => |ptr| {
                switch (ptr.size) {
                    .one => try writer.writeAll("*"),
                    .many => {
                        try writer.writeAll("[*");
                        if (ptr.sentinel) |sentinel| {
                            try writer.print(":{s}", .{sentinel});
                        }
                        try writer.writeAll("]");
                    },
                }
                const const_s = if (ptr.is_const) "const " else "";
                try writer.print("{s}{}", .{ const_s, ptr.child.* });
            },

            .array => |ary| {
                try writer.print("[{}", .{ary.len});
                if (ary.sentinel) |sentinel| {
                    try writer.print(":{s}", .{sentinel});
                }
                try writer.print("]{}", .{ary.child.*});
            },

            .func => |func| {
                try writer.writeAll("fn (");
                for (func.args) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{arg});
                }
                if (func.variadic) {
                    try writer.writeAll(", ...");
                }
                try writer.print(") callconv(.C) {}", .{func.return_type});
            },
        }
    }

    pub fn parse(allocator: *std.mem.Allocator, str: [:0]const u8) !?TypeDesc {
        var parser = Parser{
            .allocator = allocator,
            .toks = std.zig.Tokenizer.init(str),
        };
        return parser.parse(parser.toks.next()) catch |err| switch (err) {
            error.WrongToken => null,
            else => |e| return e,
        };
    }

    const Parser = struct {
        allocator: *std.mem.Allocator,
        toks: std.zig.Tokenizer,

        fn parse(self: *Parser, tok: std.zig.Token) !TypeDesc {
            return switch (tok.tag) {
                .asterisk => self.parsePointer(.one, null),
                .l_bracket => self.parseArray(),
                .keyword_fn => self.parseFn(),
                .identifier => TypeDesc{
                    .named = self.toks.buffer[tok.loc.start..tok.loc.end],
                },
                else => error.WrongToken, // TODO: better errors
            };
        }
        fn parseAlloc(self: *Parser, tok: std.zig.Token) !*TypeDesc {
            const desc = try self.allocator.create(TypeDesc);
            desc.* = try self.parse(tok);
            return desc;
        }

        fn parsePointer(self: *Parser, size: Pointer.Size, sentinel: ?[]const u8) !TypeDesc {
            var ptr = Pointer{
                .size = size,
                .is_const = false,
                .child = undefined,
                .sentinel = sentinel,
            };

            var tok = self.toks.next();
            if (tok.tag == .keyword_const) {
                ptr.is_const = true;
                tok = self.toks.next();
            }

            ptr.child = try self.parseAlloc(tok);
            return TypeDesc{ .ptr = ptr };
        }

        fn parseArray(self: *Parser) !TypeDesc {
            const tok = self.toks.next();
            return switch (tok.tag) {
                .integer_literal => blk: {
                    const len = std.fmt.parseUnsigned(
                        usize,
                        self.toks.buffer[tok.loc.start..tok.loc.end],
                        10,
                    ) catch return error.WrongToken;
                    const sentinel = try self.parseSentinel();

                    break :blk TypeDesc{ .array = .{
                        .len = len,
                        .child = try self.parseAlloc(self.toks.next()),
                        .sentinel = sentinel,
                    } };
                },

                .asterisk => self.parsePointer(.many, try self.parseSentinel()),

                else => error.WrongToken,
            };
        }

        fn parseSentinel(self: *Parser) !?[]const u8 {
            var tok = self.toks.next();
            if (tok.tag != .colon) return null;

            const start = tok.loc.end;
            var end = start;
            while (tok.tag != .r_bracket) : (tok = self.toks.next()) {
                if (tok.tag == .eof) return error.WrongToken;
                end = tok.loc.end;
            }

            if (start == end) {
                return error.WrongToken;
            } else {
                return self.toks.buffer[start..end];
            }
        }

        fn parseFn(self: *Parser) !TypeDesc {
            try self.expect(.l_paren);

            var args = std.ArrayList(TypeDesc).init(self.allocator);
            var tok = self.toks.next();
            var variadic = false;
            while (tok.tag != .r_paren) : (tok = self.toks.next()) {
                if (variadic) {
                    return error.WrongToken;
                }
                if (tok.tag == .ellipsis3) {
                    variadic = true;
                } else {
                    try args.append(try self.parse(tok));
                }
                const sep = self.toks.next();
                switch (sep.tag) {
                    .comma => {},
                    .r_paren => break,
                    else => return error.WrongToken,
                }
            }

            return TypeDesc{ .func = .{
                .args = args.toOwnedSlice(),
                .return_type = try self.parseAlloc(self.toks.next()),
                .variadic = variadic,
            } };
        }

        fn expect(self: *Parser, tag: std.zig.Token.Tag) !void {
            const tok = self.toks.next();
            if (tok.tag != tag) return error.WrongToken;
        }
    };
};
