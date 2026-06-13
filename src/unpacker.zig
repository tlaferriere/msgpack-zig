const std = @import("std");
const testing = std.testing;
const Endian = std.builtin.Endian;
const Type = std.builtin.Type;

const marker = @import("marker.zig");
const Marker = marker.Marker;

pub const DeserializeError = error{
    TypeTooSmall,
    WrongType,
    Finished,
    WrongArrayLength,
    WrongExtType,
    WrongFields,
};

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
            .int => |int| self.unpack_int(int, As),
            .bool => switch (try marker.decode(self.buffer[self.offset])) {
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
            .optional => |optional| switch (try marker.decode(self.buffer[self.offset])) {
                .Nil => {
                    self.offset += 1;
                    return null;
                },
                else => try self.unpack_as(optional.child),
            },
            .float => |float| self.unpack_float(float, As),
            .pointer => |pointer| switch (pointer.size) {
                .one => if (pointer.child == .Array) {
                    return self.unpack_array(pointer.child.Array.len, As);
                } else {
                    @compileError("Can't serialize objects behind pointers yet.");
                },
                .slice, .many => if (pointer.child == u8) {
                    return self.unpack_string(As);
                } else {
                    return self.unpack_array(null, As);
                },
                .c => @compileError("C sized pointer."),
            },
            .array => |array| self.unpack_array(array.len, As),
            .@"struct" => {
                if (@hasDecl(As, "__msgpack__")) {
                    return self.unpack_struct(As);
                }
                if (@hasDecl(As, "put") and
                    @typeInfo(@TypeOf(As.put)).@"fn".params.len == 4 and
                    @hasDecl(As, "KV"))
                {
                    return self.unpack_map(As);
                }
                @compileError(std.fmt.comptimePrint(
                    \\I don't know how to deserialize your struct {}.
                    \\Please add a `__msgpack__` declaration to your struct with type `msgpack.Repr`:
                    \\Suggested:
                    \\```
                    \\    const {} = struct {{
                    \\        ...
                    \\        pub const __msgpack__ = struct {
                    \\            pub const repr = msgpack.Repr.map
                    \\        };
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
                            self.buffer[self.offset +
                                1 .. self.offset + 9],
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
                    const value: As = @intCast(self.buffer[self.offset]);
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
        // Bounds check: ensure the declared length doesn't exceed
        // the remaining buffer.
        if (len > self.buffer.len - self.offset) return DeserializeError.Finished;
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
                    array = try self.allocator.alloc(info.pointer.child, len);
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
                    array = try self.allocator.alloc(info.pointer.child, len);
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
                    array = try self.allocator.alloc(info.pointer.child, len);
                }
                self.offset += 5;
            },
            else => return DeserializeError.WrongType,
        }
        for (if (info == .array) &array else array) |*element| {
            element.* = try self.unpack_as(@TypeOf(element.*));
        }
        return array;
    }

    fn unpack_map(self: *Unpacker, comptime As: type) !As {
        var map: As = .empty;
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
        try map.ensureTotalCapacity(self.allocator, len);
        for (0..len) |_| {
            try map.put(
                self.allocator,
                try self.unpack_as(@TypeOf(@as(As.KV, undefined).key)),
                try self.unpack_as(@TypeOf(@as(As.KV, undefined).value)),
            );
        }
        return map;
    }

    fn unpack_struct(self: *Unpacker, comptime As: type) !As {
        const msgpack_decl = As.__msgpack__;
        if (!@hasDecl(msgpack_decl, "repr")) {
            @compileError(std.fmt.comptimePrint(
                \\Missing the repr declaration in your `__msgpack__` declaration.
                \\Please add a `repr` declaration to your `__msgpack__` struct with type `msgpack.Repr`:
                \\Suggested:
                \\```
                \\    const {} = struct {{
                \\        ...
                \\        pub const __msgpack__ = struct {{
                \\            pub const repr = msgpack.Repr.map
                \\        }};
                \\    }}
                \\```
            , .{ .a = As }));
        }
        return switch (msgpack_decl.repr) {
            .ext => |ext| blk: {
                if (!@hasDecl(msgpack_decl, "unpack_ext")) {
                    @compileError(std.fmt.comptimePrint(
                        \\Missing the unpack_ext function in your `__msgpack__` declaration.
                        \\Please add an unpack_ext function to your `__msgpack__` struct:
                        \\Suggested:
                        \\```
                        \\    const {} = struct {{
                        \\        ...
                        \\        pub const __msgpack__ = struct {{
                        \\            pub const repr = msgpack.Repr{{ .ext = type_id }};
                        \\            pub fn unpack_ext(alloc: std.mem.Allocator, buf: []u8) !{} {{...}}
                        \\        }};
                        \\    }}
                        \\```
                        \\Note: unpack_ext must be marked pub.
                    , .{ .a = As, .b = As }));
                }
                break :blk self.unpack_ext(
                    As,
                    ext,
                    msgpack_decl.unpack_ext,
                );
            },
            .map => unpack_map_as_struct(self, As),
        };
    }

    fn unpack_map_as_struct(self: *Unpacker, comptime As: type) !As {
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
        const fields = @typeInfo(As).@"struct".fields;
        if (len != fields.len) {
            return DeserializeError.WrongFields;
        }
        var fields_to_fill = std.BufSet.init(self.allocator);
        defer fields_to_fill.deinit();
        inline for (fields) |field| {
            try fields_to_fill.insert(field.name);
        }
        var out = std.mem.zeroes(As);
        for (0..len) |_| {
            const key = try self.unpack_as([]const u8);
            defer self.allocator.free(key);
            if (!fields_to_fill.contains(key)) {
                return DeserializeError.WrongFields;
            }
            fields_to_fill.remove(key);
            inline for (fields) |field| {
                if (std.mem.eql(u8, key, field.name)) {
                    @field(out, field.name) = try self.unpack_as(field.type);
                    break;
                }
            }
        }
        return out;
    }

    fn unpack_ext(
        self: *Unpacker,
        comptime As: type,
        comptime type_id: i8,
        comptime callback: anytype,
    ) !As {
        const metadata = try self.ext_decode();
        if (metadata.type_id != type_id) {
            return DeserializeError.WrongExtType;
        }
        const slice = try self.allocator.alloc(u8, metadata.len);
        @memcpy(
            slice,
            self.buffer[self.offset .. self.offset + metadata.len],
        );
        return callback(self.allocator, slice);
    }

    const ExtMetadata = struct {
        type_id: i8,
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
        const type_id: i8 = @bitCast(self.buffer[self.offset]);
        self.offset += 1;
        return ExtMetadata{
            .type_id = type_id,
            .len = len,
        };
    }
};
