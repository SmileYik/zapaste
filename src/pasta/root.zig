pub const Pasta = @import("pasta.zig").Pasta;
pub const PastaDao = @import("pasta_dao.zig").PastaDao;
pub const SqlitePastaDao = @import("pasta_dao.zig").SqlitePastaDao;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}