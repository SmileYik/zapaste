const std = @import("std");
const zap = @import("zap");

const Options = @import("options.zig").Options;
const WrapperRouter = @import("variable_router.zig").WrapperRouter;

const Allocator = std.mem.Allocator;

pub const Self = @This();

var options: *Options = undefined;

pub fn init(
    allocator: Allocator, 
    router: *WrapperRouter, 
    opt: *Options
) !void {
    if (opt.web) |web| {
        if (web.enable) {
            options = opt;
            const get_router = try router.special(allocator, .GET);
            get_router.not_found = static_file_request;
        } 
    }
}

fn static_file_request(r: zap.Request) !void {
    if (r.path) |path| {
        if (std.ascii.startsWithIgnoreCase(path, options.web.?.prefix)) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            const suffix_path = path[options.web.?.prefix.len - 1..];
            var real_path: []const u8 = undefined;
            if (std.ascii.endsWithIgnoreCase(suffix_path, "/")) {
                real_path = options.get_path(
                    allocator, 
                    try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ options.web.?.static_path, suffix_path, options.web.?.default_file }),
                    ""
                );
            } else {
                real_path = options.get_path(
                    allocator, 
                    try std.fmt.allocPrint(allocator, "{s}{s}", .{ options.web.?.static_path, suffix_path }),
                    ""
                );
            }
            std.debug.print("[Static]: {s} => {s}\n", .{ path, real_path });
            var send: bool = true;
            r.sendFile(real_path) catch {
                send = false;
            };
            if (send) return;
        }
    }
    r.setStatus(.not_found);
    try r.sendBody("");
}