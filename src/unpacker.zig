const std = @import("std");

const marker = @import("marker.zig");
const Marker = marker.Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;
pub const DeserializeError = error{ TypeTooSmall, WrongType, Finished, WrongArrayLength };

pub const Unpacker = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    offset: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        offset: usize,
    ) !Unpacker {
        return Unpacker{
            .allocator = allocator,
            .buffer = buffer,
            .offset = offset,
        };
    }

    pub fn unpack_as(self: *Unpacker, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .Int => |int| self.unpack_int(int, As),
            .Bool => switch (try marker.decode(self.buffer[self.offset])) {
                .False => {
                    self.offset += 1;
                    return false;
                },
                .True => {
                    self.offset += 1;
                    return true;
                },
                else => DeserializeError.WrongType,
            },
            .Optional => |optional| switch (try marker.decode(self.buffer[self.offset])) {
                .Nil => {
                    self.offset += 1;
                    return null;
                },
                else => try self.unpack_as(optional.child),
            },
            .Float => |float| self.unpack_float(float, As),
            .Pointer => |pointer| switch (pointer.size) {
                .One => if (pointer.child == .Array) {
                    return self.unpack_array(pointer.child.Array.len, As);
                } else {
                    @compileError("Can't serialize objects behind pointers yet.");
                },
                .Slice => if (pointer.child == u8) {
                    return self.unpack_string(As);
                } else {
                    return self.unpack_array(null, As);
                },
                .Many => self.unpack_array(null, As),
                .C => @compileError("C sized pointer."),
            },
            .Array => |array| self.unpack_array(array.len, As),
            else => {
                @compileLog(As);
                @compileLog(@typeInfo(As));
                @compileError("Msgpack cannot serialize this type.");
            },
        };
    }

    fn unpack_float(
        self: *Unpacker,
        comptime float: Type.Float,
        comptime As: type,
    ) !As {
        return switch (try marker.decode(self.buffer[self.offset])) {
            .Float_32 => if (float.bits >= 32) {
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
            .Float_64 => if (float.bits >= 64) {
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
            .unsigned => switch (try marker.decode(self.buffer[self.offset])) {
                .Uint_64 => if (int.bits >= 64) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 9],
                        Endian.big,
                    );
                    self.offset += 9;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_32 => if (int.bits >= 32) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 5],
                        Endian.big,
                    );
                    self.offset += 5;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_16 => if (int.bits >= 16) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 3],
                        Endian.big,
                    );
                    self.offset += 3;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_8 => if (int.bits >= 8) {
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
            .signed => switch (try marker.decode(self.buffer[self.offset])) {
                .Uint_64, .Int_64 => if (int.bits >= 64) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 9],
                        Endian.big,
                    );
                    self.offset += 9;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_32, .Int_32 => if (int.bits >= 32) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 5],
                        Endian.big,
                    );
                    self.offset += 5;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_16, .Int_16 => if (int.bits >= 16) {
                    const value = std.mem.readVarInt(
                        As,
                        self.buffer[self.offset + 1 .. self.offset + 3],
                        Endian.big,
                    );
                    self.offset += 3;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Uint_8 => if (int.bits > 8) {
                    const value: As = @intCast(self.buffer[self.offset + 1]);
                    self.offset += 2;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .Int_8 => if (int.bits >= 8) {
                    const value: As = @intCast(
                        @as(i8, @bitCast(self.buffer[self.offset + 1])),
                    );
                    self.offset += 2;
                    return value;
                } else DeserializeError.TypeTooSmall,

                .FixPositive => |number| {
                    const value: As = @intCast(number);
                    self.offset += 1;
                    return value;
                },
                .FixNegative => |number| {
                    const value: As = @intCast(@as(i6, @bitCast(0b10_0000 | @as(u6, number))));
                    self.offset += 1;
                    return value;
                },
                else => return DeserializeError.WrongType,
            },
        };
    }

    fn unpack_string(self: *Unpacker, comptime As: type) !As {
        const len: usize = switch (try marker.decode(self.buffer[self.offset])) {
            .Bin_32, .Str_32 => blk: {
                const len = std.mem.readVarInt(
                    usize,
                    self.buffer[self.offset + 1 .. self.offset + 5],
                    Endian.big,
                );
                self.offset += 5;
                break :blk len;
            },
            .Bin_16, .Str_16 => blk: {
                const len = std.mem.readVarInt(
                    usize,
                    self.buffer[self.offset + 1 .. self.offset + 3],
                    Endian.big,
                );
                self.offset += 3;
                break :blk len;
            },
            .Bin_8, .Str_8 => blk: {
                const len: usize = @intCast(self.buffer[self.offset + 1]);
                self.offset += 2;
                break :blk len;
            },
            .FixStr => |len| blk: {
                self.offset += 1;
                break :blk len;
            },
            else => return DeserializeError.WrongType,
        };
        const str = try self.allocator.alloc(u8, len);
        @memcpy(str, self.buffer[self.offset .. self.offset + len]);
        self.offset += 1 + len;
        return @as(As, str);
    }

    fn unpack_array(self: *Unpacker, comptime target_len: ?usize, comptime As: type) !As {
        const info = @typeInfo(As);
        var array: As = undefined;
        switch (try marker.decode(self.buffer[self.offset])) {
            .FixArray => |len| {
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    // if (info == .Pointer) {
                    // @compileLog("FixArray to unknown size size array: ", info);
                    array = try self.allocator.alloc(info.Pointer.child, len);
                    // }
                }
                self.offset += 1;
            },
            .Array_16 => {
                const len = std.mem.readVarInt(
                    u16,
                    self.buffer[self.offset + 1 .. self.offset + 3],
                    Endian.big,
                );
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    // if (info == .Pointer) {
                    // @compileLog("FixArray to unknown size size array: ", info);
                    array = try self.allocator.alloc(info.Pointer.child, len);
                    // }
                }
                self.offset += 3;
            },
            .Array_32 => {
                const len = std.mem.readVarInt(
                    u32,
                    self.buffer[self.offset + 1 .. self.offset + 5],
                    Endian.big,
                );
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    // if (info == .Pointer) {
                    // @compileLog("FixArray to unknown size size array: ", info);
                    array = try self.allocator.alloc(info.Pointer.child, len);
                    // }
                }
                self.offset += 5;
            },
            else => return DeserializeError.WrongType,
        }
        for (if (info == .Array) &array else array) |*element| {
            element.* = try self.unpack_as(@TypeOf(element.*));
        }
        return array;
    }
};
