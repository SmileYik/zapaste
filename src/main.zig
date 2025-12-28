const std = @import("std");
const zap = @import("zap");
const zapaste = @import("zapaste");
const U8Result = zapaste.common.Result.U8Result;
const WrapperRouter = zapaste.common.WrapperRouter;
const Options = zapaste.common.Options;
const PasteController = zapaste.paste.PasteController;

// const Router = zap.Router;
// const DaoType = zapaste.common.DaoType;

fn on_not_found(r: zap.Request) !void {
    return U8Result.init(404, null, null).send_json(r, .{ .emit_null_optional_fields = false });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const options_json = zapaste.get_config(allocator, if (args.len < 2) null else args[1])
    catch |e| {
        std.debug.print("Failed to load config: {}\n", .{e});
        return;
    };
    std.debug.print(
        \\
        \\ Loading config:
        \\ {f}
        \\
        , 
        .{ std.json.fmt(options_json, .{ .whitespace = .indent_4 }) }
    );

    const options = Options.init(allocator, options_json) catch |e| {
        std.debug.print("Cannot initialize: {}", .{e});
        return;
    };

    var router: *WrapperRouter = WrapperRouter.init(allocator, .{
        .not_found = on_not_found
    }) catch |e| {
        std.debug.print("Web router initialize failed: {}", .{e});
        return;
    };

    const paste_controller = PasteController.init(allocator, options)
    catch |e| {
        std.debug.print("PasteController initialize failed: {}", .{e});
        return;
    };

    paste_controller.register(allocator, router, "/api/paste")
    catch |e| {
        std.debug.print("PasteController register failed: {}", .{e});
        return;
    };

    var listener = zap.HttpListener.init(.{
        .port = options.bind_port.?,
        .on_request = router.on_request_handler(),
        .log = options.enable_log.?,
        .max_clients = options.max_clients.?,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = @intCast(options.threads.?),
        .workers = @intCast(options.workers.?),
    });
}

test {
    std.testing.refAllDecls(@This());
}