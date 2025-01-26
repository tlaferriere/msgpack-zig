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

    /// Transfer ownership of the buffer back to the caller to be transmitted.
    ///
    /// Remember to free the memory of the buffer.
    pub fn finish(self: Packer) []const u8 {
        return self.buffer;
    }

    test finish {
        var packer = try Packer.init(
            testing.allocator,
        );
        const val: u7 = 0x7F;
        try packer.pack(val);
        const actual = packer.finish();
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings("\x7F", actual);
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

test "Serialize i8 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i8 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize i32 to 7-bit positive fixint" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = 0x7F;
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\x7F", actual);
}

test "Serialize i8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i8 = @bitCast(@as(u8, 0x80));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd0\x80", actual);
}

test "Serialize i32 to int8" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xFFFF_FF80));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd0\x80", actual);
}

test "Serialize i16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i16 = @bitCast(@as(u16, 0xBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd1\xBE\xEF", actual);
}

test "Serialize i32 to int16" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xFFFFBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd1\xBE\xEF", actual);
}

test "Serialize i32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i32 = @bitCast(@as(u32, 0xDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd2\xDE\xAD\xBE\xEF", actual);
}

test "Serialize i64 to uint32" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i64 = std.math.minInt(i32);
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd2\x80\x00\x00\x00", actual);
}

test "Serialize i64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i64 = @bitCast(@as(u64, 0xDEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize i128 to uint64" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i128 = @bitCast(@as(u128, 0xFFFFFFFFFFFFFFFF_DEADBEEFDEADBEEF));
    try packer.pack(val);
    const actual = packer.finish();
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("\xd3\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF", actual);
}

test "Serialize error TypeTooLarge with int" {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val: i128 = @bitCast(@as(u128, 0xFFFFFFFFFFFFFFF0_DEADBEEFDEADBEEF));
    try testing.expectError(
        SerializeError.TypeTooLarge,
        packer.pack(val),
    );
}
