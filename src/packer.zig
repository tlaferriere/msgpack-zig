const std = @import("std");
const maxInt = std.math.maxInt;
const testing = std.testing;
const Endian = std.builtin.Endian;

const marker = @import("marker.zig");
const Marker = marker.Marker;

pub const SerializeError = error{
    IntTooLarge,
    StringTooLarge,
    ArrayTooLarge,
    MapTooLarge,
    ExtTooLarge,
};

const BinType = struct {
    str: []const u8,
};

/// Newtype to differentiate between a string (STR) and a byte array (BIN).
///
/// Since there is no distinction in Zig between strings and []u8, we provide
/// a newtype to signal to msgpack that you wish these bytes to be packed as
/// a bin.
pub fn Bin(str: []const u8) BinType {
    return BinType{ .str = str };
}

test Bin {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "Hello, World!";
    try packer.pack(Bin(val));

    const actual = packer.finish();
    defer testing.allocator.free(actual);

    try testing.expectEqualStrings(
        // Packed with the special markers for strings
        "\xc4" ++ .{13} ++ val,
        actual,
    );
}

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
        const required_bytes = try packed_size(object);
        if (!self.allocator.resize(
            self.buffer,
            self.buffer.len + required_bytes,
        )) {
            self.buffer = try self.allocator.realloc(
                self.buffer,
                self.buffer.len + required_bytes,
            );
        }
        errdefer self.allocator.free(self.buffer);
        return self.write(object);
    }

    fn write(self: *Packer, object: anytype) !void {
        const T = @TypeOf(object);
        return switch (@typeInfo(T)) {
            .int => self.write_int(@TypeOf(object), object),
            .bool => {
                self.buffer[self.offset] = marker.encode(if (object)
                    Marker.True
                else
                    Marker.False);
                self.offset += 1;
            },
            .optional => {
                if (object == null) {
                    self.buffer[self.offset] = marker.encode(Marker.Nil);
                    self.offset += 1;
                } else {
                    try self.write(object.?);
                }
            },
            .float => {
                try self.write_float(@TypeOf(object), object);
            },
            .@"struct" => {
                if (T == BinType) {
                    return self.write_bin(object.str);
                }
                if (@hasDecl(T, "iterator") and
                    @hasDecl(T, "Iterator") and
                    @hasDecl(T, "Entry") and
                    @hasField(T.Entry, "key_ptr") and
                    @hasField(T.Entry, "value_ptr") and
                    @hasDecl(T, "count"))
                {
                    return self.write_map(object);
                }
                if (@hasDecl(T, "__msgpack__")) {
                    return self.write_struct(object);
                }
                @compileError("Struct not supported yet.");
            },
            .array => |array| if (array.child == u8)
                self.write_string(&object)
            else
                self.write_array(array.len, object),
            .pointer => |pointer| switch (pointer.size) {
                .one => self.write(object.*),
                .slice, .many => if (pointer.child == u8) {
                    try self.write_string(object);
                } else self.write_array(null, object),
                .c => {
                    @compileLog(pointer);
                    @compileError("C sized pointer is not supported.");
                },
            },
            else => {
                @compileLog(T);
                @compileError("Type not serializable into msgpack.");
            },
        };
    }

    fn write_float(self: *Packer, comptime T: type, value: T) !void {
        const mark = marker.encode(switch (@typeInfo(T).float.bits) {
            32 => .Float_32,
            64 => .Float_64,
            else => unreachable,
        });

        const bytes_needed = @sizeOf(T);
        self.buffer[self.offset] = mark;
        self.offset += 1;

        const OutType = @Int(.unsigned, @typeInfo(T).float.bits);
        std.mem.writeInt(
            OutType,
            @ptrCast(self.buffer[self.offset .. self.offset + bytes_needed].ptr),
            @bitCast(value),
            Endian.big,
        );
        // TODO: Test the bug of this statement missing
        self.offset += bytes_needed;
    }

    fn write_int(self: *Packer, comptime T: type, value: T) !void {
        if (std.math.minInt(i6) <= value and value <= maxInt(u7)) {
            const mark = marker.encode(if (std.math.sign(value) == -1)
                Marker{ .FixNegative = @bitCast(@as(i5, @truncate(value))) }
            else
                Marker{ .FixPositive = @intCast(value) });

            self.buffer[self.offset] = mark;
            self.offset += 1;
            return;
        }
        const byte_counts = .{ 1, 2, 4, 8 };
        const markers = .{
            .{ .signed = Marker.Int_8, .unsigned = Marker.Uint_8 },
            .{ .signed = Marker.Int_16, .unsigned = Marker.Uint_16 },
            .{ .signed = Marker.Int_32, .unsigned = Marker.Uint_32 },
            .{ .signed = Marker.Int_64, .unsigned = Marker.Uint_64 },
        };
        inline for (byte_counts, markers) |byte_count, mark| {
            const i = @Int(.signed, byte_count * 8);
            const u = @Int(.unsigned, byte_count * 8);
            if (std.math.minInt(i) <= value and value <= maxInt(u)) {
                comptime var type_info = @typeInfo(T);
                type_info.int.bits = byte_count * 8;
                const OutType = @Int(type_info.int.signedness, type_info.int.bits);

                self.buffer[self.offset] = marker.encode(
                    if (type_info.int.signedness == .signed and value <= maxInt(OutType))
                        mark.signed
                    else
                        mark.unsigned,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    @ptrCast(self.buffer[self.offset .. self.offset + byte_count].ptr),
                    @intCast(value),
                    Endian.big,
                );
                self.offset += byte_count;
                return;
            }
        }
    }

    fn write_string(self: *Packer, string: []const u8) !void {
        const len = string.len;
        const mark =
            if (len < maxInt(u5))
                Marker{ .FixStr = @intCast(len) }
            else if (len <= maxInt(u8))
                Marker{ .Str_8 = 0 }
            else if (len <= maxInt(u16))
                Marker{ .Str_16 = 0 }
            else if (len <= maxInt(u32))
                Marker{ .Str_32 = 0 }
            else {
                return SerializeError.StringTooLarge;
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        inline for (.{
            Marker.Str_8,
            Marker.Str_16,
            Marker.Str_32,
        }, .{ u8, u16, u32 }) |m, OutType| {
            if (m == mark) {
                const byte_count = @typeInfo(OutType).int.bits / 8;
                std.mem.writeInt(
                    OutType,
                    @ptrCast(self.buffer[self.offset .. self.offset + byte_count].ptr),
                    @intCast(len),
                    Endian.big,
                );
                self.offset += byte_count;
                break;
            }
        }

        @memcpy(self.buffer[self.offset .. self.offset + len], string);
        self.offset += len;
    }

    fn write_bin(self: *Packer, string: []const u8) !void {
        const len = string.len;
        const mark =
            if (len <= maxInt(u8))
                Marker{ .Bin_8 = 0 }
            else if (len <= maxInt(u16))
                Marker{ .Bin_16 = 0 }
            else if (len <= maxInt(u32))
                Marker{ .Bin_32 = 0 }
            else {
                return SerializeError.StringTooLarge;
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        inline for (.{
            Marker.Bin_8,
            Marker.Bin_16,
            Marker.Bin_32,
        }, .{ u8, u16, u32 }) |m, OutType| {
            if (m == mark) {
                const byte_count = @typeInfo(OutType).int.bits / 8;
                std.mem.writeInt(
                    OutType,
                    @ptrCast(self.buffer[self.offset .. self.offset + byte_count].ptr),
                    @intCast(len),
                    Endian.big,
                );
                self.offset += byte_count;
                break;
            }
        }

        @memcpy(self.buffer[self.offset .. self.offset + len], string);
        self.offset += len;
    }

    fn write_array(
        self: *Packer,
        comptime static_len: ?usize,
        array: anytype,
    ) !void {
        const len = if (static_len == null)
            array.len
        else
            static_len.?;

        const mark =
            if (len <= maxInt(u4))
                Marker{ .FixArray = @intCast(len) }
            else if (len <= maxInt(u16))
                Marker{ .Array_16 = 0 }
            else if (len <= maxInt(u32))
                Marker{ .Array_32 = 0 }
            else {
                return SerializeError.ArrayTooLarge;
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        switch (mark) {
            .FixArray => {},
            .Array_16 => {
                std.mem.writeInt(
                    u16,
                    @ptrCast(self.buffer[self.offset .. self.offset + 2].ptr),
                    @intCast(len),
                    Endian.big,
                );
                self.offset += 2;
            },
            .Array_32 => {
                std.mem.writeInt(
                    u32,
                    @ptrCast(self.buffer[self.offset .. self.offset + 4].ptr),
                    @intCast(len),
                    Endian.big,
                );
                self.offset += 4;
            },
            else => unreachable,
        }
        for (array) |element| {
            try self.write(element);
        }
    }

    fn write_map(self: *Packer, map: anytype) !void {
        const count = map.count();
        const mark =
            if (count <= maxInt(u4))
                Marker{ .FixMap = @intCast(count) }
            else if (count <= maxInt(u16))
                Marker{ .Map_16 = 0 }
            else if (count <= maxInt(u32))
                Marker{ .Map_32 = 0 }
            else {
                return SerializeError.MapTooLarge;
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        switch (mark) {
            .FixMap => {},
            .Map_16 => {
                std.mem.writeInt(
                    u16,
                    @ptrCast(self.buffer[self.offset .. self.offset + 2].ptr),
                    @intCast(count),
                    Endian.big,
                );
                self.offset += 2;
            },
            .Map_32 => {
                std.mem.writeInt(
                    u32,
                    @ptrCast(self.buffer[self.offset .. self.offset + 4].ptr),
                    @intCast(count),
                    Endian.big,
                );
                self.offset += 4;
            },
            else => unreachable,
        }
        var iter = map.iterator();
        while (iter.next()) |entry| {
            try self.write(entry.key_ptr);
            try self.write(entry.value_ptr);
        }
    }

    fn write_struct(self: *Packer, object: anytype) !void {
        switch (@TypeOf(object).__msgpack__.repr) {
            .ext => |ext| try self.write_ext(object, ext),
            .map => try self.write_struct_as_map(object),
        }
    }

    fn write_struct_as_map(self: *Packer, object: anytype) !void {
        const fields = @typeInfo(@TypeOf(object)).@"struct".fields;
        const count = fields.len;

        const mark =
            if (count <= maxInt(u4))
                Marker{ .FixMap = @intCast(count) }
            else if (count <= maxInt(u16))
                Marker{ .Map_16 = 0 }
            else if (count <= maxInt(u32))
                Marker{ .Map_32 = 0 }
            else {
                return SerializeError.MapTooLarge;
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        switch (mark) {
            .FixMap => {},
            .Map_16 => {
                std.mem.writeInt(
                    u16,
                    @ptrCast(self.buffer[self.offset .. self.offset + 2].ptr),
                    @intCast(count),
                    Endian.big,
                );
                self.offset += 2;
            },
            .Map_32 => {
                std.mem.writeInt(
                    u32,
                    @ptrCast(self.buffer[self.offset .. self.offset + 4].ptr),
                    @intCast(count),
                    Endian.big,
                );
                self.offset += 4;
            },
            else => unreachable,
        }

        inline for (fields) |field| {
            try self.write(field.name);
            try self.write(@field(object, field.name));
        }
    }

    fn write_ext(self: *Packer, object: anytype, ext: i8) !void {
        const size = try @TypeOf(object).__msgpack__.packed_size(object);
        const mark =
            switch (size) {
                1 => Marker{ .FixExt_1 = 0 },
                2 => Marker{ .FixExt_2 = 0 },
                4 => Marker{ .FixExt_4 = 0 },
                8 => Marker{ .FixExt_8 = 0 },
                16 => Marker{ .FixExt_16 = 0 },
                3, 5...7, 9...15, 17...maxInt(u8) => Marker{ .Ext_8 = 0 },
                maxInt(u8) + 1...maxInt(u16) => Marker{
                    .Ext_16 = 0,
                },
                maxInt(u16) + 1...maxInt(u32) => Marker{
                    .Ext_32 = 0,
                },
                else => {
                    unreachable;
                },
            };

        self.buffer[self.offset] = marker.encode(mark);
        self.offset += 1;

        switch (mark) {
            .FixExt_1,
            .FixExt_2,
            .FixExt_4,
            .FixExt_8,
            .FixExt_16,
            => {},
            .Ext_8 => {
                self.buffer[self.offset] = @intCast(size);
                self.offset += 1;
            },
            .Ext_16 => {
                std.mem.writeInt(
                    u16,
                    @ptrCast(self.buffer[self.offset .. self.offset + 2].ptr),
                    @intCast(size),
                    Endian.big,
                );
                self.offset += 2;
            },
            .Ext_32 => {
                std.mem.writeInt(
                    u32,
                    @ptrCast(self.buffer[self.offset .. self.offset + 4].ptr),
                    @intCast(size),
                    Endian.big,
                );
                self.offset += 4;
            },
            else => unreachable,
        }

        self.buffer[self.offset] = @bitCast(ext);
        self.offset += 1;

        const custom_buffer = try @TypeOf(object).__msgpack__.pack_ext(object, self.allocator);
        defer self.allocator.free(custom_buffer);
        @memcpy(
            self.buffer[self.offset .. self.offset + size],
            custom_buffer,
        );
        self.offset += size;
    }
};

fn packed_size(object: anytype) !usize {
    const T = @TypeOf(object);
    return switch (@typeInfo(T)) {
        .int => try int_packed_size(@TypeOf(object), object),
        .bool => 1,
        .optional => if (object == null)
            1
        else
            packed_size(object.?),
        .float => float_packed_size(@TypeOf(object)),
        .@"struct" => if (T == BinType)
            bin_packed_size(object.str)
        else if (@hasDecl(T, "iterator") and
            @hasDecl(T, "Iterator") and
            @hasDecl(T, "Entry") and
            @hasField(T.Entry, "key_ptr") and
            @hasField(T.Entry, "value_ptr") and
            @hasDecl(T, "count"))
            map_packed_size(object)
        else if (@hasDecl(T, "__msgpack__"))
            struct_packed_size(object)
        else {
            @compileError(std.fmt.comptimePrint(
                \\I don't know how to serialize your struct {}.
                \\Please add a `__msgpack__` declaration to your struct with type `msgpack.Repr`:
                \\Suggested:
                \\```
                \\    const {} = struct {{
                \\        ...
                \\        pub const __msgpack__ = {{
                \\            pub const repr = msgpack.Repr{{ .ext = type_id }};
                \\            pub fn pack_ext(self: Self, alloc: std.mem.Allocator) ![]const u8 {{...}}
                \\            pub fn packed_size(self: Self) !usize {{...}}
                \\        }}
                \\    }}
                \\```
                \\Note: For ext types, pack_ext and packed_size must be marked pub.
            , .{ .a = T, .b = T }));
        },
        .array => |array| if (array.child == u8)
            bin_packed_size(&object)
        else
            array_packed_size(array.len, object),
        .pointer => |pointer| switch (pointer.size) {
            .one => if (@typeInfo(pointer.child) == .array and
                @typeInfo(pointer.child).array.child == u8)
                string_packed_size(object)
            else
                packed_size(object.*),
            .slice, .many => array_packed_size(null, object),
            .c => @compileError("C sized pointer."),
        },
        else => {
            @compileLog(T);
            @compileError("Type not serializable into msgpack.");
        },
    };
}

fn int_packed_size(comptime T: type, value: T) !usize {
    return if (std.math.minInt(i6) <= value and value <= maxInt(u7))
        1
    else if (std.math.minInt(i8) <= value and value <= maxInt(u8))
        2
    else if (std.math.minInt(i16) <= value and value <= maxInt(u16))
        3
    else if (std.math.minInt(i32) <= value and value <= maxInt(u32))
        5
    else if (std.math.minInt(i64) <= value and value <= maxInt(u64))
        9
    else
        SerializeError.IntTooLarge;
}

fn float_packed_size(comptime T: type) !usize {
    return switch (@typeInfo(T).float.bits) {
        32 => 5,
        64 => 9,
        else => @compileError(std.fmt.comptimePrint(
            "{} not supported in msgpack.",
            .{@typeName(T)},
        )),
    };
}

fn string_packed_size(string: []const u8) !usize {
    const bytes_needed = string.len;
    return if (bytes_needed <= maxInt(u5))
        1 + bytes_needed
    else if (bytes_needed <= maxInt(u8))
        2 + bytes_needed
    else if (bytes_needed <= maxInt(u16))
        3 + bytes_needed
    else if (bytes_needed <= maxInt(u32))
        5 + bytes_needed
    else
        SerializeError.StringTooLarge;
}

fn bin_packed_size(bin: []const u8) !usize {
    const bytes_needed = bin.len;
    return if (bytes_needed <= maxInt(u8))
        2 + bytes_needed
    else if (bytes_needed <= maxInt(u16))
        3 + bytes_needed
    else if (bytes_needed <= maxInt(u32))
        5 + bytes_needed
    else
        SerializeError.StringTooLarge;
}

fn array_packed_size(comptime len: ?usize, array: anytype) !usize {
    const array_len = if (len == null) array.len else len.?;
    var packed_len: usize = if (array_len <= maxInt(u4))
        1
    else if (array_len <= maxInt(u16))
        3
    else if (array_len <= maxInt(u32))
        5
    else
        return SerializeError.ArrayTooLarge;
    for (array) |element| {
        packed_len += try packed_size(element);
    }
    return packed_len;
}

fn map_packed_size(map: anytype) !usize {
    const count = map.count();
    var packed_len: usize = if (count <= maxInt(u4))
        1
    else if (count <= maxInt(u16))
        3
    else if (count <= maxInt(u32))
        5
    else
        return SerializeError.ArrayTooLarge;
    var iter = map.iterator();
    while (iter.next()) |entry| {
        packed_len += try packed_size(entry.key_ptr.*);
        packed_len += try packed_size(entry.value_ptr.*);
    }
    return packed_len;
}

fn struct_packed_size(object: anytype) !usize {
    switch (@TypeOf(object).__msgpack__.repr) {
        .ext => {
            const size = try @TypeOf(object).__msgpack__.packed_size(object);
            const marker_overhead_bytes = 2;
            const length_overhead_bytes: usize = switch (size) {
                1, 2, 4, 8, 16 => 0,
                3, 5...7, 9...15, 17...maxInt(u8) => 1,
                maxInt(u8) + 1...maxInt(u16) => 2,
                maxInt(u16) + 1...maxInt(u32) => 4,
                else => return SerializeError.ExtTooLarge,
            };
            return marker_overhead_bytes + length_overhead_bytes + size;
        },
        .map => {
            const fields = @typeInfo(@TypeOf(object)).@"struct".fields;
            const count = fields.len;
            var packed_len: usize = if (count <= maxInt(u4))
                1
            else if (count <= maxInt(u16))
                3
            else if (count <= maxInt(u32))
                5
            else
                return SerializeError.MapTooLarge;
            inline for (fields) |field| {
                packed_len += try packed_size(field.name);
                packed_len += try packed_size(@field(object, field.name));
            }
            return packed_len;
        },
    }
}
