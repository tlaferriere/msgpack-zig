//! Integration tests for the msgpack module.
const std = @import("std");
const testing = std.testing;

const msgpack = @import("msgpack");

test "u7 round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer_ = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val: u7 = 0x7F;
    try packer_.pack(val);
    packer_.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(val, try message.unpack_as(u7));
}

test "i8 round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer_ = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val: i8 = 0x7F;
    try packer_.pack(val);
    packer_.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(val, try message.unpack_as(i8));
}

test "null round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer_ = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val: ?i8 = null;
    try packer_.pack(val);
    packer_.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(val, try message.unpack_as(?i8));
}

test "optional bool round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer_ = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val: ?bool = true;
    try packer_.pack(val);
    packer_.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(val, try message.unpack_as(?bool));
}

test "float round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer_ = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val: f32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer_.pack(val);
    packer_.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    try testing.expectEqual(val, try message.unpack_as(f32));
}

test "32-bit length bin round_trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 0x0001_0000;
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "32-bit length string round_trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val = "t" ** 0x0001_0000;
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([]const u8);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualStrings(
        val,
        unpacked,
    );
}

test "32-bit length array round_trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([len]u32);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "32-bit length slice round_trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val[0..len]);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as([]u32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val[0..len],
        unpacked,
    );
}

test "16-bit length map round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const len = 0b0001_0000;
    var val: std.array_hash_map.Auto(u32, u32) = .empty;
    defer val.deinit(testing.allocator);
    for (0..len) |i| {
        try val.put(testing.allocator, @intCast(i), 0xDEADBEEF);
    }
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    var unpacked = try message.unpack_as(std.array_hash_map.Auto(u32, u32));
    defer unpacked.deinit(testing.allocator);
    try testing.expectEqualDeep(
        val.keys(),
        unpacked.keys(),
    );
    try testing.expectEqualDeep(
        val.values(),
        unpacked.values(),
    );
}

test "32-bit length map round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    var val: std.array_hash_map.Auto(u32, u32) = .empty;
    defer val.deinit(testing.allocator);
    for (0..len) |i| {
        try val.put(testing.allocator, @intCast(i), 0xDEADBEEF);
    }
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    var unpacked = try message.unpack_as(std.array_hash_map.Auto(u32, u32));
    defer unpacked.deinit(testing.allocator);
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
const MySerializeError = error{OhNo};
const MySizeError = error{OhNo};
const MyType = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr{ .ext = 0x71 };

        pub fn pack_ext(
            self: MyType,
            allocator: std.mem.Allocator,
        ) ![]const u8 {
            const out = try allocator.alloc(u8, self.buf.len);
            @memcpy(out, self.buf);
            return out;
        }

        pub fn packed_size(self: MyType) !usize {
            return self.buf.len;
        }

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

test "32-bit length ext round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const len = 0x00_01_00_00;
    const content = ("\xDE" ** len);
    const val = MyType{ .buf = content };
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "timestamp 32 round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val = msgpack.Timestamp{
        .seconds = 0xDEADBEEF,
        .nanoseconds = 0,
    };
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as(msgpack.Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "timestamp 64 round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val = msgpack.Timestamp{
        .seconds = 0xDEADBEEF,
        .nanoseconds = 1,
    };
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as(msgpack.Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

const MyStruct = struct {
    a: u32,
    b: []const u8,
    @"1 2 3 weird $name": u8,
    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr.map;
    };
};

test "object as map round-trip" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = msgpack.Packer.init(&aw.writer, testing.allocator);
    const val = MyStruct{
        .@"1 2 3 weird $name" = 2,
        .a = 0xDEADBEEF,
        .b = "Hello!",
    };
    try packer.pack(val);
    packer.finish();
    var r = std.Io.Reader.fixed(aw.written());
    var message = msgpack.Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as(MyStruct);
    defer testing.allocator.free(unpacked.b);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}
