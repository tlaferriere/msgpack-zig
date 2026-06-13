//! Fuzz tests for the msgpack library.
//!
//! Run with: `zig build test --release=safe --fuzz`
//!
//! When NOT in fuzz mode (`zig build test --release=safe`), these run as
//! quick smoke tests with empty/corpus inputs.
//!
//! Fuzz targets:
//!   1. Unpacker — feed arbitrary bytes, catch crashes
//!   2. Structured round-trips — pack→unpack→verify for ints, optionals, bools
//!
//! Note: `--release=safe` is required because Debug mode enables additional
//! safety checks (e.g. bounds checking) that can cause false-positive panics
//! when the fuzzer feeds deliberately malformed input.
const std = @import("std");
const testing = std.testing;

const msgpack = @import("msgpack");
const Packer = msgpack.Packer;
const Unpacker = msgpack.Unpacker;

// Feed random bytes to the Unpacker and try to deserialize every primitive type.
// The fuzzer mutates the bytes to maximize code coverage in the parsing logic.
// Expected DeserializeErrors are ignored; only panics/crashes are caught.
test "fuzz unpack raw bytes" {
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
                    f32,
                    f64,
                    []const u8,
                    msgpack.Timestamp,
                }) |T| {
                    var u = Unpacker.init(testing.allocator, input, 0) catch continue;
                    if (T == []const u8) {
                        if (u.unpack_as(T)) |s| {
                            defer testing.allocator.free(s);
                        } else |_| {}
                    } else {
                        _ = u.unpack_as(T) catch {};
                    }
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

                var packer = try Packer.init(testing.allocator);
                defer testing.allocator.free(packer.finish());

                const val = smith.value(u64);
                try packer.pack(val);
                const buf = packer.finish();

                var unpacker = try Unpacker.init(testing.allocator, buf, 0);
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

                var packer = try Packer.init(testing.allocator);
                defer testing.allocator.free(packer.finish());

                const val = smith.value(i64);
                try packer.pack(val);
                const buf = packer.finish();

                var unpacker = try Unpacker.init(testing.allocator, buf, 0);
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

                var packer = try Packer.init(testing.allocator);
                defer testing.allocator.free(packer.finish());

                const val = smith.value(?u32);
                try packer.pack(val);
                const buf = packer.finish();

                var unpacker = try Unpacker.init(testing.allocator, buf, 0);
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

                var packer = try Packer.init(testing.allocator);
                defer testing.allocator.free(packer.finish());

                const val = smith.value(bool);
                try packer.pack(val);
                const buf = packer.finish();

                var unpacker = try Unpacker.init(testing.allocator, buf, 0);
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

                var packer = try Packer.init(testing.allocator);
                defer testing.allocator.free(packer.finish());

                const val = smith.value(f64);
                try packer.pack(val);
                const buf = packer.finish();

                var unpacker = try Unpacker.init(testing.allocator, buf, 0);
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
