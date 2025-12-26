const Allocator = @import("std").mem.Allocator;

pub const Pasta = struct {
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

    pub fn dupe(self: Self, gpa: Allocator) !Pasta {
        var pasta: Pasta = self;
        pasta.name = try dupe_str(self.name, gpa);
        pasta.content = try dupe_str(self.content, gpa);
        pasta.content_type = try dupe_str(self.content_type, gpa);
        pasta.attachements = try dupe_str(self.attachements, gpa);
        pasta.password = try dupe_str(self.password, gpa);
        pasta.profiles = try dupe_str(self.profiles, gpa);
        return pasta;
    }

    fn dupe_str(str: ?[]const u8, gpa: Allocator) !?[]u8 {
        if (str) |s| {
            return try gpa.dupe(u8, s);
        }
        return null;
    } 
};