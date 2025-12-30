const std = @import("std");
const Paste = @import("paste.zig").Paste;
const sqlite = @import("sqlite");
const SimpleSqlitePool = @import("common").SimpleSqlitePool;

pub const PasteDao = struct {
    ptr: *anyopaque,
    create_table_if_not_exists_fn: *const fn (ptr: *anyopaque) anyerror!void,
    get_paste_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Paste,
    get_paste_by_name_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, name: []const u8) anyerror!?Paste,
    list_pastes_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Paste) anyerror!?[]Paste,
    page_summary_pastes_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Paste, page_no: ?u32, page_size: ?u32) anyerror!Paste.Page,
    delete_paste_fn: *const fn (ptr: *anyopaque, id: u64) anyerror!bool,
    delete_paste_by_name_fn: *const fn (ptr: *anyopaque, name: []const u8) anyerror!bool,
    update_paste_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste,
    update_paste_by_name_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste,
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

    pub fn update_paste_by_name(self: PasteDao, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste {
        return try self.update_paste_by_name_fn(self.ptr, allocator, entity);
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

    pub fn page_summary_pastes(self: PasteDao, allocator: std.mem.Allocator, query: ?Paste, page_no: ?u32, page_size: ?u32) anyerror!Paste.Page {
        return try self.page_summary_pastes_fn(self.ptr, allocator, query, page_no, page_size);
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
        \\
    ;
    const SELECT_SUMMARY_SQL =
        \\SELECT 
        \\  paste.id, 
        \\  paste.name, 
        \\  paste.content_type, 
        \\  paste.read_only, 
        \\  paste.editable, 
        \\  paste.has_password, 
        \\  paste.read_count, 
        \\  paste.latest_read_at, 
        \\  paste.create_at, 
        \\  paste.expiration_at
        \\FROM paste
        \\
    ;
    const SELECT_COUNT_SQL = "SELECT COUNT(id) FROM paste ";
    const WHERE_SQL =
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
    const QUERY_SQL = SELECT_SQL ++ WHERE_SQL;
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
    ;

    pool: *SimpleSqlitePool,

    pub fn create(self: *SqlitePasteDao) PasteDao {
        return .{
            .ptr = self,
            .create_table_if_not_exists_fn = create_table_if_not_exists,
            .get_paste_fn = get_paste,
            .get_paste_by_name_fn = get_paste_by_name,
            .list_pastes_fn = list_pastes,
            .page_summary_pastes_fn = page_summary_pastes,
            .delete_paste_fn = delete_paste,
            .delete_paste_by_name_fn = delete_paste_by_name,
            .update_paste_fn = update_paste,
            .update_paste_by_name_fn = update_paste_by_name,
            .increase_read_count_fn = increase_read_count,
            .insert_paste_fn = insert_paste,
            .clean_paste_fn = clean_paste
        };
    }

    fn create_table_if_not_exists(ptr: *anyopaque) anyerror!void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        try conn.get_db().exec(CREATE_TABLE_SQL, .{}, .{});
    }

    fn get_paste(ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        const query = SELECT_SQL ++ " WHERE paste.id = ?";
        var stmt = try conn.get_db().prepare(query);
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
        const conn = try self.pool.get_connection();
        defer conn.release();

        const query = SELECT_SQL ++ " WHERE paste.name = ?";
        var stmt = try conn.get_db().prepare(query);
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
        const conn = try self.pool.get_connection();
        defer conn.release();

        var stmt = try conn.get_db().prepareDynamic(QUERY_SQL);
        defer stmt.deinit();
        return try stmt.all(
            Paste,
            allocator,
            .{},
            query orelse Paste {},
        );
    }

    fn page_summary_pastes(ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Paste, page_no: ?u32, page_size: ?u32) anyerror!Paste.Page {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();
        const empty = comptime Paste.Page {
            .list = &[_]Paste.Summary{},
            .page_size = 0,
            .page_no = 0,
            .page_count = 0,
            .total = 0,
        };

        const db = conn.get_db();
        var total: ?u64 = undefined;
        {
            var stmt = try db.prepareDynamic(SELECT_COUNT_SQL ++ WHERE_SQL ++ " ORDER BY paste.create_at DESC");
            defer stmt.deinit();
            total = try stmt.one(
                u64,
                .{},
                query orelse Paste {},
            );
        }
        if (total) |count| {
            if (count == 0) return empty;
            const pg_size = @min(100, @max(1, page_size orelse 10));
            const page_count: u32 = @intCast(count / pg_size + if (count % pg_size == 0) @as(u32, 0) else 1);
            const pg_no = @min(page_count, @max(1, page_no orelse 1));
            const offset = (pg_no - 1) * pg_size;
            const sql = try std.fmt.allocPrint(
                allocator,
                SELECT_SUMMARY_SQL ++ WHERE_SQL ++ " ORDER BY paste.create_at DESC LIMIT {} OFFSET {}", 
                .{ pg_size, offset }
            );
            defer allocator.free(sql);
            var stmt = try db.prepareDynamic(sql);
            defer stmt.deinit();
            const result = try stmt.all(
                Paste.Summary,
                allocator,
                .{},
                query orelse Paste {},
            );
            return .{
                .list = result,
                .page_size = pg_size,
                .page_no = pg_no,
                .page_count = page_count,
                .total = count,
            };
        }
        return empty;
    }

    fn delete_paste(ptr: *anyopaque, id: u64) anyerror!bool {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        const sql = "DELETE FROM paste WHERE paste.id = ?";
        var stmt = try conn.get_db().prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{id});
        return true;
    }

    fn delete_paste_by_name(ptr: *anyopaque, name: []const u8) anyerror!bool {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        const sql = "DELETE FROM paste WHERE paste.name = ?";
        var stmt = try conn.get_db().prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{name});
        return true;
    }

    fn clean_paste(ptr: *anyopaque) !void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        const sql =
            \\DELETE FROM paste WHERE
            \\(burn_after_reads IS NOT NULL AND read_count > burn_after_reads)
            \\OR
            \\(expiration_at IS NOT NULL AND expiration_at > ?)
        ;
        var stmt = try conn.get_db().prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{ @as(u64, @intCast(std.time.timestamp())) });
    }

    fn update_paste(ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        if (entity.id) |id| {
            var stmt = try conn.get_db().prepareDynamic(UPDATE_SQL ++ " WHERE id = :id ");
            defer stmt.deinit();

            try stmt.exec(.{}, entity);
            return try get_paste(ptr, allocator, id);
        }
        return entity;
    }

    fn update_paste_by_name(ptr: *anyopaque, allocator: std.mem.Allocator, entity: Paste) anyerror!?Paste {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        if (entity.name) |name| {
            var stmt = try conn.get_db().prepareDynamic(UPDATE_SQL ++ " WHERE COALESCE(:id, 0) IS NOT NULL AND name = :name");
            defer stmt.deinit();

            try stmt.exec(.{}, entity);
            return try get_paste_by_name(ptr, allocator, name);
        }
        return entity;
    }

    fn increase_read_count(ptr: *anyopaque, paste: Paste) !void {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

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
            var stmt = try conn.get_db().prepareDynamic(s);
            defer stmt.deinit();
            try stmt.exec(.{}, .{});
        }
    }

    fn insert_paste(ptr: *anyopaque, entity: Paste) anyerror!?u64 {
        const self: *SqlitePasteDao = @ptrCast(@alignCast(ptr));
        const conn = try self.pool.get_connection();
        defer conn.release();

        var stmt = try conn.get_db().prepareDynamic(INSERT_SQL);
        defer stmt.deinit();

        return try stmt.one(u64, .{}, entity);
    }
};

fn get_dao(allocator: std.mem.Allocator) !PasteDao {
    var pool = SimpleSqlitePool.init(allocator, .{
        .mode = sqlite.Db.Mode{ .File = "./mydata.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    }, 1);
    var sqldao: *SqlitePasteDao = try allocator.create(SqlitePasteDao);
    sqldao.* = .{ .pool = &pool };
    return sqldao.create();
}
