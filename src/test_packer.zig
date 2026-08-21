const std = @import("std");
const testing = std.testing;

const Bin = @import("packer.zig").Bin;
const Packer = @import("packer.zig").Packer;
const Repr = @import("root.zig").Repr;
const SerializeError = @import("packer.zig").SerializeError;
const Timestamp = @import("root.zig").Timestamp;
const Unpacker = @import("unpacker.zig").Unpacker;

test "Serialize u7 to 7-bit positive fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u7 = 0x7F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize u32 to 7-bit positive fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u32 = 0x7F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize i6 to 5-bit negative fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i6 = -32;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize i32 to 5-bit negative fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i32 = -32;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize u8" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u8 = 0x8F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test "Serialize u32 to uint8" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u32 = 0x8F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test Packer {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u16 = 0xBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32 to uint16" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u32 = 0xBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u32 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64 to uint32" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u64 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u64 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u128 to uint64" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u128 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize error IntTooLarge" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: u128 = 0xFDEADBEEFDEADBEEF;
    try testing.expectError(
        SerializeError.IntTooLarge,
        packer.pack(val),
    );
}

test "Serialize i8 to 7-bit positive fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i8 = 0x7F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\x7F",
        actual,
    );
}

test "Serialize i32 to 7-bit positive fixint" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i32 = 0x7F;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\x7F",
        actual,
    );
}

test "Serialize i8" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i8 = @bitCast(@as(u8, 0x80));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd0\x80",
        actual,
    );
}

test "Serialize i32 to int8" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i32 = @bitCast(@as(u32, 0xFFFF_FF80));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd0\x80",
        actual,
    );
}

test "Serialize i16" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i16 = @bitCast(@as(u16, 0xBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd1\xBE\xEF",
        actual,
    );
}

test "Serialize i32 to int16" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i32 = @bitCast(@as(u32, 0xFFFFBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd1\xBE\xEF",
        actual,
    );
}

test "Serialize i32" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd2\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize i64 to uint32" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i64 = std.math.minInt(i32);
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd2\x80\x00\x00\x00",
        actual,
    );
}

test "Serialize i64" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i64 = @bitCast(@as(u64, 0xDEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings(
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
        actual,
    );
}

test "Serialize i128 to uint64" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i128 = @bitCast(@as(u128, 0xFFFFFFFFFFFFFFFF_DEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

// Found by fuzzing: a signed value that fits the unsigned encoding of a width
// but not the signed one picked the uint marker while still writing through the
// signed type of that width, panicking on the @intCast.
test "Serialize i9 to uint8" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i9 = 200;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcc\xc8", actual);
}

test "Serialize i17 to uint16" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i17 = 40000;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcd\x9C\x40", actual);
}

test "Serialize error IntTooLarge with int" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: i128 = @bitCast(@as(u128, 0xFFFFFFFFFFFFFFF0_DEADBEEFDEADBEEF));
    try testing.expectError(
        SerializeError.IntTooLarge,
        packer.pack(val),
    );
}

test "Serialize true" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: bool = true;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc3", actual);
}

test "Serialize false" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: bool = false;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc2", actual);
}

test "Serialize null" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: ?i32 = null;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc0", actual);
}

test "Serialize optional int" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: ?u32 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize optional bool" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: ?bool = true;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc3", actual);
}

test "Serialize f32" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: f32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xca\xDE\xAD\xBE\xEF", actual);
}

test "Serialize f64" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: f64 = @bitCast(@as(u64, 0xDEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize fixstr" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "Hello, World!";
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xAD" ++ val, actual);
}

test "Serialize 8-bit length string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 32;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd9" ++ .{32} ++ val, actual);
}

test "Serialize 16-bit length string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 256;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xda\x01\x00" ++ val, actual);
}

test "Serialize 32-bit length string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 65536;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xdb\x00\x01\x00\x00" ++ val, actual);
}

test "Serialize 8-bit length string from statically sized array" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = [_]u8{0x71} ** 32;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd9" ++ .{32} ++ val, actual);
}

test "Serialize 8-bit length binary string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 32;
    try packer.pack(Bin(val));
    const actual = aw.written();
    try testing.expectEqualStrings("\xc4" ++ .{32} ++ val, actual);
}

test "Serialize 16-bit length binary string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 0x0100;
    try packer.pack(Bin(val));
    const actual = aw.written();
    try testing.expectEqualStrings("\xc5\x01\x00" ++ val, actual);
}

test "Serialize 32-bit length binary string" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 0x0001_0000;
    try packer.pack(Bin(val));
    const actual = aw.written();
    try testing.expectEqualStrings("\xc6\x00\x01\x00\x00" ++ val, actual);
}

test "Serialize FixArray" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF", actual);
}

test "Serialize 16-bit length array" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const len = 0b0001_0000;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len), actual);
}

test "Serialize 32-bit length array" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len), actual);
}

test "Serialize slice to FixArray" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val: [4]i32 = .{ 0x0EADBEEF, 32, 0, -1 };
    try packer.pack(val[0..4]);
    const actual = aw.written();
    try testing.expectEqualStrings("\x94\xd2\x0E\xAD\xBE\xEF\x20\x00\xFF", actual);
}

test "Serialize slice to 16-bit length array" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const len = 0b0001_0000;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val[0..len]);
    const actual = aw.written();
    try testing.expectEqualStrings("\xdc\x00\x10" ++ ("\xce\xDE\xAD\xBE\xEF" ** len), actual);
}

test "Serialize slice to 32-bit length array" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val[0..len]);
    const actual = aw.written();
    try testing.expectEqualStrings("\xdd\x00\x01\x00\x00" ++ ("\xce\xDE\xAD\xBE\xEF" ** len), actual);
}

test "Serialize FixMap" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    var val: std.array_hash_map.String(i32) = .empty;
    defer val.deinit(testing.allocator);
    try val.put(testing.allocator, "key1", 0x0EADBEEF);
    try val.put(testing.allocator, "key2", 32);
    try val.put(testing.allocator, "key3", -1);
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\x83\xA4key1\xd2\x0E\xAD\xBE\xEF\xA4key2\x20\xA4key3\xFF", actual);
}

const MySerializeError = error{OhNo};
const MyType = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr =
            Repr{ .ext = 0x71 };

        pub fn pack_ext(
            self: MyType,
            writer: *std.Io.Writer,
        ) !void {
            try writer.writeAll(self.buf);
        }

        pub fn unpack_ext(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            len: usize,
        ) !MyType {
            return MyType{ .buf = try reader.readAlloc(allocator, len) };
        }
    };
};

test "Serialize FixExt_1 right type" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = "\xEF" };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd4\x71\xEF", actual);
}

test "Serialize FixExt_2 right type" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = "\xBE\xEF" };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd5\x71\xBE\xEF", actual);
}

test "Serialize FixExt_4 right type" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF" };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd6\x71\xDE\xAD\xBE\xEF", actual);
}

test "Serialize FixExt_8 right type" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd7\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize FixExt_16 right type" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd8\x71\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize Ext_8 right type" {
    const len = 255;
    const content = ("\xDE" ** len);
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = content };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc7\xFF\x71" ++ content, actual);
}

test "Serialize Ext_16 right type" {
    const len = 0xFF_FF;
    const content = ("\xDE" ** len);
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = content };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc8\xFF\xFF\x71" ++ content, actual);
}

test "Serialize Ext_32 right type" {
    const len = 0x00_01_00_00;
    const content = ("\xDE" ** len);
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = MyType{ .buf = content };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc9\x00\x01\x00\x00\x71" ++ content, actual);
}

test "Serialize ext header accounts for every byte pack_ext wrote" {
    // Lengths either side of the fixext sizes, and across the ext_8/ext_16
    // boundary, since each picks a differently shaped header.
    inline for (.{ 0, 1, 2, 3, 4, 8, 16, 17, 255, 256 }) |len| {
        const content = "\xDE" ** len;
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        var packer = Packer.init(&aw.writer, testing.allocator);

        try packer.pack(MyType{ .buf = content });
        // A second value, which a reader must still be able to find afterwards.
        try packer.pack(@as(i32, 0x0EADBEEF));
        packer.finish();

        var r = std.Io.Reader.fixed(aw.written());
        var message = Unpacker.init(testing.allocator, &r);
        const unpacked = try message.unpack_as(MyType);
        testing.allocator.free(unpacked.buf);

        // Reaching the next value intact is what says the header declared
        // exactly the number of bytes that followed it.
        try testing.expectEqual(
            @as(i32, 0x0EADBEEF),
            try message.unpack_as(i32),
        );
    }
}

test "Serialize FixExt_4 timestamp" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{ .nanoseconds = 0, .seconds = 0xDEADBEEF };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd6\xFF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize FixExt_8 timestamp" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{ .nanoseconds = 1, .seconds = 0xDEADBEEF };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd7\xFF\x00\x00\x00\x04\xDE\xAD\xBE\xEF", actual);
}

test "Serialize Ext_8 timestamp" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{ .nanoseconds = 1, .seconds = 0x0EADBEEFDEADBEEF };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xc7\x0C\xFF\x00\x00\x00\x01\x0E\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

// The pack side of the boundary the unpacker tests cover. Neither of these
// could be written before the field was widened: `u29` cannot hold either
// value, so the `TooManyNanoseconds` guard was unreachable.
test "Serialize FixExt_8 timestamp at the maximum legal nanoseconds" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{ .nanoseconds = 999_999_999, .seconds = 0 };
    try packer.pack(val);
    const actual = aw.written();
    try testing.expectEqualStrings("\xd7\xFF\xEE\x6B\x27\xFC\x00\x00\x00\x00", actual);
}

// Above the limit there is no encoding to reach for, so packing has to refuse.
// `write_ext` buffers the payload before it can write a header derived from the
// payload's length, so `pack_ext` refuses before anything has reached the
// writer.
test "Serialize timestamp over the nanosecond limit" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{ .nanoseconds = 1_000_000_000, .seconds = 0 };
    try testing.expectError(
        Timestamp.Error.TooManyNanoseconds,
        packer.pack(val),
    );
    try testing.expectEqualStrings("", aw.written());
}

// Packing an ext value buffers the payload so the length header can be written
// ahead of it. That is an allocation the pack side did not used to make — the
// payload arrived as a slice the type had already built — and it fails like any
// other. A failure has to release the buffer rather than strand it.
//
// This walks every allocation failure point of such a pack and reports leaked
// bytes if any of them loses the payload buffer or the writer's own.
test "Packing an ext value leaks nothing when an allocation fails" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn encode(allocator: std.mem.Allocator) !void {
            // A fixed destination, so the payload buffer is the only allocation
            // in play. An `Allocating` destination would fail here too, and its
            // failure arrives as `WriteFailed` rather than `OutOfMemory`, which
            // is not what this test is asking about.
            var out: [512]u8 = undefined;
            var writer = std.Io.Writer.fixed(&out);
            var packer = Packer.init(&writer, allocator);

            // Past 255 bytes, so the header is an ext_16 (marker, two length
            // bytes, type) and the payload buffer grows more than once getting
            // there.
            try packer.pack(MyType{ .buf = "\xDE" ** 300 });
            packer.finish();

            try testing.expectEqual(@as(usize, 300 + 4), writer.end);
        }
    }.encode, .{});
}

// fixstr covers lengths 0 through 31, so 31 bytes is the last length that fits
// in a one-byte header. The bound was written as `len < maxInt(u5)`, which
// stops at 30 and pushes 31 out to a str_8 — a valid encoding, a byte longer
// than it needs to be, and not what any other implementation emits.
//
// The array and map headers next to it use `<=` for the same boundary, so this
// is also an inconsistency within the packer. Round-trips cannot see it: a
// str_8 decodes back to the same string.
test "Serialize a 31-byte string as a fixstr" {
    const val = "a" ** 31;
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    try packer.pack(val);
    packer.finish();

    // 0xa0 | 31
    try testing.expectEqualStrings("\xbf" ++ val, aw.written());
}

// The length either side of it, to pin that the boundary moved rather than
// shifted.
test "Serialize strings either side of the fixstr boundary" {
    {
        const val = "b" ** 30;
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        var packer = Packer.init(&aw.writer, testing.allocator);
        try packer.pack(val);
        packer.finish();
        try testing.expectEqualStrings("\xbe" ++ val, aw.written());
    }
    {
        const val = "c" ** 32;
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        var packer = Packer.init(&aw.writer, testing.allocator);
        try packer.pack(val);
        packer.finish();
        try testing.expectEqualStrings("\xd9\x20" ++ val, aw.written());
    }
}
