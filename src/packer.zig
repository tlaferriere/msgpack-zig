const std = @import("std");
const marker = @import("marker.zig");
const Marker = marker.Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
pub const SerializeError = error{
    TypeTooLarge,
    WrongType,
    TypeUnsupported,
    StringTooLarge,
};

const StringType = struct {
    str: []const u8,
};

/// Newtype to differentiate between a string (STR) and a byte array (BIN).
///
/// Since there is no distinction in Zig between strings and []u8, we provide
/// a newtype to signal to msgpack that you wish these bytes to be packed as
/// a string.
pub fn String(str: []const u8) StringType {
    return StringType{ .str = str };
}

test String {
    var packer = try Packer.init(
        testing.allocator,
    );
    const val = "Hello, World!";
    try packer.pack(String(val));

    const actual = packer.finish();
    defer testing.allocator.free(actual);

    try testing.expectEqualStrings(
        // Packed with the special markers for strings
        "\xAD" ++ val,
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
            .Int => self.pack_int(@TypeOf(object), object),
            .Bool => {
                self.buffer[self.offset] = marker.encode(if (object)
                    Marker.True
                else
                    Marker.False);
                self.offset += 1;
            },
            .Optional => {
                if (object == null) {
                    self.buffer[self.offset] = marker.encode(Marker.Nil);
                    self.offset += 1;
                } else {
                    try self.pack(object.?);
                }
            },
            .Float => {
                try self.pack_float(@TypeOf(object), object);
            },
            .Struct => {
                if (T == StringType) {
                    try self.pack_string(object.str);
                } else {
                    @compileError("Structs not supported yet.");
                }
            },
            .Array => {},
            .Pointer => |pointer| if (@typeInfo(pointer.child).Array.child == u8) {
                const bytes_needed = object.len;
                const mark = marker.encode(
                    if (bytes_needed <= std.math.maxInt(u8))
                        Marker.Bin_8
                    else if (bytes_needed <= std.math.maxInt(u16))
                        Marker.Bin_16
                    else if (bytes_needed <= std.math.maxInt(u32))
                        Marker.Bin_32
                    else
                        unreachable,
                );

                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    mark,
                    Endian.big,
                );
                self.offset += 1;

                @memcpy(self.buffer[self.offset .. self.offset + bytes_needed], object);
            } else {
                self.pack(object.*);
            },
            else => {
                @compileLog(T);
                @compileError("Type not serializable into msgpack.");
            },
        };
    }

    fn pack_float(self: *Packer, comptime T: type, value: T) !void {
        const mark = marker.encode(switch (@typeInfo(T).Float.bits) {
            32 => .Float_32,
            64 => .Float_64,
            else => unreachable,
        });

        const bytes_needed = @sizeOf(T);
        std.mem.writeInt(
            u8,
            std.mem.bytesAsValue(
                [1]u8,
                self.buffer[self.offset .. self.offset + 1],
            ),
            mark,
            Endian.big,
        );
        self.offset += 1;

        const OutType = @Type(
            Type{
                .Int = Type.Int{
                    .signedness = .unsigned,
                    .bits = @typeInfo(T).Float.bits,
                },
            },
        );
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

    fn pack_int(self: *Packer, comptime T: type, value: T) !void {
        if (std.math.minInt(i6) <= value and value <= std.math.maxInt(u7)) {
            const mark = marker.encode(if (std.math.sign(value) == -1)
                Marker{ .FixNegative = @bitCast(@as(i5, @truncate(value))) }
            else
                Marker{ .FixPositive = @intCast(value) });

            std.mem.writeInt(
                u8,
                std.mem.bytesAsValue(
                    [1]u8,
                    self.buffer[self.offset .. self.offset + 1],
                ),
                mark,
                Endian.big,
            );
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
            const i = @Type(Type{
                .Int = Type.Int{
                    .signedness = .signed,
                    .bits = byte_count * 8,
                },
            });
            const u = @Type(Type{
                .Int = Type.Int{
                    .signedness = .unsigned,
                    .bits = byte_count * 8,
                },
            });
            if (std.math.minInt(i) <= value and value <= std.math.maxInt(u)) {
                comptime var type_info = @typeInfo(T);
                type_info.Int.bits = byte_count * 8;
                const OutType = @Type(type_info);

                std.mem.writeInt(
                    u8,
                    std.mem.bytesAsValue(
                        [1]u8,
                        self.buffer[self.offset .. self.offset + 1],
                    ),
                    marker.encode(
                        if (type_info.Int.signedness == .signed and value <= std.math.maxInt(OutType))
                            mark.signed
                        else
                            mark.unsigned,
                    ),
                    Endian.big,
                );
                self.offset += 1;

                std.mem.writeInt(
                    OutType,
                    std.mem.bytesAsValue(
                        [byte_count]u8,
                        self.buffer[self.offset .. self.offset + byte_count],
                    ),
                    @intCast(value),
                    Endian.big,
                );
                self.offset += byte_count;
                return;
            }
        }
    }

    fn pack_string(self: *Packer, string: []const u8) !void {
        const bytes_needed = string.len;
        const mark = marker.encode(
            if (bytes_needed < std.math.maxInt(u5))
                Marker{ .FixStr = @intCast(bytes_needed) }
            else if (bytes_needed <= std.math.maxInt(u8))
                Marker.Str_8
            else if (bytes_needed <= std.math.maxInt(u16))
                Marker.Str_16
            else if (bytes_needed <= std.math.maxInt(u32))
                Marker.Str_32
            else
                return SerializeError.StringTooLarge,
        );

        std.mem.writeInt(
            u8,
            std.mem.bytesAsValue(
                [1]u8,
                self.buffer[self.offset .. self.offset + 1],
            ),
            mark,
            Endian.big,
        );
        self.offset += 1;

        // TODO: Add str len here for types other than FixStr.

        @memcpy(self.buffer[self.offset .. self.offset + bytes_needed], string);
    }
};

fn packed_size(object: anytype) !usize {
    const T = @TypeOf(object);
    return switch (@typeInfo(T)) {
        .Int => try int_packed_size(@TypeOf(object), object),
        .Bool => 1,
        .Optional => if (object == null)
            1
        else
            packed_size(object.?),
        .Float => float_packed_size(@TypeOf(object)),
        .Struct => if (T == StringType)
            string_packed_size(object.str)
        else
            @compileError("Structs not supported yet."),
        .Array => |array| if (array.child == u8)
            bin_packed_size(object)
        else
            @compileError("Arrays not supported yet."),
        .Pointer => |pointer| if (@typeInfo(pointer.child).Array.child == u8)
            bin_packed_size(object)
        else
            packed_size(object.*),
        else => {
            @compileLog(T);
            @compileError("Type not serializable into msgpack.");
        },
    };
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

fn float_packed_size(comptime T: type) !usize {
    return switch (@typeInfo(T).Float.bits) {
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
    return if (bytes_needed <= std.math.maxInt(u5))
        1 + bytes_needed
    else if (bytes_needed <= std.math.maxInt(u8))
        2 + bytes_needed
    else if (bytes_needed <= std.math.maxInt(u16))
        3 + bytes_needed
    else if (bytes_needed <= std.math.maxInt(u32))
        5 + bytes_needed
    else
        SerializeError.StringTooLarge;
}

fn bin_packed_size(bin: []const u8) !usize {
    const bytes_needed = bin.len;
    return if (bytes_needed <= std.math.maxInt(u8))
        2 + bytes_needed
    else if (bytes_needed <= std.math.maxInt(u16))
        3 + bytes_needed
    else if (bytes_needed <= std.math.maxInt(u32))
        5 + bytes_needed
    else
        SerializeError.StringTooLarge;
}
