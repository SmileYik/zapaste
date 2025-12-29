const std = @import("std");
const zap = @import("zap");
const common = @import("common");
const res = @import("res");

const WrapperRouter = common.WrapperRouter;

const Allocator = std.mem.Allocator;

pub const Self = @This();

index: []const u8 = res.file("swagger/swagger.html"),
default_api: []const u8 = res.file("swagger/openapi.yml"),
index_file: ?[]const u8 = null,
api_file: ?[]const u8 = null,

pub fn init(
    allocator: Allocator, 
    router: *WrapperRouter, 
    comptime prefix_path: []const u8,
    options: *common.Options
) !?*Self {
    if (options.swagger) |o| {
        if (o.enable) |flag| {
            if (flag) {
                var controller = try allocator.create(Self);
                controller.* = .{};
                try controller.register(allocator, router, prefix_path, options);
                return controller;
            }
        }
    }
    return null;
}

pub fn info(bind_port: u16) void {
    std.debug.print(
        \\
        \\Enabled swagger document: 
        \\  http://localhost:{}/swagger/
        \\
        \\
        ,
        .{ bind_port }
    );
}

fn register(
    self: *Self, 
    allocator: Allocator, 
    router: *WrapperRouter, 
    comptime prefix_path: []const u8,
    options: *common.Options
) !void {
    if (options.swagger) |o| {
        if (o.swagger_config_path) |api_path| {
            self.api_file = options.get_path(allocator, api_path, "/app/openapi.yml");
        }
        if (o.swagger_index_path) |index_path| {
            self.index_file = options.get_path(allocator, index_path, "/app/openapi.yml");
        }

        const get_router = try router.special(allocator, .GET);
        try get_router.handle_func_bound(prefix_path, self, &get_swagger_index);
        try get_router.handle_func_bound(prefix_path ++ "/", self, &get_swagger_index);
        try get_router.handle_func_bound(prefix_path ++ "/openapi.yml", self, &get_swagger_config);
    }
}

fn get_swagger_index(self: *Self, r: zap.Request) !void {
    errdefer common.Result.UnknownError.send_json(r, .{ .emit_null_optional_fields = false });
    if (self.index_file) |f| try r.sendFile(f)
    else {
        try r.setContentType(.HTML);
        try r.sendBody(self.index);
    }
}

fn get_swagger_config(self: *Self, r: zap.Request) !void {
    errdefer common.Result.UnknownError.send_json(r, .{ .emit_null_optional_fields = false });
    
    var failed: bool = false;
    if (self.api_file) |file| r.sendFile(file) catch {
        failed = true;
    };
    if (failed) {
        try r.sendBody(self.default_api);
    }
}