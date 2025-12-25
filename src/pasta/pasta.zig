pub const Pasta = struct {
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
};