const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const DeserializeError = @import("unpacker.zig").DeserializeError;
const Repr = @import("root.zig").Repr;
const Timestamp = @import("root.zig").Timestamp;
const Unpacker = @import("unpacker.zig").Unpacker;

test "Deserialize false" {
    var r = std.Io.Reader.fixed("\xc2");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        false,
        try message.unpack_as(bool),
    );
}

test "Deserialize true" {
    var r = std.Io.Reader.fixed("\xc3");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        true,
        try message.unpack_as(bool),
    );
}

test "Deserialize optional bool: true" {
    var r = std.Io.Reader.fixed("\xc3");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        true,
        try message.unpack_as(?bool),
    );
}

test "Deserialize optional bool: null" {
    var r = std.Io.Reader.fixed("\xc0");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        null,
        try message.unpack_as(?bool),
    );
}

test "Deserialize u7" {
    var r = std.Io.Reader.fixed("\x7F");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(u7),
    );
}

test "Deserialize u8" {
    var r = std.Io.Reader.fixed("\xcc\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(u8),
    );
}

test "Deserialize optional u8" {
    var r = std.Io.Reader.fixed("\xcc\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(?u8),
    );
}

test "Deserialize optional u8: null" {
    var r = std.Io.Reader.fixed("\xc0");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        null,
        try message.unpack_as(?u8),
    );
}

test "Deserialize u16" {
    var r = std.Io.Reader.fixed("\xcd\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xBEEF,
        try message.unpack_as(u16),
    );
}

test "Deserialize u32" {
    var r = std.Io.Reader.fixed("\xce\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xDEADBEEF,
        try message.unpack_as(u32),
    );
}

test "Deserialize u64" {
    var r = std.Io.Reader.fixed("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xDEADBEEFDEADBEEF,
        try message.unpack_as(u64),
    );
}

test "Deserialize unsigned TypeTooSmall" {
    var r = std.Io.Reader.fixed("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    const actual_error_union = message.unpack_as(u32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

test "Deserialize negative i6" {
    var r = std.Io.Reader.fixed("\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -17,
        try message.unpack_as(i6),
    );
}

test "Deserialize one-byte positive i8" {
    var r = std.Io.Reader.fixed("\x7F");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(i8),
    );
}

test "Deserialize i8" {
    var r = std.Io.Reader.fixed("\xd0\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -17,
        try message.unpack_as(i8),
    );
}

test "Deserialize i9 from msgpack 8-bit uint" {
    var r = std.Io.Reader.fixed("\xcc\xFF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0xFF,
        try message.unpack_as(i9),
    );
}

test "Deserialize i16" {
    var r = std.Io.Reader.fixed("\xd1\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -16657,
        try message.unpack_as(i16),
    );
}

test "Deserialize i32" {
    var r = std.Io.Reader.fixed("\xd2\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -559038737,
        try message.unpack_as(i32),
    );
}

test "Deserialize i64" {
    var r = std.Io.Reader.fixed("\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -2401053088876216593,
        try message.unpack_as(i64),
    );
}

test "Deserialize signed TypeTooSmall" {
    var r = std.Io.Reader.fixed("\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    const actual_error_union = message.unpack_as(i32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

// Found by fuzzing: whether a value fits was decided from the width of the
// encoding rather than from the value, so a small uint64 was rejected for any
// target narrower than 64 bits.
test "Deserialize u33 from uint64" {
    var r = std.Io.Reader.fixed("\xcf\x00\x00\x00\x01\x00\x00\x00\x01");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0x1_00000001,
        try message.unpack_as(u33),
    );
}

test "Deserialize i63 from uint64" {
    var r = std.Io.Reader.fixed("\xcf\x00\x00\x00\x01\x00\x00\x00\x01");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        0x1_00000001,
        try message.unpack_as(i63),
    );
}

// Same root cause, opposite direction: a negative int8 widened into an i64 was
// read as an unsigned byte, silently turning -17 into 239.
test "Deserialize i64 from int8" {
    var r = std.Io.Reader.fixed("\xd0\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -17,
        try message.unpack_as(i64),
    );
}

test "Deserialize i64 from int16" {
    var r = std.Io.Reader.fixed("\xd1\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        -16657,
        try message.unpack_as(i64),
    );
}

// A uint64 past maxInt(i64) was reinterpreted as a negative i64 instead of
// being reported as too large.
test "Deserialize i64 from uint64 out of range" {
    var r = std.Io.Reader.fixed("\xcf\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.TypeTooSmall,
        message.unpack_as(i64),
    );
}

// A positive fixint always fits the marker, but not necessarily the target
// type: the @intCast panicked instead of reporting TypeTooSmall.
test "Deserialize u1 from positive fixint out of range" {
    var r = std.Io.Reader.fixed("\x7F");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.TypeTooSmall,
        message.unpack_as(u1),
    );
}

test "Deserialize i2 from negative fixint out of range" {
    var r = std.Io.Reader.fixed("\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.TypeTooSmall,
        message.unpack_as(i2),
    );
}

test "Deserialize f64" {
    var r = std.Io.Reader.fixed("\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        @as(f64, @bitCast(@as(u64, 0xDEADBEEF_DEADBEEF))),
        try message.unpack_as(f64),
    );
}

test "Deserialize f32" {
    var r = std.Io.Reader.fixed("\xca\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(
        @as(f32, @bitCast(@as(u32, 0xDEADBEEF))),
        try message.unpack_as(f32),
    );
}

test "Deserialize fixstr" {
    const val = "Hello, World!";
    var r = std.Io.Reader.fixed("\xAd" ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xd9" ++ .{len} ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xda\x01\x00" ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xdb\x00\x01\x00\x00" ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xc4" ++ .{len} ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xc5\x01\x00" ++ val);
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xc6\x00\x01\x00\x00" ++ val);
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "Deserialize FixArray of i32" {
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    var r = std.Io.Reader.fixed("\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF");
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([4]i32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize 16-bit array" {
    const len = 0b0001_0000;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    var r = std.Io.Reader.fixed("\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len));
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize 32-bit length array" {
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    var r = std.Io.Reader.fixed("\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len));
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize slice as FixArray of i32" {
    const val: []const i32 = &.{ 0x0EADBEEF, 32, 0, -1 };
    var r = std.Io.Reader.fixed("\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF");
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len));
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len));
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([]u32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixMap" {
    var r = std.Io.Reader.fixed("\x83\xA4key1\xd2\x0E\xAD\xBE\xEF\xA4key2\x20\xA4key3\xFF");
    var message = Unpacker.init(testing.allocator, &r);
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
    var r = std.Io.Reader.fixed("\xd4\x71\xFF");
    var message = Unpacker.init(testing.allocator, &r);

    const unpacked = message.unpack_as(MyType);
    try testing.expectError(
        MyDeserializeError.OhNo,
        unpacked,
    );
}

test "Deserialize FixExt_1 wrong type id" {
    var r = std.Io.Reader.fixed("\xd4\x01\xFF");
    var message = Unpacker.init(testing.allocator, &r);

    const unpacked = message.unpack_as(MyType);
    try testing.expectError(
        DeserializeError.WrongExtType,
        unpacked,
    );
}

test "Deserialize FixExt_1 right type" {
    var r = std.Io.Reader.fixed("\xd4\x71\xEF");
    var message = Unpacker.init(testing.allocator, &r);

    const val = MyType{ .buf = "\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_2 right type" {
    var r = std.Io.Reader.fixed("\xd5\x71\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

    const val = MyType{ .buf = "\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_4 right type" {
    var r = std.Io.Reader.fixed("\xd6\x71\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_8 right type" {
    var r = std.Io.Reader.fixed("\xd7\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize FixExt_16 right type" {
    var r = std.Io.Reader.fixed("\xd8\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

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
    var r = std.Io.Reader.fixed("\xc7\xFF\x71" ++ content);
    var message = Unpacker.init(testing.allocator, &r);

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
    var r = std.Io.Reader.fixed("\xc8\xFF\xFF\x71" ++ content);
    var message = Unpacker.init(testing.allocator, &r);

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
    var r = std.Io.Reader.fixed("\xc9\x00\x01\x00\x00\x71" ++ content);
    var message = Unpacker.init(testing.allocator, &r);

    const val = MyType{ .buf = content };
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "Deserialize Timestamp 32" {
    var r = std.Io.Reader.fixed("\xd6\xFF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

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
    var r = std.Io.Reader.fixed("\xd7\xFF\x00\x00\x00\x04\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

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
    var r = std.Io.Reader.fixed("\xc7\x0C\xFF\x00\x00\x00\x01\x0E\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    var message = Unpacker.init(testing.allocator, &r);

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

// Nightly fuzzing hit this in `fuzz unpack scalars`:
//
//     thread 2353 panic: integer does not fit in destination type
//     src/root.zig:101:13: in unpack_ext
//
// Both decode paths check the spec's `nanoseconds <= 999_999_999` rule and then
// cast the value into the struct's field, which is narrower than the rule: the
// whole range 536_870_912 ..= 999_999_999 clears the check and dies on the cast.
// These are timestamps msgpack considers well-formed.
//
// The expectations go through a `u32` local because the field cannot hold the
// value being asserted — writing it as a struct literal would fail to compile
// instead of reproducing the panic.

// 64-bit encoding: payload is `(nanoseconds << 34) | seconds`, and
// 999_999_999 << 34 is 0xEE6B27FC_00000000.
test "Deserialize Timestamp 64 at the maximum legal nanoseconds" {
    var r = std.Io.Reader.fixed("\xd7\xFF\xEE\x6B\x27\xFC\x00\x00\x00\x00");
    var message = Unpacker.init(testing.allocator, &r);

    const expected_nanoseconds: u32 = 999_999_999;
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqual(expected_nanoseconds, unpacked.nanoseconds);
    try testing.expectEqual(@as(i64, 0), unpacked.seconds);
}

// 96-bit encoding, where nanoseconds get a 32-bit field of their own ahead of
// the 64-bit seconds.
test "Deserialize Timestamp 96 at the maximum legal nanoseconds" {
    var r = std.Io.Reader.fixed("\xc7\x0C\xFF\x3B\x9A\xC9\xFF" ++ "\x00" ** 8);
    var message = Unpacker.init(testing.allocator, &r);

    const expected_nanoseconds: u32 = 999_999_999;
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqual(expected_nanoseconds, unpacked.nanoseconds);
    try testing.expectEqual(@as(i64, 0), unpacked.seconds);
}

// The other side of the boundary. Both wire fields are wider than the spec's
// limit, so a decoder has to reject the excess rather than truncate it — and
// with the field widened, "reject" is now the only thing separating these from
// the two tests above.
test "Deserialize Timestamp 64 over the nanosecond limit" {
    var r = std.Io.Reader.fixed("\xd7\xFF\xEE\x6B\x28\x00\x00\x00\x00\x00");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        Timestamp.Error.TooManyNanoseconds,
        message.unpack_as(Timestamp),
    );
}

test "Deserialize Timestamp 96 over the nanosecond limit" {
    var r = std.Io.Reader.fixed("\xc7\x0C\xFF\x3B\x9A\xCA\x00" ++ "\x00" ** 8);
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        Timestamp.Error.TooManyNanoseconds,
        message.unpack_as(Timestamp),
    );
}

test "OOB: string with length exceeding buffer" {
    // A single byte 0xa1 = FixStr with declared length 1.
    // The unpacker advances offset to 1, then tries to @memcpy
    // buffer[1..2] — but the buffer is only 1 byte.
    // Before the fix, this panics with index-out-of-bounds.
    // After the fix, it returns DeserializeError.Finished.
    var r = std.Io.Reader.fixed("\xa1");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str8 with bogus length" {
    // Str8 marker (0xd9) + length byte 0xff = 255-byte string,
    // but only 2 bytes of input total.
    var r = std.Io.Reader.fixed("\xd9\xff");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str32 with huge length" {
    // Str32 marker (0xdb) + 4-byte big-endian length 0x0000ffff = 65535,
    // but only 5 bytes of input total.
    var r = std.Io.Reader.fixed("\xdb\x00\x00\xff\xff");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str16 slice panics before bounds check (repro: index 3, len 2)" {
    // Str16 marker (0xda) + only 1 extra byte = 2 bytes total.
    // The unpacker creates buffer[1..3] before checking if 3 bytes exist,
    // causing an index-out-of-bounds panic.
    var r = std.Io.Reader.fixed("\xda\x00");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str16 with only 1 byte total" {
    // Str16 marker alone — not even the first length byte is present.
    var r = std.Io.Reader.fixed("\xda");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Bin16 slice panics before bounds check" {
    // Bin16 marker (0xc5) + only 1 extra byte = 2 bytes total.
    var r = std.Io.Reader.fixed("\xc5\x00");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Str32 with short buffer panics before bounds check" {
    // Str32 marker (0xdb) + only 1 extra byte = 2 bytes total.
    // The unpacker creates buffer[1..5] before checking, causing OOB.
    var r = std.Io.Reader.fixed("\xdb\x00");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Bin32 with short buffer panics before bounds check" {
    // Bin32 marker (0xc6) + only 1 extra byte = 2 bytes total.
    var r = std.Io.Reader.fixed("\xc6\x00");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "OOB: Int8 with 1-byte buffer" {
    // Int8 marker (0xd0) but no data byte.
    var r = std.Io.Reader.fixed("\xd0");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(i8) catch {};
}

test "OOB: Uint8 with 1-byte buffer" {
    // Uint8 marker (0xcc) but no data byte.
    var r = std.Io.Reader.fixed("\xcc");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(u8) catch {};
}

test "OOB: Int16 with 2-byte buffer" {
    // Int16 marker (0xd1) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xd1\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(i16) catch {};
}

test "OOB: Uint16 with 2-byte buffer" {
    // Uint16 marker (0xcd) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xcd\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(u16) catch {};
}

test "OOB: Int32 with 2-byte buffer" {
    // Int32 marker (0xd2) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xd2\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(i32) catch {};
}

test "OOB: Uint32 with 2-byte buffer" {
    // Uint32 marker (0xce) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xce\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(u32) catch {};
}

test "OOB: Int64 with 2-byte buffer" {
    // Int64 marker (0xd3) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xd3\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(i64) catch {};
}

test "OOB: Uint64 with 2-byte buffer" {
    // Uint64 marker (0xcf) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xcf\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(u64) catch {};
}

test "OOB: Float32 with 2-byte buffer" {
    // Float32 marker (0xca) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xca\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(f32) catch {};
}

test "OOB: Float64 with 2-byte buffer" {
    // Float64 marker (0xcb) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xcb\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(f64) catch {};
}

test "OOB: FixArray with short buffer" {
    // FixArray of length 1 (0x91) but no element data.
    var r = std.Io.Reader.fixed("\x91");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: Array16 with 2-byte buffer" {
    // Array16 marker (0xdc) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xdc\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: Array32 with 2-byte buffer" {
    // Array32 marker (0xdd) + only 1 extra byte.
    var r = std.Io.Reader.fixed("\xdd\x00");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([]u8) catch {};
}

test "OOB: empty buffer" {
    // Empty input — the fuzzer already guards against this, but the
    // unpacker should handle it gracefully too.
    var r = std.Io.Reader.fixed("");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(u8) catch {};
}

// Found by fuzzing: `unpack_array` allocated the element buffer, then let a
// failing element read propagate without freeing it.
test "Leak: array truncated before its last element" {
    // FixArray of 2 (0x92) but only one element follows.
    var r = std.Io.Reader.fixed("\x92\x01");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([]u32) catch {};
}

test "Leak: array of strings truncated before its last element" {
    // FixArray of 2 (0x92), one FixStr "a", then nothing: the outer buffer and
    // the already-unpacked string both leaked.
    var r = std.Io.Reader.fixed("\x92\xa1a");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([][]const u8) catch {};
}

// Found by fuzzing: `unpack_map` reserved capacity, then let a failing entry
// read propagate, stranding the map's own allocation.
test "Leak: map truncated before its value" {
    // FixMap of 1 (0x81) with a key but no value.
    var r = std.Io.Reader.fixed("\x81\x01");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(std.array_hash_map.Auto(u32, u32)) catch {};
}

test "Leak: map with string keys truncated before its value" {
    // Same, but the key allocation leaked too since it never reached the map.
    var r = std.Io.Reader.fixed("\x81\xa1a");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as(std.array_hash_map.String(u32)) catch {};
}

// Same class of leak as the slice case, on the fixed-size path: the elements
// unpacked before the failure were never released.
test "Leak: fixed-size array truncated before its last element" {
    // FixArray of 2 (0x92), one FixStr "a", then nothing.
    var r = std.Io.Reader.fixed("\x92\xa1a");
    var message = Unpacker.init(testing.allocator, &r);
    _ = message.unpack_as([2][]const u8) catch {};
}

// Found by fuzzing: a declared length was used as an allocation size before any
// of the payload had been seen, so a 5-byte header could demand tens of
// gigabytes and get the process OOM-killed.
//
// These run against `testing.failing_allocator` rather than `testing.allocator`
// on purpose. None of these messages contains anything legitimate to allocate,
// so before the fix the oversized request is the very first allocation and comes
// back as `error.OutOfMemory` instead of taking the test runner down with it.
// After the fix the budget rejects the header before any allocator is touched,
// which is exactly what `expectError(MessageTooLong, ...)` pins down.

test "Bounded: map header declaring more entries than the budget allows" {
    // The exact input the fuzzer found: Map_32 (0xdf) declaring 2_790_458_596
    // entries, which at 8 bytes per u32/u32 pair is over 20 GiB.
    var r = std.Io.Reader.fixed("\xdf\xa6\x54\xf8\xe4");
    var message = Unpacker.init(testing.failing_allocator, &r);
    try testing.expectError(
        DeserializeError.MessageTooLong,
        message.unpack_as(std.array_hash_map.Auto(u32, u32)),
    );
}

test "Bounded: array header declaring more elements than the budget allows" {
    // Array_32 (0xdd) of 0xFFFFFFFF u64s — 32 GiB.
    var r = std.Io.Reader.fixed("\xdd\xff\xff\xff\xff");
    var message = Unpacker.init(testing.failing_allocator, &r);
    try testing.expectError(
        DeserializeError.MessageTooLong,
        message.unpack_as([]u64),
    );
}

test "Bounded: string header declaring more bytes than the budget allows" {
    // Str_32 (0xdb) declaring 4 GiB of payload, with none of it present.
    var r = std.Io.Reader.fixed("\xdb\xff\xff\xff\xff");
    var message = Unpacker.init(testing.failing_allocator, &r);
    try testing.expectError(
        DeserializeError.MessageTooLong,
        message.unpack_as([]const u8),
    );
}

test "Bounded: ext header declaring more bytes than the budget allows" {
    // Ext_32 (0xc9) declaring 4 GiB, type id 0x71, no payload.
    var r = std.Io.Reader.fixed("\xc9\xff\xff\xff\xff\x71");
    var message = Unpacker.init(testing.failing_allocator, &r);
    try testing.expectError(
        DeserializeError.MessageTooLong,
        message.unpack_as(MyType),
    );
}

// The point of growing from delivered bytes rather than the declared length: a
// header can claim a size that is under the budget and still unbacked, and that
// must cost only what the stream actually holds. Str_32 declaring 60 MiB with a
// handful of bytes behind it used to mean a 60 MiB allocation; now it is a small
// allocation, a short read and `Finished`. `testing.allocator` failing the run on
// a leak is what pins the cleanup.
test "Bounded: string declaring far more than it delivers costs only what arrives" {
    // 0xdb = Str_32, 0x03C00000 = 62_914_560 bytes declared, 8 bytes present.
    var r = std.Io.Reader.fixed("\xdb\x03\xC0\x00\x00" ++ "abcdefgh");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        DeserializeError.Finished,
        message.unpack_as([]const u8),
    );
}

test "Bounded: array declaring far more elements than it delivers" {
    // Array_32 of 1_000_000 u32s, with two elements actually present.
    var r = std.Io.Reader.fixed("\xdd\x00\x0F\x42\x40" ++ "\x01\x02");
    var message = Unpacker.init(testing.allocator, &r);
    try testing.expectError(
        error.EndOfStream,
        message.unpack_as([]u32),
    );
}

// The exact-size reserve below `max_prealloc_bytes` is load-bearing, not a
// nicety: without it the decode would allocate the payload, then grow capacity
// past it and memcpy, on every string. Pinning that is what this test is for —
// the arena holds the payload and little else, so a decode that grew beyond the
// declared length would run out of memory instead of passing.
test "Bounded: a value under the reserve cap decodes in one exact allocation" {
    const len = 4096;
    const payload = "z" ** len;
    // 0xdb = Str_32, then the length, then exactly that many bytes.
    var r = std.Io.Reader.fixed("\xdb\x00\x00\x10\x00" ++ payload);

    var scratch: [len + 64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    var message = Unpacker.init(fba.allocator(), &r);
    const unpacked = try message.unpack_as([]const u8);
    try testing.expectEqualStrings(payload, unpacked);
}

// `list.append(gpa, x)` is `ensureUnusedCapacity(gpa, 1)` plus an assignment, so
// the split below looks redundant. It is not, and the difference is argument
// evaluation order: `append(gpa, try unpack_value(Child))` decodes the element
// *before* reserving room for it, so an `OutOfMemory` from the growth drops an
// element that already owns heap memory. Reserving first makes the append
// infallible and the element's ownership transfer unconditional.
//
// This walks every allocation failure point of a decode whose elements own
// memory, and reports leaked bytes if any of them strands one.
test "Bounded: growing a slice of owning elements leaks nothing on failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn decode(allocator: std.mem.Allocator) !void {
            // FixArray of three 4-byte FixStrs.
            var r = std.Io.Reader.fixed("\x93" ++ "\xa4aaaa" ++ "\xa4bbbb" ++ "\xa4cccc");
            // A reserve too small for even one element forces the list to grow
            // mid-decode, which is where the interesting failures land.
            var message = Unpacker.initWithOptions(allocator, &r, .{ .max_prealloc_bytes = 1 });
            const unpacked = try message.unpack_as([][]const u8);
            defer {
                for (unpacked) |element| allocator.free(element);
                allocator.free(unpacked);
            }
            try testing.expectEqual(@as(usize, 3), unpacked.len);
        }
    }.decode, .{});
}
