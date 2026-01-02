const std = @import("std");
const zap = @import("zap");
const Options = @import("common").Options;
const Authenticator = @import("authenticator.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const ZapBasic = zap.Auth.Basic(std.StringHashMap([]const u8), .UserPass);

allocator: Allocator = undefined,
auth: ZapBasic = undefined,
header: []const u8 = "authorization",
map: ?std.StringHashMap([]const u8) = null,

pub fn init(allocator: Allocator, options: *Options) !Authenticator {
    const self = try allocator.create(Self);
    self.* = .{
        .map = null,
        .auth = undefined,
        .allocator = allocator
    };

    const auth = if (options.auth.?.basic.?.users) |*map| 
        try ZapBasic.init(allocator, map, null) 
    else blk: {
        self.*.map = std.StringHashMap([]const u8).init(allocator);
        break :blk try ZapBasic.init(allocator, &self.*.map.?, null);
    };
    self.*.auth = auth;
    
    return .{
        .ptr = self,
        .authenticate_fn = authenticate,
        .deinit_fn = deinit,
        .get_header_fn = get_header,
    };
}

pub fn deinit(ptr: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ptr));

    self.auth.deinit();
    if (self.map) |m| {
        var var_m = m;
        var_m.deinit();
    }
    self.allocator.destroy(self);
}

pub fn authenticate(ptr: *anyopaque, auth: []const u8) bool {
    const self: *Self = @ptrCast(@alignCast(ptr));

    return switch (self.auth.authenticate(auth)) {
        .AuthOK => true,
        else => false
    };
}

pub fn get_header(ptr: *anyopaque) []const u8 {
    const self: *Self = @ptrCast(@alignCast(ptr));

    return self.header;
}