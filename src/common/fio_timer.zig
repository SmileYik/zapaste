const std = @import("std");
const fio = @import("fio.zig");
const Allocator = std.mem.Allocator;

/// type T need two method: `task_callback` and `finshed_callback`
pub fn FIOTimer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        t: T,
        
        pub fn init(allocator: Allocator, t: T) !*Self {
            const self: *Self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .t = t
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn run_every(self: *Self, milliseconds: usize, repetitions: usize) !void {
            const result = fio.fio_run_every(
                milliseconds, 
                repetitions, 
                task_callback, 
                self, 
                finish_callback
            );
            if (result == -1) return error.RunEveryFailed;
        }

        fn task_callback(arg: ?*anyopaque) callconv(.c) void {
            if (arg) |ptr| {
                var data: *Self = @ptrCast(@alignCast(ptr));
                data.t.task_callback() catch |e| {
                    std.debug.print("Throws error when run timer task: {}", .{e});
                };
            }
        }

        fn finish_callback(arg: ?*anyopaque) callconv(.c) void {
            if (arg) |ptr| {
                var data: *Self = @ptrCast(@alignCast(ptr));
                data.t.finish_callback() catch |e| {
                    std.debug.print("Throws error when run timer task: {}", .{e});
                };
                data.deinit();
            }
        }
    };
}