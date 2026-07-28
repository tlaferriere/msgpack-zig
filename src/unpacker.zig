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

    // TODO(#10): every container path reaches the reader through here and
    // through a bare `try self.reader.takeInt(...)` for its length —
    // `unpack_array`, `unpack_map`, `unpack_map_as_struct` and `ext_decode` all
    // propagate `EndOfStream`/`ReadFailed` raw, while `unpack_string` maps them
    // to `Finished`. Streaming needs one consistent answer for "ended early",
    // distinct from "the transport broke".
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
    ///
    /// The reader must have been constructed with a buffer of at least 8 bytes:
    /// `takeInt` asserts a capacity of `@bitSizeOf(T) / 8` and the widest read
    /// here is a `u64`, while `peek_marker` needs one byte to peek.
    pub fn unpack_as(self: *Unpacker, comptime As: type) !As {
        // TODO(#10): this is where resumable decoding would begin and end. A
        // message arriving in pieces needs the recursion below to suspend and be
        // resumed with more data, which means the budget must persist across
        // resumptions instead of resetting on entry.
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
        // TODO(#10): these `catch`es flatten `ReadFailed` and `EndOfStream` into
        // one error, and the other containers propagate the reader's error raw
        // instead — so "the message ended early" surfaces differently depending
        // on which container you were decoding. Streaming needs both unified and
        // transport failure kept distinct from truncation.
        const declared: u64 = switch (try self.take_marker()) {
            .Bin_32, .Str_32 => self.reader.takeInt(u32, Endian.big) catch return DeserializeError.Finished,
            .Bin_16, .Str_16 => self.reader.takeInt(u16, Endian.big) catch return DeserializeError.Finished,
            .Bin_8, .Str_8 => self.reader.takeByte() catch return DeserializeError.Finished,
            .FixStr => |fix_len| fix_len,
            else => return DeserializeError.WrongType,
        };
        try self.charge(declared, 1);
        return @as(As, try self.read_bytes(declared));
    }

    /// Read exactly `len` bytes into a caller-owned slice, freeing them again if
    /// the stream turns out not to have that many.
    ///
    /// The declared length is passed to the Reader as a *limit* rather than used
    /// as an allocation size, so capacity follows the bytes that actually arrive
    /// and a length the stream cannot back costs only what it delivers.
    fn read_bytes(self: *Unpacker, len: u64) ![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(self.allocator);
        // Speculate only up to the reserve cap. Below it this is the exact size,
        // which keeps an honest value at one allocation: `Writer.write` copies
        // straight into this capacity without reaching `Allocating.drain`, and
        // `toOwnedSlice` then remaps in place. Removing this reserve would add a
        // realloc and a full-payload memcpy to every string, bin and ext.
        const reserve: usize = @intCast(@min(len, self.options.max_prealloc_bytes));
        try list.ensureTotalCapacityPrecise(self.allocator, reserve);
        self.reader.appendRemaining(self.allocator, &list, .limited64(len)) catch |e| switch (e) {
            // Inverted on purpose: hitting the limit means every requested byte
            // arrived, which is the success case. A short stream returns
            // normally instead, with fewer bytes than asked for.
            error.StreamTooLong => {},
            // TODO(#10): streaming readers need these kept apart. `ReadFailed`
            // is the transport breaking, not the message ending, and a caller on
            // a socket has to be able to tell those apart.
            error.ReadFailed => return DeserializeError.Finished,
            error.OutOfMemory => return e,
        };
        // TODO(#10): for a reader that has not been handed the whole message
        // yet, this is where decoding would have to suspend and resume rather
        // than give up. Looping here would not be enough: `appendRemaining` only
        // returns short on a true `EndOfStream`, so the loop has to live where
        // more data can actually be supplied.
        if (list.items.len != len) return DeserializeError.Finished;
        return list.toOwnedSlice(self.allocator);
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
        if (target_len == null) return self.unpack_slice(info.pointer.child, As, declared);

        // Fixed-size target: the buffer is the caller's, so there is nothing to
        // allocate and nothing to charge — only the length to validate.
        if (target_len.? != declared) return DeserializeError.WrongArrayLength;
        var array: As = undefined;
        // A failing element read must not strand the elements unpacked so far.
        var unpacked: usize = 0;
        errdefer for (array[0..unpacked]) |element| self.free_unpacked(element);
        for (&array) |*element| {
            element.* = try self.unpack_value(@TypeOf(element.*));
            unpacked += 1;
        }
        return array;
    }

    /// Decode `count` elements into a caller-owned slice.
    ///
    /// Capacity grows from the elements actually decoded rather than from
    /// `count`, so a header promising four billion elements only ever costs what
    /// the stream can deliver. `ArrayList` supplies the geometric growth, so this
    /// stays amortized O(1) per element.
    fn unpack_slice(
        self: *Unpacker,
        comptime Child: type,
        comptime As: type,
        count: u64,
    ) !As {
        try self.charge(count, @sizeOf(Child));
        var list: std.ArrayList(Child) = .empty;
        // TODO(#10): resumable decoding would have to hand this partially filled
        // list back to the next call rather than unwind it. Same for the map in
        // `unpack_map` and `fields_to_fill` in `unpack_map_as_struct` — the
        // `errdefer` below is what makes a short read final.
        // Everything already in the list still owns its own allocations.
        errdefer {
            for (list.items) |element| self.free_unpacked(element);
            list.deinit(self.allocator);
        }
        try list.ensureTotalCapacityPrecise(
            self.allocator,
            self.prealloc_count(Child, @intCast(count)),
        );
        for (0..@as(usize, @intCast(count))) |_| {
            // Deliberately not `append`, which is this same reserve plus an
            // assignment: its argument is evaluated first, so the element would
            // be decoded before there is room for it, and a growth that fails
            // with OutOfMemory would drop an element already owning memory.
            // Reserving first makes the append infallible.
            try list.ensureUnusedCapacity(self.allocator, 1);
            list.appendAssumeCapacity(try self.unpack_value(Child));
        }
        return list.toOwnedSlice(self.allocator);
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
        // TODO(#10): and for streaming it would have to be kept instead of
        // unwound, so decoding can resume into the same partially built map.
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
        const entry_bytes = @sizeOf(Key) + @sizeOf(Value) + @sizeOf(u32);
        try self.charge(len, entry_bytes);
        // Reserve only up to the cap and let `put` grow the rest geometrically,
        // so a declared entry count the stream cannot back costs nothing up
        // front.
        const cap_entries = @max(1, self.options.max_prealloc_bytes / entry_bytes);
        try map.ensureTotalCapacity(self.allocator, @min(len, cap_entries));
        for (0..len) |_| {
            const key = try self.unpack_value(@TypeOf(@as(As.KV, undefined).key));
            errdefer self.free_unpacked(key);
            const value = try self.unpack_value(@TypeOf(@as(As.KV, undefined).value));
            errdefer self.free_unpacked(value);
            // Deliberately not `put`, which drops whatever it displaces on the
            // floor: nothing forbids a message from repeating a key, and on a
            // repeat the map keeps the copy of the key it already holds while
            // overwriting the value. Both of the things it lets go were decoded
            // by us and are ours to release.
            const entry = try map.getOrPut(self.allocator, key);
            if (entry.found_existing) {
                self.free_unpacked(key);
                self.free_unpacked(entry.value_ptr.*);
            }
            entry.value_ptr.* = value;
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
        // TODO(#10): resuming a partially decoded struct would mean carrying
        // `fields_to_fill` and `out` across calls rather than unwinding them.
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
        // Charging before the callback runs is what bounds it: whatever the
        // callback chooses to allocate, it is working from a length that already
        // fits inside `max_message_bytes`. It is not held to `max_prealloc_bytes`
        // the way the library's own decoding is — that is the callback's call to
        // make, and `len` is given to it so it can make it.
        try self.charge(metadata.len, 1);

        // The callback gets a reader that ends where its payload does, so
        // reading too far fails on its own rather than eating the next value.
        // The buffer has to hold the widest single `takeInt` a callback might
        // do; `Timestamp` reads a u64, and `takeInt` asserts the capacity.
        var buf: [16]u8 = undefined;
        var limited = self.reader.limited(.limited64(metadata.len), &buf);
        const value = callback(self.allocator, &limited.interface, metadata.len);

        // Whatever the callback did not read is still payload, and leaving it
        // in the stream would hand it to the next value. `remaining` counts only
        // the bytes never pulled from the underlying reader — anything buffered
        // above is already consumed from it — so this realigns exactly.
        //
        // A saturated `Limit` reads back as `.unlimited`, which can only happen
        // when `len` itself saturated, and `remaining` never exceeds `len`.
        const unread = limited.remaining.toInt() orelse metadata.len;
        try self.reader.discardAll64(unread);

        return value;
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
