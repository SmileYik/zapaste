pub const File = @import("file.zig").File;
pub const FileDao = @import("file_dao.zig");
pub const SqliteFileDao = @import("sqlite_file_dao.zig");
pub const FileService = @import("file_service.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common");


var file_dao: ?*FileDao = null;
var file_service: ?*FileService = null;

pub fn init_file(allocator: Allocator, options: *common.Options) !bool {
    switch (options.dao_type) {
        .Sqlite => {
            var sqldao: *SqliteFileDao = try allocator.create(SqliteFileDao);
            errdefer allocator.destroy(sqldao);

            sqldao.* = .{ .pool = options.sqlite.? };
            
            const dao = try allocator.create(FileDao);
            errdefer allocator.destroy(dao);

            dao.* = sqldao.init();
            try dao.create_table_if_not_exists();
            file_dao = dao;
        }
    }

    if (file_dao) |dao| {
        const service: *FileService = try allocator.create(FileService);
        errdefer allocator.destroy(service);

        service.* = .{
            .dao = dao,
            .store_path = options.get_path(allocator, "uploads", "./uploads")
        };
        file_service = service;
        return true;
    }

    return false;
}

pub fn get_file_dao() ?*FileDao {
    return file_dao;
}

pub fn get_file_service() ?*FileService {
    return file_service;
}

test {
    std.testing.refAllDecls(@This());
}