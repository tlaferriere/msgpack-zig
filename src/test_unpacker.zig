const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const DeserializeError = @import("unpacker.zig").DeserializeError;
const Repr = @import("root.zig").Repr;
const Timestamp = @import("root.zig").Timestamp;
const Unpacker = @import("unpacker.zig").Unpacker;

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

test "Deserialize slice as FixArray of i32" {
    const val: []const i32 = &.{ 0x0EADBEEF, 32, 0, -1 };
    var message = try Unpacker.init(
        testing.allocator,
        "\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF",
        0,
    );
    const unpacked = try message.unpack_as([]i32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize slice as 16-bit array" {
    const len = 0b0001_0000;
    const val = &[_]u32{0xDEADBEEF} ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        0,
    );
    const unpacked = try message.unpack_as([]u32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize slice as 32-bit length array" {
    const len = 0x00_01_00_00;
    const val = &[_]u32{0xDEADBEEF} ** len;
    var message = try Unpacker.init(
        testing.allocator,
        "\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len),
        0,
    );
    const unpacked = try message.unpack_as([]u32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixMap" {
    var message = try Unpacker.init(
        testing.allocator,
        "\x83\xA4key1\xd2\x0E\xAD\xBE\xEF\xA4key2\x20\xA4key3\xFF",
        0,
    );
    var val: std.array_hash_map.String(i32) = .empty;
    defer val.deinit(testing.allocator);
    try val.put(testing.allocator, "key1", 0x0EADBEEF);
    try val.put(testing.allocator, "key2", 32);
    try val.put(testing.allocator, "key3", -1);
    var unpacked = try message.unpack_as(std.array_hash_map.String(i32));
    defer {
        for (unpacked.keys()) |key| {
            testing.allocator.free(key);
        }
        unpacked.deinit(testing.allocator);
    }
    try testing.expectEqualDeep(
        val.keys(),
        unpacked.keys(),
    );
    try testing.expectEqualDeep(
        val.values(),
        unpacked.values(),
    );
}

const MyDeserializeError = error{OhNo};
const MyType = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = Repr{ .ext = 0x71 };
        pub fn unpack_ext(allocator: std.mem.Allocator, data: []const u8) !MyType {
            errdefer allocator.free(data);
            for (data) |b| {
                if (b == 0xFF) {
                    return MyDeserializeError.OhNo;
                }
            }
            return MyType{ .buf = data };
        }
    };
};

test "Deserialize FixExt_1 callback error" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd4\x71\xFF",
        0,
    );

    const unpacked = message.unpack_as(MyType);
    try testing.expectError(
        MyDeserializeError.OhNo,
        unpacked,
    );
}

test "Deserialize FixExt_1 wrong type id" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd4\x01\xFF",
        0,
    );

    const unpacked = message.unpack_as(MyType);
    try testing.expectError(
        DeserializeError.WrongExtType,
        unpacked,
    );
}

test "Deserialize FixExt_1 right type" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd4\x71\xEF",
        0,
    );

    const val = MyType{ .buf = "\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_2 right type" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd5\x71\xBE\xEF",
        0,
    );

    const val = MyType{ .buf = "\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_4 right type" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd6\x71\xDE\xAD\xBE\xEF",
        0,
    );

    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_8 right type" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd7\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );

    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_16 right type" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd8\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );

    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Ext_8 right type" {
    const len = 255;
    const content = ("\xDE" ** len);
    var message = try Unpacker.init(
        testing.allocator,
        "\xc7\xFF\x71" ++ content,
        0,
    );

    const val = MyType{ .buf = content };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Ext_16 right type" {
    const len = 0xFF_FF;
    const content = ("\xDE" ** len);
    var message = try Unpacker.init(
        testing.allocator,
        "\xc8\xFF\xFF\x71" ++ content,
        0,
    );

    const val = MyType{ .buf = content };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Ext_32 right type" {
    const len = 0x00_01_00_00;
    const content = ("\xDE" ** len);
    var message = try Unpacker.init(
        testing.allocator,
        "\xc9\x00\x01\x00\x00\x71" ++ content,
        0,
    );

    const val = MyType{ .buf = content };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Timestamp 32" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd6\xFF\xDE\xAD\xBE\xEF",
        0,
    );

    const val = Timestamp{
        .nanoseconds = 0,
        .seconds = 0xDEADBEEF,
    };
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Timestamp 64" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xd7\xFF\x00\x00\x00\x04\xDE\xAD\xBE\xEF",
        0,
    );

    const val = Timestamp{
        .nanoseconds = 1,
        .seconds = 0xDEADBEEF,
    };
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Timestamp 96" {
    var message = try Unpacker.init(
        testing.allocator,
        "\xc7\x0C\xFF\x00\x00\x00\x01\x0E\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        0,
    );

    const val = Timestamp{
        .nanoseconds = 1,
        .seconds = 0x0EADBEEFDEADBEEF,
    };
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "OOB: string with length exceeding buffer" {
    // A single byte 0xa1 = FixStr with declared length 1.
    // The unpacker advances offset to 1, then tries to @memcpy
    // buffer[1..2] — but the buffer is only 1 byte.
    // Before the fix, this panics with index-out-of-bounds.
    // After the fix, it returns DeserializeError.Finished.
    var message = try Unpacker.init(testing.allocator, "\xa1", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str8 with bogus length" {
    // Str8 marker (0xd9) + length byte 0xff = 255-byte string,
    // but only 2 bytes of input total.
    var message = try Unpacker.init(testing.allocator, "\xd9\xff", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str32 with huge length" {
    // Str32 marker (0xdb) + 4-byte big-endian length 0x0000ffff = 65535,
    // but only 5 bytes of input total.
    var message = try Unpacker.init(testing.allocator, "\xdb\x00\x00\xff\xff", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str16 slice panics before bounds check (repro: index 3, len 2)" {
    // Str16 marker (0xda) + only 1 extra byte = 2 bytes total.
    // The unpacker creates buffer[1..3] before checking if 3 bytes exist,
    // causing an index-out-of-bounds panic.
    var message = try Unpacker.init(testing.allocator, "\xda\x00", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str16 with only 1 byte total" {
    // Str16 marker alone — not even the first length byte is present.
    var message = try Unpacker.init(testing.allocator, "\xda", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Bin16 slice panics before bounds check" {
    // Bin16 marker (0xc5) + only 1 extra byte = 2 bytes total.
    var message = try Unpacker.init(testing.allocator, "\xc5\x00", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str32 with short buffer panics before bounds check" {
    // Str32 marker (0xdb) + only 1 extra byte = 2 bytes total.
    // The unpacker creates buffer[1..5] before checking, causing OOB.
    var message = try Unpacker.init(testing.allocator, "\xdb\x00", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Bin32 with short buffer panics before bounds check" {
    // Bin32 marker (0xc6) + only 1 extra byte = 2 bytes total.
    var message = try Unpacker.init(testing.allocator, "\xc6\x00", 0);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Int8 with 1-byte buffer" {
    // Int8 marker (0xd0) but no data byte.
    var message = try Unpacker.init(testing.allocator, "\xd0", 0);
    _ = message.unpack_as(i8) catch {};
}

test "OOB: Uint8 with 1-byte buffer" {
    // Uint8 marker (0xcc) but no data byte.
    var message = try Unpacker.init(testing.allocator, "\xcc", 0);
    _ = message.unpack_as(u8) catch {};
}

test "OOB: Int16 with 2-byte buffer" {
    // Int16 marker (0xd1) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xd1\x00", 0);
    _ = message.unpack_as(i16) catch {};
}

test "OOB: Uint16 with 2-byte buffer" {
    // Uint16 marker (0xcd) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xcd\x00", 0);
    _ = message.unpack_as(u16) catch {};
}

test "OOB: Int32 with 2-byte buffer" {
    // Int32 marker (0xd2) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xd2\x00", 0);
    _ = message.unpack_as(i32) catch {};
}

test "OOB: Uint32 with 2-byte buffer" {
    // Uint32 marker (0xce) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xce\x00", 0);
    _ = message.unpack_as(u32) catch {};
}

test "OOB: Int64 with 2-byte buffer" {
    // Int64 marker (0xd3) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xd3\x00", 0);
    _ = message.unpack_as(i64) catch {};
}

test "OOB: Uint64 with 2-byte buffer" {
    // Uint64 marker (0xcf) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xcf\x00", 0);
    _ = message.unpack_as(u64) catch {};
}

test "OOB: Float32 with 2-byte buffer" {
    // Float32 marker (0xca) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xca\x00", 0);
    _ = message.unpack_as(f32) catch {};
}

test "OOB: Float64 with 2-byte buffer" {
    // Float64 marker (0xcb) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xcb\x00", 0);
    _ = message.unpack_as(f64) catch {};
}

test "OOB: FixArray with short buffer" {
    // FixArray of length 1 (0x91) but no element data.
    var message = try Unpacker.init(testing.allocator, "\x91", 0);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: Array16 with 2-byte buffer" {
    // Array16 marker (0xdc) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xdc\x00", 0);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: Array32 with 2-byte buffer" {
    // Array32 marker (0xdd) + only 1 extra byte.
    var message = try Unpacker.init(testing.allocator, "\xdd\x00", 0);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: empty buffer" {
    // Empty input — the fuzzer already guards against this, but the
    // unpacker should handle it gracefully too.
    var message = try Unpacker.init(testing.allocator, "", 0);
    _ = message.unpack_as(u8) catch {};
}
