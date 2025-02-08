const std = @import("std");

const marker = @import("marker.zig");
const Marker = marker.Marker;

const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;

/// Deserialization Errors
pub const DeserializeError = error{
    TypeTooSmall,
    WrongType,
    Finished,
    WrongArrayLength,
    WrongExtType,
};

/// Msgpack unpacker.
///
/// # Memory safety
/// This object **_borrows_** the buffer you wish to unpack, therefore it is your
/// responsiblity to ensure the buffer lives long enough for you to unpack
/// everything you want before freeing this buffer.
///
/// All values read from this buffer are copied out, hence the allocator for
/// runtime-sized types.
pub const Unpacker = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    offset: usize,

    /// Initialize a msgpack unpacker with a **_borrowed_** message buffer
    /// slice.
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

    /// Unpack an object from the buffer.
    ///
    /// # Memory Safety
    /// This method will attempt to unpack an object of the type you pass in.
    /// In all cases this method will copy the memory, decoupling the value's
    /// lifetime from the msgpacked buffer's lifetime.
    ///
    /// If the type's size is only known at runtime, it will be allocated with
    /// the allocator provided to `init` and ownership of the object is
    /// transferred to the caller.
    ///
    /// # Type Families
    /// Msgpack has a few different type families with their particularities.
    ///
    /// ## Integers
    /// TODO
    ///
    /// ## Floats
    /// TODO
    ///
    /// ## Strings and Binary Strings
    /// TODO
    ///
    /// ## Arrays
    /// TODO
    ///
    /// ## Maps
    /// TODO
    ///
    /// ## Extension types
    /// You can define extension types by creating a struct with a
    /// `__msgpack_repr__` declaration with type `msgpack.Repr`.
    /// Specifically, you must use the `Repr.Ext` and provide the `type_id` (a
    /// `u8`) and a callback taking a byte slice.
    ///
    /// The callback takes ownership of the byte-slice, therefore it is your
    /// responsibility to free the memory once you are done with it.
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
                .Slice, .Many => if (pointer.child == u8) {
                    return self.unpack_string(As);
                } else {
                    return self.unpack_array(null, As);
                },
                .C => @compileError("C sized pointer."),
            },
            .Array => |array| self.unpack_array(array.len, As),
            .Struct => {
                if (@hasDecl(As, "put") and
                    ((@hasDecl(As, "init") and
                    @typeInfo(@TypeOf(As.put)).Fn.params.len == 3) or
                    @typeInfo(@TypeOf(As.put)).Fn.params.len == 4) and
                    @hasDecl(As, "KV"))
                {
                    return self.unpack_map(As);
                }
                if (@hasDecl(As, "__msgpack_repr__")) {
                    switch (As.__msgpack_repr__) {
                        .Ext => |ext| {
                            return self.unpack_ext(
                                As,
                                ext.type_id,
                                ext.callback,
                            );
                        },
                    }
                }
                @compileLog(As);
                @compileLog(@typeInfo(As).Struct.decls);
                @compileError(std.fmt.comptimePrint(
                    \\I don't know how to deserialize your struct {}.
                    \\Please add a `__msgpack_repr__` declaration to your struct with type `msgpack.Repr`:
                    \\Suggested: 
                    \\```
                    \\    const {} = struct {{
                    \\        ...
                    \\        const __msgpack_repr__ = msgpack.Repr{{...}};
                    \\    }}
                    \\```
                , .{ .a = As, .b = As }));
            },
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
        self.offset += len;
        return @as(As, str);
    }

    fn unpack_array(
        self: *Unpacker,
        comptime target_len: ?usize,
        comptime As: type,
    ) !As {
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

    fn unpack_map(self: *Unpacker, comptime As: type) !As {
        var map: As = As.init(self.allocator);
        const len = switch (try marker.decode(self.buffer[self.offset])) {
            .FixMap => |len| blk: {
                self.offset += 1;
                break :blk len;
            },
            .Map_16 => blk: {
                const len = std.mem.readVarInt(
                    u16,
                    self.buffer[self.offset + 1 .. self.offset + 3],
                    Endian.big,
                );
                self.offset += 3;
                break :blk len;
            },
            .Map_32 => blk: {
                const len = std.mem.readVarInt(
                    u32,
                    self.buffer[self.offset + 1 .. self.offset + 5],
                    Endian.big,
                );
                self.offset += 5;
                break :blk len;
            },
            else => return DeserializeError.WrongType,
        };
        try map.ensureTotalCapacity(len);
        for (0..len) |_| {
            try map.put(
                try self.unpack_as(std.meta.FieldType(As.KV, .key)),
                try self.unpack_as(std.meta.FieldType(As.KV, .value)),
            );
        }
        return map;
    }

    fn unpack_ext(
        self: *Unpacker,
        comptime As: type,
        comptime type_id: u8,
        comptime callback: anytype,
    ) !As {
        const metadata = try self.ext_decode();
        if (metadata.type_id != type_id) {
            return DeserializeError.WrongExtType;
        }
        const slice = try self.allocator.alloc(u8, metadata.len);
        @memcpy(slice, self.buffer[self.offset .. self.offset + metadata.len]);
        return callback(self.allocator, slice);
    }

    const ExtMetadata = struct {
        type_id: u8,
        len: usize,
    };

    fn ext_decode(self: *Unpacker) !ExtMetadata {
        const mark = try marker.decode(self.buffer[self.offset]);
        self.offset += 1;
        const len: usize = switch (mark) {
            .FixExt_1 => 1,
            .FixExt_2 => 2,
            .FixExt_4 => 4,
            .FixExt_8 => 8,
            .FixExt_16 => 16,
            .Ext_8 => blk: {
                const len = self.buffer[self.offset];
                self.offset += 1;
                break :blk len;
            },
            .Ext_16 => blk: {
                const len = std.mem.readVarInt(
                    u16,
                    self.buffer[self.offset .. self.offset + 2],
                    Endian.big,
                );
                self.offset += 2;
                break :blk len;
            },
            .Ext_32 => blk: {
                const len = std.mem.readVarInt(
                    u32,
                    self.buffer[self.offset .. self.offset + 4],
                    Endian.big,
                );
                self.offset += 4;
                break :blk len;
            },
            else => return DeserializeError.WrongType,
        };
        const type_id = self.buffer[self.offset];
        self.offset += 1;
        return ExtMetadata{
            .type_id = type_id,
            .len = len,
        };
    }
};
