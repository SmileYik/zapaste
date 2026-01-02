pub const Paste = @import("paste.zig").Paste;
pub const PasteDao = @import("paste_dao.zig").PasteDao;
pub const SqlitePasteDao = @import("paste_dao.zig").SqlitePasteDao;
pub const PasteService = @import("paste_service.zig").PasteService;
pub const PasteController = @import("paste_controller.zig");
pub const PasteCleaner = @import("paste_cleaner.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common");

var paste_dao: ?*PasteDao = null;
var paste_service: ?*PasteService = null;

pub fn init_paste(allocator: Allocator, options: *common.Options) !bool {
    switch (options.dao_type) {
        .Sqlite => {
            var sqldao: *SqlitePasteDao = try allocator.create(SqlitePasteDao);
            errdefer allocator.destroy(sqldao);

            sqldao.* = .{ .pool = options.sqlite.? };
            
            const dao = try allocator.create(PasteDao);
            errdefer allocator.destroy(dao);

            dao.* = sqldao.create();
            try dao.create_table_if_not_exists();
            paste_dao = dao;
        }
    }

    if (paste_dao) |dao| {
        const service: *PasteService = try allocator.create(PasteService);
        errdefer allocator.destroy(service);

        service.* = PasteService.create(.{ .dao = dao });
        paste_service = service;
        return true;
    }
    return false;
}

pub fn get_paste_dao() ?*PasteDao {
    return paste_dao;
}

pub fn get_paste_service() ?*PasteService {
    return paste_service;
}

test {
    std.testing.refAllDecls(@This());
}