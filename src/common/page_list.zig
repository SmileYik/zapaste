pub fn PageList(comptime T: type) type {
    return struct {
        pub const Self = @This();
        
        list: []T,
        page_size: u32,
        page_no: u32,
        page_count: u32,
        total: u64,
    };
}