//! Msgpack. Like JSON, but byte-oriented.
const std = @import("std");
const Endian = std.builtin.Endian;

// Reexports
pub const Unpacker = @import("unpacker.zig").Unpacker;
pub const Packer = @import("packer.zig").Packer;
pub const Bin = @import("packer.zig").Bin;

pub const repr = @import("repr.zig");

/// Msgpack-serializable timestamp extension type.
pub const Timestamp = struct {
    /// Seconds since 1970-01-01 00:00
    seconds: i64,
    /// Nanoseconds since the last second. Must not be over 999_999_999 or
    /// serialization/deserialization will fail.
    nanoseconds: u29,

    pub const __msgpack_pack_repr__ = repr.PackAsExt(
        -1,
        pack_ext,
        packed_size,
    );

    /// Serialization/deserialization failure.
    pub const Error = error{
        /// Nanoseconds are larger than 999_999_999.
        TooManyNanoseconds,
    };

    fn pack_ext(self: Timestamp, alloc: std.mem.Allocator) ![]const u8 {
        if (self.nanoseconds == 0 and self.seconds <= std.math.maxInt(u32)) {
            const buf = try alloc.alloc(u8, 4);
            std.mem.writeInt(
                u32,
                std.mem.bytesAsValue(
                    [4]u8,
                    buf,
                ),
                @intCast(self.seconds),
                Endian.big,
            );
            return buf;
        }

        if (self.nanoseconds > 999_999_999) {
            return Error.TooManyNanoseconds;
        }

        if (self.seconds <= std.math.maxInt(u34)) {
            const combined: u64 = (@as(u64, self.nanoseconds) << 34) |
                @as(u64, @intCast(self.seconds));
            const buf = try alloc.alloc(u8, 8);
            std.mem.writeInt(
                u64,
                std.mem.bytesAsValue(
                    [8]u8,
                    buf,
                ),
                @intCast(combined),
                Endian.big,
            );
            return buf;
        }

        const buf = try alloc.alloc(u8, 12);
        std.mem.writeInt(
            u32,
            std.mem.bytesAsValue(
                [4]u8,
                buf[0..4],
            ),
            self.nanoseconds,
            Endian.big,
        );
        std.mem.writeInt(
            i64,
            std.mem.bytesAsValue(
                [8]u8,
                buf[4..12],
            ),
            self.seconds,
            Endian.big,
        );
        return buf;
    }

    fn packed_size(self: Timestamp) !usize {
        if (self.nanoseconds == 0 and self.seconds <= std.math.maxInt(u32)) {
            return 4;
        }

        if (self.nanoseconds > 999_999_999) {
            return Error.TooManyNanoseconds;
        }

        if (self.seconds <= std.math.maxInt(u34)) {
            return 8;
        }

        return 12;
    }
};
