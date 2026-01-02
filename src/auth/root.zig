const std = @import("std");
const zap = @import("zap");
const Authentocator = @import("authenticator.zig");
const common = @import("common");

const Allocator = std.mem.Allocator;
const PathTree = common.path_tree.PathTree(u8);

const HttpMethodMask = enum(u8) {
    GET    = 1 << 0,
    POST   = 1 << 1,
    PUT    = 1 << 2,
    DELETE = 1 << 3,
    PATCH  = 1 << 4,
    HEAD   = 1 << 5,
    OPTIONS= 1 << 6,
    OTHER  = 1 << 7,
};

var skip_auth_path: *PathTree = undefined;
var authentocator: Authentocator = undefined;
var init: bool = false;

pub fn init_auth(allocator: Allocator, options: *common.Options) !?zap.HttpRequestFn {
    switch (options.auth.?.auth_type.?) {
        .Basic => {
            authentocator = try @import("basic.zig").init(allocator, options);
        },
        else => return null
    }
    init = true;
    try init_skip_auth_path(allocator, options);
    return authentocator_handler;
}

fn init_skip_auth_path(allocator: Allocator, options: *common.Options) !void {
    skip_auth_path = try PathTree.init(.{ .allocator = allocator });
    if (options.auth.?.skip_auth_path) |map| {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            const allows = entry.value_ptr.*;
            var mask: u8 = 0;
            var method_iter = std.mem.splitAny(u8, allows, ", ;");
            while (method_iter.next()) |method| {
                const m = std.meta.stringToEnum(HttpMethodMask, method) orelse .OTHER;
                if (m != .OTHER) mask |= @intFromEnum(m);
            }

            std.debug.print("Skip verify path {s} for request methods: {s}\n", .{
                entry.key_ptr.*, entry.value_ptr.*
            });
            try skip_auth_path.put_pattern(entry.key_ptr.*, mask);
        }
    }
}

pub fn deinit_auth() void {
    if (init) {
        authentocator.deinit();
        skip_auth_path.deinit();
    }
}

fn authentocator_handler(r: zap.Request) !void {
    if (r.path) |path| {
        if (skip_auth_path.find_path(path)) |allows| {
            if (r.method) |method| {
                const m = std.meta.stringToEnum(HttpMethodMask, method) orelse .OTHER;
                if (m == .OPTIONS or (@intFromEnum(m) & allows) != 0) {
                    return;
                }
            }
        }
    }

    var flag: bool = true;
    if (r.getHeader(authentocator.get_header())) |header| {
        if (authentocator.authenticate(header)) |result| {
            flag = !result;
        } else |err| {
            std.debug.print("error when authenticate: {}\n", .{err});
        }
    }
    if (flag) {
        r.setStatus(.unauthorized);
        r.markAsFinished(true);
    }
}
