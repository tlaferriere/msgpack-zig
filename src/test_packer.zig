const Packer = @import("packer.zig").Packer;
const SerializeError = @import("packer.zig").SerializeError;
const String = @import("packer.zig").String;

const std = @import("std");
const testing = std.testing;

test "Serialize u7 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u7 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize u32 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize i6 to 5-bit negative fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i6 = -32;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize i32 to 5-bit negative fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = -32;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize u8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u8 = 0x8F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test "Serialize u32 to uint8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0x8F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test Packer {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u16 = 0xBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32 to uint16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0xBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64 to uint32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u64 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u64 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u128 to uint64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u128 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize error TypeTooLarge" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u128 = 0xFDEADBEEFDEADBEEF;
    try testing.expectError(
        SerializeError.TypeTooLarge,
        packer.pack(val),
    );
}

test "Serialize i8 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i8 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\x7F",
        actual,
    );
}

test "Serialize i32 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\x7F",
        actual,
    );
}

test "Serialize i8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i8 = @bitCast(@as(u8, 0x80));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd0\x80",
        actual,
    );
}

test "Serialize i32 to int8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xFFFF_FF80));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd0\x80",
        actual,
    );
}

test "Serialize i16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i16 = @bitCast(@as(u16, 0xBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd1\xBE\xEF",
        actual,
    );
}

test "Serialize i32 to int16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xFFFFBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd1\xBE\xEF",
        actual,
    );
}

test "Serialize i32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd2\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize i64 to uint32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i64 = std.math.minInt(i32);
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd2\x80\x00\x00\x00",
        actual,
    );
}

test "Serialize i64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i64 = @bitCast(@as(u64, 0xDEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize i128 to uint64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i128 = @bitCast(@as(
        u128,
        0xFFFFFFFFFFFFFFFF_DEADBEEFDEADBEEF,
    ));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize error TypeTooLarge with int" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i128 = @bitCast(@as(
        u128,
        0xFFFFFFFFFFFFFFF0_DEADBEEFDEADBEEF,
    ));
    try testing.expectError(
        SerializeError.TypeTooLarge,
        packer.pack(val),
    );
}

test "Serialize true" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: bool = true;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc3",
        actual,
    );
}

test "Serialize false" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: bool = false;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc2",
        actual,
    );
}

test "Serialize null" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: ?i32 = null;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc0",
        actual,
    );
}

test "Serialize optional int" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: ?u32 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xce\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize optional bool" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: ?bool = true;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc3",
        actual,
    );
}

test "Serialize f32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: f32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xca\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize f64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: f64 = @bitCast(@as(u64, 0xDEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize fixstr" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "Hello, World!";
    try packer.pack(String(val));
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xAD" ++ val,
        actual,
    );
}

test "Serialize 8-bit length string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 32;
    try packer.pack(String(val));
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xd9" ++ .{32} ++ val,
        actual,
    );
}

test "Serialize 16-bit length string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 256;
    try packer.pack(String(val));
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xda\x01\x00" ++ val,
        actual,
    );
}

test "Serialize 32-bit length string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 65536;
    try packer.pack(String(val));
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xdb\x00\x01\x00\x00" ++ val,
        actual,
    );
}

test "Serialize 8-bit length binary string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 32;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc4" ++ .{32} ++ val,
        actual,
    );
}

test "Serialize 16-bit length binary string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 0x0100;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc5\x01\x00" ++ val,
        actual,
    );
}

test "Serialize 32-bit length binary string" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "t" ** 0x0001_0000;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xc6\x00\x01\x00\x00" ++ val,
        actual,
    );
}

test "Serialize FixArray" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF",
        actual,
    );
}

test "Serialize 16-bit length array" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const len = 0b0001_0000;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        actual,
    );
}

test "Serialize 32-bit length array" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        actual,
    );
}

test "Serialize slice to FixArray" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    try packer.pack(val[0..4]);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(
        "\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF",
        actual,
    );
}

// test "Serialize slice to 16-bit length array" {
//     var packer = try Packer.init(
//         testing.allocator,
//     );
//     const len = 0b0001_0000;
//     const val: [len]u32 = .{0xDEADBEEF} ** len;
//     try packer.pack(val[0..len]);
//     const actual = packer.finish();
//     defer testing.allocator.free(actual);
//     try testing.expectEqualStrings(
//         "\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
//         actual,
//     );
// }

// test "Serialize slice to 32-bit length array" {
//     var packer = try Packer.init(
//         testing.allocator,
//     );
//     const len = 0x00_01_00_00;
//     const val: [len]u32 = .{0xDEADBEEF} ** len;
//     try packer.pack(val[0..len]);
//     const actual = packer.finish();
//     defer testing.allocator.free(actual);
//     try testing.expectEqualStrings(
//         "\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
//         actual,
//     );
// }
