const Allocator = @import("std").mem.Allocator;
const PageList = @import("common").PageList;

pub const Paste = struct {
    const Self = @This();

    /// id
    id: ?u64 = null,

    /// name
    name: ?[]const u8 = null,

    /// text content
    content: ?[]const u8 = null,
    content_type: ?[]const u8 = null,

    /// file ids 
    attachements: ?[]const u8 = null,
    private: ?bool = null,
    read_only: ?bool = null,
    editable: ?bool = null,
    
    has_password: ?bool = null,
    password: ?[]const u8 = null,

    read_count: ?u64 = null,
    burn_after_reads: ?u64 = null,
    latest_read_at: ?u64 = null,

    create_at: ?u64 = null,
    expiration_at: ?u64 = null,
    profiles: ?[]const u8 = null,

    pub fn dupe(self: Self, gpa: Allocator) !Paste {
        var paste: Paste = self;
        paste.name = try dupe_str(self.name, gpa);
        paste.content = try dupe_str(self.content, gpa);
        paste.content_type = try dupe_str(self.content_type, gpa);
        paste.attachements = try dupe_str(self.attachements, gpa);
        paste.password = try dupe_str(self.password, gpa);
        paste.profiles = try dupe_str(self.profiles, gpa);
        return paste;
    }

    fn dupe_str(str: ?[]const u8, gpa: Allocator) !?[]u8 {
        if (str) |s| {
            return try gpa.dupe(u8, s);
        }
        return null;
    }

    pub const Page = PageList(Summary);
    pub const Summary = struct {
        /// id
        id: ?u64 = null,
        /// name
        name: ?[]const u8 = null,
        content_type: ?[]const u8 = null,
        read_only: ?bool = null,
        editable: ?bool = null,
        has_password: ?bool = null,
        read_count: ?u64 = null,
        latest_read_at: ?u64 = null,
        create_at: ?u64 = null,
        expiration_at: ?u64 = null,
    };
};