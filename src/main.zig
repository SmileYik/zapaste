const std = @import("std");
const zap = @import("zap");
const Paste = @import("paste").Paste;
const PasteDao = @import("paste").PasteDao;
const SqlitePasteDao = @import("paste").SqlitePasteDao;
const sqlite = @import("sqlite");
const WrapperRouter = @import("zapaste").WrapperRouter;
const Router = zap.Router;
const Options = @import("zapaste").common.Options;
const DaoType = @import("zapaste").common.DaoType;
const Result = @import("zapaste").common.Result;
const PasteController = @import("zapaste").PasteController;

fn on_not_found(r: zap.Request) !void {
    return Result.create(u8).init(404, null, null).send_json(r, .{ .emit_null_optional_fields = false });
}

pub fn main() !void {
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

    var router: *WrapperRouter = try WrapperRouter.init(allocator, .{
        .not_found = on_not_found
    });

    const paste_controller = try PasteController.init(allocator, options);
    try paste_controller.register(allocator, router);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = router.on_request_handler(),
        .log = true,
        .max_clients = 100000,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 10,
        .workers = 1, // 1 worker enables sharing state between threads
    });
}

test {
    std.testing.refAllDecls(@This());
}