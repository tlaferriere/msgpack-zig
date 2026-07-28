//! Fuzz tests for the msgpack library.
//!
//! Run with: `zig build test --release=safe --fuzz`
//!
//! When NOT in fuzz mode (`zig build test --release=safe`), these run as
//! quick smoke tests with empty/corpus inputs.
//!
//! Fuzz targets:
//!   1. Unpacker — feed arbitrary bytes, catch crashes. One target per family:
//!      scalars, arrays, maps, structs/ext.
//!   2. Structured round-trips — pack→unpack→verify for every supported type.
//!   3. Mutation — pack a valid message, flip one byte, unpack.
//!
//! Note: `--release=safe` is required because Debug mode enables additional
//! safety checks (e.g. bounds checking) that can cause false-positive panics
//! when the fuzzer feeds deliberately malformed input.
const std = @import("std");
const testing = std.testing;

const msgpack = @import("msgpack");
const Packer = msgpack.Packer;
const Unpacker = msgpack.Unpacker;

/// Pack `val`, then unpack the bytes back as `T`.
/// The caller owns any allocation in the returned value.
fn roundTrip(comptime T: type, val: anytype) !T {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    try packer.pack(val);
    packer.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var unpacker = Unpacker.init(testing.allocator, &r);
    return unpacker.unpack_as(T);
}

/// Extension type with an opaque byte payload. Unlike `MyType` in the
/// integration tests, this one accepts every payload, so round-trips are total.
/// The unpacked value owns `buf`, so callers free it.
const MyExt = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr{ .ext = 0x71 };

        pub fn pack_ext(self: MyExt, writer: *std.Io.Writer) !void {
            try writer.writeAll(self.buf);
        }

        pub fn unpack_ext(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            len: usize,
        ) !MyExt {
            return MyExt{ .buf = try reader.readAlloc(allocator, len) };
        }
    };
};

/// How many bytes `MisreadExt`'s callback will try to take. The fuzzer sets it
/// before each round; the library has to leave the stream positioned after the
/// payload whether that is too much, too little, or exactly right.
var misread_take: usize = 0;

/// Extension type whose callback deliberately reads the wrong amount. It keeps
/// nothing, so the value it returns does not matter — the point is where the
/// stream is left once the callback is done with it.
const MisreadExt = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr{ .ext = 0x72 };

        pub fn pack_ext(self: MisreadExt, writer: *std.Io.Writer) !void {
            try writer.writeAll(self.buf);
        }

        pub fn unpack_ext(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            len: usize,
        ) !MisreadExt {
            _ = allocator;
            _ = len;
            var sink: [8192]u8 = undefined;
            const want = @min(misread_take, sink.len);
            // Over-reading is supposed to fail rather than reach the next value,
            // so failing here is a valid outcome, not a finding.
            _ = reader.readSliceShort(sink[0..want]) catch {};
            return MisreadExt{ .buf = &.{} };
        }
    };
};

/// How many bytes `PartialExt`'s callback keeps. The fuzzer sets it before each
/// round.
var partial_take: usize = 0;

/// Ext type whose callback keeps a fuzzer-chosen slice of its payload. Unlike
/// `MisreadExt` this one allocates, so a frame the library cannot finish
/// processing has something outstanding to strand.
const PartialExt = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr{ .ext = 0x75 };

        pub fn pack_ext(self: PartialExt, writer: *std.Io.Writer) !void {
            try writer.writeAll(self.buf);
        }

        pub fn unpack_ext(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            len: usize,
        ) !PartialExt {
            const want = @min(partial_take, len);
            return PartialExt{ .buf = try reader.readAlloc(allocator, want) };
        }
    };
};

/// Struct serialized as a map of field name → value.
const MyStruct = struct {
    a: u32,
    b: []const u8,
    flag: bool,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr.map;
    };
};

// Feed random bytes to the Unpacker and try to deserialize every primitive type.
// The fuzzer mutates the bytes to maximize code coverage in the parsing logic.
// Expected DeserializeErrors are ignored; only panics/crashes are caught.
test "fuzz unpack scalars" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;
                // Get up to 4096 bytes from the fuzzer
                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const input = buf[0..len];

                // Try to unpack every primitive type from the raw bytes.
                // Each call to unpack_as advances the offset, so we try
                // multiple types from the same buffer until exhausted.
                // Guard against empty buffers (causes index-out-of-bounds
                // panic in the unpacker before it can return an error).
                if (input.len == 0) return;

                // Try each type independently with a fresh unpacker so
                // a successful parse doesn't advance the offset past the
                // buffer length for subsequent type attempts.
                inline for (.{
                    bool,
                    ?bool,
                    u8,
                    u16,
                    u32,
                    u64,
                    i8,
                    i16,
                    i32,
                    i64,
                    // Odd widths and widths past msgpack's 64-bit encodings
                    // exercise the @intCast/takeVarInt paths that the
                    // power-of-two types never reach.
                    u1,
                    u7,
                    i9,
                    u128,
                    i128,
                    f32,
                    f64,
                    ?u32,
                    msgpack.Timestamp,
                }) |T| {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    _ = u.unpack_as(T) catch {};
                }

                // Types owning an allocation need the result freed.
                inline for (.{ []const u8, ?[]const u8 }) |T| {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(T)) |s| {
                        if (T == []const u8) {
                            testing.allocator.free(s);
                        } else if (s) |inner| {
                            testing.allocator.free(inner);
                        }
                    } else |_| {}
                }
            }
        }.fuzz,
        .{},
    );
}

// Feed random bytes to the Unpacker as array types. These paths allocate a
// buffer sized by a length field taken straight from the input
// (`unpack_array`), then fill it with fallible element reads.
test "fuzz unpack arrays" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;
                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const input = buf[0..len];
                if (input.len == 0) return;

                // Fixed-size array: length is checked against the marker, so
                // nothing is allocated for the array itself.
                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    _ = u.unpack_as([3]u8) catch {};
                }

                // Fixed-size array of strings: no outer allocation, but one per
                // element.
                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as([2][]const u8)) |array| {
                        for (array) |inner| testing.allocator.free(inner);
                    } else |_| {}
                }

                // Slices of scalars: one allocation, freed on success.
                inline for (.{ []u32, []u64, []f64 }) |T| {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(T)) |slice| {
                        testing.allocator.free(slice);
                    } else |_| {}
                }

                // Nested: the outer allocation plus one per element.
                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as([][]const u8)) |slice| {
                        for (slice) |inner| testing.allocator.free(inner);
                        testing.allocator.free(slice);
                    } else |_| {}
                }
            }
        }.fuzz,
        .{},
    );
}

// Feed random bytes to the Unpacker as map types. `unpack_map` reserves
// capacity from an input-controlled length, then does a fallible read per entry.
test "fuzz unpack maps" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;
                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const input = buf[0..len];
                if (input.len == 0) return;

                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(std.array_hash_map.Auto(u32, u32))) |map| {
                        var m = map;
                        m.deinit(testing.allocator);
                    } else |_| {}
                }

                // String keys are allocated per entry.
                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(std.array_hash_map.String(u32))) |map| {
                        var m = map;
                        for (m.keys()) |key| testing.allocator.free(key);
                        m.deinit(testing.allocator);
                    } else |_| {}
                }

                // Both halves of an entry own memory here. The maps above
                // cannot see a value leak at all — an entry that displaces a
                // `u32` strands nothing — so a bug that drops a value on the
                // floor stays invisible until the value type has something to
                // drop. The duplicate-key leak was exactly that: fuzzing found
                // the key half and could not have found the value half.
                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(std.array_hash_map.String([]const u8))) |map| {
                        var m = map;
                        for (m.keys()) |key| testing.allocator.free(key);
                        for (m.values()) |value| testing.allocator.free(value);
                        m.deinit(testing.allocator);
                    } else |_| {}
                }
            }
        }.fuzz,
        .{},
    );
}

// Feed random bytes to the Unpacker as user-defined types: a map-repr struct
// (`unpack_map_as_struct`, which allocates a key string per field) and an
// ext-repr struct (`unpack_ext`, where the callback reads its own payload and
// allocates whatever it decides to keep).
test "fuzz unpack structs" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;
                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const input = buf[0..len];
                if (input.len == 0) return;

                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(MyStruct)) |val| {
                        testing.allocator.free(val.b);
                    } else |_| {}
                }

                {
                    var r = std.Io.Reader.fixed(input);
                    var u = Unpacker.init(testing.allocator, &r);
                    if (u.unpack_as(MyExt)) |val| {
                        testing.allocator.free(val.buf);
                    } else |_| {}
                }
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for unsigned 64-bit integers.
// The Smith generates random u64 values from the fuzzer's byte stream.
test "fuzz round-trip u64" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);

                const val = smith.value(u64);
                try packer.pack(val);
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var unpacker = Unpacker.init(testing.allocator, &r);
                const result = try unpacker.unpack_as(u64);
                try testing.expectEqual(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for signed 64-bit integers.
test "fuzz round-trip i64" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);

                const val = smith.value(i64);
                try packer.pack(val);
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var unpacker = Unpacker.init(testing.allocator, &r);
                const result = try unpacker.unpack_as(i64);
                try testing.expectEqual(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for optional u32 (may be null).
test "fuzz round-trip optional u32" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);

                const val = smith.value(?u32);
                try packer.pack(val);
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var unpacker = Unpacker.init(testing.allocator, &r);
                const result = try unpacker.unpack_as(?u32);
                try testing.expectEqual(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for booleans.
test "fuzz round-trip bool" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);

                const val = smith.value(bool);
                try packer.pack(val);
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var unpacker = Unpacker.init(testing.allocator, &r);
                const result = try unpacker.unpack_as(bool);
                try testing.expectEqual(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for f64 floats.
test "fuzz round-trip f64" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);

                const val = smith.value(f64);
                try packer.pack(val);
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var unpacker = Unpacker.init(testing.allocator, &r);
                const result = try unpacker.unpack_as(f64);

                // NaN != NaN, use bitwise comparison for NaN
                if (std.math.isNan(val)) {
                    try testing.expect(std.math.isNan(result));
                } else {
                    try testing.expectEqual(val, result);
                }
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for f32 floats.
test "fuzz round-trip f32" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                const val = smith.value(f32);
                const result = try roundTrip(f32, val);

                if (std.math.isNan(val)) {
                    try testing.expect(std.math.isNan(result));
                } else {
                    try testing.expectEqual(val, result);
                }
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for int widths that aren't a power of two, plus widths past
// what msgpack can encode (those must report IntTooLarge rather than truncate).
test "fuzz round-trip odd-width ints" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                // Widths msgpack can always encode.
                inline for (.{ u7, i9, u33, i63 }) |T| {
                    const val = smith.value(T);
                    try testing.expectEqual(val, try roundTrip(T, val));
                }

                // Wider than any msgpack int encoding: values that don't fit
                // must be reported, not truncated.
                inline for (.{ u128, i128 }) |T| {
                    const val = smith.value(T);
                    if (roundTrip(T, val)) |result| {
                        try testing.expectEqual(val, result);
                    } else |e| switch (e) {
                        error.IntTooLarge => {},
                        else => return e,
                    }
                }
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for strings (STR markers).
test "fuzz round-trip string" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const val = buf[0..len];

                const result = try roundTrip([]const u8, val);
                defer testing.allocator.free(result);
                try testing.expectEqualStrings(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for binary blobs (BIN markers, which the string path never
// emits — `Bin` is the only way to reach them).
test "fuzz round-trip bin" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const val = buf[0..len];

                const result = try roundTrip([]const u8, msgpack.Bin(val));
                defer testing.allocator.free(result);
                try testing.expectEqualStrings(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for slices of non-u8 elements (ARRAY markers).
test "fuzz round-trip slice" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                const count = smith.valueRangeAtMost(u32, 0, 64);
                const val = try testing.allocator.alloc(u32, count);
                defer testing.allocator.free(val);
                for (val) |*element| element.* = smith.value(u32);

                const result = try roundTrip([]u32, val);
                defer testing.allocator.free(result);
                try testing.expectEqualSlices(u32, val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for hash maps (MAP markers).
test "fuzz round-trip map" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                const Map = std.array_hash_map.Auto(u32, u32);
                var val: Map = .empty;
                defer val.deinit(testing.allocator);
                const count = smith.valueRangeAtMost(u32, 0, 32);
                for (0..count) |_| {
                    try val.put(testing.allocator, smith.value(u32), smith.value(u32));
                }

                var result = try roundTrip(Map, val);
                defer result.deinit(testing.allocator);
                try testing.expectEqualSlices(u32, val.keys(), result.keys());
                try testing.expectEqualSlices(u32, val.values(), result.values());
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for a struct serialized as a map of field name → value.
test "fuzz round-trip struct as map" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var buf: [1024]u8 = undefined;
                const len = smith.slice(&buf);
                const val = MyStruct{
                    .a = smith.value(u32),
                    .b = buf[0..len],
                    .flag = smith.value(bool),
                };

                const result = try roundTrip(MyStruct, val);
                defer testing.allocator.free(result.b);
                try testing.expectEqualDeep(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for an extension type. The drawn payload length selects
// between fixext 1/2/4/8/16 and ext 8/16/32.
test "fuzz round-trip ext" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var buf: [4096]u8 = undefined;
                const len = smith.slice(&buf);
                const val = MyExt{ .buf = buf[0..len] };

                const result = try roundTrip(MyExt, val);
                defer testing.allocator.free(result.buf);
                try testing.expectEqualStrings(val.buf, result.buf);
            }
        }.fuzz,
        .{},
    );
}

// Keeping the stream aligned across an ext value is the library's job, not the
// callback's. Draw a payload and an unrelated number of bytes for the callback
// to take, then check the value *after* the ext still decodes: whatever the
// callback read or declined to read, the next value has to start where it
// should. The drawn count spans both the payload length and the buffer the
// library hands the callback, since those are the two boundaries the
// realignment arithmetic turns on.
test "fuzz ext callback misreads its payload" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var payload: [1024]u8 = undefined;
                const len = smith.slice(&payload);
                misread_take = smith.valueRangeAtMost(u32, 0, len + 64);

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);
                try packer.pack(MisreadExt{ .buf = payload[0..len] });
                try packer.pack(@as(u32, 0xDEADBEEF));
                packer.finish();

                var r = std.Io.Reader.fixed(aw.written());
                var u = Unpacker.init(testing.allocator, &r);
                _ = u.unpack_as(MisreadExt) catch {};
                try testing.expectEqual(@as(u32, 0xDEADBEEF), try u.unpack_as(u32));
            }
        }.fuzz,
        .{},
    );
}

// Ext frames built by hand, with the declared length drawn independently of how
// many payload bytes actually follow. Truncated frames, over-long frames and
// zero-length ones all fall out of that, which the round-trip targets cannot
// produce because they only ever emit headers that match their payload.
//
// The callback keeps a fuzzer-chosen part of the payload, so a frame the
// library cannot finish has a live allocation at the moment it gives up —
// which is the shape a truncated frame used to leak.
test "fuzz adversarial ext frames" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var payload: [512]u8 = undefined;
                const avail = smith.slice(&payload);
                // Deliberately unrelated to `avail`, and allowed past it.
                const declared = smith.valueRangeAtMost(u32, 0, 600);
                partial_take = smith.valueRangeAtMost(u32, 0, 600);

                // ext_32, so any drawn length is expressible in the header.
                var frame: [6 + payload.len]u8 = undefined;
                frame[0] = 0xc9;
                std.mem.writeInt(u32, frame[1..5], declared, .big);
                frame[5] = 0x75;
                @memcpy(frame[6..][0..avail], payload[0..avail]);

                // A private allocator per iteration, because `testing.allocator`
                // only reports leaks when the test tears down — which never
                // happens while the fuzzer is looping, so a leak inside an
                // iteration would go unseen. This one is checked every round.
                var gpa: std.heap.DebugAllocator(.{}) = .init;
                const alloc = gpa.allocator();
                {
                    var r = std.Io.Reader.fixed(frame[0 .. 6 + avail]);
                    var u = Unpacker.init(alloc, &r);
                    if (u.unpack_as(PartialExt)) |v| {
                        alloc.free(v.buf);
                    } else |_| {}
                }
                try testing.expect(gpa.deinit() == .ok);
            }
        }.fuzz,
        .{},
    );
}

// Round-trip fuzz for the Timestamp extension. Which of the 4/8/12-byte
// encodings is used depends on both fields, and nanoseconds over 999_999_999
// must be rejected rather than encoded.
test "fuzz round-trip timestamp" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                const val = msgpack.Timestamp{
                    .seconds = smith.value(i64),
                    .nanoseconds = smith.value(u32),
                };

                const result = roundTrip(msgpack.Timestamp, val) catch |e| switch (e) {
                    error.TooManyNanoseconds => {
                        try testing.expect(val.nanoseconds > 999_999_999);
                        return;
                    },
                    else => return e,
                };
                try testing.expectEqualDeep(val, result);
            }
        }.fuzz,
        .{},
    );
}

// Pack a valid message, then let the fuzzer corrupt one byte of it. Keeping the
// prefix structurally valid reaches parser states that uniformly random bytes
// almost never hit.
test "fuzz mutated valid message" {
    try testing.fuzz(
        {},
        struct {
            fn fuzz(ctx: void, smith: *testing.Smith) anyerror!void {
                _ = ctx;

                var aw: std.Io.Writer.Allocating = .init(testing.allocator);
                defer aw.deinit();
                var packer = Packer.init(&aw.writer, testing.allocator);
                try packer.pack(MyStruct{
                    .a = 0xDEADBEEF,
                    .b = "Hello!",
                    .flag = true,
                });
                packer.finish();

                var buf: [128]u8 = undefined;
                const written = aw.written();
                @memcpy(buf[0..written.len], written);
                const message = buf[0..written.len];

                message[smith.index(message.len)] = smith.value(u8);

                var r = std.Io.Reader.fixed(message);
                var u = Unpacker.init(testing.allocator, &r);
                if (u.unpack_as(MyStruct)) |val| {
                    testing.allocator.free(val.b);
                } else |_| {}
            }
        }.fuzz,
        .{},
    );
}
