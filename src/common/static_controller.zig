const std = @import("std");
const zap = @import("zap");

const Options = @import("options.zig").Options;
const WrapperRouter = @import("variable_router.zig").WrapperRouter;

const Allocator = std.mem.Allocator;

pub const Self = @This();

var options: *Options = undefined;
var compression_static: bool = undefined;

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
            compression_static = web.compression_static;
        } 
    }
}

inline fn send_compressed_file(
    allocator: Allocator,
    req: zap.Request,
    base_path: []const u8,
    accept_encoding: []const u8,
    target_encoding: []const u8,
    file_suffix: []const u8 
) !bool {
    if (std.mem.indexOf(u8, accept_encoding, target_encoding)) |_| {
        const target_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base_path, file_suffix});
        defer allocator.free(target_path);
        std.fs.cwd().access(target_path, .{}) catch {
            return false;
        };
        
        try req.setHeader("Content-Encoding", target_encoding);
        try req.setContentTypeFromFilename(base_path);
        try req.sendFile(target_path);
        std.debug.print("[Static Send Compressed]: {s}\n", .{ target_path });
        return true;
    }
    return false;
}

fn static_file_request(r: zap.Request) !void {
    if (r.path) |raw_path| {
        if (std.ascii.startsWithIgnoreCase(raw_path, options.web.?.prefix)) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            const filename_buf: []u8 = try allocator.alloc(u8, raw_path.len);
            defer allocator.free(filename_buf);
            @memcpy(filename_buf, raw_path);
            const path =std.Uri.percentDecodeInPlace(filename_buf);

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

            if (compression_static) {
                const accept_encoding = r.getHeader("accept-encoding") orelse "";
                if (send_compressed_file(allocator, r, real_path, accept_encoding, "br", "br")) |flag| {
                    if (flag) return;
                } else |_| {}
                if (send_compressed_file(allocator, r, real_path, accept_encoding, "gzip", "gz")) |flag| {
                    if (flag) return;
                } else |_| {}
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