const std = @import("std");

/// Represent your type in msgpack.
const Repr = enum {
    // Int,
    /// Extension type.
    Ext,
    // Map,
    // Array,
};

/// Represent your type in msgpack as an extension type.
/// This is a convenience method to infer the type parameters to
/// `PackingRepr`.
/// # An extension type is identified by an i8 type id.
/// You must provide a callback that takes a byte slice and returns an error
/// union with your type as payload.
pub fn PackAsExt(
    /// Type ID.
    comptime type_id: i8,
    /// Packing callback for your type T. Signature is `pack(T: type, std.mem.Allocator) ![]u8`
    comptime pack: anytype,
    /// Size callback for your type T. Signature is `packed_size(T: type) !usize`
    comptime packed_size: anytype,
) Pack(
    @typeInfo(@TypeOf(pack)).Fn.params[0].type.?,
    @typeInfo(
        @typeInfo(@TypeOf(pack)).Fn.return_type.?,
    ).ErrorUnion.error_set,
    @typeInfo(
        @typeInfo(@TypeOf(packed_size)).Fn.return_type.?,
    ).ErrorUnion.error_set,
) {
    return Pack(
        @typeInfo(@TypeOf(pack)).Fn.params[0].type.?,
        @typeInfo(
            @typeInfo(@TypeOf(pack)).Fn.return_type.?,
        ).ErrorUnion.error_set,
        @typeInfo(
            @typeInfo(@TypeOf(packed_size)).Fn.return_type.?,
        ).ErrorUnion.error_set,
    ){ .ext = .{
        .type_id = type_id,
        .pack = &pack,
        .packed_size = &packed_size,
    } };
}

/// Represent how to pack your type in msgpack.
pub fn Pack(
    comptime T: type,
    comptime PackError: type,
    comptime SizeError: type,
) type {
    return union(Repr) {
        ext: Ext,

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

/// Represent your type in msgpack as an extension type.
///
/// This is a convenience method to infer the type parameters to
/// `UnpackingRepr`.
/// ### An extension type is identified by an i8 type id.
/// You must provide a callback that takes a byte slice and returns an error
/// union with your type as payload.
pub fn UnpackAsExt(
    comptime type_id: i8,
    comptime unpack: anytype,
) Unpack(
    @typeInfo(
        @typeInfo(@TypeOf(unpack)).Fn.return_type.?,
    ).ErrorUnion.payload,
    @typeInfo(
        @typeInfo(@TypeOf(unpack)).Fn.return_type.?,
    ).ErrorUnion.error_set,
) {
    return Unpack(
        @typeInfo(
            @typeInfo(@TypeOf(unpack)).Fn.return_type.?,
        ).ErrorUnion.payload,
        @typeInfo(
            @typeInfo(@TypeOf(unpack)).Fn.return_type.?,
        ).ErrorUnion.error_set,
    ){ .ext = .{
        .type_id = type_id,
        .callback = &unpack,
    } };
}

/// Represent your type in msgpack.
pub fn Unpack(comptime T: type, comptime E: ?type) type {
    return union(Repr) {
        ext: Ext,

        /// Extension type representation.
        const Ext = struct {
            /// Extension types are identified by a positive i8.
            /// Negative values are reserved for future use.
            type_id: i8,
            /// You must provide a callback to unpack your type to and
            /// from msgpack.
            callback: *const fn (std.mem.Allocator, []const u8) E.?!T,
        };
    };
}
