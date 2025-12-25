pub const Pasta = struct {
    /// id
    id: ?u64,

    /// name
    name: ?[]u8,

    /// text content
    content: ?[]u8,
    content_type: ?[]u8,

    /// file ids 
    attachements: ?[]u8,
    private: ?bool,
    read_only: ?bool,
    editable: ?bool,
    
    has_password: ?bool,
    password: ?[]u8,

    read_count: ?u64,
    burn_after_reads: ?u64,
    latest_read_at: ?u64,

    create_at: ?u64,
    expiration_at: ?u64,
    profiles: ?[]u8,
};