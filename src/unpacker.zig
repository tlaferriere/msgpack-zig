const std = @import("std");

const Marker = @import("marker.zig").Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
pub const DeserializeError = error{ TypeTooSmall, WrongType, Finished };

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

    pub fn unpack_as(self: *Unpacker, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .Int => |int| self.unpack_int(int, As),
            .Bool => switch (self.buffer[0]) {
                Marker.FALSE => {
                    self.offset += 1;
                    return false;
                },
                Marker.TRUE => {
                    self.offset += 1;
                    return true;
                },
                else => DeserializeError.WrongType,
            },
            .Optional => |optional| switch (self.buffer[0]) {
                Marker.NIL => {
                    self.offset += 1;
                    return null;
                },
                else => try self.unpack_as(optional.child),
            },
            .Float => |float| self.unpack_float(float, As),
            else => @compileError("Msgpack cannot serialize this type."),
        };
    }

    fn unpack_float(
        self: *Unpacker,
        comptime float: Type.Float,
        comptime As: type,
    ) !As {
        return switch (self.buffer[self.offset]) {
            Marker.FLOAT_32 => if (float.bits >= 32) {
                const value = @as(
                    As,
                    @floatCast(
                        @as(f32, @bitCast(std.mem.readVarInt(
                            u32,
                            self.buffer[self.offset + 1 .. self.offset + 5],
                            Endian.big,
                        ))),
                    ),
                );
                self.offset += 5;
                return value;
            } else DeserializeError.TypeTooSmall,
            Marker.FLOAT_64 => if (float.bits >= 64) {
                const value = @as(
                    As,
                    @floatCast(
                        @as(f64, @bitCast(std.mem.readVarInt(
                            u64,
                            self.buffer[self.offset + 1 .. self.offset + 9],
                            Endian.big,
                        ))),
                    ),
                );
                self.offset += 9;
                return value;
            } else DeserializeError.TypeTooSmall,
            else => DeserializeError.WrongType,
        };
    }

    fn unpack_int(
        self: *Unpacker,
        comptime int: Type.Int,
        comptime As: type,
    ) !As {
        return switch (int.signedness) {
            .unsigned => switch (self.buffer[self.offset]) {
                Marker.UINT_64 => if (int.bits >= 64) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 9],
                        Endian.big,
                    );
                    self.offset += 9;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_32 => if (int.bits >= 32) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 5],
                        Endian.big,
                    );
                    self.offset += 5;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_16 => if (int.bits >= 16) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 3],
                        Endian.big,
                    );
                    self.offset += 3;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits >= 8) {
                    const value: As = @intCast(self.buffer[self.offset + 1]);
                    self.offset += 2;
                    return value;
                } else DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[self.offset] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    const value: As = @intCast(self.buffer[self.offset]); // Unsafe if compiler-optimized.
                    self.offset += 1;
                    return value;
                },
            },
            .signed => switch (self.buffer[self.offset]) {
                Marker.UINT_64, Marker.INT_64 => if (int.bits >= 64) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 9],
                        Endian.big,
                    );
                    self.offset += 9;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_32, Marker.INT_32 => if (int.bits >= 32) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 5],
                        Endian.big,
                    );
                    self.offset += 5;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_16, Marker.INT_16 => if (int.bits >= 16) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 3],
                        Endian.big,
                    );
                    self.offset += 3;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.UINT_8 => if (int.bits > 8) {
                    const value: As = @intCast(self.buffer[self.offset + 1]);
                    self.offset += 2;
                    return value;
                } else DeserializeError.TypeTooSmall,

                Marker.INT_8 => if (int.bits >= 8) {
                    const value: As = @intCast(
                        @as(i8, @bitCast(self.buffer[self.offset + 1])),
                    );
                    self.offset += 2;
                    return value;
                } else DeserializeError.TypeTooSmall,

                else => {
                    if (self.buffer[self.offset] & 0xE0 != 0xE0 and
                        self.buffer[self.offset] & 0x80 != 0)
                        return DeserializeError.WrongType;
                    // Fixint
                    return @intCast(@as(i8, @bitCast(self.buffer[self.offset]))); // Unsafe if compiler-optimized.
                },
            },
        };
    }
};
