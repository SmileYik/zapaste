const std = @import("std");
const Paste = @import("paste.zig").Paste;
const sqlite = @import("sqlite");

pub const PasteDao = struct {
    ptr: *anyopaque,
    create_table_if_not_exists_fn: *const fn (ptr: *anyopaque) anyerror!void,
    get_paste_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Paste,
    get_paste_by_name_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, name: []const u8) anyerror!?Paste,
    list_pastes_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Paste) anyerror!?[]Paste,
    delete_paste_fn: *const fn (ptr: *anyopaque, id: u64) anyerror!bool,
    delete_paste_by_name_fn: *const fn (ptr: *anyopaque, name: []const u8) anyerror!bool,
    update_paste_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste,
    increase_read_count_fn: *const fn (ptr: *anyopaque, paste: Paste) anyerror!void,
    insert_paste_fn: *const fn (ptr: *anyopaque, entity: Paste) anyerror!?u64,
    clean_paste_fn: *const fn (ptr: *anyopaque) anyerror!void,

    pub fn create_table_if_not_exists(self: PasteDao) anyerror!void {
        return try self.create_table_if_not_exists_fn(self.ptr);
    }

    pub fn get_paste(self: PasteDao, allocator: std.mem.Allocator, id: u64) anyerror!?Paste {
        return try self.get_paste_fn(self.ptr, allocator, id);
    }

    pub fn get_paste_by_name(self: PasteDao, allocator: std.mem.Allocator, name: []const u8) anyerror!?Paste {
        return try self.get_paste_by_name_fn(self.ptr, allocator, name);
    }

    pub fn list_pastes(self: PasteDao, allocator: std.mem.Allocator, query: ?Paste) anyerror!?[]Paste {
        return try self.list_pastes_fn(self.ptr, allocator, query);
    }

    pub fn delete_paste(self: PasteDao, id: u64) anyerror!bool {
        return try self.delete_paste_fn(self.ptr, id);
    }

    pub fn delete_paste_by_name(self: PasteDao, name: []const u8) anyerror!bool {
        return try self.delete_paste_by_name_fn(self.ptr, name);
    }

    pub fn update_paste(self: PasteDao, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste {
        return try self.update_paste_fn(self.ptr, allocator, entity);
    }

    /// increase read count. allow pass name or id. id has higer priority.
    pub fn increase_read_count(self: PasteDao, paste: Paste) !void {
        return try self.increase_read_count_fn(self.ptr, paste);
    }

    /// insert Paste into table and return the id in the table.
    pub fn insert_paste(self: PasteDao, entity: Paste) anyerror!?u64 {
        return try self.insert_paste_fn(self.ptr, entity);
    }

    /// clean paste includes burn_after_reads and expirations.
    pub fn clean_paste(self: PasteDao) !void {
        return try self.clean_paste_fn(self.ptr);
    }
};

pub const SqlitePasteDao = struct {
    const CREATE_TABLE_SQL =
        \\CREATE TABLE IF NOT EXISTS paste (
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
        \\  paste.id, 
        \\  paste.name, 
        \\  paste.content, 
        \\  paste.content_type, 
        \\  paste.attachements, 
        \\  paste.private, 
        \\  paste.read_only, 
        \\  paste.editable, 
        \\  paste.has_password, 
        \\  paste.password, 
        \\  paste.read_count, 
        \\  paste.burn_after_reads, 
        \\  paste.latest_read_at, 
        \\  paste.create_at, 
        \\  paste.expiration_at, 
        \\  paste.profiles 
        \\FROM paste
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
        \\INSERT INTO paste (
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
        \\UPDATE paste SET 
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

    pub fn create(self: *SqlitePasteDao) PasteDao {
        return .{
            .ptr = self,
            .create_table_if_not_exists_fn = create_table_if_not_exists,
            .get_paste_fn = get_paste,
            .get_paste_by_name_fn = get_paste_by_name,
            .list_pastes_fn = list_pastes,
            .delete_paste_fn = delete_paste,
            .delete_paste_by_name_fn = delete_paste_by_name,
            .update_paste_fn = update_paste,
            .increase_read_count_fn = increase_read_count,
            .insert_paste_fn = insert_paste,
            .clean_paste_fn = clean_paste
        };
    }

    fn create_table_if_not_exists(ptr: *anyopaque) anyerror!void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        try self.db.exec(CREATE_TABLE_SQL, .{}, .{});
    }

    fn get_paste(ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));

        const query = SELECT_SQL ++ " WHERE paste.id = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Paste,
            allocator,
            .{},
            .{ .id = id },
        );
        return row;
    }

    fn get_paste_by_name(ptr: *anyopaque, allocator: std.mem.Allocator, name: []const u8) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));

        const query = SELECT_SQL ++ " WHERE paste.name = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Paste,
            allocator,
            .{},
            .{ .name = name },
        );
        return row;
    }

    fn list_pastes(ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Paste) anyerror!?[]Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        var stmt = try self.db.prepareDynamic(QUERY_SQL);
        defer stmt.deinit();
        return try stmt.all(
            Paste,
            allocator,
            .{},
            query orelse Paste {},
        );
    }

    fn delete_paste(ptr: *anyopaque, id: u64) anyerror!bool {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM paste WHERE paste.id = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{id});
        return true;
    }

    fn delete_paste_by_name(ptr: *anyopaque, name: []const u8) anyerror!bool {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM paste WHERE paste.name = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{name});
        return true;
    }

    fn clean_paste(ptr: *anyopaque) !void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const sql =
            \\DELETE FROM paste WHERE
            \\(burn_after_reads IS NOT NULL AND read_count > burn_after_reads)
            \\OR
            \\(expiration_at IS NOT NULL AND expiration_at > ?)
        ;
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{ @as(u64, @intCast(std.time.timestamp())) });
    }

    fn update_paste(ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        if (entity.id) |id| {
            var stmt = try self.db.prepareDynamic(UPDATE_SQL);
            defer stmt.deinit();

            try stmt.exec(.{}, entity);
            return try get_paste(ptr, allocator, id);
        }
        return entity;
    }

    fn increase_read_count(ptr: *anyopaque, paste: Paste) !void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_gpa = arena.allocator();

        var sql: ?[]u8 = null;
        if (paste.id) |id| {
            sql = try std.fmt.allocPrint(
                temp_gpa, 
                "UPDATE paste SET latest_read_at = {}, read_count = COALESCE(read_count, 0) + 1 WHERE id = {}", 
                .{
                    @as(u64, @intCast(std.time.timestamp())),
                    id
                }
            );
        } else if (paste.name) |name| {
            sql = try std.fmt.allocPrint(
                temp_gpa, 
                "UPDATE paste SET latest_read_at = {}, read_count = COALESCE(read_count, 0) + 1 WHERE name = '{s}'", 
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

    fn insert_paste(ptr: *anyopaque, entity: Paste) anyerror!?u64 {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        var stmt = try self.db.prepareDynamic(INSERT_SQL);
        defer stmt.deinit();

        return try stmt.one(u64, .{}, entity);
    }
};


test "[SqlitePasteDao] create table" {
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
    try dao.create_table_if_not_exists();
}

test "[SqlitePasteDao] insert" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    var sqldao: SqlitePasteDao = .{ .db = &db };
    var dao: PasteDao = sqldao.create();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (0..100) |i| {
        var paste: Paste = Paste {
            .name = try std.fmt.allocPrint(allocator, "test-{}", .{i}),
            .private = i % 2 == 0,
            .expiration_at = 123456 * i
        };
        if (dao.insert_paste(paste)) |id| {
            paste.id = id;
            std.debug.print("insert test success: {}\n", .{paste});
        } else |err| {
            std.debug.print("insert test faield: {}\n", .{err});
        }
    }
}

test "[SqlitePasteDao] query by id" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const paste1 = try dao.get_paste(allocator, 1);
    std.debug.assert(paste1 != null);
    std.debug.print("paste 1: {}\n", .{paste1.?});
    std.debug.assert(std.mem.eql(u8, paste1.?.name.?, "test-0"));
}

test "[SqlitePasteDao] query by name" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const paste1 = try dao.get_paste_by_name(allocator, "test-1");
    std.debug.assert(paste1 != null);
    std.debug.print("paste test-1: {}\n", .{paste1.?});
    std.debug.assert(paste1.?.id.? == 2);
}

test "[SqlitePasteDao] query all list" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.list_pastes(allocator, null)) |paste| {
        std.debug.print("query all list: {any}\n", .{paste.?});
    } else |e| {
        std.debug.print("query all list failed: {}\n", .{e});
    }
}

test "[SqlitePasteDao] query all private list" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.list_pastes(allocator, .{
        .private = true
    })) |paste| {
        std.debug.print("query all private list: {any}\n", .{paste.?});
    } else |e| {
        std.debug.print("query all private list failed: {}\n", .{e});
    }
}

test "[SqlitePasteDao] delete by id" {
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
    const flag1 = try dao.delete_paste(10);
    std.debug.print("delete id 10: {}\n", .{flag1});
    const flag2 = try dao.delete_paste(110);
    std.debug.print("delete id 110: {}\n", .{flag2});
    // std.debug.assert(flag);
    // std.debug.assert(try dao.delete_paste(10));
    // std.debug.assert(!try dao.delete_paste(110));
}

test "[SqlitePasteDao] delete by name" {
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
    const flag1 = try dao.delete_paste_by_name("test-20");
    std.debug.print("delete id test-20: {}\n", .{flag1});
    const flag2 = try dao.delete_paste_by_name("test-200");
    std.debug.print("delete id test-200: {}\n", .{flag2});
}

test "[SqlitePasteDao] update" {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (dao.update_paste(allocator, .{
        .id = 12,
        .latest_read_at = 548451654561,
        .name = "modified"
    })) |result| {
        std.debug.print("modified id 12: {}\n", .{result.?});
    } else |e| {
        std.debug.print("modified id 12 error: {}\n", .{e});
    }
}

test "[SqlitePasteDao] test options" {
    const Options = @import("common").Options;
    const DaoType = @import("common").DaoType;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const options = Options.init(allocator, .{
        .dao_type = DaoType.Sqlite,
        .work_dir = "./"
    }) catch |e| {
        std.debug.print("test options failed, cannot init options: {}", .{e});
        return;
    };

    var sqldao: SqlitePasteDao = SqlitePasteDao{ .db = options.sqlite_db.? };
    var dao: PasteDao = sqldao.create();
        if (dao.list_pastes(allocator, .{
        .private = false
    })) |paste| {
        std.debug.print("query all public list: {any}\n", .{paste.?});
    } else |e| {
        std.debug.print("query all public list failed: {}\n", .{e});
    }
}