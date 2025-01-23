const std = @import("std");
const testing = std.testing;

const DeserializeError = error{
    BufferTooLong,
    IntTooLarge,
    UnknownType,
};

pub fn deserialize_as(comptime As: type, buffer: []const u8) !As {
    return switch (@typeInfo(As)) {
        .Int => |int_info| if (int_info.bits <= 64)
            if (buffer.len <= 8)
                std.mem.readVarInt(As, buffer, std.builtin.Endian.big)
            else
                DeserializeError.BufferTooLong
        else
            DeserializeError.IntTooLarge,
        else => DeserializeError.UnknownType,
    };
}

test "Deserialize u32" {
    const deadbeef_bytes = "\xDE\xAD\xBE\xEF";
    try testing.expect(try deserialize_as(u32, deadbeef_bytes) == 0xDEADBEEF);
}

test "Deserialize u64" {
    const deadbeef_bytes = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF";
    try testing.expect(try deserialize_as(u64, deadbeef_bytes) == 0xDEADBEEFDEADBEEF);
}

test "Deserialize u56" {
    const deadbeef_bytes = "\xBE\xEF\xDE\xAD\xBE\xEF";
    try testing.expect(try deserialize_as(u56, deadbeef_bytes) == 0xBEEFDEADBEEF);
}

test "Deserialize IntTooLarge" {
    const deadbeef_bytes = "\xBE\xEF\xDE\xAD\xBE\xEF";
    try testing.expect(deserialize_as(u65, deadbeef_bytes) == DeserializeError.IntTooLarge);
}

test "Deserialize BufferTooLong" {
    const deadbeef_bytes = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF";
    try testing.expect(deserialize_as(u64, deadbeef_bytes) == DeserializeError.BufferTooLong);
}

test "Deserialize UnknownType" {
    const deadbeef_bytes = "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF";
    const UnknownStruct = struct { a: u32, b: u42 };
    try testing.expect(deserialize_as(UnknownStruct, deadbeef_bytes) == DeserializeError.UnknownType);
}
