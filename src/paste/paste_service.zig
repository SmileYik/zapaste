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
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        const has_name = paste.name != null;
        var entity: Paste = try paste.dupe(temp_gpa);
        entity.name = entity.name orelse try self.random_animal_name(temp_gpa);
        entity.profiles = entity.profiles orelse "{}";
        entity.create_at = @intCast(std.time.timestamp());
        entity.latest_read_at = @intCast(std.time.timestamp());
        
        const password_len = std.mem.trim(u8, entity.password orelse "", " \n\r\t").len;
        entity.has_password = password_len != 0;
        // TODO some password thing,

        const retry = 3;
        for (0..retry) |i| {
            const result = self.dao.?.insert_paste(entity) catch |err| {
                if (retry == i + 1) {
                    if (err == sqlite.Error.SQLiteConstraint) {
                        const name = try std.fmt.allocPrint(temp_gpa, "{s}-{s}", .{ 
                            entity.name.?, try self.random_string(temp_gpa, 4)
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
                        entity.name.?, try self.random_string(temp_gpa, 4)
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
            if (check_paste_passwod(&p, query.password)) {
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
            if (force_delete or check_paste_passwod(&p, password)) {
                _ = try self.dao.?.delete_paste_by_name(name);
                return true;
            }
            return error.PasswordRequired;
        }
        return false;
    }
    
    inline fn check_paste_passwod(paste: *const Paste, password: ?[]const u8) bool {
        var success: bool = true;
        if (paste.has_password != null and paste.has_password.?) {
            if (!std.mem.eql(u8, paste.password orelse "", password orelse "")) {
                success = false;
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
        force_update: bool
    ) !?Paste {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        var entity = try paste.dupe(temp_gpa);
        entity.name = null;
        if (try self.find_paste(temp_gpa, name)) |stored| {
            if (!force_update and stored.read_only orelse false) {
                return error.ReadOnly;
            } else if (force_update or check_paste_passwod(&stored, password)) {
                entity.id = stored.id;

                // TODO password things
                const password_len = std.mem.trim(
                    u8, 
                    entity.password orelse stored.password orelse "", 
                    " \n\r\t"
                ).len;
                entity.has_password = password_len != 0;

                return try self.dao.?.update_paste(gpa, entity);
            }
            return error.PasswordRequired;
        }
        return null;
    }

    pub fn increase_read_count(self: *Self, paste: Paste) !void {
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
};

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