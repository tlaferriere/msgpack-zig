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

    var message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
        0,
    );
    try testing.expectEqual(val, try message.unpack_as(u7));
}

test "i8 round-trip" {
    var packer_ = try msgpack.Packer.init(
        testing.allocator,
    );
    const val: i8 = 0x7F;
    try packer_.pack(val);
    const packed_message = packer_.finish();
    defer testing.allocator.free(packed_message);

    var message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
        0,
    );
    try testing.expectEqual(val, try message.unpack_as(i8));
}

test "null round-trip" {
    var packer_ = try msgpack.Packer.init(
        testing.allocator,
    );
    const val: ?i8 = null;
    try packer_.pack(val);
    const packed_message = packer_.finish();
    defer testing.allocator.free(packed_message);

    var message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
        0,
    );
    try testing.expectEqual(val, try message.unpack_as(?i8));
}

test "optional bool round-trip" {
    var packer_ = try msgpack.Packer.init(
        testing.allocator,
    );
    const val: ?bool = true;
    try packer_.pack(val);
    const packed_message = packer_.finish();
    defer testing.allocator.free(packed_message);

    var message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
        0,
    );
    try testing.expectEqual(val, try message.unpack_as(?bool));
}

test "float round-trip" {
    var packer_ = try msgpack.Packer.init(
        testing.allocator,
    );
    const val: f32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer_.pack(val);
    const packed_message = packer_.finish();
    defer testing.allocator.free(packed_message);

    var message = try msgpack.Unpacker.init(
        testing.allocator,
        packed_message,
        0,
    );
    try testing.expectEqual(val, try message.unpack_as(f32));
}

test "Deserialize 32-bit length bin round_trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const val = "t" ** 0x0001_0000;
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length string round_trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const val = "t" ** 0x0001_0000;
    try packer.pack(msgpack.String(val));
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length array round_trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}
