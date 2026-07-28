//! Msgpack. Like JSON, but byte-oriented.
const std = @import("std");
const Endian = std.builtin.Endian;

pub const Bin = @import("packer.zig").Bin;
pub const Packer = @import("packer.zig").Packer;
pub const Unpacker = @import("unpacker.zig").Unpacker;

// Reexports
/// Msgpack-serializable timestamp extension type.
pub const Timestamp = struct {
    /// Seconds since 1970-01-01 00:00
    seconds: i64,
    /// Nanoseconds since the last second. Must not be over 999_999_999 or
    /// serialization/deserialization will fail.
    ///
    /// Sized to the widest field msgpack gives nanoseconds — the 32 bits of the
    /// 96-bit encoding — so every value the wire can carry has somewhere to
    /// land. The `<= 999_999_999` rule is narrower than any integer width, so
    /// it stays a run-time check on both directions rather than this type's job.
    nanoseconds: u32,

    pub const __msgpack__ = struct {
        pub const repr = Repr{ .ext = -1 };
        pub fn pack_ext(self: Timestamp, writer: *std.Io.Writer) !void {
            if (self.nanoseconds == 0 and
                self.seconds >= 0 and
                self.seconds <= std.math.maxInt(u32))
            {
                return writer.writeInt(u32, @intCast(self.seconds), Endian.big);
            }

            if (self.nanoseconds > 999_999_999) {
                return Error.TooManyNanoseconds;
            }

            if (self.seconds >= 0 and self.seconds <= std.math.maxInt(u34)) {
                const combined: u64 = (@as(u64, self.nanoseconds) << 34) |
                    @as(u64, @intCast(self.seconds));
                return writer.writeInt(u64, combined, Endian.big);
            }

            try writer.writeInt(u32, self.nanoseconds, Endian.big);
            try writer.writeInt(i64, self.seconds, Endian.big);
        }

        pub fn unpack_ext(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            len: usize,
        ) !Timestamp {
            // A timestamp is three fixed layouts told apart by their length, so
            // it keeps nothing past this call and never allocates.
            _ = allocator;
            return switch (len) {
                4 => Timestamp{
                    .seconds = @intCast(try reader.takeInt(u32, Endian.big)),
                    .nanoseconds = 0,
                },
                8 => blk: {
                    const data = try reader.takeInt(u64, Endian.big);
                    const nanos: u64 = data >> 34;
                    if (nanos > 999_999_999) {
                        return Error.TooManyNanoseconds;
                    }
                    const timestamp = Timestamp{
                        .seconds = @bitCast(data & 0x00000003ffffffff),
                        .nanoseconds = @intCast(nanos),
                    };
                    break :blk timestamp;
                },
                12 => blk: {
                    const nanos = try reader.takeInt(u32, Endian.big);
                    if (nanos > 999_999_999) {
                        return Error.TooManyNanoseconds;
                    }
                    const timestamp = Timestamp{
                        .seconds = try reader.takeInt(i64, Endian.big),
                        .nanoseconds = nanos,
                    };
                    break :blk timestamp;
                },
                else => {
                    return Error.WrongLength;
                },
            };
        }
    };

    /// Serialization/deserialization failure.
    pub const Error = error{
        /// Nanoseconds are larger than 999_999_999.
        TooManyNanoseconds,
        WrongLength,
    };
};

test Timestamp {
    const testing = std.testing;

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    var packer = Packer.init(&aw.writer, testing.allocator);
    const val = Timestamp{
        .seconds = 0x0EADBEEFDEADBEEF,
        .nanoseconds = 1,
    };
    try packer.pack(val);
    packer.finish();

    var r = std.Io.Reader.fixed(aw.written());
    var message = Unpacker.init(testing.allocator, &r);
    const unpacked = try message.unpack_as(Timestamp);
    try testing.expectEqualDeep(
        val,
        unpacked,
    );
}

/// Represent your type in msgpack.
pub const Repr = union(enum) {
    // Int,
    /// # Extension type
    ///
    /// Extension types are identified by a positive i8.
    /// Negative values are reserved for future use.
    ///
    /// - Unpacking requires:
    ///    - `__msgpack__.unpack_ext(std.mem.Allocator, *std.Io.Reader, usize) !T`
    ///
    ///   The reader yields exactly the payload and nothing beyond it, and the
    ///   length is given so a type told apart by its size does not have to read
    ///   the payload to find out how long it is. Reading less than the whole
    ///   payload is fine — the remainder is discarded either way. Only what the
    ///   returned `T` keeps needs to come from the allocator.
    /// - Packing requires:
    ///    - `__msgpack__.pack_ext(T, *std.Io.Writer) !void`
    ///
    ///   Whatever is written becomes the payload, and the header is derived from
    ///   it, so there is no size to declare and nothing to keep in sync.
    ext: i8,
    /// # Map
    ///
    /// The type's fields will be serialized into a map
    /// with field names as string keys.
    map: void,
    // Array,
};
