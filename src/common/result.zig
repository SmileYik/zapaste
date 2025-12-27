const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;

pub fn create(comptime T: type) type {
    return struct {
        pub const Self = @This();

        code: u16,
        data: ?T = null,
        message: ?[]const u8 = null,

        pub fn success(data: T, message: ?[]const u8) Self {
            return .{
                .code = 200,
                .data = data,
                .message = message,
            };
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

        pub inline fn send_json(self: Self, req: zap.Request) void {
            var buf: [256]u8 = undefined;
            var json_to_send: []const u8 = undefined;
            json_to_send = zap.util.stringifyBuf(&buf, self, .{}) catch |e| {
                std.log.err("JSON failed: {s}\n", .{@errorName(e)});
                return;
            };
            
            std.debug.print("<< json: {s}\n", .{json_to_send});
            req.setContentType(.JSON) catch return;
            req.sendBody(json_to_send) catch return;
        }
    };
}