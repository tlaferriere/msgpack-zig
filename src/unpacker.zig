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
    /// A message asked for more memory than `Unpacker.Options.max_message_bytes`.
    MessageTooLong,
};

pub const Unpacker = struct {
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    options: Options,
    /// Bytes charged against `options.max_message_bytes` so far, reset by each
    /// top-level `unpack_as`.
    budget_used: usize = 0,

    /// Limits on what a single message is allowed to cost.
    pub const Options = struct {
        /// Total bytes one message may demand while being decoded; exceeding it
        /// is `DeserializeError.MessageTooLong`.
        ///
        /// This is charged against the *declared* size of each container, and is
        /// never given back within a message — it is a ceiling on what a message
        /// may ask for, not a measurement of live heap. Decoding a struct
        /// over-charges slightly, since each field's key string is charged and
        /// then freed once matched; that is bounded by the field count.
        max_message_bytes: usize = 64 * 1024 * 1024,
        /// How much may be reserved up front from a declared length, before any
        /// of that data has actually been seen. At or below this, a value costs
        /// one exact allocation; above it, capacity follows the data as it
        /// arrives. Purely a performance dial — `max_message_bytes` is what
        /// bounds the damage.
        max_prealloc_bytes: usize = 1024 * 1024,
    };

    /// Initialize from a Reader (e.g. file, network, fixed buffer) with the
    /// default limits.
    pub fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) Unpacker {
        return initWithOptions(allocator, reader, .{});
    }

    /// Initialize with explicit limits. See `Options`.
    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: Options,
    ) Unpacker {
        return Unpacker{
            .allocator = allocator,
            .reader = reader,
            .options = options,
        };
    }

    /// Charge one container's declared size against the message budget, before
    /// any of it is allocated. `count` and `elem_size` are `u64` so that the
    /// multiply cannot wrap a 32-bit `usize`, and it saturates rather than
    /// overflowing so an absurd declared length fails the comparison instead of
    /// wrapping into a small one.
    fn charge(self: *Unpacker, count: u64, elem_size: u64) DeserializeError!void {
        const bytes = count *| elem_size;
        if (bytes > self.options.max_message_bytes - self.budget_used) {
            return DeserializeError.MessageTooLong;
        }
        self.budget_used += @intCast(bytes);
    }

    /// Number of elements worth reserving up front for `Elem`, given the
    /// declared `count`. Never speculates past `max_prealloc_bytes`, but always
    /// allows at least one element so an oversized single element still decodes.
    fn prealloc_count(self: *Unpacker, comptime Elem: type, count: usize) usize {
        if (@sizeOf(Elem) == 0) return count;
        const cap = @max(1, self.options.max_prealloc_bytes / @sizeOf(Elem));
        return @min(count, cap);
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

    /// Decode one message as `As`.
    ///
    /// Each call starts a fresh `options.max_message_bytes` budget, so this is
    /// the message boundary: nested values recurse through `unpack_value` and
    /// share the budget of the message they belong to.
    pub fn unpack_as(self: *Unpacker, comptime As: type) !As {
        self.budget_used = 0;
        return self.unpack_value(As);
    }

    fn unpack_value(self: *Unpacker, comptime As: type) !As {
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
                else => try self.unpack_value(optional.child),
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

    /// Read one `Encoded` from the stream, then narrow to `As`.
    ///
    /// `Encoded` must match the width and signedness of the msgpack encoding,
    /// so that the bytes are interpreted with the right sign, and whether the
    /// value fits `As` is decided from the value rather than from the width of
    /// the encoding. How many bytes to read follows from `Encoded`, which is
    /// what `takeInt` derives it from.
    fn take_int(self: *Unpacker, comptime As: type, comptime Encoded: type) !As {
        const value = try self.reader.takeInt(Encoded, Endian.big);
        return std.math.cast(As, value) orelse DeserializeError.TypeTooSmall;
    }

    fn unpack_int(self: *Unpacker, comptime int: Type.Int, comptime As: type) !As {
        return switch (int.signedness) {
            .unsigned => switch (try self.take_marker()) {
                .Uint_64 => self.take_int(As, u64),
                .Uint_32 => self.take_int(As, u32),
                .Uint_16 => self.take_int(As, u16),
                .Uint_8 => self.take_int(As, u8),
                .FixPositive => |number| std.math.cast(As, number) orelse
                    DeserializeError.TypeTooSmall,
                else => DeserializeError.WrongType,
            },
            .signed => switch (try self.take_marker()) {
                .Uint_64 => self.take_int(As, u64),
                .Int_64 => self.take_int(As, i64),
                .Uint_32 => self.take_int(As, u32),
                .Int_32 => self.take_int(As, i32),
                .Uint_16 => self.take_int(As, u16),
                .Int_16 => self.take_int(As, i16),
                .Uint_8 => self.take_int(As, u8),
                .Int_8 => self.take_int(As, i8),
                .FixPositive => |number| std.math.cast(As, number) orelse
                    DeserializeError.TypeTooSmall,
                .FixNegative => |number| std.math.cast(
                    As,
                    @as(i6, @bitCast(0b10_0000 | @as(u6, number))),
                ) orelse DeserializeError.TypeTooSmall,
                else => DeserializeError.WrongType,
            },
        };
    }

    fn unpack_string(self: *Unpacker, comptime As: type) !As {
        // Read the declared length as a u64 and charge it before narrowing to
        // usize, so an oversized header is rejected without the allocator ever
        // seeing the number.
        const declared: u64 = switch (try self.take_marker()) {
            .Bin_32, .Str_32 => self.reader.takeInt(u32, Endian.big) catch return DeserializeError.Finished,
            .Bin_16, .Str_16 => self.reader.takeInt(u16, Endian.big) catch return DeserializeError.Finished,
            .Bin_8, .Str_8 => self.reader.takeByte() catch return DeserializeError.Finished,
            .FixStr => |fix_len| fix_len,
            else => return DeserializeError.WrongType,
        };
        try self.charge(declared, 1);
        const len: usize = @intCast(declared);
        const str = try self.allocator.alloc(u8, len);
        errdefer self.allocator.free(str);
        self.reader.readSliceAll(str) catch return DeserializeError.Finished;
        return @as(As, str);
    }

    fn unpack_array(self: *Unpacker, comptime target_len: ?usize, comptime As: type) !As {
        const info = @typeInfo(As);
        // Read the length once, then decide what to do with it: a fixed-size
        // target only validates it, while a slice has to be sized from it and so
        // must charge for it first.
        const declared: u64 = switch (try self.take_marker()) {
            .FixArray => |fix_len| fix_len,
            .Array_16 => try self.reader.takeInt(u16, Endian.big),
            .Array_32 => try self.reader.takeInt(u32, Endian.big),
            else => return DeserializeError.WrongType,
        };
        var array: As = undefined;
        if (target_len) |want| {
            // The caller owns the buffer, so there is nothing to charge.
            if (want != declared) return DeserializeError.WrongArrayLength;
        } else {
            try self.charge(declared, @sizeOf(info.pointer.child));
            array = try self.allocator.alloc(info.pointer.child, @intCast(declared));
        }
        // A failing element read must not strand the buffer, nor the elements
        // unpacked into it so far.
        var unpacked: usize = 0;
        errdefer {
            for (array[0..unpacked]) |element| self.free_unpacked(element);
            if (info != .array) self.allocator.free(array);
        }
        for (if (info == .array) &array else array) |*element| {
            element.* = try self.unpack_value(@TypeOf(element.*));
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
        // Charge the declared entry count before reserving anything for it. The
        // per-entry figure is an approximation, not the map's exact footprint:
        // an ArrayHashMap keeps an index table alongside the entry array, so the
        // extra u32 stands in for the index slot. Better to over-charge than to
        // under-charge something whose job is to bound memory.
        const Key = @TypeOf(@as(As.KV, undefined).key);
        const Value = @TypeOf(@as(As.KV, undefined).value);
        try self.charge(len, @sizeOf(Key) + @sizeOf(Value) + @sizeOf(u32));
        try map.ensureTotalCapacity(self.allocator, len);
        for (0..len) |_| {
            const key = try self.unpack_value(@TypeOf(@as(As.KV, undefined).key));
            errdefer self.free_unpacked(key);
            const value = try self.unpack_value(@TypeOf(@as(As.KV, undefined).value));
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
            const key = try self.unpack_value([]const u8);
            defer self.allocator.free(key);
            if (!fields_to_fill.contains(key)) return DeserializeError.WrongFields;
            inline for (fields) |field| {
                if (std.mem.eql(u8, key, field.name)) {
                    @field(out, field.name) = try self.unpack_value(field.type);
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
        try self.charge(metadata.len, 1);
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
