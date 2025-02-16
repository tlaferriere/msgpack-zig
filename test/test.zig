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

test "32-bit length bin round_trip" {
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

test "32-bit length string round_trip" {
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

test "32-bit length array round_trip" {
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

test "32-bit length slice round_trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const len = 0x00_01_00_00;
    const val: [len]u32 = .{0xDEADBEEF} ** len;
    try packer.pack(val[0..len]);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as([]u32);
    defer testing.allocator.free(unpacked);
    try testing.expectEqualDeep(
        val[0..len],
        unpacked,
    );
}

test "16-bit length map round-trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const len = 0b0001_0000;
    var val = std.AutoArrayHashMap(u32, u32).init(testing.allocator);
    defer val.deinit();
    for (0..len) |i| {
        try val.put(@intCast(i), 0xDEADBEEF);
    }
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    var unpacked = try message.unpack_as(std.AutoArrayHashMap(u32, u32));
    defer unpacked.deinit();
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
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const len = 0x00_01_00_00;
    var val = std.AutoArrayHashMap(u32, u32).init(testing.allocator);
    defer val.deinit();
    for (0..len) |i| {
        try val.put(@intCast(i), 0xDEADBEEF);
    }
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    var unpacked = try message.unpack_as(std.AutoArrayHashMap(u32, u32));
    defer unpacked.deinit();
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

    pub const __msgpack_pack_repr__ =
        msgpack.repr.PackAsExt(
        0x71,
        pack_ext,
        packed_size,
    );

    fn pack_ext(
        self: MyType,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const out = try allocator.alloc(u8, self.buf.len);
        @memcpy(out, self.buf);
        return out;
    }

    fn packed_size(self: MyType) !usize {
        return self.buf.len;
    }

    pub const __msgpack_unpack_repr__ = msgpack.repr.UnpackAsExt(
        0x71,
        unpack_ext,
    );

    fn unpack_ext(allocator: std.mem.Allocator, data: []const u8) !MyType {
        errdefer allocator.free(data);
        for (data) |b| {
            if (b == 0xFF) {
                return MyDeserializeError.OhNo;
            }
        }
        return MyType{ .buf = data };
    }
};

test "32-bit length ext round-trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const len = 0x00_01_00_00;
    const content = ("\xDE" ** len);
    const val = MyType{ .buf = content };
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as(MyType);
    defer testing.allocator.free(unpacked.buf);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "timestamp 32 round-trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const val = msgpack.Timestamp{
        .seconds = 0xDEADBEEF,
        .nanoseconds = 0,
    };
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as(msgpack.Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

test "timestamp 64 round-trip" {
    var packer = try msgpack.Packer.init(
        testing.allocator,
    );
    const val = msgpack.Timestamp{
        .seconds = 0xDEADBEEF,
        .nanoseconds = 1,
    };
    try packer.pack(val);
    const buffer = packer.finish();
    defer testing.allocator.free(buffer);
    var message = try msgpack.Unpacker.init(
        testing.allocator,
        buffer,
        0,
    );
    const unpacked = try message.unpack_as(msgpack.Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}
