const std = @import("std");
const sqlite = @import("sqlite");
const SimpleSqlitePool = @import("simple_sqlite_pool.zig");

const Allocator = std.mem.Allocator;

pub const DaoType = enum {
    Sqlite
};

pub const Options = struct {

    pub const SqliteOptions = struct {
        memory_mode: ?bool = false,
        pool_size: ?u16 = 8,
        shared_cache: ?bool = false,
        pragma: ?std.json.Value = null,
    };

    pub const JsonOptions = struct {
        dao_type: DaoType,
        work_dir: ?[]const u8 = "/app",
        sqlite_options: ?SqliteOptions = SqliteOptions {},
        bind_port: ?u16 = 3000,
        max_clients: ?isize = 100000,
        enable_log: ?bool = true,
        threads: ?u16 = 16,
        workers: ?u16 = 1,
    };

    dao_type: DaoType,
    work_dir: ?[]const u8 = "/app",
    sqlite: ?*SimpleSqlitePool = null,
    sqlite_options: ?SqliteOptions = .{},
    bind_port: ?u16 = 3000,
    max_clients: ?isize = 100000,
    enable_log: ?bool = true,
    threads: ?u16 = 16,
    workers: ?u16 = 1,

    pub fn get_path(self: *Options, gpa: Allocator, path: []const u8, comptime fallback_path: []const u8) []const u8 {
        return std.fmt.allocPrint(gpa, "{s}{s}", .{ self.work_dir.?, path }) catch |e| {
            std.debug.print("Out of memery when get path: {any}", .{e});
            return fallback_path;
        };
    }

    pub fn init(gpa: Allocator, opt: JsonOptions) anyerror!Options {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        var options: Options = .{
            .dao_type = opt.dao_type,
            .work_dir = opt.work_dir,
            .sqlite_options = opt.sqlite_options,
            .bind_port = opt.bind_port,
            .max_clients = opt.max_clients,
            .enable_log = opt.enable_log,
            .threads = opt.threads,
            .workers = opt.workers,
        };
        const default_opt = Options { .dao_type = options.dao_type };
        options.work_dir = options.work_dir orelse default_opt.work_dir;
        options.sqlite_options = options.sqlite_options orelse default_opt.sqlite_options;
        options.bind_port = options.bind_port orelse default_opt.bind_port;
        options.max_clients = options.max_clients orelse default_opt.max_clients;
        options.enable_log = options.enable_log orelse default_opt.enable_log;
        options.threads = options.threads orelse default_opt.threads;
        options.workers = options.workers orelse default_opt.workers;

        const default_sqlite_opt = SqliteOptions {};
        options.sqlite_options.?.memory_mode = options.sqlite_options.?.memory_mode orelse default_sqlite_opt.memory_mode;
        options.sqlite_options.?.pool_size = options.sqlite_options.?.pool_size orelse default_sqlite_opt.pool_size;
        options.sqlite_options.?.shared_cache = options.sqlite_options.?.shared_cache orelse default_sqlite_opt.shared_cache;

        options.work_dir = try dupe_str(options.work_dir, "/app", gpa);
        if (options.dao_type == DaoType.Sqlite) {
            const sql_opt = options.sqlite_options orelse SqliteOptions {};
            
            const mode = if (sql_opt.memory_mode orelse false) blk: {
                break :blk sqlite.Db.Mode.Memory;
            } else blk: {
                const path = options.get_path(temp_allocator, "/database.db", "/app/database.db");
                const path_z = try gpa.dupeZ(u8, path);
                break :blk sqlite.Db.Mode{ .File = path_z };
            };
            
            options.sqlite = try SimpleSqlitePool.init(
                gpa, 
                .{
                    .mode = mode,
                    .open_flags = .{
                        .write = true,
                        .create = true,
                    },
                    .shared_cache = sql_opt.shared_cache.?,
                    .threading_mode = .MultiThread,
                }, 
                sql_opt.pool_size.?,
                sql_opt.pragma
            );
        }
        return options;
    }
};

fn dupe_str(str: ?[]const u8, comptime default_str: []const u8, gpa: Allocator) ![]const u8 {
    if (str) |s| {
        return try gpa.dupe(u8, s);
    }
    return default_str;
} 