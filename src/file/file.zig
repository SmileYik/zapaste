pub const File = struct {
    id: ?u64 = null,
    hash: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    filesize: ?u32 = null,
    filepath: ?[]const u8 = null,
    mimetype: ?[]const u8 = null,
};