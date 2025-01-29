const std = @import("std");

const Marker = @import("marker.zig").Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
pub const DeserializeError = error{ TypeTooSmall, WrongType };

pub const Unpacker = struct {
    buffer: []const u8,
    offset: usize,

    pub fn init(
        buffer: []const u8,
        offset: usize,
    ) !Unpacker {
        return Unpacker{
            .buffer = buffer,
            .offset = offset,
        };
    }

    pub fn unpack_as(self: Unpacker, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .Int => |int| self.unpack_int(int, As),
            .Bool => switch (self.buffer[0]) {
                Marker.FALSE => false,
                Marker.TRUE => true,
                else => DeserializeError.WrongType,
            },
            .Optional => |optional| switch (self.buffer[0]) {
                Marker.NIL => null,
                else => try self.unpack_as(optional.child),
            },
            .Float => |float| self.unpack_float(float, As),
            else => @compileError("Msgpack cannot serialize this type."),
        };
    }

    fn unpack_float(
        self: Unpacker,
        comptime float: Type.Float,
        comptime As: type,
    ) !As {
        return switch (self.buffer[0]) {
            0xca => if (float.bits >= 32) @as(
                As,
                @floatCast(
                    @as(f32, @bitCast(std.mem.readVarInt(
                        u32,
                        self.buffer[1..5],
                        Endian.big,
                    ))),
                ),
            ) else DeserializeError.TypeTooSmall,
            0xcb => if (float.bits >= 64) @as(
                As,
                @floatCast(
                    @as(f64, @bitCast(std.mem.readVarInt(
                        u64,
                        self.buffer[1..9],
                        Endian.big,
                    ))),
                ),
            ) else DeserializeError.TypeTooSmall,
            else => DeserializeError.WrongType,
        };
    }

    fn unpack_int(
        self: Unpacker,
        comptime int: Type.Int,
        comptime As: type,
    ) !As {
        return switch (int.signedness) {
            .unsigned => switch (self.buffer[0]) {
                Marker.UINT_64 => if (int.bits >= 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_32 => if (int.bits >= 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_16 => if (int.bits >= 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits >= 8)
                    @intCast(self.buffer[1])
                else
                    DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[0] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    return @intCast(self.buffer[0]); // Unsafe if compiler-optimized.
                },
            },
            .signed => switch (self.buffer[0]) {
                // Is it safe to accept a uint encoded as an int?
                Marker.UINT_64 => if (int.bits > 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_32 => if (int.bits > 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_16 => if (int.bits > 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits > 8)
                    @intCast(self.buffer[1])
                else
                    DeserializeError.TypeTooSmall,
                Marker.INT_64 => if (int.bits >= 64) std.mem.readVarInt(
                    As,
                    self.buffer[1..9],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_32 => if (int.bits >= 32) std.mem.readVarInt(
                    As,
                    self.buffer[1..5],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_16 => if (int.bits >= 16) std.mem.readVarInt(
                    As,
                    self.buffer[1..3],
                    Endian.big,
                ) else DeserializeError.TypeTooSmall,

                Marker.INT_8 => if (int.bits >= 8)
                    @intCast(@as(i8, @bitCast(self.buffer[1])))
                else
                    DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[0] & 0xE0 != 0xE0 and
                        self.buffer[0] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    return @intCast(@as(i8, @bitCast(self.buffer[0]))); // Unsafe if compiler-optimized.
                },
            },
        };
    }
};
