const PastaDao = @import("pasta_dao.zig").PastaDao;
const Pasta = @import("pasta.zig").Pasta;
const std = @import("std");
const Random = std.Random;
const Allocator = std.mem.Allocator;

pub const PastaService = struct {
    const Self = @This();

    dao: ?*PastaDao = null,
    prng: ?Random.DefaultPrng = null,
    animal_names: []const []const u8 = split_static_file("animals.txt"),
    animal_adjectives: []const []const u8 = split_static_file("adjectives.txt"),

    /// create pasta service instance. dao instance is required, others all optional.
    pub fn create(config: Self) PastaService {
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

    pub fn create_pasta(self: *Self, gpa: Allocator, pasta: Pasta) !Pasta {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        var entity: Pasta = try pasta.dupe(temp_gpa);
        entity.name = entity.name orelse try self.random_animal_name(temp_gpa);
        entity.profiles = entity.profiles orelse "{}";
        entity.create_at = @intCast(std.time.timestamp());
        entity.latest_read_at = @intCast(std.time.timestamp());

        const retry = 3;
        for (0..retry) |i| {
            const result = self.dao.?.insert_pasta(entity) catch |err| {
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

    /// read pasta by name. will check password.  
    /// if password is correct, it's will increased pasta read count and clean expired pastas. 
    pub fn read_pasta(self: *Self, gpa: Allocator, query: Pasta) ?Pasta {
        if (query.name == null) {
            return null;
        }
        const pasta = self.find_pasta(gpa, query.name.?);
        if (pasta) |p| {
            var success: bool = true;
            if (p.has_password != null and p.has_password.?) {
                if (!std.mem.eql(u8, p.password orelse "", query.password orelse "")) {
                    success = false;
                }
            }
            if (success) {
                self.increase_read_count(p) catch |e| {
                    std.log.debug("[PastaService] failed increase read count: {}", .{e});
                };
                return p;
            }
        }
        return null;
    }

    pub fn find_pasta(self: *Self, gpa: Allocator, pasta_name: []const u8) ?Pasta {
        const pasta = self.dao.?.get_pasta_by_name(gpa, pasta_name) catch |err| {
            std.debug.print("[PastaService] failed to find a pasta by name {s}: {}", .{pasta_name, err});
            return null;
        };
        return pasta;
    }

    pub fn update_pasta(self: *Self, gpa: Allocator, pasta: Pasta) !?Pasta {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();
        var entity = try pasta.dupe(temp_gpa);
        if (entity.id == null) {
            var found: ?Pasta = null;
            if (entity.name) |name| {
                if (self.find_pasta(temp_gpa, name)) |f| {
                    found = f;
                }
            }
            if (found) |f| {
                entity.id = f.id;
            } else {
                return error.CannotFindPasta;
            }
        }
        entity.name = null;
        return try self.dao.?.update_pasta(gpa, entity);
    }

    pub fn increase_read_count(self: *Self, pasta: Pasta) !void {
        try self.dao.?.increase_read_count(pasta);
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

const SqlitePastaDao = @import("pasta_dao.zig").SqlitePastaDao;
const sqlite = @import("sqlite");
test "test random animal name" {
    var s = PastaService.create(.{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
    std.debug.print("random animal name: {s}\n", .{try s.random_animal_name(temp_alloc)});
}

test "create a pasta" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.create_pasta(gpa, .{
        .content = "new content without name"
    }) catch |err| {
        std.debug.print("create a pasta whitout name failed: {}\n", .{err});
        return;
    };
    std.debug.print("create a pasta whitout name: {}\n", .{result});
}

test "create a pasta with special name" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.create_pasta(gpa, .{
        .name = "i am the pasta name",
        .content = "new content 2"
    }) catch |err| {
        std.debug.print("create a pasta failed: {}\n", .{err});
        return;
    };
    std.debug.print("create a pasta: {}\n", .{result});
}

test "update a pasta" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.update_pasta(gpa, .{
        .id = 101,
        .read_count = 99999
    }) catch |err| {
        std.debug.print("update a pasta failed: {}\n", .{err});
        return;
    };
    std.debug.print("update a pasta: {}\n", .{result.?});
}

test "update a pasta with name" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = service.update_pasta(gpa, .{
        .name = "i am the pasta name",
        .read_count = 100000
    }) catch |err| {
        std.debug.print("update a pasta with name failed: {}\n", .{err});
        return;
    };
    std.debug.print("update a pasta with name: {}\n", .{result.?});
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
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
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
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    for (0..100) |_| {
        try service.increase_read_count(.{
            .name = "test-66"
        });
        const result = service.find_pasta(gpa, "test-66");

        std.debug.print("increase read count with name: {}\n", .{result.?});
    }
}

test "read pasta" {
var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = SqlitePastaDao{ .db = &db };
    var dao: PastaDao = sqldao.create();
    var service: PastaService = PastaService.create(.{ .dao = &dao });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    for (0..100) |_| {
        const result = service.read_pasta(gpa, .{
            .name = "test-56"
        });
        std.debug.print("read pasta: {}\n", .{result.?});
    }
}