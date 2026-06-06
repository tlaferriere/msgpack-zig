const std = @import("std");
const debug = std.debug;
const math = std.math;
const meta = std.meta;
const Signedness = std.builtin.Signedness;
const testing = std.testing;

const MarkerMask = struct { marker: u8, mask: u8 = 0xFF };
pub const MarkerMasks = struct {
    pub const Nil = MarkerMask{
        .marker = 0xc0,
    };

    pub const False = MarkerMask{
        .marker = 0xc2,
    };
    pub const True = MarkerMask{
        .marker = 0xc3,
    };

    pub const FixPositive = MarkerMask{
        .marker = 0,
        .mask = 0x80,
    };
    pub const FixNegative = MarkerMask{
        .marker = 0xE0,
        .mask = 0xE0,
    };
    pub const Uint_8 = MarkerMask{
        .marker = 0xcc,
    };
    pub const Uint_16 = MarkerMask{
        .marker = 0xcd,
    };
    pub const Uint_32 = MarkerMask{
        .marker = 0xce,
    };
    pub const Uint_64 = MarkerMask{
        .marker = 0xcf,
    };

    pub const Int_8 = MarkerMask{
        .marker = 0xd0,
    };
    pub const Int_16 = MarkerMask{
        .marker = 0xd1,
    };
    pub const Int_32 = MarkerMask{
        .marker = 0xd2,
    };
    pub const Int_64 = MarkerMask{
        .marker = 0xd3,
    };

    pub const Float_32 = MarkerMask{
        .marker = 0xca,
    };
    pub const Float_64 = MarkerMask{
        .marker = 0xcb,
    };

    pub const FixStr = MarkerMask{
        .marker = 0xA0,
        .mask = 0xE0,
    };
    pub const Str_8 = MarkerMask{
        .marker = 0xd9,
    };
    pub const Str_16 = MarkerMask{
        .marker = 0xda,
    };
    pub const Str_32 = MarkerMask{
        .marker = 0xdb,
    };

    pub const Bin_8 = MarkerMask{
        .marker = 0xc4,
    };
    pub const Bin_16 = MarkerMask{
        .marker = 0xc5,
    };
    pub const Bin_32 = MarkerMask{
        .marker = 0xc6,
    };

    pub const FixArray = MarkerMask{
        .marker = 0x90,
        .mask = 0xF0,
    };
    pub const Array_16 = MarkerMask{
        .marker = 0xdc,
    };
    pub const Array_32 = MarkerMask{
        .marker = 0xdd,
    };

    pub const FixMap = MarkerMask{
        .marker = 0x80,
        .mask = 0xF0,
    };
    pub const Map_16 = MarkerMask{
        .marker = 0xde,
    };
    pub const Map_32 = MarkerMask{
        .marker = 0xdf,
    };

    pub const FixExt_1 = MarkerMask{
        .marker = 0xd4,
    };
    pub const FixExt_2 = MarkerMask{
        .marker = 0xd5,
    };
    pub const FixExt_4 = MarkerMask{
        .marker = 0xd6,
    };
    pub const FixExt_8 = MarkerMask{
        .marker = 0xd7,
    };
    pub const FixExt_16 = MarkerMask{
        .marker = 0xd8,
    };

    pub const Ext_8 = MarkerMask{
        .marker = 0xc7,
    };
    pub const Ext_16 = MarkerMask{
        .marker = 0xc8,
    };
    pub const Ext_32 = MarkerMask{
        .marker = 0xc9,
    };
};

pub const Marker = init: {
    // Generate the Marker Union from the MarkerMasks struct fields
    const markers = @typeInfo(MarkerMasks).@"struct".decls;
    var field_names: [markers.len][]const u8 = undefined;
    var field_types: [markers.len]type = undefined;
    var field_values: [markers.len]u8 = undefined;
    var union_field_attrs: [markers.len]std.builtin.Type.UnionField.Attributes = undefined;

    for (&field_names, &field_types, &field_values, &union_field_attrs, markers) |*name, *ft, *fv, *attr, marker| {
        const mask = @field(MarkerMasks, marker.name).mask;
        name.* = marker.name;
        // Take the bits left in the byte as the value.
        const bits: u16 = if (mask != 0xFF) math.log2_int_ceil(u16, ~mask) else 0;
        ft.* = @Int(.unsigned, bits);
        fv.* = @field(MarkerMasks, marker.name).marker;
        attr.* = .{ .@"align" = 1 };
    }

    const TagType: type = @Enum(
        u8,
        .exhaustive,
        &field_names,
        &field_values,
    );

    break :init @Union(
        .auto,
        TagType,
        &field_names,
        &field_types,
        &union_field_attrs,
    );
};

pub const MarkerDecodeError = error{NotAMarker};

pub fn decode(byte: u8) MarkerDecodeError!Marker {
    inline for (@typeInfo(MarkerMasks).@"struct".decls) |field| {
        const field_value = @field(MarkerMasks, field.name);
        if (byte & field_value.mask == field_value.marker) {
            return @unionInit(
                Marker,
                field.name,
                @truncate(byte),
            );
        }
    }
    return MarkerDecodeError.NotAMarker;
}

pub const MarkerEncodeError = error{NotAMarker};

pub fn encode(marker: Marker) u8 {
    inline for (@typeInfo(Marker).@"union".fields) |field| {
        if (marker == @field(Marker, field.name)) {
            const marker_mask: MarkerMask = @field(MarkerMasks, field.name);
            return (marker_mask.marker & marker_mask.mask) |
                (@field(marker, field.name) & ~marker_mask.mask);
        }
    }
    unreachable;
}

test "FixPositive is a u7" {
    const un = Marker{ .FixPositive = 8 };
    try testing.expectEqual(u7, @TypeOf(un.FixPositive));
}

test "Encode a FixPositive" {
    const un = Marker{ .FixPositive = 8 };
    try testing.expectEqual(8, encode(un));
}

test "FixNegative is a u5" {
    const un = Marker{ .FixNegative = 8 };
    try testing.expectEqual(u5, @TypeOf(un.FixNegative));
}

test "FixStr is a u5" {
    const un = Marker{ .FixStr = 8 };
    try testing.expectEqual(u5, @TypeOf(un.FixStr));
}

test "Decode FixNegative" {
    const marker: u8 = 0b1110_0000;
    // The decode only returns the leftover bits from the mask, not the sign or anything else.
    try testing.expectEqual(
        0,
        (try decode(marker)).FixNegative,
    );
}
