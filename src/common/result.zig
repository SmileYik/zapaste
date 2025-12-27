const std = @import("std");
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
                break :blk try std.fmt.allocPrint(allocator, "{}: {s}", .{ e, msg orelse "" });
            } else blk: {
                break :blk msg orelse "";
            };

            return .{
                .code = 500,
                .message = final_msg
            };
        }
    };
}