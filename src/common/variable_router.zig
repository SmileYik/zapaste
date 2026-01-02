const std = @import("std");
const zap = @import("zap");
const PathTree = @import("path_tree.zig").PathTree;

const U8Result = @import("result.zig").U8Result;
const Router = zap.Router;

pub const RouterOptions = struct {
    not_found: ?zap.HttpRequestFn = null,
    interceptors: ?[]zap.HttpRequestFn = null,
};

pub const RouterError = error {
    InterceptorReject,
    InterceptorFastReturn,
};

/// This router similiar with zap.Router
pub const VariableRouter = struct {

    const VariablePath = struct {
        paths: []const []const u8,
        variable_idxes: []const usize,

        /// initialize a variable path. use `:` to mark a variable.
        /// 
        /// for example: `/user/:id` contains `id` variable, it's matches path: `/user/tom`, then the `id` value is `tom`  
        /// 
        /// you also can mark multiple variables in one path, just like `/user/:username/detail/:id`
        pub fn init(comptime path: []const u8) VariablePath {
            const count, const variable_count = comptime counts: {
                var iter = std.mem.splitSequence(u8, path, "/");
                var c_count: usize = 0;
                var c_variable_count: usize = 0;
                while (iter.next()) |line| {
                    c_count += 1;
                    if (std.mem.startsWith(u8, line, ":")) {
                        c_variable_count += 1;
                    }
                }
                break :counts  .{ c_count, c_variable_count };
            };
            
            const array, const variables = comptime blk: {
                var result: [count][]const u8 = undefined;
                var variable_idxes: [variable_count]usize = undefined;
                var i: usize = 0;
                var j: usize = 0;
                
                var iter = std.mem.splitSequence(u8, path, "/");
                while (iter.next()) |line| {
                    result[i] = line;
                    if (std.mem.startsWith(u8, line, ":")) {
                        variable_idxes[j] = i;
                        j += 1;
                    }
                    i += 1;
                }
                break :blk . { result, variable_idxes };
            };
            return .{
                .paths = &array,
                .variable_idxes = &variables
            };
        }

        /// matches path
        pub fn matches(self: *const VariablePath, path: []const u8) bool {
            var iter = std.mem.splitSequence(u8, path, "/");
            var variable_idx: usize = 0;
            var idx: usize = 0;
            while (iter.next()) |line| {
                if (idx == self.paths.len) {
                    return false;
                } else if (variable_idx < self.variable_idxes.len and idx == self.variable_idxes[variable_idx]) {
                    variable_idx += 1;
                } else if (!std.mem.eql(u8, line, self.paths[idx])) {
                    return false;
                }
                idx += 1;
            }
            return idx == self.paths.len;
        }

        /// get path variables. if it's not matches then will return null.
        pub fn get_variables(self: *const VariablePath, gpa: std.mem.Allocator, path: []const u8) !?std.StringHashMap([]const u8) {
            var variables = std.StringHashMap([]const u8).init(gpa);
            var iter = std.mem.splitSequence(u8, path, "/");
            var variable_idx: usize = 0;
            var idx: usize = 0;
            while (iter.next()) |line| {
                if (self.variable_idxes.len == variable_idx) break;
                const v_idx = self.variable_idxes[variable_idx];
                if (idx == v_idx) {
                    variable_idx += 1;
                    try variables.put(self.paths[idx][1..], line);
                }
                idx += 1;
            }
            return variables;
        }
    };
    
    const CallbackType = enum {
        bound,
        unbound
    };

    const Callback = union (CallbackType) {
        bound: struct {
            instance: usize,
            handler: usize
        },
        unbound: usize
    };

    const BoundHandler = *fn (*const anyopaque, path_variables: std.StringHashMap([]const u8), zap.Request) anyerror!void;
    const UnboundHandler = *fn (path_variables: std.StringHashMap([]const u8), zap.Request) anyerror!void;

    const Record = struct {
        path: VariablePath,
        callback: Callback
    };

    const PTree = PathTree(Record);

    routes: *PTree,
    not_found: ?zap.HttpRequestFn = null,
    inner_router: Router,

    var _instance: *VariableRouter = undefined;
    
    pub fn init(allocator: std.mem.Allocator, options: RouterOptions) !*VariableRouter {
        var router = try allocator.create(VariableRouter);
        router.* = .{
            .routes = try PTree.init(.{ .allocator = allocator }),
            .not_found = options.not_found orelse null,
            .inner_router = undefined
        };
        router.inner_router = Router.init(allocator, .{
            .not_found = router.on_inner_router_not_fount()
        });
        return router;
    }

    /// handle function unbound with none variable path, as same as zap.Router
    pub fn handle_func_unbound(self: *VariableRouter, comptime path: []const u8, h: anytype) !void {
        try self.inner_router.handle_func_unbound(path, h);
    }

    /// handle function bound with none variable path, as same as zap.Router
    pub fn handle_func_bound(self: *VariableRouter, comptime path: []const u8, instance: *anyopaque, h: anytype) !void {
        try self.inner_router.handle_func(path, instance, h);
    }

    /// handle function unbound with includes variable path.  
    /// the passed `path` must includes path variable, a path variable starts with `:`, `:name` means `name` variable. there are some examples:
    /// 
    /// + `/user/:firstname/:lastname/files`: this path includes two variables `firstname` and `lastname`, 
    /// it's will matches paths like `/user/tom/green/files`, `/user/jecky/zhang/files`
    /// + `/user/:id`: this path includes `id` variable.
    /// it's will matches paths like `/user/1`, `/user/2`
    /// 
    /// and `h` is your handler, it's must be `*fn (path_variables: std.StringHashMap([]const u8), zap.Request) anyerror!void`
    pub fn handle_var_func_unbound(self: *VariableRouter, allocator: std.mem.Allocator, comptime path: []const u8, h: anytype) !void {
        if (path.len == 0) {
            return;
        }

        _ = allocator;
        try self.routes.put_pattern(path, .{
            .path = VariablePath.init(path),
            .callback = .{
                .unbound = @intFromPtr(h)
            }
        });
    }

    /// handle function unbound with includes variable path.  
    /// the passed `path` must includes path variable, a path variable starts with `:`, `:name` means `name` variable. there are some examples:
    /// 
    /// + `/user/:firstname/:lastname/files`: this path includes two variables `firstname` and `lastname`, 
    /// it's will matches paths like `/user/tom/green/files`, `/user/jecky/zhang/files`
    /// + `/user/:id`: this path includes `id` variable.
    /// it's will matches paths like `/user/1`, `/user/2`
    /// 
    /// and `h` is your handler, it's must be `*fn (*const anyopaque, path_variables: std.StringHashMap([]const u8), zap.Request) anyerror!void`
    pub fn handle_var_func_bound(self: *VariableRouter, allocator: std.mem.Allocator, comptime path: []const u8, instance: *const anyopaque, h: anytype) !void {
        if (path.len == 0) {
            return;
        }
        
        _ = allocator;
        try self.routes.put_pattern(path, .{
            .path = VariablePath.init(path),
            .callback = .{
                .bound = .{
                    .instance = @intFromPtr(instance),
                    .handler = @intFromPtr(h)
                }
            }
        });
    }

    pub fn deinit(self: *VariableRouter) void {
        defer self.inner_router.deinit();
        defer self.routes.deinit();
    }

    pub fn on_request_handler(self: *VariableRouter) zap.HttpRequestFn {
        self.inner_router.not_found = self.on_inner_router_not_fount();
        return self.inner_router.on_request_handler();
    }

    fn on_inner_router_not_fount(self: *VariableRouter) zap.HttpRequestFn {
        _instance = self;
        return zap_on_request;
    }

    fn zap_on_request(r: zap.Request) !void {
        return serve(_instance, r);
    }

    fn serve(self: *VariableRouter, r: zap.Request) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const path = r.path orelse "/";
        var target: ?Record = null;
        var path_variables: ?std.StringHashMap([]const u8) = null;
        if (self.routes.find_path(path)) |route| {
            if (try route.path.get_variables(gpa, path)) |map| {
                path_variables = map;
                target = route;
            }
        }

        if (target) |record| {
            switch (record.callback) {
                .bound => |b| {
                    try @call(
                        .auto, 
                        @as(BoundHandler, @ptrFromInt(b.handler)), 
                        .{ @as(*anyopaque, @ptrFromInt(b.instance)), path_variables.?, r }
                    );
                },
                .unbound => |h| {
                    try @call(
                        .auto,
                        @as(UnboundHandler, @ptrFromInt(h)),
                        .{ path_variables.?, r }
                    );
                },
            }
            path_variables.?.deinit();
        } else if (self.not_found) |handler| {
            try handler(r);
        } else {
            r.setStatus(.not_found);
        }
    }
};

pub const WrapperRouter = struct {
    const RouterMap = std.AutoHashMap(zap.http.Method, *VariableRouter);
    var _instance: *WrapperRouter = undefined;

    router_map: RouterMap,
    not_found: ?zap.HttpRequestFn = null,
    interceptors: ?[]const zap.HttpRequestFn,

    pub fn init(allocator: std.mem.Allocator, options: RouterOptions) !*WrapperRouter {
        const r = try allocator.create(WrapperRouter);
        r.* = .{
            .router_map = RouterMap.init(allocator),
            .not_found = options.not_found orelse null,
            .interceptors = options.interceptors
        };
        return r;
    }

    pub fn deinit(self: *WrapperRouter, allocator: std.mem.Allocator) void {
        var iter = self.router_map.valueIterator();
        while (iter.next()) |r| {
            r.*.deinit();
        }
        self.router_map.deinit();
        allocator.destroy(self);
    }

    pub fn special(self: *WrapperRouter, allocator: std.mem.Allocator, method: zap.http.Method) !*VariableRouter {
        if (self.router_map.contains(method)) {
            return self.router_map.get(method).?;
        } else {
            const r = try VariableRouter.init(allocator, .{
                .not_found = self.not_found
            });
            try self.router_map.put(method, r);
            return r;
        }
    }

    pub fn on_request_handler(self: *WrapperRouter) zap.HttpRequestFn {
        _instance = self;
        return zap_on_request;
    }

    fn zap_on_request(r: zap.Request) !void {
        return serve(_instance, r);
    }

    fn serve(self: *WrapperRouter, r: zap.Request) !void {

        if (self.interceptors) |interceptors| {
            for (interceptors) |inte| {
                var ee: ?anyerror = null;
                var message: ?[]const u8 = null;
                inte(r) catch |err| switch (err) {
                    RouterError.InterceptorReject => |e| {
                        ee = e;
                        message = "Blocked";
                    },
                    else => |e| {
                        ee = e;
                        message = "Unknow Error";
                    }
                };
                if (ee) |e| {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    const allocator = arena.allocator();
                    const result = try U8Result.failed(allocator, e, message.?);
                    result.send_json(r, .{ .emit_null_optional_fields = false });
                    return;
                }
                if (r.isFinished()) {
                    return;
                }
            }
        }

        const method = r.methodAsEnum();
        if (self.router_map.get(method)) |dispatch| {
            try dispatch.on_request_handler()(r);
        } else if (self.not_found) |handler| {
            try handler(r);
        } else {
            r.setStatus(.not_found);
        }
    }
};

test "[VariablePath] test1" {
    const VariablePath = VariableRouter.VariablePath;
    std.debug.print("Start [VariablePath] test1 \n", .{});
    const vp = VariablePath.init("/user/:username/info");
    std.debug.assert(vp.matches("/user/zhangsan/info"));
    std.debug.assert(vp.matches("/user/张三/info"));
    std.debug.assert(vp.matches("/user/z/info"));
    std.debug.assert(!vp.matches("/user/z/info/abc"));
}