const std = @import("std");
const PasteDao = @import("paste_dao.zig").PasteDao;
const Paste = @import("paste.zig").Paste;
const res = @import("res");
const sqlite = @import("sqlite");
const Random = std.Random;
const Allocator = std.mem.Allocator;

pub const PasteService = struct {
    const Self = @This();

    dao: ?*PasteDao = null,
    prng: ?Random.DefaultPrng = null,
    animal_names: []const []const u8 = split_static_file("paste/animals.txt"),
    animal_adjectives: []const []const u8 = split_static_file("paste/adjectives.txt"),

    /// create paste service instance. dao instance is required, others all optional.
    pub fn create(config: Self) PasteService {
        return .{
            .dao = config.dao,
            .prng = Random.DefaultPrng.init(@intCast(std.time.timestamp())),
            .animal_names = config.animal_names,
            .animal_adjectives = config.animal_adjectives
        };
    }

    pub fn random_string(self: *Self, allocator: std.mem.Allocator, length: usize) ![]u8 {
        const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        const random = self.prng.?.random();

        var result = try allocator.alloc(u8, length);
        for (0..length) |i| {
            const random_index = random.uintAtMost(usize, charset.len - 1);
            result[i] = charset[random_index];
        }
        
        return result;
    }

    pub fn random_animal_name(self: *Self, gpa: Allocator) ![]const u8 {
        const random = self.prng.?.random();
        const name = self.animal_names[random.uintLessThan(usize, self.animal_names.len)];
        const adjective = self.animal_adjectives[random.uintLessThan(usize, self.animal_adjectives.len)];
        return try std.fmt.allocPrint(gpa, "{s}-{s}", .{ adjective, name });
    }

    pub fn create_paste(self: *Self, gpa: Allocator, paste: Paste) !Paste {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        const has_name = paste.name != null;
        var entity: Paste = try paste.dupe(temp_gpa);
        entity.name = entity.name orelse try self.random_animal_name(temp_gpa);
        entity.profiles = entity.profiles orelse "{}";
        entity.create_at = @intCast(std.time.timestamp());
        entity.latest_read_at = @intCast(std.time.timestamp()); 
        try update_password(temp_gpa, &entity, entity.password orelse "");

        const retry = 3;
        const count: usize = 4;
        for (0..retry) |i| {
            const result = self.dao.?.insert_paste(entity) catch |err| {
                if (retry == i + 1) {
                    if (err == sqlite.Error.SQLiteConstraint) {
                        const name = try std.fmt.allocPrint(temp_gpa, "{s}-{s}", .{ 
                            entity.name.?, try self.random_string(temp_gpa, count * (i + 1))
                        });
                        entity.name = name;
                        if (try self.dao.?.insert_paste(entity)) |id| {
                            entity.id = id;
                            break;
                        }
                    }
                    return err;                    
                }
                if (has_name) {
                    entity.name = try std.fmt.allocPrint(temp_gpa, "{s}-{s}", .{ 
                        entity.name.?, try self.random_string(temp_gpa, count * (i + 1))
                    });
                } else {
                    entity.name = try self.random_animal_name(temp_gpa);
                }
                continue;
            };
            if (result) |id| {
                entity.id = id;
                break;
            }
        }
        return try entity.dupe(gpa);
    }

    /// read paste by name. will check password.  
    /// if password is correct, it's will increased paste read count and clean expired pastes. 
    pub fn read_paste(self: *Self, gpa: Allocator, query: Paste) !?Paste {
        if (query.name == null) {
            return null;
        }
        const paste = try self.find_paste(gpa, query.name.?);
        if (paste) |p| {
            // check time
            if (p.expiration_at) |expiration| {
                if (expiration <= @as(u64, @intCast(std.time.timestamp()))) {
                    return null;
                }
            }

            // check password
            if (try check_paste_password(gpa, &p, query.password)) {
                self.increase_read_count(p) catch |e| {
                    std.log.debug("[PasteService] failed increase read count: {}", .{e});
                };
                return p;
            } else {
                return error.PasswordRequired;
            }
        }
        return null;
    }

    /// delete paste by name, will check password, if real delete a paste then return true, else return false.
    /// if you set `force_delete` to `true`, then will ignore password
    pub fn delete_paste(self: *Self, allocator: Allocator, name: []const u8, password: ?[]const u8, force_delete :bool) !bool {
        const paste = try self.find_paste(allocator, name);
        if (paste) |p| {
            if (force_delete or try check_paste_password(allocator, &p, password)) {
                _ = try self.dao.?.delete_paste_by_name(name);
                return true;
            }
            return error.PasswordRequired;
        }
        return false;
    }
    
    inline fn check_paste_password(allocator: Allocator, paste: *const Paste, password: ?[]const u8) !bool {
        var success: bool = true;
        if (paste.has_password orelse false) {
            if (paste.password) |pp| {
                if (password) |p| {
                    success = compare_password(allocator, pp, p);
                } else success = false;
            }
        }
        
        return success;
    }

    pub fn find_paste(self: *Self, gpa: Allocator, paste_name: []const u8) !?Paste {
        return try self.dao.?.get_paste_by_name(gpa, paste_name);
    }

    pub fn update_paste(
        self: *Self, 
        gpa: Allocator, 
        paste: Paste, 
        name: []const u8,
        password: ?[]const u8,
        new_attachements: ?[] const u8,
        force_update: bool
    ) !?Paste {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        var entity = try paste.dupe(temp_gpa);
        entity.name = null;
        if (try self.find_paste(temp_gpa, name)) |stored| {
            if (!force_update and stored.read_only orelse false) {
                return error.ReadOnly;
            } else if (force_update or try check_paste_password(temp_gpa, &stored, password)) {
                entity.id = stored.id;
                
                try update_password(temp_gpa, &entity, entity.password orelse stored.password orelse "");

                // attachement things
                var real_attachements: ?[]const u8 = null;
                var attachements = try std.ArrayList(u8).initCapacity(temp_gpa, 1024);
                defer attachements.deinit(temp_gpa);
                {
                    var ids = try std.ArrayList([]const u8).initCapacity(temp_gpa, 1024);
                    defer ids.deinit(temp_gpa);
                    var old_set = std.StringHashMap(bool).init(temp_gpa);
                    defer old_set.deinit();
                    var set = std.StringHashMap(bool).init(temp_gpa);
                    defer set.deinit();

                    if (stored.attachements) |old_attach| {
                        var old = std.mem.splitAny(u8, old_attach, ",");
                        while (old.next()) |id| {
                            try old_set.put(id, true);
                        }

                        if (entity.attachements) |new_attach| {
                            var new = std.mem.splitAny(u8, new_attach, ",");
                            while (new.next()) |id| {
                                if (old_set.contains(id) and !set.contains(id)) {
                                    try set.put(id, true);
                                    try attachements.append(temp_gpa, ',');
                                    try std.fmt.format(attachements.writer(temp_gpa), "{s}", .{ id });
                                }
                            }
                        } else {
                            var old_iter = old_set.keyIterator();
                            while (old_iter.next()) |id| {
                                try set.put(id.*, true);
                                try attachements.append(temp_gpa, ',');
                                try std.fmt.format(attachements.writer(temp_gpa), "{s}", .{ id.* });
                            }
                        }
                    }
                    if (new_attachements) |new_attach| {
                        var new = std.mem.splitAny(u8, new_attach, ",");
                        while (new.next()) |id| {
                            if (!set.contains(id)) {
                                try set.put(id, true);
                                try attachements.append(temp_gpa, ',');
                                try std.fmt.format(attachements.writer(temp_gpa), "{s}", .{ id });
                            }
                        }
                    }
                    real_attachements = if (attachements.items.len > 0) attachements.items[1..] else "";
                }
                entity.attachements = real_attachements;
                
                return try self.dao.?.update_paste(gpa, entity);
            }
            return error.PasswordRequired;
        }
        return null;
    }

    pub fn increase_read_count(self: *Self, paste: Paste) !void {
        if (paste.read_count) |count| {
            if (paste.burn_after_reads) |limit| {
                if (limit != 0 and count + 1 >= limit) {
                    if (paste.id) |id| {
                        _ = try self.dao.?.delete_paste(id);
                        return;
                    } else if (paste.name) |name| {
                        _ = try self.dao.?.delete_paste_by_name(name);
                        return;
                    }
                }
            }
        }
        try self.dao.?.increase_read_count(paste);
    }

    pub fn list_public_pastes(self: *Self, allocator: Allocator) anyerror![]Paste {
        const result = try self.dao.?.list_pastes(allocator, .{
            .private = false
        });
        return result orelse &[_]Paste{};
    }

    pub fn page_public_pastes_summary(self: *Self, allocator: Allocator, page_no: ?u32, page_size: ?u32) !Paste.Page {
        return try self.dao.?.page_summary_pastes(
            allocator, .{ .private = false }, page_no, page_size
        );
    }

    pub fn clean_paste(self: *Self) !void {
        try self.dao.?.clean_paste();
    }
};

inline fn update_password(allocator: Allocator, entity: *Paste, password: ?[]const u8) !void {
    const password_len = std.mem.trim(
        u8, 
        password orelse "", 
        " \n\r\t"
    ).len;
    entity.has_password = if (password_len == 0) false else blk: {
        entity.password = try encode_password(allocator, password.?);
        break :blk true;
    };
}

/// need free
inline fn encode_password(allocator: Allocator, password: []const u8) ![]const u8 {
    var hash: [128]u8 = undefined;
    return try std.crypto.pwhash.argon2.strHash(password, .{
        .allocator = allocator,
        .params = .{ .t = 1, .m = 8192, .p = 1 }
    }, &hash);
}

inline fn compare_password(allocator: Allocator, hash: []const u8, password: []const u8) bool {
    std.crypto.pwhash.argon2.strVerify(hash, password, .{
        .allocator = allocator
    }) catch {
        return false;
    };
    return true;
}

fn split_static_file(comptime filename: []const u8) []const []const u8 {
    @setEvalBranchQuota(2000000);
    const content = res.file(filename);
    var count: usize = 0;
    var iter = std.mem.splitSequence(u8, content, "\n");
    while (iter.next()) |line| {
        if (std.mem.trim(u8, line, " \r\t").len > 0) {
            count += 1;
        }
    }

    const array = comptime blk: {
        var result: [count][]const u8 = undefined;
        var i: usize = 0;
        iter.reset();
        while (iter.next()) |line| {
            const trimed = std.mem.trim(u8, line, " \r\t");
            if (trimed.len > 0) {
                result[i] = trimed;
                i += 1;
            }
        }
        break :blk result;
    };
    return &array;
}