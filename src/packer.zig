const std = @import("std");
const Marker = @import("marker.zig").Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
pub const SerializeError = error{ TypeTooLarge, WrongType, TypeUnsupported };

/// Newtype to differentiate between a string (STR) and a byte array (BIN).
pub const String = struct {
    str: []const u8,
    pub fn init(str: []const u8) String {
        return String{ .str = str };
    }
};

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
            .buffer = try allocator.alloc(u8, 0),
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
        // Don't forget this
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings("\x7F", actual);
    }

    pub fn pack(self: *Packer, object: anytype) !void {
        errdefer self.allocator.free(self.buffer);
        const T = @TypeOf(object);
        return switch (@typeInfo(T)) {
            .Int => self.pack_int(@TypeOf(object), object),
            .Bool => {
                if (!self.allocator.resize(
                    self.buffer,
                    self.buffer.len + 1,
                )) {
                    self.buffer = try self.allocator.realloc(
                        self.buffer,
                        self.buffer.len + 1,
                    );
                }
                if (object) {
                    self.buffer[self.offset] = Marker.TRUE;
                } else {
                    self.buffer[self.offset] = Marker.FALSE;
                }
                self.offset += 1;
            },
            .Optional => {
                if (object == null) {
                    if (!self.allocator.resize(
                        self.buffer,
                        self.buffer.len + 1,
                    )) {
                        self.buffer = try self.allocator.realloc(
                            self.buffer,
                            self.buffer.len + 1,
                        );
                    }
                    self.buffer[self.offset] = Marker.NIL;
                    self.offset += 1;
                } else {
                    try self.pack(object.?);
                }
            },
            .Float => {
                try self.pack_float(@TypeOf(object), object);
            },
            .Struct => {
                if (T == String) {
                    const bytes_needed = object.str.len;
                    if (!self.allocator.resize(
                        self.buffer,
                        self.buffer.len + bytes_needed + 1,
                    )) {
                        self.buffer = try self.allocator.realloc(
                            self.buffer,
                            self.buffer.len + bytes_needed + 1,
                        );
                    }
                    std.mem.writeInt(
                        u8,
                        std.mem.bytesAsValue(
                            [1]u8,
                            self.buffer[self.offset .. self.offset + 1],
                        ),
                        0x50 | @as(u8, @intCast(bytes_needed)),
                        Endian.big,
                    );
                    self.offset += 1;

                    @memcpy(self.buffer[self.offset .. self.offset + bytes_needed], object.str);
                } else {
                    std.debug.print("Pointer not supported.", .{});
                }
            },
            else => @compileError("Type not serializable into msgpack."),
        };
    }

    fn pack_float(self: *Packer, comptime T: type, value: T) !void {
        const marker = switch (@typeInfo(T).Float.bits) {
            32 => Marker.FLOAT_32,
            64 => Marker.FLOAT_64,
            else => return SerializeError.TypeUnsupported,
        };

        const bytes_needed = @sizeOf(T);
        if (!self.allocator.resize(
            self.buffer,
            self.buffer.len + bytes_needed + 1,
        )) {
            self.buffer = try self.allocator.realloc(
                self.buffer,
                self.buffer.len + bytes_needed + 1,
            );
        }
        std.mem.writeInt(
            u8,
            std.mem.bytesAsValue(
                [1]u8,
                self.buffer[self.offset .. self.offset + 1],
            ),
            marker,
            Endian.big,
        );
        self.offset += 1;

        comptime var type_info = @typeInfo(u32);
        type_info.Int.bits = bytes_needed * 8;
        const OutType = @Type(type_info);
        std.mem.writeInt(
            OutType,
            std.mem.bytesAsValue(
                [bytes_needed]u8,
                self.buffer[self.offset .. self.offset + bytes_needed],
            ),
            @bitCast(value),
            Endian.big,
        );
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
