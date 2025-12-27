const PasteDao = @import("paste_dao.zig").PasteDao;
const Paste = @import("paste.zig").Paste;
const std = @import("std");
const Random = std.Random;
const Allocator = std.mem.Allocator;

pub const PasteService = struct {
    const Self = @This();

    dao: ?*PasteDao = null,
    prng: ?Random.DefaultPrng = null,
    animal_names: []const []const u8 = split_static_file("animals.txt"),
    animal_adjectives: []const []const u8 = split_static_file("adjectives.txt"),

    /// create paste service instance. dao instance is required, others all optional.
    pub fn create(config: Self) PasteService {
        return .{
            .dao = config.dao,
            .prng = Random.DefaultPrng.init(@intCast(std.time.timestamp())),
            .animal_names = config.animal_names,
            .animal_adjectives = config.animal_adjectives
        };
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

        var entity: Paste = try paste.dupe(temp_gpa);
        entity.name = entity.name orelse try self.random_animal_name(temp_gpa);
        entity.profiles = entity.profiles orelse "{}";
        entity.create_at = @intCast(std.time.timestamp());
        entity.latest_read_at = @intCast(std.time.timestamp());

        const retry = 3;
        for (0..retry) |i| {
            const result = self.dao.?.insert_paste(entity) catch |err| {
                if (retry == i + 1) {
                    return err;                    
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
    pub fn read_paste(self: *Self, gpa: Allocator, query: Paste) ?Paste {
        if (query.name == null) {
            return null;
        }
        const paste = self.find_paste(gpa, query.name.?);
        if (paste) |p| {
            var success: bool = true;
            if (p.has_password != null and p.has_password.?) {
                if (!std.mem.eql(u8, p.password orelse "", query.password orelse "")) {
                    success = false;
                }
            }
            if (success) {
                self.increase_read_count(p) catch |e| {
                    std.log.debug("[PasteService] failed increase read count: {}", .{e});
                };
                return p;
            }
        }
        return null;
    }

    pub fn find_paste(self: *Self, gpa: Allocator, paste_name: []const u8) ?Paste {
        const paste = self.dao.?.get_paste_by_name(gpa, paste_name) catch |err| {
            std.debug.print("[PasteService] failed to find a paste by name {s}: {}", .{paste_name, err});
            return null;
        };
        return paste;
    }

    pub fn update_paste(self: *Self, gpa: Allocator, paste: Paste) !?Paste {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();
        var entity = try paste.dupe(temp_gpa);
        if (entity.id == null) {
            var found: ?Paste = null;
            if (entity.name) |name| {
                if (self.find_paste(temp_gpa, name)) |f| {
                    found = f;
                }
            }
            if (found) |f| {
                entity.id = f.id;
            } else {
                return error.CannotFindPaste;
            }
        }
        entity.name = null;
        return try self.dao.?.update_paste(gpa, entity);
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
    const content = @embedFile(filename);
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

const SqlitePasteDao = @import("paste_dao.zig").SqlitePasteDao;
const sqlite = @import("sqlite");
test "test random animal name" {
    var s = PasteService.create(.{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
}

test "create a paste" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.create_paste(gpa, .{
        .content = "new content without name"
    }) catch |err| {
        std.debug.print("create a paste whitout name failed: {}\n", .{err});
        return;
    };
    std.debug.print("create a paste whitout name: {}\n", .{result});
}

test "create a paste with special name" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.create_paste(gpa, .{
        .name = "i am the paste name",
        .content = "new content 2"
    }) catch |err| {
        std.debug.print("create a paste failed: {}\n", .{err});
        return;
    };
    std.debug.print("create a paste: {}\n", .{result});
}

test "update a paste" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.update_paste(gpa, .{
        .id = 101,
        .read_count = 99999
    }) catch |err| {
        std.debug.print("update a paste failed: {}\n", .{err});
        return;
    };
    std.debug.print("update a paste: {}\n", .{result.?});
}

test "update a paste with name" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.update_paste(gpa, .{
        .name = "i am the paste name",
        .read_count = 100000
    }) catch |err| {
        std.debug.print("update a paste with name failed: {}\n", .{err});
        return;
    };
    std.debug.print("update a paste with name: {}\n", .{result.?});
}

test "increase read count" {
var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = arena.allocator();
    try service.increase_read_count(.{
        .id = 102
    });
}

test "increase read count by name" {
var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    for (0..100) |_| {
        try service.increase_read_count(.{
            .name = "test-66"
        });
        const result = service.find_paste(gpa, "test-66");

        std.debug.print("increase read count with name: {}\n", .{result.?});
    }
}

test "read paste" {
var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = &db };
    var dao: PasteDao = sqldao.create();
    var service: PasteService = PasteService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    for (0..100) |_| {
        const result = service.read_paste(gpa, .{
            .name = "test-56"
        });
        std.debug.print("read paste: {}\n", .{result.?});
    }
}