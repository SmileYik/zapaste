const std = @import("std");
const Pasta = @import("pasta.zig").Pasta;
const sqlite = @import("sqlite");

pub const PastaDao = struct {
    ptr: *anyopaque,
    create_table_if_not_exists_fn: *const fn (ptr: *anyopaque) anyerror!void,
    get_pasta_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta,
    get_pasta_by_name_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, name: []const u8) anyerror!?Pasta,
    list_pastas_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta,
    delete_pasta_fn: *const fn (ptr: *anyopaque, id: u64) anyerror!bool,
    delete_pasta_by_name_fn: *const fn (ptr: *anyopaque, name: []const u8) anyerror!bool,
    update_pasta_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta,
    increase_read_count_fn: *const fn (ptr: *anyopaque, pasta: Pasta) anyerror!void,
    insert_pasta_fn: *const fn (ptr: *anyopaque, entity: Pasta) anyerror!?u64,
    clean_pasta_fn: *const fn (ptr: *anyopaque) anyerror!void,

    pub fn create_table_if_not_exists(self: PastaDao) anyerror!void {
        return self.create_table_if_not_exists_fn(self.ptr);
    }

    pub fn get_pasta(self: PastaDao, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta {
        return self.get_pasta_fn(self.ptr, allocator, id);
    }

    pub fn get_pasta_by_name(self: PastaDao, allocator: std.mem.Allocator, name: []const u8) anyerror!?Pasta {
        return self.get_pasta_by_name_fn(self.ptr, allocator, name);
    }

    pub fn list_pastas(self: PastaDao, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta {
        return self.list_pastas_fn(self.ptr, allocator, query);
    }

    pub fn delete_pasta(self: PastaDao, id: u64) anyerror!bool {
        return self.delete_pasta_fn(self.ptr, id);
    }

    pub fn delete_pasta_by_name(self: PastaDao, name: []const u8) anyerror!bool {
        return self.delete_pasta_by_name_fn(self.ptr, name);
    }

    pub fn update_pasta(self: PastaDao, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta {
        return self.update_pasta_fn(self.ptr, allocator, entity);
    }

    /// increase read count. allow pass name or id. id has higer priority.
    pub fn increase_read_count(self: PastaDao, pasta: Pasta) !void {
        return self.increase_read_count_fn(self.ptr, pasta);
    }

    /// insert Pasta into table and return the id in the table.
    pub fn insert_pasta(self: PastaDao, entity: Pasta) anyerror!?u64 {
        return self.insert_pasta_fn(self.ptr, entity);
    }

    /// clean pasta includes burn_after_reads and expirations.
    pub fn clean_pasta(self: PastaDao) !void {
        return self.clean_pasta_fn(self.ptr);
    }
};

pub const SqlitePastaDao = struct {
    const CREATE_TABLE_SQL =
        \\CREATE TABLE IF NOT EXISTS pasta (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL UNIQUE,
        \\  content TEXT,
        \\  content_type TEXT,
        \\  attachements TEXT,
        \\  private INTEGER,
        \\  read_only INTEGER,
        \\  editable INTEGER,
        \\  has_password INTEGER,
        \\  password TEXT,
        \\  read_count INTEGER,
        \\  burn_after_reads INTEGER,
        \\  latest_read_at INTEGER,
        \\  create_at INTEGER,
        \\  expiration_at INTEGER,
        \\  profiles TEXT
        \\)
    ;
    const SELECT_SQL =
        \\SELECT 
        \\  pasta.id, 
        \\  pasta.name, 
        \\  pasta.content, 
        \\  pasta.content_type, 
        \\  pasta.attachements, 
        \\  pasta.private, 
        \\  pasta.read_only, 
        \\  pasta.editable, 
        \\  pasta.has_password, 
        \\  pasta.password, 
        \\  pasta.read_count, 
        \\  pasta.burn_after_reads, 
        \\  pasta.latest_read_at, 
        \\  pasta.create_at, 
        \\  pasta.expiration_at, 
        \\  pasta.profiles 
        \\FROM pasta
    ;
    const QUERY_SQL = SELECT_SQL ++
        \\ WHERE
        \\  (:id IS NULL OR id = :id) AND
        \\  (:name IS NULL OR name = :name) AND
        \\  (:content IS NULL OR content = :content) AND
        \\  (:content_type IS NULL OR content_type = :content_type) AND
        \\  (:attachements IS NULL OR attachements = :attachements) AND
        \\  (:private IS NULL OR private = :private) AND
        \\  (:read_only IS NULL OR read_only = :read_only) AND
        \\  (:editable IS NULL OR editable = :editable) AND
        \\  (:has_password IS NULL OR has_password = :has_password) AND
        \\  (:password IS NULL OR password = :password) AND
        \\  (:read_count IS NULL OR read_count = :read_count) AND
        \\  (:burn_after_reads IS NULL OR burn_after_reads = :burn_after_reads) AND
        \\  (:latest_read_at IS NULL OR latest_read_at = :latest_read_at) AND
        \\  (:create_at IS NULL OR create_at = :create_at) AND
        \\  (:expiration_at IS NULL OR expiration_at = :expiration_at) AND
        \\  (:profiles IS NULL OR profiles = :profiles)
    ;
    const INSERT_SQL =
        \\INSERT INTO pasta (
        \\  name, 
        \\  content, 
        \\  content_type, 
        \\  attachements, 
        \\  private, 
        \\  read_only, 
        \\  editable, 
        \\  has_password, 
        \\  password, 
        \\  read_count, 
        \\  burn_after_reads, 
        \\  latest_read_at, 
        \\  create_at, 
        \\  expiration_at, 
        \\  profiles 
        \\) VALUES (
        \\  :name, 
        \\  :content, 
        \\  :content_type, 
        \\  :attachements, 
        \\  :private, 
        \\  :read_only, 
        \\  :editable, 
        \\  :has_password, 
        \\  :password, 
        \\  :read_count, 
        \\  :burn_after_reads, 
        \\  :latest_read_at, 
        \\  :create_at, 
        \\  :expiration_at, 
        \\  :profiles 
        \\) RETURNING id
    ;
    const UPDATE_SQL = 
        \\UPDATE pasta SET 
        \\  name = COALESCE(:name, name),
        \\  content = COALESCE(:content, content),
        \\  content_type = COALESCE(:content_type, content_type),
        \\  attachements = COALESCE(:attachements, attachements),
        \\  private = COALESCE(:private, private),
        \\  read_only = COALESCE(:read_only, read_only),
        \\  editable = COALESCE(:editable, editable),
        \\  has_password = COALESCE(:has_password, has_password),
        \\  password = COALESCE(:password, password),
        \\  read_count = COALESCE(:read_count, read_count),
        \\  burn_after_reads = COALESCE(:burn_after_reads, burn_after_reads),
        \\  latest_read_at = COALESCE(:latest_read_at, latest_read_at),
        \\  create_at = COALESCE(:create_at, create_at),
        \\  expiration_at = COALESCE(:expiration_at, expiration_at),
        \\  profiles = COALESCE(:profiles, profiles)
        \\WHERE id = :id
    ;

    db: *sqlite.Db,

    pub fn create(self: *SqlitePastaDao) PastaDao {
        return .{
            .ptr = self,
            .create_table_if_not_exists_fn = create_table_if_not_exists,
            .get_pasta_fn = get_pasta,
            .get_pasta_by_name_fn = get_pasta_by_name,
            .list_pastas_fn = list_pastas,
            .delete_pasta_fn = delete_pasta,
            .delete_pasta_by_name_fn = delete_pasta_by_name,
            .update_pasta_fn = update_pasta,
            .increase_read_count_fn = increase_read_count,
            .insert_pasta_fn = insert_pasta,
            .clean_pasta_fn = clean_pasta
        };
    }

    fn create_table_if_not_exists(ptr: *anyopaque) anyerror!void {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        try self.db.exec(CREATE_TABLE_SQL, .{}, .{});
    }

    fn get_pasta(ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));

        const query = SELECT_SQL ++ " WHERE pasta.id = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Pasta,
            allocator,
            .{},
            .{ .id = id },
        );
        return row;
    }

    fn get_pasta_by_name(ptr: *anyopaque, allocator: std.mem.Allocator, name: []const u8) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));

        const query = SELECT_SQL ++ " WHERE pasta.name = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Pasta,
            allocator,
            .{},
            .{ .name = name },
        );
        return row;
    }

    fn list_pastas(ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        var stmt = try self.db.prepareDynamic(QUERY_SQL);
        defer stmt.deinit();
        return try stmt.all(
            Pasta,
            allocator,
            .{},
            query orelse Pasta {},
        );
    }

    fn delete_pasta(ptr: *anyopaque, id: u64) anyerror!bool {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM pasta WHERE pasta.id = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{id});
        return true;
    }

    fn delete_pasta_by_name(ptr: *anyopaque, name: []const u8) anyerror!bool {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM pasta WHERE pasta.name = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{name});
        return true;
    }

    fn clean_pasta(ptr: *anyopaque) !void {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql =
            \\DELETE FROM pasta WHERE
            \\(burn_after_reads IS NOT NULL AND read_count > burn_after_reads)
            \\OR
            \\(expiration_at IS NOT NULL AND expiration_at > ?)
        ;
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{ @as(u64, @intCast(std.time.timestamp())) });
    }

    fn update_pasta(ptr: *anyopaque, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        if (entity.id) |id| {
            var stmt = try self.db.prepareDynamic(UPDATE_SQL);
            defer stmt.deinit();

            try stmt.exec(.{}, entity);
            return try get_pasta(ptr, allocator, id);
        }
        return entity;
    }

    fn increase_read_count(ptr: *anyopaque, pasta: Pasta) !void {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        var sql: ?[]u8 = null;
        if (pasta.id) |id| {
            sql = try std.fmt.allocPrint(
                temp_gpa, 
                "UPDATE pasta SET latest_read_at = {}, read_count = COALESCE(read_count, 0) + 1 WHERE id = {}", 
                .{
                    @as(u64, @intCast(std.time.timestamp())),
                    id
                }
            );
        } else if (pasta.name) |name| {
            sql = try std.fmt.allocPrint(
                temp_gpa, 
                "UPDATE pasta SET latest_read_at = {}, read_count = COALESCE(read_count, 0) + 1 WHERE name = '{s}'", 
                .{
                    @as(u64, @intCast(std.time.timestamp())),
                    name
                }
            );
        } else {
            sql = null;
        }
        if (sql) |s| {
            var stmt = try self.db.prepareDynamic(s);
            defer stmt.deinit();
            try stmt.exec(.{}, .{});
        }
    }

    fn insert_pasta(ptr: *anyopaque, entity: Pasta) anyerror!?u64 {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        var stmt = try self.db.prepareDynamic(INSERT_SQL);
        defer stmt.deinit();

        return try stmt.one(u64, .{}, entity);
    }
};


test "[SqlitePastaDao] create table" {
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
    try dao.create_table_if_not_exists();
}

test "[SqlitePastaDao] insert" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePastaDao = .{ .db = &db };
    var dao: PastaDao = sqldao.create();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (0..100) |i| {
        var pasta: Pasta = Pasta {
            .name = try std.fmt.allocPrint(allocator, "test-{}", .{i}),
            .private = i % 2 == 0,
            .expiration_at = 123456 * i
        };
        if (dao.insert_pasta(pasta)) |id| {
            pasta.id = id;
            std.debug.print("insert test success: {}\n", .{pasta});
        } else |err| {
            std.debug.print("insert test faield: {}\n", .{err});
        }
    }
}

test "[SqlitePastaDao] query by id" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const pasta1 = try dao.get_pasta(allocator, 1);
    std.debug.assert(pasta1 != null);
    std.debug.print("pasta 1: {}\n", .{pasta1.?});
    std.debug.assert(std.mem.eql(u8, pasta1.?.name.?, "test-0"));
}

test "[SqlitePastaDao] query by name" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const pasta1 = try dao.get_pasta_by_name(allocator, "test-1");
    std.debug.assert(pasta1 != null);
    std.debug.print("pasta test-1: {}\n", .{pasta1.?});
    std.debug.assert(pasta1.?.id.? == 2);
}

test "[SqlitePastaDao] query all list" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.list_pastas(allocator, null)) |pasta| {
        std.debug.print("query all list: {any}\n", .{pasta.?});
    } else |e| {
        std.debug.print("query all list failed: {}\n", .{e});
    }
}

test "[SqlitePastaDao] query all private list" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.list_pastas(allocator, .{
        .private = true
    })) |pasta| {
        std.debug.print("query all private list: {any}\n", .{pasta.?});
    } else |e| {
        std.debug.print("query all private list failed: {}\n", .{e});
    }
}

test "[SqlitePastaDao] delete by id" {
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
    const flag1 = try dao.delete_pasta(10);
    std.debug.print("delete id 10: {}\n", .{flag1});
    const flag2 = try dao.delete_pasta(110);
    std.debug.print("delete id 110: {}\n", .{flag2});
    // std.debug.assert(flag);
    // std.debug.assert(try dao.delete_pasta(10));
    // std.debug.assert(!try dao.delete_pasta(110));
}

test "[SqlitePastaDao] delete by name" {
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
    const flag1 = try dao.delete_pasta_by_name("test-20");
    std.debug.print("delete id test-20: {}\n", .{flag1});
    const flag2 = try dao.delete_pasta_by_name("test-200");
    std.debug.print("delete id test-200: {}\n", .{flag2});
}

test "[SqlitePastaDao] update" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.update_pasta(allocator, .{
        .id = 12,
        .latest_read_at = 548451654561,
        .name = "modified"
    })) |result| {
        std.debug.print("modified id 12: {}\n", .{result.?});
    } else |e| {
        std.debug.print("modified id 12 error: {}\n", .{e});
    }
}
