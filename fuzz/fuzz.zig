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
const MyExt = struct {
    buf: []const u8,

    pub const __msgpack__ = struct {
        pub const repr = msgpack.Repr{ .ext = 0x71 };

        pub fn pack_ext(self: MyExt, allocator: std.mem.Allocator) ![]const u8 {
            const out = try allocator.alloc(u8, self.buf.len);
            @memcpy(out, self.buf);
            return out;
        }

        pub fn packed_size(self: MyExt) !usize {
            return self.buf.len;
        }

        pub fn unpack_ext(allocator: std.mem.Allocator, data: []const u8) !MyExt {
            _ = allocator;
            return MyExt{ .buf = data };
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
            }
        }.fuzz,
        .{},
    );
}

// Feed random bytes to the Unpacker as user-defined types: a map-repr struct
// (`unpack_map_as_struct`, which allocates a key string per field) and an
// ext-repr struct (`unpack_ext`, which allocates the payload before handing
// ownership to the callback).
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
                    .nanoseconds = smith.value(u29),
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
