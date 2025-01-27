pub const Marker = enum(u8) {
    pub const NIL = 0xc0;

    pub const FALSE = 0xc2;
    pub const TRUE = 0xc3;

    pub const UINT_8 = 0xcc;
    pub const UINT_16 = 0xcd;
    pub const UINT_32 = 0xce;
    pub const UINT_64 = 0xcf;

    pub const INT_8 = 0xd0;
    pub const INT_16 = 0xd1;
    pub const INT_32 = 0xd2;
    pub const INT_64 = 0xd3;

    pub const FLOAT_32 = 0xca;
    pub const FLOAT_64 = 0xcb;

    pub const STR_8 = 0xd9;
    pub const STR_16 = 0xda;
    pub const STR_32 = 0xdb;

    pub const BIN_8 = 0xc4;
    pub const BIN_16 = 0xc5;
    pub const BIN_32 = 0xc6;

    pub const ARRAY_16 = 0xdc;
    pub const ARRAY_32 = 0xdd;

    pub const MAP_16 = 0xde;
    pub const MAP_32 = 0xdf;

    pub const FIXEXT_1 = 0xd4;
    pub const FIXEXT_2 = 0xd5;
    pub const FIXEXT_4 = 0xd6;
    pub const FIXEXT_8 = 0xd7;
    pub const FIXEXT_16 = 0xd8;

    pub const EXT_8 = 0xc7;
    pub const EXT_16 = 0xc8;
    pub const EXT_32 = 0xc9;
};
