const std = @import("std");
const zap = @import("zap");
const zapaste = @import("zapaste");
const U8Result = zapaste.common.Result.U8Result;
const WrapperRouter = zapaste.common.WrapperRouter;
const RouterError = zapaste.common.RouterError;
const Options = zapaste.common.Options;
const PasteController = zapaste.paste.PasteController;

// const Router = zap.Router;
// const DaoType = zapaste.common.DaoType;

fn on_not_found(r: zap.Request) !void {
    return U8Result.init(404, null, null).send_json(r, .{ .emit_null_optional_fields = false });
}

fn cors_handler(r: zap.Request) !void {
    if (r.methodAsEnum() == .OPTIONS) {
        try set_custom_header(options.cors_headers, r);
        r.setStatus(.ok);
        r.markAsFinished(true);
    }
}

fn custom_header_handler(r: zap.Request) !void {
    try set_custom_header(options.custom_headers, r);
}

fn set_custom_header(headers: ?std.json.Value, r: zap.Request) !void {
    if (headers) |v| {
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
                    std.debug.print("[CustomHeader] set custom header: {s} = {s}\n", .{
                        entry.key_ptr.*, value.?
                    });
                    try r.setHeader(entry.key_ptr.*, value.?);
                }
            },
            else => return
        }
    }
}

var options: Options = undefined;

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

    options = Options.init(allocator, options_json) catch |e| {
        std.debug.print("Cannot initialize: {}", .{e});
        return;
    };
    defer options.deinit();

    var router: *WrapperRouter = WrapperRouter.init(allocator, .{
        .not_found = on_not_found,
        .interceptors = &[_]zap.HttpRequestFn {
            &custom_header_handler,
            &cors_handler
        }
    }) catch |e| {
        std.debug.print("Web router initialize failed: {}", .{e});
        return;
    };
    defer router.deinit();

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