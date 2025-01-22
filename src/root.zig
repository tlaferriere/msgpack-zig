const std = @import("std");
const testing = std.testing;

const DeserializeError = error{
    BadCast,
};

pub fn deserialize_as(comptime As: type, buffer: []const u8) !As {
    return switch (As) {
        std.builtin.Type.Int => |int_info| if (int_info.bits <= 64)
            if (buffer.len <= 8)
                std.mem.readVarInt(As, buffer, std.builtin.Endian.big)
            else
                DeserializeError.BadCast
        else
            DeserializeError.BadCast,
        else => DeserializeError.BadCast,
    };
}

test "Deserialize u32" {
    const deadbeef_bytes = "\xDE\xAD\xBE\xEF";
    try testing.expect(try deserialize_as(u32, deadbeef_bytes) == 0xDEADBEEF);
}
