const std = @import("std");
const zap = @import("zap");
const Authentocator = @import("authenticator.zig");
const common = @import("common");

const Allocator = std.mem.Allocator;
const PathTree = common.path_tree.PathTree([]const u8);

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
    skip_auth_path = try PathTree.init(.{ .allocator = allocator });
    if (options.auth.?.skip_auth_path) |map| {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            std.debug.print("Skip verify path {s} for request methods: {s}\n", .{
                entry.key_ptr.*, entry.value_ptr.*
            });
            try skip_auth_path.put_pattern(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    return authentocator_handler;
}

pub fn deinit_auth() void {
    if (init) {
        authentocator.deinit();
        skip_auth_path.deinit();
    }
}

fn authentocator_handler(r: zap.Request) !void {
    var flag: bool = true;
    if (r.path) |path| {
        if (skip_auth_path.find_path(path)) |allow| {
            if (r.method) |method| {
                if (std.mem.indexOf(u8, allow, method)) |_| {
                    return;
                }
            }
        }
    }

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
