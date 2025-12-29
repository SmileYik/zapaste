const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;

pub const U8Result = create(u8);
pub const UnknownError = U8Result.init(500, null, "Unknown Error");

pub fn create(comptime T: type) type {
    return struct {
        pub const Self = @This();

        code: u16,
        data: ?T = null,
        message: ?[]const u8 = null,

        pub fn init(code: u16, data: ?T, message: ?[]const u8) Self {
            return .{
                .code = code,
                .data = data,
                .message = message,
            };
        }

        pub fn success(data: ?T, message: ?[]const u8) Self {
            return .{
                .code = 200,
                .data = data,
                .message = message,
            };
        }

        pub fn failed_message(msg: ?[]const u8) Self {
            return init(500, null, msg);
        }

        pub fn failed(allocator: Allocator, err: ?anyerror, msg: ?[]const u8) !Self {
            const final_msg = if (err) |e| blk: {
                break :blk try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(e), msg orelse "" });
            } else blk: {
                break :blk msg orelse "";
            };

            return .{
                .code = 500,
                .message = final_msg
            };
        }

        fn create_error_json(allocator: Allocator, err: anyerror) U8Result {
            const msg = std.fmt.allocPrint(
                allocator, 
                "create array list failed: {s}\n", 
                .{@errorName(err)}
            ) catch |e| {
                std.log.err("failed to create result: {s}\n", .{@errorName(e)});
                return UnknownError;
            };
            return U8Result.init(500, null, msg);
        }

        pub fn send_json(self: Self, req: zap.Request, options: std.json.Stringify.Options) void {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            const formatter = std.json.fmt(self, options);
            const json_to_send = std.fmt.allocPrint(allocator, "{f}", .{formatter}) catch |e| {
                std.log.err("struct stringify failed: {s}\n", .{@errorName(e)});
                create_error_json(allocator, e).send_json(req, options);
                return;
            };
            
            std.debug.print("<< json: {s}\n", .{json_to_send});
            req.sendJson(json_to_send) catch return;
        }
    };
}