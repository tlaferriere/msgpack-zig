const std = @import("std");

/// Represent your type in msgpack.
const Repr = enum {
    // Int,
    /// Extension type.
    Ext,
    // Map,
    // Array,
};

pub fn PackAsExt(
    comptime type_id: u8,
    comptime pack: anytype,
    comptime packed_size: anytype,
) PackingRepr(
    @typeInfo(@TypeOf(pack)).Fn.params[0].type.?,
    @typeInfo(
        @typeInfo(@TypeOf(pack)).Fn.return_type.?,
    ).ErrorUnion.error_set,
    @typeInfo(
        @typeInfo(@TypeOf(packed_size)).Fn.return_type.?,
    ).ErrorUnion.error_set,
) {
    return PackingRepr(
        @typeInfo(@TypeOf(pack)).Fn.params[0].type.?,
        @typeInfo(
            @typeInfo(@TypeOf(pack)).Fn.return_type.?,
        ).ErrorUnion.error_set,
        @typeInfo(
            @typeInfo(@TypeOf(packed_size)).Fn.return_type.?,
        ).ErrorUnion.error_set,
    ){ .Ext = .{
        .type_id = type_id,
        .pack = &pack,
        .packed_size = &packed_size,
    } };
}

/// Represent how to pack your type in msgpack.
pub fn PackingRepr(
    comptime T: type,
    comptime PackError: type,
    comptime SizeError: type,
) type {
    return union(Repr) {
        Ext: Ext,

        /// Extension type representation.
        ///
        /// Extension types are identified by a u8.
        /// You must provide callbacks to pack and/or unpack your type to and
        /// from msgpack.
        pub const Ext = struct {
            type_id: i8,
            pack: *const fn (
                T,
                std.mem.Allocator,
            ) PackError![]const u8,
            packed_size: *const fn (T) SizeError!usize,
        };
    };
}

/// Represent your type in msgpack.
pub fn UnpackingRepr(comptime T: type, comptime E: type) type {
    return union(Repr) {
        Ext: Ext,

        /// Extension type representation.
        pub const Ext = struct {
            /// Extension types are identified by a positive i8.
            /// Negative values are reserved for future use.
            type_id: i8,
            /// You must provide a callback to unpack your type to and
            /// from msgpack.
            callback: *const fn (std.mem.Allocator, []const u8) E!T,
        };
    };
}
