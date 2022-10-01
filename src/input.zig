const std = @import("std");
const sdk = @import("sdk");
const ifaces = &@import("interface.zig").ifaces;

pub fn getButton(btn: sdk.ButtonCode) bool {
    return ifaces.IInputSystem.isButtonDown(btn);
}

pub fn getCursorPos() [2]i32 {
    var x: c_int = undefined;
    var y: c_int = undefined;
    ifaces.IInputSystem.getCursorPosition(&x, &y);
    return .{ x, y };
}

pub fn setCursorPos(pos: [2]i32) void {
    ifaces.IInputSystem.setCursorPosition(pos[0], pos[1]);
}
