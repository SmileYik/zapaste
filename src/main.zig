const std = @import("std");
const zap = @import("zap");
const Paste = @import("paste").Paste;
const PasteDao = @import("paste").PasteDao;
const SqlitePasteDao = @import("paste").SqlitePasteDao;
const sqlite = @import("sqlite");
const VariableRouter = @import("variable_router.zig").VariableRouter;

fn on_request(r: zap.Request) !void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }

    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}

fn on_request_1(path_variables: std.StringHashMap([]const u8), r: zap.Request) !void {
    r.sendBody(path_variables.get("id").?) catch return;
}

fn on_request_2(ptr: *const anyopaque, path_variables: std.StringHashMap([]const u8), r: zap.Request) !void {
    const paste: *const Paste = @ptrCast(@alignCast(ptr));
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const result = try std.fmt.allocPrint(gpa, "{s}-{s}", .{ path_variables.get("id").?, paste.name.? });
    r.sendBody(result) catch return;
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var router: VariableRouter = try VariableRouter.init(gpa, .{});
    try router.handle_func_unbound(gpa, "/user/:id", &on_request_1);
    const a: Paste = .{
        .name = "abc"
    };
    try router.handle_func_bound(gpa, "/user/name/:id", &a, &on_request_2);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = router.on_request_handler(),
        .log = true,
        .max_clients = 100000,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1, // 1 worker enables sharing state between threads
    });
}

test {
    std.testing.refAllDecls(@This());
}