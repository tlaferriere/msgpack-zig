const std = @import("std");
const testing = std.testing;

const DeserializeError = error{ IntTooSmall, BadCast };

pub const Message = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8) !Message {
        const message = Message{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, buffer.len),
        };
        @memcpy(message.buffer, buffer);
        return message;
    }

    pub fn deinit(self: Message) void {
        self.allocator.free(self.buffer);
    }

    pub fn unpack_as(self: Message, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .Int => |int_info| switch (int_info.signedness) {
                .unsigned => switch (self.buffer[0]) {
                    0xcf => if (int_info.bits >= 64) std.mem.readVarInt(
                        As,
                        self.buffer[1..9],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xce => if (int_info.bits >= 32) std.mem.readVarInt(
                        As,
                        self.buffer[1..5],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xcd => if (int_info.bits >= 16) std.mem.readVarInt(
                        As,
                        self.buffer[1..3],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xcc => if (int_info.bits >= 8)
                        @intCast(self.buffer[1])
                    else
                        DeserializeError.IntTooSmall,

                    else => {
                        if (self.buffer[0] & 0x80 != 0)
                            return DeserializeError.BadCast;
                        return @intCast(self.buffer[0]); // Unsafe if compiler-optimized.
                    },
                },
                .signed => switch (self.buffer[0]) {
                    0xd3 => if (int_info.bits >= 64) std.mem.readVarInt(
                        As,
                        self.buffer[1..9],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xd2 => if (int_info.bits >= 32) std.mem.readVarInt(
                        As,
                        self.buffer[1..5],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xd1 => if (int_info.bits >= 16) std.mem.readVarInt(
                        As,
                        self.buffer[1..3],
                        std.builtin.Endian.big,
                    ) else DeserializeError.IntTooSmall,

                    0xd0 => if (int_info.bits >= 8)
                        @intCast(@as(i8, @bitCast(self.buffer[1])))
                    else
                        DeserializeError.IntTooSmall,

                    else => {
                        if (self.buffer[0] & 0xE0 != 0xE0)
                            return DeserializeError.BadCast;
                        return @intCast(@as(i8, @bitCast(self.buffer[0]))); // Unsafe if compiler-optimized.
                    },
                },
            },
            else => @compileError("Msgpack cannot serialize this type."),
        };
    }
};

pub fn pack(allocator: std.mem.Allocator, object: anytype) []const u8 {
    const buffer = switch (@typeInfo(object)) {
        .Int => |int| {
            const buffer = try allocator.alloc(u8, std.math.ceil(int.bits / 8.0));
            if (int.bits <= 7 and int.signedness == .unsigned) {
                @memcpy(buffer, &object);
            }
            return buffer;
        },
    };
    return buffer;
}

test "Deserialize u7" {
    const message = try Message.init(
        testing.allocator,
        "\x7F",
    );
    defer message.deinit();
    try testing.expectEqual(0x7F, try message.unpack_as(u7));
}

test "Deserialize u8" {
    const message = try Message.init(
        testing.allocator,
        "\xcc\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(0xEF, try message.unpack_as(u8));
}

test "Deserialize u16" {
    const message = try Message.init(
        testing.allocator,
        "\xcd\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(0xBEEF, try message.unpack_as(u16));
}

test "Deserialize u32" {
    const message = try Message.init(
        testing.allocator,
        "\xce\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(0xDEADBEEF, try message.unpack_as(u32));
}

test "Deserialize u64" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(0xDEADBEEFDEADBEEF, try message.unpack_as(u64));
}

test "Deserialize unsigned IntTooSmall" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    const actual_error_union = message.unpack_as(u32);
    const expected_error = DeserializeError.IntTooSmall;
    try testing.expectError(expected_error, actual_error_union);
}

test "Deserialize i6" {
    const message = try Message.init(
        testing.allocator,
        "\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(-17, try message.unpack_as(i6));
}

test "Deserialize i8" {
    const message = try Message.init(
        testing.allocator,
        "\xd0\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(-17, try message.unpack_as(i8));
}

test "Deserialize i16" {
    const message = try Message.init(
        testing.allocator,
        "\xd1\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(-16657, try message.unpack_as(i16));
}

test "Deserialize i32" {
    const message = try Message.init(
        testing.allocator,
        "\xd2\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(-559038737, try message.unpack_as(i32));
}

test "Deserialize i64" {
    const message = try Message.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expectEqual(-2401053088876216593, try message.unpack_as(i64));
}

test "Deserialize signed IntTooSmall" {
    const message = try Message.init(
        testing.allocator,
        "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    const actual_error_union = message.unpack_as(i32);
    const expected_error = DeserializeError.IntTooSmall;
    try testing.expectError(expected_error, actual_error_union);
}
