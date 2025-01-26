//! Integration tests for the msgpack module.
const msgpack = @import("msgpack");
const std = @import("std");

const testing = std.testing;

test "u7 round-trip" {
    var packer_ = try msgpack.Packer.init(
        testing.allocator,
    );
    const val: u7 = 0x7F;
    try packer_.pack(val);
    const packed_message = packer_.finish();
    defer testing.allocator.free(packed_message);

    const message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
    );
    defer message.deinit();
    try testing.expectEqual(val, try message.unpack_as(u7));
}
