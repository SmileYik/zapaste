pub const Pasta = @import("pasta.zig").Pasta;
pub const PastaDao = @import("pasta_dao.zig").PastaDao;
pub const SqlitePastaDao = @import("pasta_dao.zig").SqlitePastaDao;
pub const PastaService = @import("pasta_service.zig").PastaService;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}