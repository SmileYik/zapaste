const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Options = struct {
    allocator: Allocator = undefined,
    split_slice: []const u8 = "/",
    pattern_prefix: []const u8 = ":",
};

pub fn PathTree(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = std.StringHashMap(*Self);
        const List = std.ArrayList(*Self);

        allocator: Allocator = undefined,
        is_path: bool = false,
        value: ?T = null,
        split_slice: []const u8 = undefined,
        pattern_prefix: []const u8 = undefined,
        map: ?Map = null,
        patterns: ?List = null,

        pub fn init(options: Options) !*Self {
            const self: *Self = try options.allocator.create(Self);
            self.* = .{
                .allocator = options.allocator,
                .split_slice = options.split_slice,
                .pattern_prefix = options.pattern_prefix
            };
            return self;
        }

        fn init_self(self: *Self) !*Self {
            return try init(.{
                .allocator = self.allocator,
                .split_slice = self.split_slice,
                .pattern_prefix = self.pattern_prefix,
            });
        }

        pub fn deinit(self: *Self) void {
            if (self.patterns) |*p| {
                p.*.deinit(self.allocator);
            }
            if (self.map) |*map| {
                defer map.*.deinit();
                var iter = map.valueIterator();
                while (iter.next()) |*item| {
                    item.*.*.deinit();
                }
            }
            self.allocator.destroy(self);
        }

        pub fn put_pattern(self: *Self, path: []const u8, val: T) !void {
            const node = try self.find_pattern_node(path);
            node.*.is_path = true;
            node.*.value = val;
        }

        pub fn find_path(self: *Self, path: []const u8) ?T {
            const iter = std.mem.splitSequence(u8, path, self.split_slice);
            return find_path_inner(self, iter);
        }

        fn find_path_inner(node_final: *Self, iter_final: std.mem.SplitIterator(u8, .sequence)) ?T {
            var node = node_final;
            var iter = iter_final;
            while (iter.next()) |p| {
                if (node.map) |map| {
                    if (map.get(p)) |sub_node| {
                        node = sub_node;
                    } else if (node.patterns) |list| {
                        for (list.items) |item| {
                            if (find_path_inner(item, iter)) |result| return result;
                        }
                    }
                }
            }
            if (node.is_path) {
                if (node.value) |value| return value;
            }
            return null;
        }

        inline fn find_pattern_node(self: *Self, path: []const u8) !*Self {
            var node: *Self = self;
            var iter = std.mem.splitSequence(u8, path, self.split_slice);
            while (iter.next()) |p| {
                if (node.map == null) {
                    node.map = Map.init(self.allocator);
                }
                if (node.map) |*map| {
                    var entry = map.*.getEntry(p);
                    if (entry) |*e| {
                        node = e.*.value_ptr.*;
                    } else {
                        const tmp = try Self.init_self(self);
                        try map.put(p, tmp);
                        if (std.mem.startsWith(u8, p, self.pattern_prefix)) {
                            if (node.*.patterns == null) {
                                node.*.patterns = try List.initCapacity(self.allocator, 1);
                                try node.*.patterns.?.append(self.allocator, tmp);
                            }
                        }
                        node = tmp;
                    }
                }
            }
            return node;
        }
    };
}

