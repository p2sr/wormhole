const std = @import("std");
const sdk = @import("sdk");
const Wormhole = @import("Wormhole.zig");

pub fn getButton(btn: sdk.ButtonCode) bool {
    return Wormhole.getInst().interface_manager.ifaces.IInputSystem.isButtonDown(btn);
}

pub fn getCursorPos() [2]i32 {
    var x: c_int = undefined;
    var y: c_int = undefined;
    Wormhole.getInst().interface_manager.ifaces.IInputSystem.getCursorPosition(&x, &y);
    return .{ x, y };
}

pub fn setCursorPos(pos: [2]i32) void {
    Wormhole.getInst().interface_manager.ifaces.IInputSystem.setCursorPosition(pos[0], pos[1]);
}
