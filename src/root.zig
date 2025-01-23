const std = @import("std");
const testing = std.testing;

const DeserializeError = error{
    BufferTooLong,
};

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
            .Int => |int_info| if (int_info.bits <= 64)
                if (self.buffer.len <= 8)
                    std.mem.readVarInt(As, self.buffer, std.builtin.Endian.big)
                else
                    DeserializeError.BufferTooLong
            else
                @compileError("Integer too large for msgpack. Maximum integer size is 64 bits."),
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

test "Deserialize u8" {
    const message = try Message.init(testing.allocator, "\x7F");
    defer message.deinit();
    try testing.expect(try message.unpack_as(u9) == 0x7F);
}

test "Deserialize u32" {
    const message = try Message.init(testing.allocator, "\xDE\xAD\xBE\xEF");
    defer message.deinit();
    try testing.expect(try message.unpack_as(u32) == 0xDEADBEEF);
}

test "Deserialize u64" {
    const message = try Message.init(testing.allocator, "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    defer message.deinit();
    try testing.expect(try message.unpack_as(u64) == 0xDEADBEEFDEADBEEF);
}

test "Deserialize u56" {
    const message = try Message.init(testing.allocator, "\xBE\xEF\xDE\xAD\xBE\xEF");
    defer message.deinit();
    try testing.expect(try message.unpack_as(u56) == 0xBEEFDEADBEEF);
}

test "Deserialize non 8-bit aligned type" {
    const message = try Message.init(testing.allocator, "\x01\xBE\xEF\xDE\xAD\xBE\xEF");
    defer message.deinit();
    try testing.expect(try message.unpack_as(u57) == 0x1BEEFDEADBEEF);
}

// Compilation error, uncomment to test.
// test "Deserialize IntTooLarge" {
//     const message = try Message.init(testing.allocator, "\xBE\xEF\xDE\xAD\xBE\xEF");
//     defer message.deinit();
//     try testing.expect(deserialize_as(u65) == DeserializeError.IntTooLarge);
// }

test "Deserialize BufferTooLong" {
    const message = try Message.init(testing.allocator, "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
    defer message.deinit();
    try testing.expect(message.unpack_as(u64) == DeserializeError.BufferTooLong);
}

// Compilation error, uncomment to test.
// test "Deserialize UnknownType" {
//     const message = try Message.init(testing.allocator, "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF");
//     defer message.deinit();
//     const UnknownStruct = struct { a: u32, b: u42 };
//     try testing.expect(deserialize_as(UnknownStruct) == DeserializeError.UnknownType);
// }
