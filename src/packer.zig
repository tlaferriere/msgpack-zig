const std = @import("std");
const Marker = @import("marker.zig").Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
const SerializeError = error{ TypeTooLarge, WrongType };

/// Packer struct.
///
/// Holds the in-construction msgpack buffer until it is ready to be sent.
/// When the message is complete, call `Packer.finish()` to get ownership
/// of the completed buffer. You will have to manage this memory.
pub const Packer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    offset: usize = 0,

    /// Initialize a Packer.
    ///
    /// Remember to `errdefer Packer.deinit`.
    pub fn init(allocator: std.mem.Allocator) !Packer {
        return Packer{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, 1),
        };
    }

    pub fn finish(self: Packer) []const u8 {
        return self.buffer;
    }

    pub fn pack(self: *Packer, object: anytype) !void {
        errdefer self.allocator.free(self.buffer);
        return switch (@typeInfo(@TypeOf(object))) {
            .Int => self.pack_int(@TypeOf(object), object),
            else => @compileError("Type not serializable into msgpack."),
        };
    }

    fn pack_float(self: *Packer, comptime float: Type.Float, comptime As: type) !As {
        switch (self.buffer[0]) {
            0xca => if (float.bits >= 32)
                @as(As, @floatCast(
                    @as(f32, @bitCast(std.mem.readVarInt(
                        u32,
                        self.buffer[1..5],
                        Endian.big,
                    ))),
                ))
            else
                SerializeError.FloatTooSmall,
            0xcb => if (float.bits >= 64)
                @as(As, @floatCast(
                    @as(f64, @bitCast(std.mem.readVarInt(
                        u64,
                        self.buffer[1..9],
                        Endian.big,
                    ))),
                ))
            else
                SerializeError.FloatTooSmall,
        }
    }

    fn pack_int(self: *Packer, comptime T: type, object: T) !void {
        const bytes_needed = try int_packed_size(T, object);
        if (!self.allocator.resize(
            self.buffer,
            bytes_needed,
        )) {
            self.buffer = try self.allocator.realloc(
                self.buffer,
                bytes_needed,
            );
        }
        switch (bytes_needed) {
            1 => {
                const OutType = if (@typeInfo(T).Int.signedness == .unsigned) u8 else i8;
                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    @intCast(object),
                    Endian.big,
                );
                self.offset += bytes_needed;
            },
            2 => {
                const byte_count = 1;
                comptime var type_info = @typeInfo(T);
                type_info.Int.bits = byte_count * 8;
                const OutType = @Type(type_info);

                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    if (type_info.Int.signedness == .signed and object <= std.math.maxInt(OutType))
                        Marker.INT_8
                    else
                        Marker.UINT_8,
                    Endian.big,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [byte_count]u8,
                        self.buffer[self.offset .. self.offset + byte_count],
                    ),
                    @intCast(object),
                    Endian.big,
                );
                self.offset += byte_count;
            },
            3 => {
                const byte_count = 2;
                comptime var type_info = @typeInfo(T);
                type_info.Int.bits = byte_count * 8;
                const OutType = @Type(type_info);

                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    if (type_info.Int.signedness == .signed and object <= std.math.maxInt(OutType))
                        Marker.INT_16
                    else
                        Marker.UINT_16,
                    Endian.big,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [byte_count]u8,
                        self.buffer[self.offset .. self.offset + byte_count],
                    ),
                    @intCast(object),
                    Endian.big,
                );
                self.offset += byte_count;
            },
            5 => {
                const byte_count = 4;
                comptime var type_info = @typeInfo(T);
                type_info.Int.bits = byte_count * 8;
                const OutType = @Type(type_info);
                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    if (type_info.Int.signedness == .signed and object <= std.math.maxInt(OutType))
                        Marker.INT_32
                    else
                        Marker.UINT_32,
                    Endian.big,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [byte_count]u8,
                        self.buffer[self.offset .. self.offset + byte_count],
                    ),
                    @intCast(object),
                    Endian.big,
                );
                self.offset += byte_count;
            },
            9 => {
                const byte_count = 8;
                comptime var type_info = @typeInfo(T);
                type_info.Int.bits = byte_count * 8;
                const OutType = @Type(type_info);
                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    if (type_info.Int.signedness == .signed and object <= std.math.maxInt(OutType))
                        Marker.INT_64
                    else
                        Marker.UINT_64,
                    Endian.big,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [byte_count]u8,
                        self.buffer[self.offset .. self.offset + byte_count],
                    ),
                    @intCast(object),
                    Endian.big,
                );
                self.offset += byte_count;
            },
            else => unreachable,
        }
    }

    fn int_packed_size(comptime T: type, value: T) !usize {
        return if (std.math.minInt(i6) <= value and value <= std.math.maxInt(u7))
            1
        else if (std.math.minInt(i8) <= value and value <= std.math.maxInt(u8))
            2
        else if (std.math.minInt(i16) <= value and value <= std.math.maxInt(u16))
            3
        else if (std.math.minInt(i32) <= value and value <= std.math.maxInt(u32))
            5
        else if (std.math.minInt(i64) <= value and value <= std.math.maxInt(u64))
            9
        else
            SerializeError.TypeTooLarge;
    }
};

test "Serialize u7 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u7 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize u32 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize i6 to 5-bit negative fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i6 = -32;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize i32 to 5-bit negative fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = -32;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xE0", actual);
}

test "Serialize u8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u8 = 0x8F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test "Serialize u32 to uint8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0x8F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcc\x8f", actual);
}

test Packer {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u16 = 0xBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32 to uint16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0xBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcd\xBE\xEF", actual);
}

test "Serialize u32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u32 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64 to uint32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u64 = 0xDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xce\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u64 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize u128 to uint64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u128 = 0xDEADBEEFDEADBEEF;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize error TypeTooLarge" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: u128 = 0xFDEADBEEFDEADBEEF;
    try testing.expectError(
        SerializeError.TypeTooLarge,
        packer.pack(val),
    );
}

// test "Serialize u8" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xcc\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0xEF, try message.unpack_as(u8));
// }

// test "Serialize optional u8" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xcc\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0xEF, try message.unpack_as(?u8));
// }

// test "Serialize optional u8: null" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xc0",
//     );
//     defer message.deinit();
//     try testing.expectEqual(null, try message.unpack_as(?u8));
// }

// test "Serialize u16" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xcd\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0xBEEF, try message.unpack_as(u16));
// }

// test "Serialize u32" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xce\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0xDEADBEEF, try message.unpack_as(u32));
// }

// test "Serialize u64" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0xDEADBEEFDEADBEEF, try message.unpack_as(u64));
// }

// test "Serialize unsigned TypeTooSmall" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xcf\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     const actual_error_union = message.unpack_as(u32);
//     const expected_error = SerializeError.TypeTooSmall;
//     try testing.expectError(expected_error, actual_error_union);
// }

// test "Serialize negative i6" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(-17, try message.unpack_as(i6));
// }

// test "Serialize positive i7" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\x7F",
//     );
//     defer message.deinit();
//     try testing.expectEqual(0x7F, try message.unpack_as(i7));
// }

// test "Serialize i8" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xd0\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(-17, try message.unpack_as(i8));
// }

// test "Serialize i16" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xd1\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(-16657, try message.unpack_as(i16));
// }

// test "Serialize i32" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xd2\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(-559038737, try message.unpack_as(i32));
// }

// test "Serialize i64" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     try testing.expectEqual(-2401053088876216593, try message.unpack_as(i64));
// }

// test "Serialize signed TypeTooSmall" {
//     const message = try Packer.init(
//         testing.allocator,
//         "\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF",
//     );
//     defer message.deinit();
//     const actual_error_union = message.unpack_as(i32);
//     const expected_error = SerializeError.TypeTooSmall;
//     try testing.expectError(expected_error, actual_error_union);
// }
