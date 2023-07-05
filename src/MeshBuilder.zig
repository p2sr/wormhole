const sdk = @import("sdk");
const ifaces = &@import("interface.zig").ifaces;

const MeshBuilder = @This();

inline fn advancePtr(ptr: anytype, bytes: c_int) void {
    ptr.* = @ptrFromInt(@intFromPtr(ptr.*) + @as(usize, @intCast(bytes)));
}

desc: sdk.MeshDesc,
mesh: *sdk.IMesh,
render_ctx: *sdk.IMatRenderContext,
num_verts: u32,
num_indices: u32,
lines: bool,

cur_vert_data: struct {
    position: ?[*]f32,
    normal: ?[*]f32,
    color: ?[*]u8,
    tex_coord: [8]?[*]f32,
    tangent_s: ?[*]f32,
    tangent_t: ?[*]f32,
},

pub fn init(material: *sdk.IMaterial, lines: bool, max_verts: u32, max_indices: u32) MeshBuilder {
    const render_ctx = ifaces.IMaterialSystem.getRenderContext();
    render_ctx.beginRender();

    render_ctx.matrixMode(.projection);
    render_ctx.pushMatrix();
    render_ctx.loadMatrix(&sdk.VMatrix.scale(1, -1, 1));

    render_ctx.matrixMode(.model);
    render_ctx.pushMatrix();
    render_ctx.loadMatrix(&sdk.VMatrix.identity);

    render_ctx.matrixMode(.view);
    render_ctx.pushMatrix();
    render_ctx.loadMatrix(&sdk.VMatrix.identity);

    const mesh = render_ctx.getDynamicMesh(true, null, null, material);
    mesh.setPrimitiveType(if (lines) .lines else .triangles);

    var desc: sdk.MeshDesc = undefined;
    mesh.lockMesh(@intCast(max_verts), @intCast(max_indices), &desc, null);

    return MeshBuilder{
        .desc = desc,
        .mesh = mesh,
        .render_ctx = render_ctx,
        .num_verts = 0,
        .num_indices = 0,
        .lines = lines,
        .cur_vert_data = .{
            .position = desc.vertex.data.position,
            .normal = desc.vertex.data.normal,
            .color = desc.vertex.data.color,
            .tex_coord = desc.vertex.data.tex_coord,
            .tangent_s = desc.vertex.data.tangent_s,
            .tangent_t = desc.vertex.data.tangent_t,
        },
    };
}

pub fn finish(self: *MeshBuilder) void {
    self.mesh.unlockMesh(@intCast(self.num_verts), @intCast(self.num_indices), &self.desc);
    self.mesh.draw(-1, 0);

    self.render_ctx.matrixMode(.projection);
    self.render_ctx.popMatrix();

    self.render_ctx.matrixMode(.model);
    self.render_ctx.popMatrix();

    self.render_ctx.matrixMode(.view);
    self.render_ctx.popMatrix();

    self.render_ctx.endRender();
    _ = self.render_ctx.as(sdk.IRefCounted).release();
}

pub fn position(self: MeshBuilder, pos: sdk.Vector3D) void {
    self.cur_vert_data.position.?[0] = pos.x;
    self.cur_vert_data.position.?[1] = pos.y;
    self.cur_vert_data.position.?[2] = pos.z;
}

pub fn normal(self: MeshBuilder, vec: sdk.Vector3D) void {
    self.cur_vert_data.normal.?[0] = vec.x;
    self.cur_vert_data.normal.?[1] = vec.y;
    self.cur_vert_data.normal.?[2] = vec.z;
}

pub fn color(self: MeshBuilder, col: sdk.Color) void {
    self.cur_vert_data.color.?[0] = col.b;
    self.cur_vert_data.color.?[1] = col.g;
    self.cur_vert_data.color.?[2] = col.r;
    self.cur_vert_data.color.?[3] = col.a;
}

pub fn texCoord(self: MeshBuilder, stage: u8, s: f32, t: f32) void {
    self.cur_vert_data.tex_coord[stage].?[0] = s;
    self.cur_vert_data.tex_coord[stage].?[1] = t;
}

pub fn tangentS(self: MeshBuilder, vec: sdk.Vector3D) void {
    self.cur_vert_data.tangent_s.?[0] = vec.x;
    self.cur_vert_data.tangent_s.?[1] = vec.y;
    self.cur_vert_data.tangent_s.?[2] = vec.z;
}

pub fn tangentT(self: MeshBuilder, vec: sdk.Vector3D) void {
    self.cur_vert_data.tangent_t.?[0] = vec.x;
    self.cur_vert_data.tangent_t.?[1] = vec.y;
    self.cur_vert_data.tangent_t.?[2] = vec.z;
}

pub fn advanceVertex(self: *MeshBuilder) void {
    advancePtr(&self.cur_vert_data.position, self.desc.vertex.size.position);
    advancePtr(&self.cur_vert_data.normal, self.desc.vertex.size.normal);
    advancePtr(&self.cur_vert_data.color, self.desc.vertex.size.color);

    {
        comptime var i: u32 = 0;
        inline while (i < 8) : (i += 1) {
            advancePtr(&self.cur_vert_data.tex_coord[i], self.desc.vertex.size.tex_coord[i]);
        }
    }

    advancePtr(&self.cur_vert_data.tangent_s, self.desc.vertex.size.tangent_s);
    advancePtr(&self.cur_vert_data.tangent_t, self.desc.vertex.size.tangent_t);

    self.num_verts += 1;
}

pub fn index(self: *MeshBuilder, idx: u16) void {
    self.desc.index.data[self.num_indices] = @as(u16, @intCast(self.desc.vertex.first)) + idx;
    self.num_indices += 1;
}
