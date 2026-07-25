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
    reader: *std.Io.Reader,

    /// Initialize from a Reader (e.g. file, network, fixed buffer).
    pub fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) Unpacker {
        return Unpacker{
            .allocator = allocator,
            .reader = reader,
        };
    }

    fn take_marker(self: *Unpacker) !Marker {
        const byte = try self.reader.takeByte();
        return marker.decode(byte);
    }

    /// Decode the next marker without consuming it, so a nested `unpack_as`
    /// can read it again (used for optionals).
    fn peek_marker(self: *Unpacker) !Marker {
        const byte = try self.reader.peekByte();
        return marker.decode(byte);
    }

    pub fn unpack_as(self: *Unpacker, comptime As: type) !As {
        return switch (@typeInfo(As)) {
            .int => |int| self.unpack_int(int, As),
            .bool => switch (try self.take_marker()) {
                .False => {
                    return false;
                },
                .True => {
                    return true;
                },
                else => DeserializeError.WrongType,
            },
            .optional => |optional| switch (try self.peek_marker()) {
                .Nil => {
                    _ = try self.reader.takeByte();
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

    fn unpack_float(self: *Unpacker, comptime float: Type.Float, comptime As: type) !As {
        return switch (try self.take_marker()) {
            .Float_32 => if (float.bits >= 32) {
                const value = @as(As, @floatCast(@as(f32, @bitCast(try self.reader.takeInt(u32, Endian.big)))));
                return value;
            } else DeserializeError.TypeTooSmall,
            .Float_64 => if (float.bits >= 64) {
                const value = @as(As, @floatCast(@as(f64, @bitCast(try self.reader.takeInt(u64, Endian.big)))));
                return value;
            } else DeserializeError.TypeTooSmall,
            else => DeserializeError.WrongType,
        };
    }

    fn unpack_int(self: *Unpacker, comptime int: Type.Int, comptime As: type) !As {
        return switch (int.signedness) {
            .unsigned => switch (try self.take_marker()) {
                .Uint_64 => if (int.bits >= 64) {
                    return try self.reader.takeVarInt(As, Endian.big, 8);
                } else DeserializeError.TypeTooSmall,
                .Uint_32 => if (int.bits >= 32) {
                    return try self.reader.takeVarInt(As, Endian.big, 4);
                } else DeserializeError.TypeTooSmall,
                .Uint_16 => if (int.bits >= 16) {
                    return try self.reader.takeVarInt(As, Endian.big, 2);
                } else DeserializeError.TypeTooSmall,
                .Uint_8 => if (int.bits >= 8) {
                    return try self.reader.takeVarInt(As, Endian.big, 1);
                } else DeserializeError.TypeTooSmall,
                .FixPositive => |number| {
                    const value: As = @intCast(number);
                    return value;
                },
                else => return DeserializeError.WrongType,
            },
            .signed => switch (try self.take_marker()) {
                .Uint_64, .Int_64 => if (int.bits >= 64) {
                    return try self.reader.takeVarInt(As, Endian.big, 8);
                } else DeserializeError.TypeTooSmall,
                .Uint_32, .Int_32 => if (int.bits >= 32) {
                    return try self.reader.takeVarInt(As, Endian.big, 4);
                } else DeserializeError.TypeTooSmall,
                .Uint_16, .Int_16 => if (int.bits >= 16) {
                    return try self.reader.takeVarInt(As, Endian.big, 2);
                } else DeserializeError.TypeTooSmall,
                .Uint_8, .Int_8 => if (int.bits >= 8) {
                    return try self.reader.takeVarInt(As, Endian.big, 1);
                } else DeserializeError.TypeTooSmall,
                .FixPositive => |number| {
                    const value: As = @intCast(number);
                    return value;
                },
                .FixNegative => |number| {
                    const value: As = @intCast(@as(i6, @bitCast(0b10_0000 | @as(u6, number))));
                    return value;
                },
                else => return DeserializeError.WrongType,
            },
        };
    }

    fn unpack_string(self: *Unpacker, comptime As: type) !As {
        const len: usize = switch (try self.take_marker()) {
            .Bin_32, .Str_32 => @intCast(self.reader.takeInt(u32, Endian.big) catch return DeserializeError.Finished),
            .Bin_16, .Str_16 => @intCast(self.reader.takeInt(u16, Endian.big) catch return DeserializeError.Finished),
            .Bin_8, .Str_8 => self.reader.takeByte() catch return DeserializeError.Finished,
            .FixStr => |fix_len| fix_len,
            else => return DeserializeError.WrongType,
        };
        const str = try self.allocator.alloc(u8, len);
        errdefer self.allocator.free(str);
        self.reader.readSliceAll(str) catch return DeserializeError.Finished;
        return @as(As, str);
    }

    fn unpack_array(self: *Unpacker, comptime target_len: ?usize, comptime As: type) !As {
        const info = @typeInfo(As);
        var array: As = undefined;
        switch (try self.take_marker()) {
            .FixArray => |len| {
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    array = try self.allocator.alloc(info.pointer.child, len);
                }
            },
            .Array_16 => {
                const len = try self.reader.takeInt(u16, Endian.big);
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    array = try self.allocator.alloc(info.pointer.child, len);
                }
            },
            .Array_32 => {
                const len = try self.reader.takeInt(u32, Endian.big);
                if (target_len != null) {
                    if (target_len.? != len) return DeserializeError.WrongArrayLength;
                } else {
                    array = try self.allocator.alloc(info.pointer.child, len);
                }
            },
            else => return DeserializeError.WrongType,
        }
        // A failing element read must not strand the buffer, nor the elements
        // unpacked into it so far.
        var unpacked: usize = 0;
        errdefer {
            for (array[0..unpacked]) |element| self.free_unpacked(element);
            if (info != .array) self.allocator.free(array);
        }
        for (if (info == .array) &array else array) |*element| {
            element.* = try self.unpack_as(@TypeOf(element.*));
            unpacked += 1;
        }
        return array;
    }

    /// Release whatever `unpack_as` allocated for a value it returned.
    /// Types that own nothing are left alone.
    fn free_unpacked(self: *Unpacker, value: anytype) void {
        switch (@typeInfo(@TypeOf(value))) {
            .pointer => |pointer| switch (pointer.size) {
                .slice => {
                    for (value) |element| self.free_unpacked(element);
                    self.allocator.free(value);
                },
                else => {},
            },
            .array => for (value) |element| self.free_unpacked(element),
            .optional => if (value) |inner| self.free_unpacked(inner),
            else => {},
        }
    }

    fn unpack_map(self: *Unpacker, comptime As: type) !As {
        var map: As = .empty;
        const len = switch (try self.take_marker()) {
            .FixMap => |fix_len| fix_len,
            .Map_16 => try self.reader.takeInt(u16, Endian.big),
            .Map_32 => try self.reader.takeInt(u32, Endian.big),
            else => return DeserializeError.WrongType,
        };
        // A truncated map must not strand the map itself, the entries read so
        // far, or a key whose value never arrived.
        errdefer {
            for (map.keys()) |key| self.free_unpacked(key);
            for (map.values()) |value| self.free_unpacked(value);
            map.deinit(self.allocator);
        }
        try map.ensureTotalCapacity(self.allocator, len);
        for (0..len) |_| {
            const key = try self.unpack_as(@TypeOf(@as(As.KV, undefined).key));
            errdefer self.free_unpacked(key);
            const value = try self.unpack_as(@TypeOf(@as(As.KV, undefined).value));
            errdefer self.free_unpacked(value);
            try map.put(self.allocator, key, value);
        }
        return map;
    }

    fn unpack_struct(self: *Unpacker, comptime As: type) !As {
        const msgpack_decl = As.__msgpack__;
        if (!@hasDecl(msgpack_decl, "repr")) {
            @compileError(std.fmt.comptimePrint(
                \\Missing the repr declaration in your `__msgpack__` declaration.
            , .{ .a = As }));
        }
        return switch (msgpack_decl.repr) {
            .ext => |ext| blk: {
                if (!@hasDecl(msgpack_decl, "unpack_ext")) {
                    @compileError(std.fmt.comptimePrint("Missing unpack_ext function.", .{}));
                }
                break :blk self.unpack_ext(As, ext, msgpack_decl.unpack_ext);
            },
            .map => unpack_map_as_struct(self, As),
        };
    }

    fn unpack_map_as_struct(self: *Unpacker, comptime As: type) !As {
        const len = switch (try self.take_marker()) {
            .FixMap => |fix_len| fix_len,
            .Map_16 => try self.reader.takeInt(u16, Endian.big),
            .Map_32 => try self.reader.takeInt(u32, Endian.big),
            else => return DeserializeError.WrongType,
        };
        const fields = @typeInfo(As).@"struct".fields;
        if (len != fields.len) return DeserializeError.WrongFields;
        var fields_to_fill = std.BufSet.init(self.allocator);
        defer fields_to_fill.deinit();
        inline for (fields) |field| {
            try fields_to_fill.insert(field.name);
        }
        var out = std.mem.zeroes(As);
        // A field is filled once it leaves `fields_to_fill`; on failure every
        // filled field has to give back whatever it allocated.
        errdefer inline for (fields) |field| {
            if (!fields_to_fill.contains(field.name)) {
                self.free_unpacked(@field(out, field.name));
            }
        };
        for (0..len) |_| {
            const key = try self.unpack_as([]const u8);
            defer self.allocator.free(key);
            if (!fields_to_fill.contains(key)) return DeserializeError.WrongFields;
            inline for (fields) |field| {
                if (std.mem.eql(u8, key, field.name)) {
                    @field(out, field.name) = try self.unpack_as(field.type);
                    fields_to_fill.remove(field.name);
                    break;
                }
            }
        }
        return out;
    }

    fn unpack_ext(self: *Unpacker, comptime As: type, comptime type_id: i8, comptime callback: anytype) !As {
        const metadata = try self.ext_decode();
        if (metadata.type_id != type_id) return DeserializeError.WrongExtType;
        const slice = try self.allocator.alloc(u8, metadata.len);
        // Ownership of `slice` transfers to `callback`, which frees it on its
        // own error path — so only free here if the read itself fails.
        self.reader.readSliceAll(slice) catch |e| {
            self.allocator.free(slice);
            return switch (e) {
                error.EndOfStream => DeserializeError.Finished,
                else => e,
            };
        };
        return callback(self.allocator, slice);
    }

    const ExtMetadata = struct { type_id: i8, len: usize };

    fn ext_decode(self: *Unpacker) !ExtMetadata {
        const mark = try self.take_marker();
        const len: usize = switch (mark) {
            .FixExt_1 => 1,
            .FixExt_2 => 2,
            .FixExt_4 => 4,
            .FixExt_8 => 8,
            .FixExt_16 => 16,
            .Ext_8 => try self.reader.takeByte(),
            .Ext_16 => try self.reader.takeInt(u16, Endian.big),
            .Ext_32 => try self.reader.takeInt(u32, Endian.big),
            else => return DeserializeError.WrongType,
        };
        const type_id: i8 = @bitCast(try self.reader.takeByte());
        return ExtMetadata{ .type_id = type_id, .len = len };
    }
};
