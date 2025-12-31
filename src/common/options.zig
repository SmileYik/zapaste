const std = @import("std");
const sqlite = @import("sqlite");
const SimpleSqlitePool = @import("simple_sqlite_pool.zig");

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap([]const u8);

pub const DaoType = enum {
    Sqlite
};

pub const Options = struct {
    pub const JsonWebOptions = struct {
        enable: ?bool = false,
        default_file: ?[]const u8 = null,
        prefix: ?[]const u8 = null,
        static_path: ?[]const u8 = null,
    };

    pub const WebOptions = struct {
        enable: bool = false,
        default_file: []const u8 = "",
        prefix: []const u8 = "",
        static_path: []const u8 = "",
    };

    pub const JsonSwaggerOptions = struct {
        enable: ?bool = false,
        swagger_config_path: ?[]const u8 = "/openapi.yml",
        swagger_index_path: ?[]const u8 = null,
    };

    pub const SwaggerOptions = struct {
        enable: ?bool = false,
        swagger_config_path: ?[]const u8 = "/openapi.yml",
        swagger_index_path: ?[]const u8 = null,
    };

    pub const JsonSqliteOptions = struct {
        /// enable memory mode. if you set this to true, then pool_size must be 1
        memory_mode: ?bool = false,

        /// how many sqlite database connections.
        pool_size: ?u16 = 2,

        /// shared cache.
        shared_cache: ?bool = false,

        /// a key-value map, as same as run sql like: `SET PRAGMA KEY = VALUE`
        pragma: ?std.json.Value = null,
    };

    /// This is the sqlite configurations.
    pub const SqliteOptions = struct {
        /// enable memory mode. if you set this to true, then pool_size must be 1
        memory_mode: ?bool = false,

        /// how many sqlite database connections.
        pool_size: ?u16 = 2,

        /// shared cache.
        shared_cache: ?bool = false,

        /// a key-value map, as same as run sql like: `SET PRAGMA KEY = VALUE`
        pragma: ?StringHashMap = null,
    };

    pub const JsonOptions = struct {
        /// dao tyoe
        dao_type: ?DaoType = DaoType.Sqlite,

        /// work dir, where data stored
        work_dir: ?[]const u8 = "./",

        /// if your dao_type is Sqlite, then you can configure your sqlite options.
        sqlite_options: ?JsonSqliteOptions = JsonSqliteOptions {},

        /// zap bind port
        bind_port: ?u16 = 3000,

        /// zap max clients
        max_clients: ?isize = 100000,

        /// zap enable log
        enable_log: ?bool = true,

        /// how many threads handle http request
        threads: ?u16 = 2,

        /// how many workers, cannot share memory between workers.
        workers: ?u16 = 1,

        /// custom headers for all http request
        custom_headers: ?std.json.Value = null,

        // cors headers will set to OPTIONS requests only
        cors_headers: ?std.json.Value = null,
        swagger: ?JsonSwaggerOptions = JsonSwaggerOptions {},
        web: ?JsonWebOptions = JsonWebOptions {},
    };

    dao_type: DaoType,
    work_dir: ?[]const u8 = "./",
    sqlite: ?*SimpleSqlitePool = null,
    sqlite_options: ?SqliteOptions = .{},
    bind_port: ?u16 = 3000,
    max_clients: ?isize = 100000,
    enable_log: ?bool = true,
    threads: ?u16 = 2,
    workers: ?u16 = 1,
    custom_headers: ?StringHashMap = null,
    cors_headers: ?StringHashMap = null,
    swagger: ?SwaggerOptions = SwaggerOptions {},
    web: ?WebOptions = WebOptions {},

    pub fn get_path(self: *Options, gpa: Allocator, path: []const u8, comptime fallback_path: []const u8) []const u8 {
        return std.fmt.allocPrint(gpa, "{s}{s}", .{ self.work_dir.?, path }) catch |e| {
            std.debug.print("Out of memery when get path: {any}", .{e});
            return fallback_path;
        };
    }

    pub fn init(gpa: Allocator, opt: JsonOptions) anyerror!Options {
        var options: Options = .{
            .dao_type = opt.dao_type orelse DaoType.Sqlite,
            .work_dir = opt.work_dir,
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

        options.custom_headers = try json_obj_to_string_map(gpa, opt.custom_headers);
        options.cors_headers = try json_obj_to_string_map(gpa, opt.cors_headers);

        const default_sqlite_opt = SqliteOptions {};
        options.sqlite_options.?.memory_mode = opt.sqlite_options.?.memory_mode orelse default_sqlite_opt.memory_mode;
        options.sqlite_options.?.pool_size = opt.sqlite_options.?.pool_size orelse default_sqlite_opt.pool_size;
        options.sqlite_options.?.shared_cache = opt.sqlite_options.?.shared_cache orelse default_sqlite_opt.shared_cache;
        options.sqlite_options.?.pragma = try json_obj_to_string_map(gpa,opt.sqlite_options.?.pragma);
        options.work_dir = try dupe_str(options.work_dir, "/app", gpa);

        if (opt.swagger) |s| {
            options.swagger.?.enable = s.enable;
            if (s.swagger_config_path) |p| {
                options.swagger.?.swagger_config_path = try dupe_str(p, "/openapi.yml", gpa);
            }
            if (s.swagger_index_path) |p| {
                options.swagger.?.swagger_index_path = try dupe_str(p, "/swagger.html", gpa);
            }
        }

        if (opt.web) |web| {
            var conf = &options.web.?;
            conf.enable = web.enable orelse false;
            if (web.default_file) |s| {
                conf.default_file = try dupe_str(s, "index.html", gpa);
            }
            if (web.prefix) |s| {
                conf.prefix = try dupe_str(s, "/", gpa);
            }
            if (web.static_path) |s| {
                conf.static_path = try dupe_str(s, "static", gpa);
            }
        }

        if (options.dao_type == DaoType.Sqlite) {
            try init_sqlite(gpa, &options);
        }
        return options;
    }

    fn init_sqlite(allocator:Allocator, options: *Options) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const sql_opt = options.sqlite_options orelse SqliteOptions {};
        const mode = if (sql_opt.memory_mode orelse false) blk: {
            break :blk sqlite.Db.Mode.Memory;
        } else blk: {
            const path = options.get_path(temp_allocator, "/database.db", "/app/database.db");
            const path_z = try allocator.dupeZ(u8, path);
            break :blk sqlite.Db.Mode{ .File = path_z };
        };
        
        options.sqlite = try SimpleSqlitePool.init(
            allocator, 
            .{
                .mode = mode,
                .open_flags = .{
                    .write = true,
                    .create = true,
                },
                .shared_cache = sql_opt.shared_cache.?,
                .threading_mode = .MultiThread,
            }, 
            if(mode == .Memory) 1 else sql_opt.pool_size.?,
            sql_opt.pragma
        );
    }

    pub fn deinit(self: *Options) void {
        defer if (self.sqlite) |pool| {
            pool.deinit();
        };
        defer if (self.custom_headers != null) deinit_string_map(&self.custom_headers.?);
        defer if (self.cors_headers != null) deinit_string_map(&self.cors_headers.?);
        defer if (self.sqlite_options != null and self.sqlite_options.?.pragma != null) deinit_string_map(&self.sqlite_options.?.pragma.?);
    }
};

fn dupe_str(str: ?[]const u8, comptime default_str: []const u8, gpa: Allocator) ![]const u8 {
    if (str) |s| {
        return try gpa.dupe(u8, s);
    }
    return default_str;
}

inline fn deinit_string_map(map: ?*StringHashMap) void {
    if (map) |m| {
        var vm = m;
        var iter = vm.iterator();
        while (iter.next()) |entry| {
            vm.allocator.free(entry.key_ptr.*);
            vm.allocator.free(entry.value_ptr.*);
        }
        vm.deinit();
    }
}

inline fn json_obj_to_string_map(allocator: Allocator, json_value: ?std.json.Value) !?StringHashMap {
    if (json_value) |v| {
        var result = StringHashMap.init(allocator);
        switch (v) {
            .object => |map| {
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    var value: ?[]const u8 = null;
                    switch (entry.value_ptr.*) {
                        .string => |s| value = s,
                        .number_string => |s| value = s,
                        else => |_| continue
                    }
                    try result.put(
                        try dupe_str(entry.key_ptr.*, "", allocator), 
                        try dupe_str(value.?, "", allocator)
                    );
                }
            },
            else => return null
        }
        return result;
    }
    return null;
}