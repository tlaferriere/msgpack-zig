const std = @import("std");

/// Describe how to represent your type in msgpack.
pub fn Repr(comptime T: type, comptime E: type) type {
    return union(enum) {
        Ext: Ext,

        pub const Ext = struct {
            type_id: u8,
            callback: *const fn (std.mem.Allocator, []const u8) E!T,
        };
    };
}
