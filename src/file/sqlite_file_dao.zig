const std = @import("std");
const File = @import("file.zig").File;
const sqlite = @import("sqlite");
const SimpleSqlitePool = @import("common").SimpleSqlitePool;
const FileDao = @import("file_dao.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const CREATE_TABLE_SQL = 
    \\
    \\CREATE TABLE IF NOT EXISTS file (
    \\  id INTEGER PRIMARY KEY,
    \\  hash TEXT NOT NULL UNIQUE,
    \\  filename TEXT,
    \\  filesize INTEGER,
    \\  filepath TEXT,
    \\  mimetype TEXT
    \\)
    \\
;

const SELECT_SQL = 
    \\SELECT
    \\  file.id,
    \\  file.hash,
    \\  file.filename,
    \\  file.filesize,
    \\  file.filepath,
    \\  file.mimetype
    \\FROM file 
    \\
;

const INSERT_SQL = 
    \\INSERT INTO file (
    \\  hash, filename, filesize, filepath, mimetype
    \\) VALUES (
    \\  :hash, :filename, :filesize, :filepath, :mimetype
    \\) RETURNING id
    \\
;

const DELETE_SQL =
    \\ DELETE FROM paste 
;

pool: *SimpleSqlitePool,

fn init(self: *Self) FileDao {
    return .{
        .ptr = self,
        .create_table_if_not_exists_fn = create_table_if_not_exists,
        .get_file_fn = get_file,
        .get_file_by_hash_fn = get_file_by_hash,
        .insert_file_fn = insert_file,
        .delete_file_fn = delete_file,
        .delete_file_by_hash_fn = delete_file_by_hash,
        .list_file_by_ids_fn = list_file_by_ids,
    };
}

fn create_table_if_not_exists(ptr: *anyopaque) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();

    try conn.get_db().exec(CREATE_TABLE_SQL, .{}, .{});
}

fn get_file(ptr: *anyopaque, allocator: Allocator, id: u64) anyerror!?File {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();
    const query = SELECT_SQL ++ " WHERE file.id = :id";
    var stmt = try conn.get_db().prepare(query);
    defer stmt.deinit();
    const row = try stmt.oneAlloc(
        File,
        allocator,
        .{},
        .{ .id = id },
    );
    return row;
}

fn get_file_by_hash(ptr: *anyopaque, allocator: Allocator, hash: []const u8) anyerror!?File {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();
    const query = SELECT_SQL ++ " WHERE file.hash = :hash";
    var stmt = try conn.get_db().prepare(query);
    defer stmt.deinit();
    const row = try stmt.oneAlloc(
        File,
        allocator,
        .{},
        .{ .hash = hash },
    );
    return row;
}

fn list_file_by_ids(ptr: *anyopaque, allocator: Allocator, ids: []const u64) anyerror!?[]File {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();

    const quest_marks_len = ids.len * 2 - 1;
    var quest_marks = try allocator.alloc(u8, quest_marks_len);
    defer allocator.free(quest_marks);
    for (0..quest_marks_len) |idx| {
        quest_marks[idx] = if ((idx & 1) == 0) '?' else ',';
    }

    const sql = try std.fmt.allocPrint(allocator, SELECT_SQL ++ " WHERE file.id IN ({s}) ", .{
        quest_marks
    });

    var stmt = try conn.get_db().prepareDynamic(sql);
    defer stmt.deinit();
    return try stmt.all(
        File,
        allocator,
        .{},
        ids,
    );
}

fn insert_file(ptr: *anyopaque, entity: File) anyerror!?u64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();

    var stmt = try conn.get_db().prepareDynamic(INSERT_SQL);
    defer stmt.deinit();

    return try stmt.one(u64, .{}, entity);
}

fn delete_file(ptr: *anyopaque, id: u64) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();

    const sql = DELETE_SQL ++ " WHERE file.id = :id ";

    var stmt = try conn.get_db().prepare(sql);
    defer stmt.deinit();
    try stmt.exec(.{}, .{ .id = id });
}

fn delete_file_by_hash(ptr: *anyopaque, hash: []const u8) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const conn = try self.pool.get_connection();
    defer conn.release();

    const sql = DELETE_SQL ++ " WHERE file.hash = :hash ";

    var stmt = try conn.get_db().prepare(sql);
    defer stmt.deinit();
    try stmt.exec(.{}, .{ .hash = hash });
}

inline fn memory_dao(allocator: Allocator) !FileDao {
    errdefer std.debug.print("create memory dao failed!\n", .{});
    const pool = try SimpleSqlitePool.init(allocator, 
        .{ 
            .mode = .Memory,
            .open_flags = .{ .create = true, .write = true }
        }, 
        1, null
    );
    var dao: *Self = try allocator.create(Self);
    dao.* = .{ .pool = pool };
    return dao.init();
}

test "[sqlite-file-dao] create table if exists" { 
    errdefer std.debug.print("[sqlite-file-dao] create table if exists failed!\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_gpa = arena.allocator();
    const dao = try memory_dao(temp_gpa);
    try dao.create_table_if_not_exists();
}

test "[sqlite-file-dao] insert_file" { 
    errdefer std.debug.print("[sqlite-file-dao] insert_file failed!\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_gpa = arena.allocator();
    const dao = try memory_dao(temp_gpa);
    try dao.create_table_if_not_exists();
    const result = dao.insert_file(.{
        .filename = "name",
        .filesize = 160,
        .hash = "FFFFFFFF"
    }) catch |e| {
        std.debug.print("Error: {}\n", .{e});
        return;
    };
    std.debug.assert(result != null);
}

test "[sqlite-file-dao] list_file_by_ids" { 
    errdefer std.debug.print("[sqlite-file-dao] insert_file failed!\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_gpa = arena.allocator();
    const dao = try memory_dao(temp_gpa);
    try dao.create_table_if_not_exists();

    var ids: [10]u64 = undefined;

    for (0..10) |i| {
        const id = dao.insert_file(.{
            .filename = try std.fmt.allocPrint(temp_gpa, "{s}{}", .{ "name", i }),
            .filesize = 160,
            .hash = try std.fmt.allocPrint(temp_gpa, "{s}{}", .{ "name", i })
        }) catch |e| {
            std.debug.print("Error: {}\n", .{e});
            return;
        };
        std.debug.assert(id != null);
        ids[i] = id.?;
    }

    const list = dao.list_file_by_ids(temp_gpa, &ids) catch |e| {
        std.debug.print("list Error: {}\n", .{e});
        return;
    };
    std.debug.assert(list != null);
}