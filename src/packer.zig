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

/// Packer struct.
///
/// Writes msgpack-encoded data to an `std.Io.Writer`.
/// Call `Packer.finish()` to flush the writer when done.
pub const Packer = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    /// Initialize a Packer backed by an io.Writer.
    pub fn init(writer: *std.Io.Writer, allocator: std.mem.Allocator) Packer {
        return .{ .writer = writer, .allocator = allocator };
    }

    /// Flush the underlying writer.
    pub fn finish(self: *Packer) void {
        self.writer.flush() catch {};
    }

    pub fn pack(self: *Packer, object: anytype) !void {
        return self.write(object);
    }

    fn write(self: *Packer, object: anytype) !void {
        const T = @TypeOf(object);
        return switch (@typeInfo(T)) {
            .int => self.write_int(@TypeOf(object), object),
            .bool => self.writer.writeByte(marker.encode(if (object)
                Marker.True
            else
                Marker.False)),
            .optional => {
                if (object == null) {
                    try self.writer.writeByte(marker.encode(Marker.Nil));
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
        try self.writer.writeByte(mark);

        const OutType = @Int(.unsigned, @typeInfo(T).float.bits);
        var int_buf: [8]u8 = undefined;
        std.mem.writeInt(OutType, int_buf[0..@sizeOf(OutType)], @bitCast(value), Endian.big);
        try self.writer.writeAll(int_buf[0..bytes_needed]);
    }

    fn write_int(self: *Packer, comptime T: type, value: T) !void {
        if (std.math.minInt(i6) <= value and value <= maxInt(u7)) {
            const mark = marker.encode(if (std.math.sign(value) == -1)
                Marker{ .FixNegative = @bitCast(@as(i5, @truncate(value))) }
            else
                Marker{ .FixPositive = @intCast(value) });

            try self.writer.writeByte(mark);
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

                try self.writer.writeByte(marker.encode(
                    if (type_info.int.signedness == .signed and value <= maxInt(OutType))
                        mark.signed
                    else
                        mark.unsigned,
                ));

                var int_buf: [8]u8 = undefined;
                std.mem.writeInt(OutType, int_buf[0..@sizeOf(OutType)], @intCast(value), Endian.big);
                try self.writer.writeAll(int_buf[0..byte_count]);
                return;
            }
        }
        return SerializeError.IntTooLarge;
    }

    fn write_string(self: *Packer, string: []const u8) !void {
        const len = string.len;
        try self.write_string_header(len);
        try self.writer.writeAll(string);
    }

    fn write_string_header(self: *Packer, len: usize) !void {
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

        try self.writer.writeByte(marker.encode(mark));

        inline for (.{
            Marker.Str_8,
            Marker.Str_16,
            Marker.Str_32,
        }, .{ u8, u16, u32 }) |m, OutType| {
            if (m == mark) {
                const byte_count = @typeInfo(OutType).int.bits / 8;
                var int_buf: [4]u8 = undefined;
                std.mem.writeInt(OutType, int_buf[0..@sizeOf(OutType)], @intCast(len), Endian.big);
                try self.writer.writeAll(int_buf[0..byte_count]);
                break;
            }
        }
    }

    fn write_bin(self: *Packer, string: []const u8) !void {
        const len = string.len;
        try self.write_bin_header(len);
        try self.writer.writeAll(string);
    }

    fn write_bin_header(self: *Packer, len: usize) !void {
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

        try self.writer.writeByte(marker.encode(mark));

        inline for (.{
            Marker.Bin_8,
            Marker.Bin_16,
            Marker.Bin_32,
        }, .{ u8, u16, u32 }) |m, OutType| {
            if (m == mark) {
                const byte_count = @typeInfo(OutType).int.bits / 8;
                var int_buf: [4]u8 = undefined;
                std.mem.writeInt(OutType, int_buf[0..@sizeOf(OutType)], @intCast(len), Endian.big);
                try self.writer.writeAll(int_buf[0..byte_count]);
                break;
            }
        }
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

        try self.write_array_header(len);

        for (array) |element| {
            try self.write(element);
        }
    }

    fn write_array_header(self: *Packer, len: usize) !void {
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

        try self.writer.writeByte(marker.encode(mark));

        switch (mark) {
            .FixArray => {},
            .Array_16 => {
                var int_buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &int_buf, @intCast(len), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            .Array_32 => {
                var int_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &int_buf, @intCast(len), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            else => unreachable,
        }
    }

    fn write_map(self: *Packer, map: anytype) !void {
        const count = map.count();
        try self.write_map_header(count);
        var iter = map.iterator();
        while (iter.next()) |entry| {
            try self.write(entry.key_ptr);
            try self.write(entry.value_ptr);
        }
    }

    fn write_map_header(self: *Packer, count: usize) !void {
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

        try self.writer.writeByte(marker.encode(mark));

        switch (mark) {
            .FixMap => {},
            .Map_16 => {
                var int_buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &int_buf, @intCast(count), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            .Map_32 => {
                var int_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &int_buf, @intCast(count), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            else => unreachable,
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
        try self.write_map_header(count);
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
                maxInt(u8) + 1...maxInt(u16) => Marker{ .Ext_16 = 0 },
                maxInt(u16) + 1...maxInt(u32) => Marker{ .Ext_32 = 0 },
                else => unreachable,
            };

        try self.writer.writeByte(marker.encode(mark));

        switch (mark) {
            .FixExt_1, .FixExt_2, .FixExt_4, .FixExt_8, .FixExt_16 => {},
            .Ext_8 => try self.writer.writeByte(@intCast(size)),
            .Ext_16 => {
                var int_buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &int_buf, @intCast(size), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            .Ext_32 => {
                var int_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &int_buf, @intCast(size), Endian.big);
                try self.writer.writeAll(&int_buf);
            },
            else => unreachable,
        }

        try self.writer.writeByte(@bitCast(ext));

        const custom_buffer = try @TypeOf(object).__msgpack__.pack_ext(object, self.allocator);
        defer self.allocator.free(custom_buffer);
        try self.writer.writeAll(custom_buffer);
    }
};
