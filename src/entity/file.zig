const File = struct {
    id: ?u64,
    hash: []u8,
    filename: []u8,
    filesize: u32,
    filepath: []u8,
};