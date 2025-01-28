const test_packer = @import("test_packer.zig");
const test_unpacker = @import("test_unpacker.zig");

test {
    // Import all the tests
    @import("std").testing.refAllDecls(test_packer);
    @import("std").testing.refAllDecls(test_unpacker);
}
