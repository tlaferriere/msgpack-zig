const Type = @import("std").builtin.Type;
const Signedness = @import("std").builtin.Signedness;
const meta = @import("std").meta;
const math = @import("std").math;
const testing = @import("std").testing;

const MarkerMask = struct { marker: u8, mask: u8 = 0xFF };
pub const MarkerValue = struct {
    pub const Nil = MarkerMask{ .marker = 0xc0 };

    pub const False = MarkerMask{ .marker = 0xc2 };
    pub const True = MarkerMask{ .marker = 0xc3 };

    pub const FixPositive = MarkerMask{ .marker = 0, .mask = 0x80 };
    pub const FixNegative = MarkerMask{ .marker = 0xE0, .mask = 0xE0 };
    pub const Uint_8 = MarkerMask{ .marker = 0xcc };
    pub const Uint_16 = MarkerMask{ .marker = 0xcd };
    pub const Uint_32 = MarkerMask{ .marker = 0xce };
    pub const Uint_64 = MarkerMask{ .marker = 0xcf };

    pub const Int_8 = MarkerMask{ .marker = 0xd0 };
    pub const Int_16 = MarkerMask{ .marker = 0xd1 };
    pub const Int_32 = MarkerMask{ .marker = 0xd2 };
    pub const Int_64 = MarkerMask{ .marker = 0xd3 };

    pub const Float_32 = MarkerMask{ .marker = 0xca };
    pub const Float_64 = MarkerMask{ .marker = 0xcb };

    pub const FixStr = MarkerMask{ .marker = 0xA0, .mask = 0xE0 };
    pub const Str_8 = MarkerMask{ .marker = 0xd9 };
    pub const Str_16 = MarkerMask{ .marker = 0xda };
    pub const Str_32 = MarkerMask{ .marker = 0xdb };

    pub const Bin_8 = MarkerMask{ .marker = 0xc4 };
    pub const Bin_16 = MarkerMask{ .marker = 0xc5 };
    pub const Bin_32 = MarkerMask{ .marker = 0xc6 };

    pub const FixArray = MarkerMask{ .marker = 0x90, .mask = 0xF8 };
    pub const Array_16 = MarkerMask{ .marker = 0xdc };
    pub const Array_32 = MarkerMask{ .marker = 0xdd };

    pub const FixMap = MarkerMask{ .marker = 0x80, .mask = 0xF8 };
    pub const Map_16 = MarkerMask{ .marker = 0xde };
    pub const Map_32 = MarkerMask{ .marker = 0xdf };

    pub const FixExt_1 = MarkerMask{ .marker = 0xd4 };
    pub const FixExt_2 = MarkerMask{ .marker = 0xd5 };
    pub const FixExt_4 = MarkerMask{ .marker = 0xd6 };
    pub const FixExt_8 = MarkerMask{ .marker = 0xd7 };
    pub const FixExt_16 = MarkerMask{ .marker = 0xd8 };

    pub const Ext_8 = MarkerMask{ .marker = 0xc7 };
    pub const Ext_16 = MarkerMask{ .marker = 0xc8 };
    pub const Ext_32 = MarkerMask{ .marker = 0xc9 };
};

pub const Marker = init: {
    // Generate the Marker Union from the
    const markers = @typeInfo(MarkerValue).Struct.decls;
    var union_fields: [markers.len]Type.UnionField = undefined;
    var enum_fields: [markers.len]Type.EnumField = undefined;
    for (&union_fields, &enum_fields, markers) |*union_field, *enum_field, marker| {
        const mask = @field(MarkerValue, marker.name).mask;
        const field_type = @Type(Type{
            .Int = .{
                // Take the bits left in the byte as the value.
                .bits = if (mask != 0xFF) math.log2_int_ceil(u16, ~mask) else 0,
                .signedness = Signedness.unsigned,
            },
        });
        enum_field.* = Type.EnumField{
            .name = marker.name,
            .value = @field(MarkerValue, marker.name).marker,
        };
        union_field.* = Type.UnionField{
            .type = field_type,
            .name = marker.name,
            .alignment = 1,
        };
    }
    break :init @Type(Type{ .Union = .{
        .tag_type = @Type(Type{
            .Enum = .{
                .fields = &enum_fields,
                .decls = &.{},
                .tag_type = u8,
                .is_exhaustive = true,
            },
        }),
        .fields = &union_fields,
        .decls = &.{},
        .layout = .auto,
    } });
};

pub const MarkerDecodeError = error{NotAMarker};

pub fn decode(byte: u8) MarkerDecodeError!Marker {
    inline for (@typeInfo(MarkerValue).Struct.decls) |field| {
        const field_value = @field(MarkerValue, field.name);
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

test "FixPositive is a u7" {
    const un = Marker{ .FixPositive = 8 };
    try testing.expectEqual(u7, @TypeOf(un.FixPositive));
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
