const std = @import("std");
const testing = std.testing;

const Unpacker = @import("unpacker.zig").Unpacker;
const DeserializeError = @import("unpacker.zig").DeserializeError;

test "Deserialize false" {
    const message = try Unpacker.init(
        "\xc2",
        0,
    );
    try testing.expectEqual(
        false,
        try message.unpack_as(bool),
    );
}

test "Deserialize true" {
    const message = try Unpacker.init(
        "\xc3",
        0,
    );
    try testing.expectEqual(
        true,
        try message.unpack_as(bool),
    );
}

test "Deserialize optional bool: true" {
    const message = try Unpacker.init(
        "\xc3",
        0,
    );
    try testing.expectEqual(
        true,
        try message.unpack_as(?bool),
    );
}

test "Deserialize optional bool: null" {
    const message = try Unpacker.init(
        "\xc0",
        0,
    );
    try testing.expectEqual(
        null,
        try message.unpack_as(?bool),
    );
}

test "Deserialize u7" {
    const message = try Unpacker.init(
        "\x7F",
        0,
    );
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(u7),
    );
}

test "Deserialize u8" {
    const message = try Unpacker.init(
        "\xcc\xEF",
        0,
    );
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(u8),
    );
}

test "Deserialize optional u8" {
    const message = try Unpacker.init(
        "\xcc\xEF",
        0,
    );
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(?u8),
    );
}

test "Deserialize optional u8: null" {
    const message = try Unpacker.init(
        "\xc0",
        0,
    );
    try testing.expectEqual(
        null,
        try message.unpack_as(?u8),
    );
}

test "Deserialize u16" {
    const message = try Unpacker.init(
        "\xcd\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xBEEF,
        try message.unpack_as(u16),
    );
}

test "Deserialize u32" {
    const message = try Unpacker.init(
        "\xce\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xDEADBEEF,
        try message.unpack_as(u32),
    );
}

test "Deserialize u64" {
    const message = try Unpacker.init(
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        0xDEADBEEFDEADBEEF,
        try message.unpack_as(u64),
    );
}

test "Deserialize unsigned TypeTooSmall" {
    const message = try Unpacker.init(
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
    const message = try Unpacker.init(
        "\xEF",
        0,
    );
    try testing.expectEqual(
        -17,
        try message.unpack_as(i6),
    );
}

test "Deserialize one-byte positive i8" {
    const message = try Unpacker.init(
        "\x7F",
        0,
    );
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(i8),
    );
}

test "Deserialize i8" {
    const message = try Unpacker.init(
        "\xd0\xEF",
        0,
    );
    try testing.expectEqual(
        -17,
        try message.unpack_as(i8),
    );
}

test "Deserialize i9 from msgpack 8-bit uint" {
    const message = try Unpacker.init(
        "\xcc\xFF",
        0,
    );
    try testing.expectEqual(
        0xFF,
        try message.unpack_as(i9),
    );
}

test "Deserialize i16" {
    const message = try Unpacker.init(
        "\xd1\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -16657,
        try message.unpack_as(i16),
    );
}

test "Deserialize i32" {
    const message = try Unpacker.init(
        "\xd2\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -559038737,
        try message.unpack_as(i32),
    );
}

test "Deserialize i64" {
    const message = try Unpacker.init(
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        -2401053088876216593,
        try message.unpack_as(i64),
    );
}

test "Deserialize signed TypeTooSmall" {
    const message = try Unpacker.init(
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
    const message = try Unpacker.init(
        "\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        @as(f64, @bitCast(@as(u64, 0xDEADBEEF_DEADBEEF))),
        try message.unpack_as(f64),
    );
}

test "Deserialize f32" {
    const message = try Unpacker.init(
        "\xca\xDE\xAD\xBE\xEF",
        0,
    );
    try testing.expectEqual(
        @as(f32, @bitCast(@as(u32, 0xDEADBEEF))),
        try message.unpack_as(f32),
    );
}
