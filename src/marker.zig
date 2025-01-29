pub const Marker = enum(u8) {
    NIL = 0xc0,

    FALSE = 0xc2,
    TRUE = 0xc3,

    UINT_8 = 0xcc,
    UINT_16 = 0xcd,
    UINT_32 = 0xce,
    UINT_64 = 0xcf,

    INT_8 = 0xd0,
    INT_16 = 0xd1,
    INT_32 = 0xd2,
    INT_64 = 0xd3,

    FLOAT_32 = 0xca,
    FLOAT_64 = 0xcb,

    STR_8 = 0xd9,
    STR_16 = 0xda,
    STR_32 = 0xdb,

    BIN_8 = 0xc4,
    BIN_16 = 0xc5,
    BIN_32 = 0xc6,

    ARRAY_16 = 0xdc,
    ARRAY_32 = 0xdd,

    MAP_16 = 0xde,
    MAP_32 = 0xdf,

    FIXEXT_1 = 0xd4,
    FIXEXT_2 = 0xd5,
    FIXEXT_4 = 0xd6,
    FIXEXT_8 = 0xd7,
    FIXEXT_16 = 0xd8,

    EXT_8 = 0xc7,
    EXT_16 = 0xc8,
    EXT_32 = 0xc9,
};

pub const FixMarker = enum(struct { marker: u8, mask: u8 }) {
    pub const FIX_STR = .{};
};
