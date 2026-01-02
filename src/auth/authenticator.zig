const std = @import("std");

const Allocator = std.mem.Allocator;

const Self = @This();

ptr: *anyopaque,
deinit_fn: *const fn(*anyopaque) void,
authenticate_fn: *const fn(*anyopaque, []const u8) bool,
get_header_fn: *const fn(*anyopaque) []const u8,

pub fn deinit(self: Self) void {
    self.deinit_fn(self.ptr);
}

pub fn authenticate(self: Self, auth: []const u8) !bool {
    return self.authenticate_fn(self.ptr, auth);
}

pub fn get_header(self: Self) []const u8 {
    return self.get_header_fn(self.ptr);
}
