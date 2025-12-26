const std = @import("std");
const sqlite = @import("sqlite");

const Allocator = std.mem.Allocator;

pub const DaoType = enum {
    Sqlite
};

pub const Options = struct {
    dao_type: DaoType,
    work_dir: ?[]const u8 = "/app",
    sqlite_db: ?*sqlite.Db = null,

    pub fn get_path(self: *Options, gpa: Allocator, path: []const u8, comptime fallback_path: []const u8) []const u8 {
        return std.fmt.allocPrint(gpa, "{s}{s}", .{ self.work_dir.?, path }) catch |e| {
            std.debug.print("Out of memery when get path: {any}", .{e});
            return fallback_path;
        };
    }

    pub fn init(gpa: Allocator, opt: Options) !Options {
        var options = opt;
        options.work_dir = try dupe_str(options.work_dir, "/app", gpa);
        if (options.dao_type == DaoType.Sqlite) {
            const db_ptr = try gpa.create(sqlite.Db);
            errdefer gpa.destroy(db_ptr);
            const path = options.get_path(gpa, "/database.db", "/app/database.db");
            const path_z = try gpa.dupeZ(u8, path);
            db_ptr.* = try sqlite.Db.init(.{
                .mode = sqlite.Db.Mode{ .File = path_z },
                .open_flags = .{
                    .write = true,
                    .create = true,
                },
                .threading_mode = .MultiThread,
            });
            options.sqlite_db = db_ptr;
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