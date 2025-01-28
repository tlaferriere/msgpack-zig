const std = @import("std");

const Marker = @import("marker.zig").Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
const DeserializeError = error{ TypeTooSmall, WrongType };

pub const Unpacker = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
    ) !Unpacker {
        const unpacker = Unpacker{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, buffer.len),
        };
        @memcpy(unpacker.buffer, buffer);
        return unpacker;
    }

    pub fn deinit(self: Unpacker) void {
        self.allocator.free(self.buffer);
    }

    pub fn unpack_as(self: Unpacker, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .Int => |int| self.unpack_int(int, As),
            .Bool => switch (self.buffer[0]) {
                Marker.FALSE => false,
                Marker.TRUE => true,
                else => DeserializeError.WrongType,
            },
            .Optional => |optional| switch (self.buffer[0]) {
                Marker.NIL => null,
                else => try self.unpack_as(optional.child),
            },
            .Float => |float| self.unpack_float(float, As),
            else => @compileError("Msgpack cannot serialize this type."),
        };
    }

    fn unpack_float(
        self: Unpacker,
        comptime float: Type.Float,
        comptime As: type,
    ) !As {
        return switch (self.buffer[0]) {
            0xca => if (float.bits >= 32) @as(
                As,
                @floatCast(
                    @as(f32, @bitCast(std.mem.readVarInt(
                        u32,
                        self.buffer[1..5],
                        Endian.big,
                    ))),
                ),
            ) else DeserializeError.TypeTooSmall,
            0xcb => if (float.bits >= 64) @as(
                As,
                @floatCast(
                    @as(f64, @bitCast(std.mem.readVarInt(
                        u64,
                        self.buffer[1..9],
                        Endian.big,
                    ))),
                ),
            ) else DeserializeError.TypeTooSmall,
            else => DeserializeError.WrongType,
        };
    }

    fn unpack_int(
        self: Unpacker,
        comptime int: Type.Int,
        comptime As: type,
    ) !As {
        return switch (int.signedness) {
            .unsigned => switch (self.buffer[0]) {
                Marker.UINT_64 => if (int.bits >= 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_32 => if (int.bits >= 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_16 => if (int.bits >= 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits >= 8)
                    @intCast(self.buffer[1])
                else
                    DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[0] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    return @intCast(self.buffer[0]); // Unsafe if compiler-optimized.
                },
            },
            .signed => switch (self.buffer[0]) {
                // Is it safe to accept a uint encoded as an int?
                Marker.UINT_64 => if (int.bits > 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_32 => if (int.bits > 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_16 => if (int.bits > 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits > 8)
                    @intCast(self.buffer[1])
                else
                    DeserializeError.TypeTooSmall,
                Marker.INT_64 => if (int.bits >= 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_32 => if (int.bits >= 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_16 => if (int.bits >= 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_8 => if (int.bits >= 8)
                    @intCast(@as(i8, @bitCast(self.buffer[1])))
                else
                    DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[0] & 0xE0 != 0xE0 and
                        self.buffer[0] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    return @intCast(@as(i8, @bitCast(self.buffer[0]))); // Unsafe if compiler-optimized.
                },
            },
        };
    }
};

test "Deserialize false" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xc2",
    );
    defer message.deinit();
    try testing.expectEqual(
        false,
        try message.unpack_as(bool),
    );
}

test "Deserialize true" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xc3",
    );
    defer message.deinit();
    try testing.expectEqual(
        true,
        try message.unpack_as(bool),
    );
}

test "Deserialize optional bool: true" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xc3",
    );
    defer message.deinit();
    try testing.expectEqual(
        true,
        try message.unpack_as(?bool),
    );
}

test "Deserialize optional bool: null" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xc0",
    );
    defer message.deinit();
    try testing.expectEqual(
        null,
        try message.unpack_as(?bool),
    );
}

test "Deserialize u7" {
    const message = try Unpacker.init(
        testing.allocator,
        "\x7F",
    );
    defer message.deinit();
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(u7),
    );
}

test "Deserialize u8" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcc\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(u8),
    );
}

test "Deserialize optional u8" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcc\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xEF,
        try message.unpack_as(?u8),
    );
}

test "Deserialize optional u8: null" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xc0",
    );
    defer message.deinit();
    try testing.expectEqual(
        null,
        try message.unpack_as(?u8),
    );
}

test "Deserialize u16" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcd\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xBEEF,
        try message.unpack_as(u16),
    );
}

test "Deserialize u32" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xce\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xDEADBEEF,
        try message.unpack_as(u32),
    );
}

test "Deserialize u64" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xDEADBEEFDEADBEEF,
        try message.unpack_as(u64),
    );
}

test "Deserialize unsigned TypeTooSmall" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    const actual_error_union = message.unpack_as(u32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

test "Deserialize negative i6" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        -17,
        try message.unpack_as(i6),
    );
}

test "Deserialize one-byte positive i8" {
    const message = try Unpacker.init(
        testing.allocator,
        "\x7F",
    );
    defer message.deinit();
    try testing.expectEqual(
        0x7F,
        try message.unpack_as(i8),
    );
}

test "Deserialize i8" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xd0\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        -17,
        try message.unpack_as(i8),
    );
}

test "Deserialize i9 from msgpack 8-bit uint" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcc\xFF",
    );
    defer message.deinit();
    try testing.expectEqual(
        0xFF,
        try message.unpack_as(i9),
    );
}

test "Deserialize i16" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xd1\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        -16657,
        try message.unpack_as(i16),
    );
}

test "Deserialize i32" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xd2\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        -559038737,
        try message.unpack_as(i32),
    );
}

test "Deserialize i64" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        -2401053088876216593,
        try message.unpack_as(i64),
    );
}

test "Deserialize signed TypeTooSmall" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    const actual_error_union = message.unpack_as(i32);
    const expected_error = DeserializeError.TypeTooSmall;
    try testing.expectError(
        expected_error,
        actual_error_union,
    );
}

test "Deserialize f64" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xcb\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        @as(f64, @bitCast(@as(u64, 0xDEADBEEF_DEADBEEF))),
        try message.unpack_as(f64),
    );
}

test "Deserialize f32" {
    const message = try Unpacker.init(
        testing.allocator,
        "\xca\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(
        @as(f32, @bitCast(@as(u32, 0xDEADBEEF))),
        try message.unpack_as(f32),
    );
}
