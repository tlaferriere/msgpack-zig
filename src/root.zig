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
                    0xd1, 0xd2, 0xd3 => if (int_info.bits > 8) std.mem.readInt(
                        As,
                        self.buffer[1..],
                        std.builtin.Endian.big,
                    ),
                    0xd0 => @intCast(self.buffer[1]),
                    else => if (self.buffer[0] & 0xE0 == 0xE0)
                        @intCast(self.buffer[0]) // Unsafe if compiler-optimized.
                    else
                        DeserializeError.BadCast,
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
    try testing.expect(try message.unpack_as(u7) == 0x7F);
}

test "Deserialize u8" {
    const message = try Message.init(
        testing.allocator,
        "\xcc\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u8) == 0xEF);
}

test "Deserialize u16" {
    const message = try Message.init(
        testing.allocator,
        "\xcd\xBE\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u16) == 0xBEEF);
}

test "Deserialize u32" {
    const message = try Message.init(
        testing.allocator,
        "\xce\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u32) == 0xDEADBEEF);
}

test "Deserialize u64" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u64) == 0xDEADBEEFDEADBEEF);
}

test "Deserialize u56" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\x00\x00\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u56) == 0xBEEFDEADBEEF);
}

test "Deserialize non 8-bit aligned type" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\x00\x01\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    try testing.expect(try message.unpack_as(u57) == 0x1BEEFDEADBEEF);
}

// Compilation error, uncomment to test.
// test "Deserialize IntTooLarge" {
//     const message = try Message.init(testing.allocator, "\xBE\xEF\xDE\xAD\xBE\xEF");
//     defer message.deinit();
//     try testing.expect(deserialize_as(u65) == DeserializeError.IntTooLarge);
// }

test "Deserialize IntTooSmall" {
    const message = try Message.init(
        testing.allocator,
        "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
    );
    defer message.deinit();
    const actual_error_union = message.unpack_as(u56);
    const expected_error = DeserializeError.IntTooSmall;
    try testing.expectError(expected_error, actual_error_union);
}

// Compilation error, uncomment to test.
// test "Deserialize UnknownType" {
//     const message = try Message.init(testing.allocator, "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
//     defer message.deinit();
//     const UnknownStruct = struct { a: u32, b: u42 };
//     try testing.expect(deserialize_as(UnknownStruct) == DeserializeError.UnknownType);
// }
