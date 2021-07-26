const sdk = @import("sdk");

pub const Edict = extern struct {
    state_flags: c_int,
    network_serial_number: c_int,
    networkable: *sdk.IServerNetworkable,
    unk: *sdk.IServerUnknown,
};
