const std = @import("std");
const testing = std.testing;

const Unpacker = @import("unpacker.zig").Unpacker;
const DeserializeError = @import("unpacker.zig").DeserializeError;

test "Deserialize false" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc2",
        0,
    );
    try testing.expectEqual(
        false,
        try message.unpack_as(bool),
    );
}

test "Deserialize true" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc3",
        0,
    );
    try testing.expectEqual(
        true,
        try message.unpack_as(bool),
    );
}

test "Deserialize optional bool: true" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc3",
        0,
    );
    try testing.expectEqual(
        true,
        try message.unpack_as(?bool),
    );
}

test "Deserialize optional bool: null" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc0",
        0,
    );
    try testing.expectEqual(
        null,
        try message.unpack_as(?bool),
    );
}

test "Deserialize u7" {
    var message = try Unpacker.init(
        testing.allocator,
        "\x7F",
        0,
    );
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(u7),
    );
}

test "Deserialize u8" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcc\xEF",
        0,
    );
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(u8),
    );
}

test "Deserialize optional u8" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcc\xEF",
        0,
    );
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(?u8),
    );
}

test "Deserialize optional u8: null" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc0",
        0,
    );
    try testing.expectEqual(
        null,
        try message.unpack_as(?u8),
    );
}

test "Deserialize u16" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcd\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xBEEF,
        try message.unpack_as(u16),
    );
}

test "Deserialize u32" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xce\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xDEADBEEF,
        try message.unpack_as(u32),
    );
}

test "Deserialize u64" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xDEADBEEFDEADBEEF,
        try message.unpack_as(u64),
    );
}

test "Deserialize unsigned TypeTooSmall" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    const actual_error_union = message.unpack_as(u32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

test "Deserialize negative i6" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xEF",
        0,
    );
    try testing.expectEqual(
        -17,
        try message.unpack_as(i6),
    );
}

test "Deserialize one-byte positive i8" {
    var message = try Unpacker.init(
        testing.allocator,
        "\x7F",
        0,
    );
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(i8),
    );
}

test "Deserialize i8" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd0\xEF",
        0,
    );
    try testing.expectEqual(
        -17,
        try message.unpack_as(i8),
    );
}

test "Deserialize i9 from msgpack 8-bit uint" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcc\xFF",
        0,
    );
    try testing.expectEqual(
        0xFF,
        try message.unpack_as(i9),
    );
}

test "Deserialize i16" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd1\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -16657,
        try message.unpack_as(i16),
    );
}

test "Deserialize i32" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd2\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -559038737,
        try message.unpack_as(i32),
    );
}

test "Deserialize i64" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -2401053088876216593,
        try message.unpack_as(i64),
    );
}

test "Deserialize signed TypeTooSmall" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    const actual_error_union = message.unpack_as(i32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

test "Deserialize f64" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        @as(f64, @bitCast(@as(u64, 0xDEADBEEF_DEADBEEF))),
        try message.unpack_as(f64),
    );
}

test "Deserialize f32" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xca\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        @as(f32, @bitCast(@as(u32, 0xDEADBEEF))),
        try message.unpack_as(f32),
    );
}

test "Deserialize fixstr" {
    const val = "Hello, World!";
    var message = try Unpacker.init(
        testing.allocator,
        "\xAd" ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 8-bit length str" {
    const len = 0b0010_0000;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xd9" ++ .{len} ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 16-bit length str" {
    const len = 0x01_00;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xda\x01\x00" ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length str" {
    const len = 0x00_01_00_00;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xdb\x00\x01\x00\x00" ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 8-bit length bin" {
    const len = 0b0010_0000;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xc4" ++ .{len} ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 16-bit length bin" {
    const len = 0x01_00;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xc5\x01\x00" ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length bin" {
    const len = 0x00_01_00_00;
    const val = "t" ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xc6\x00\x01\x00\x00" ++ val,
        0,
    );
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize FixArray of i32" {
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    var message = try Unpacker.init(
        testing.allocator,
        "\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF",
        0,
    );
    const unpacked = try message.unpack_as([4]i32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize 16-bit array" {
    const len = 0b0001_0000;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        0,
    );
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length array" {
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        0,
    );
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}
