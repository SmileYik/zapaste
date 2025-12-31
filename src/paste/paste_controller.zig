const std = @import("std");
const zap = @import("zap");
const common = @import("common");
const Paste = @import("paste.zig").Paste;
const PasteDao = @import("paste_dao.zig").PasteDao;
const SqlitePasteDao = @import("paste_dao.zig").SqlitePasteDao;
const PasteService = @import("paste_service.zig").PasteService;

const file = @import("file");

const WrapperRouter = common.WrapperRouter;

const Allocator = std.mem.Allocator;

pub const Self = @This();

service: ?PasteService = undefined,
file_service: ?file.FileService = undefined,

pub fn init(allocator: Allocator, options: *common.Options) !*Self {
    var self: *Self = try allocator.create(Self);
    self.* = .{
        .service = undefined,
    };
    switch (options.dao_type) {
        .Sqlite => |_| {
            {
                var sqldao: *SqlitePasteDao = try allocator.create(SqlitePasteDao);
                sqldao.* = .{ .pool = options.sqlite.? };
                const dao = try allocator.create(PasteDao);
                dao.* = sqldao.create();
                try dao.create_table_if_not_exists();
                self.service = PasteService.create(.{
                    .dao = dao
                });
            }
            {
                var sqldao: *file.SqliteFileDao = try allocator.create(file.SqliteFileDao);
                sqldao.* = .{ .pool = options.sqlite.? };
                const dao = try allocator.create(file.FileDao);
                dao.* = sqldao.init();
                try dao.create_table_if_not_exists();
                self.file_service = file.FileService {
                    .dao = dao,
                    .store_path = options.get_path(allocator, "uploads", "./uploads")
                };
            }
        },
    }
    return self;
}

pub fn register(
    self: *Self, 
    allocator: Allocator, 
    router: *WrapperRouter, 
    comptime prefix_path: []const u8
) !void {
    const get_router = try router.special(allocator, .GET);
    try get_router.handle_func_bound(prefix_path, self, &list_public_pastes);
    try get_router.handle_var_func_bound(allocator, prefix_path ++ "/:name", self, &get_unlocked_paste);

    const post_router = try router.special(allocator, .POST);
    try post_router.handle_func_bound(prefix_path, self, &create_paste);
    try post_router.handle_var_func_bound(allocator, prefix_path ++ "/:name", self, &get_locked_paste);
    try post_router.handle_var_func_bound(allocator, prefix_path ++ "/:name/delete", self, &delete_locked_paste);

    const delete_router = try router.special(allocator, .DELETE);
    try delete_router.handle_var_func_bound(allocator, prefix_path ++ "/:name", self, &delete_unlock_paste);
    try delete_router.handle_var_func_bound(allocator, prefix_path ++ "/:name/delete", self, &delete_unlock_paste);

    const put_router = try router.special(allocator, .PUT);
    try put_router.handle_var_func_bound(allocator, prefix_path ++ "/:name", self, &update_paste);
}

const PastePageResult = common.Result.create(Paste.Page);

const PasteResult = common.Result.create(Paste);

const PasswordModel = struct {
    password: ?[]const u8 = null
};

const UpdatePasteModel = struct {
    password: ?[]const u8 = null,
    paste: ?Paste = null
};

const result_name_cannot_empty = PasteResult.init(500, null, "Paste name cannot be empty.");
const result_no_password = PasteResult.init(500, null, "Please verify your password.");
const strip_null_field = std.json.Stringify.Options { .emit_null_optional_fields = false };

fn parse_number(str: ?[]const u8, T: type, default_value: T) T {
    if (str) |s| {
        return std.fmt.parseInt(T, s, 10) catch default_value;
    } else {
        return default_value;
    }
}

inline fn handle_get_paste(
    self: *Self, 
    allocator: Allocator, 
    name: []const u8, 
    password: ?[]const u8,
    req: zap.Request
) !void {
    const trimmed_name = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed_name.len == 0) {
        result_name_cannot_empty.send_json(req, strip_null_field);
        return;
    }

    const paste_opt = self.service.?.read_paste(
        allocator, .{ 
            .name = name,
            .password = password
        }
    ) catch |e| {
        const result = try PastePageResult.failed(allocator, e, "Paste not found or incorrect password!");
        result.send_json(req, strip_null_field);
        return;
    };

    const result = 
        if (paste_opt) |p| blk: {
            // if using raw=true param.
            const raw = req.getParamSlice("raw");
            if (raw) |bool_str| {
                if (std.ascii.eqlIgnoreCase(
                    "true", 
                    std.mem.trim(u8, bool_str, " \r\n\t")
                )) {
                    try req.setContentType(.TEXT);
                    try req.sendBody(p.content orelse "");
                    return;
                }
            }

            var new = try p.dupe(allocator);
            new.password = null;
            break :blk PasteResult.success(new, null);
        } else PasteResult.init(404, null, "Paste not found or incorrect password");
    result.send_json(req, strip_null_field);
}

/// get the paste with password, need pass `password` field
/// 
/// POST /:name?raw=true/false
/// 
/// content-type: application/json
/// 
/// + params: `raw=true` just return paste content.
/// + body: `PasswordModel`
fn get_locked_paste(self: *Self, path_variables: std.StringHashMap([]const u8), req: zap.Request) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    if (req.body == null) {
        result_no_password.send_json(req, strip_null_field);
        return;
    }
    const parsed = try std.json.parseFromSlice(
        PasswordModel, 
        allocator, 
        req.body.?, 
        .{ .ignore_unknown_fields = true }
    );
    defer parsed.deinit();
    const password_model: PasswordModel = parsed.value;
    const name = path_variables.get("name").?;
    try self.handle_get_paste(allocator, name, password_model.password, req);
}

/// get none password paste by name
/// 
/// GET /:name?raw=true/false
/// 
/// + params: `raw=true` just return paste content.
fn get_unlocked_paste(self: *Self, path_variables: std.StringHashMap([]const u8), req: zap.Request) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    const name = path_variables.get("name").?;
    try self.handle_get_paste(allocator, name, null, req);
}

/// list public pastes, includes pagination
/// 
/// GET /
/// 
/// params: 
/// + `page_size`: optional, default 10, means how many paste items should be returned.
/// + `page_no`: optional, default 1, means the page number
fn list_public_pastes(self: *Self, req: zap.Request) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    const page_size = parse_number(req.getParamSlice("page_size"), u32, 10);
    const page_no = parse_number(req.getParamSlice("page_no"), u32, 1);
    
    var result: ?PastePageResult = null;
    if (self.service.?.page_public_pastes_summary(allocator, page_no, page_size)) |page| {
        result = PastePageResult.success(page, null);
    } else |err| {
        result = try PastePageResult.failed(allocator, err, "show paste list failed!" );
    }

    result.?.send_json(req, strip_null_field);
}

/// delete unlock paste by name
/// 
/// DELETE /:name/delete
/// DELETE /:name
/// 
fn delete_unlock_paste(self: *Self, path_variables: std.StringHashMap([]const u8), req: zap.Request) !void {
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const name = path_variables.get("name").?;
    try self.handle_delete_request(allocator, req, name, null);
}

/// delete paste with password, need pass `password` field
/// 
/// POST /:name/delete
/// 
/// content-type: application/json
/// 
/// + body: `PasswordModel`
fn delete_locked_paste(self: *Self, path_variables: std.StringHashMap([]const u8), req: zap.Request) !void {
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (req.body == null) {
        result_no_password.send_json(req, strip_null_field);
        return;
    }
    const parsed = try std.json.parseFromSlice(
        PasswordModel, 
        allocator, 
        req.body.?, 
        .{ .ignore_unknown_fields = true }
    );
    defer parsed.deinit();
    const password_model: PasswordModel = parsed.value;
    const name = path_variables.get("name").?;
    try self.handle_delete_request(allocator, req, name, password_model.password);
}

inline fn handle_delete_request(
    self: *Self, 
    allocator: Allocator, 
    req: zap.Request, 
    name: []const u8, 
    password: ?[]const u8
) !void {
    _ = self.service.?.delete_paste(allocator, name, password, false)
    catch |err| switch (err) {
        error.PasswordRequired => {
            result_no_password.send_json(req, strip_null_field);
            return;
        },
        else => |e| {
            const result = try PasteResult.failed(allocator, e, "failed to delete");
            result.send_json(req, strip_null_field);
            return;
        }
    };
    PasteResult.success(null, "deleted").send_json(req, strip_null_field);
}

/// create paste, you can special any field but `id`.
/// 
/// POST /
/// 
/// content-type: application/form-date
/// 
/// params: `paste={JSON}`, `{JSON}` is `Paste` type. 
/// 
fn create_paste(self: *Self, req: zap.Request) !void {
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);
    errdefer if (@errorReturnTrace()) |trace| {
        std.debug.dumpStackTrace(trace.*);
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed, const ids = try handle_receive_paste(self, allocator, req, Paste);
    defer if (ids) |list| {
        var l = list;
        l.deinit(allocator);
    };

    if (parsed) |*parsed_entity| {
        var var_parsed = parsed_entity;
        var_parsed.deinit();

        if (req.isFinished()) return;

        var entity: Paste = var_parsed.value;
        if (ids) |list| {
            if (list.items.len > 0) entity.attachements = list.items[1..];
        }
        const result = if (self.service.?.create_paste(allocator, entity)) |inserted| blk: {
            break :blk PasteResult.success(inserted, "success");
        } else |e| blk: {
            break :blk try PasteResult.failed(allocator, e, "failed to create");
        };

        result.send_json(req, strip_null_field);
    }
}

/// update paste with password, `password` field is options
/// 
/// PUT /:name
/// 
/// content-type: application/json
/// 
/// + body: `UpdatePasteModel`
fn update_paste(self: *Self, path_variables: std.StringHashMap([]const u8), req: zap.Request) !void {
    const not_update_message = comptime PasteResult.init(404, null, "Not found paste or not have update payload.");
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsed, const ids = try handle_receive_paste(self, allocator, req, UpdatePasteModel);
    if (parsed) |update_model| {
        var var_parsed = update_model;
        var_parsed.deinit();

        if (req.isFinished()) return;

        const model = var_parsed.value;
        const paste_if = model.paste;
        if (paste_if) |paste_const| {
            var paste = paste_const;
            paste.read_count = null;
            paste.create_at = null;
            paste.latest_read_at = null;

            if (ids) |list| {
                if (list.items.len > 0) paste.attachements = list.items[1..];
            }
            
            const name = path_variables.get("name").?;
            const updated = self.service.?.update_paste(allocator, paste, name, model.password, false)
            catch |err| switch (err) {
                error.PasswordRequired => {
                    result_no_password.send_json(req, strip_null_field);
                    return;
                },
                error.ReadOnly => {
                    PasteResult.failed_message("This paste is read-only!").send_json(req, strip_null_field);
                    return;
                },
                else => |e| {
                    const result = try PasteResult.failed(allocator, e, "failed to delete");
                    result.send_json(req, strip_null_field);
                    return;
                }
            };
            if (updated) |u| {
                var e = u;
                e.password = null;
                PasteResult.success(e, "Updated").send_json(req, strip_null_field);
                return;
            }
        }
        not_update_message.send_json(req, strip_null_field);
    }
}

inline fn handle_receive_paste(self: *Self, allocator: Allocator, req: zap.Request, comptime T: type) !struct {
    ?std.json.Parsed(T), ?std.ArrayList(u8)
} {
    const no_valid_payload = comptime PasteResult.init(500, null, "Not a valid payload or content-type");

    if (req.body == null) {
        result_no_password.send_json(req, strip_null_field);
        return .{ null, null };
    }

    const content_type = req.getHeaderCommon(.content_type);
    if (content_type) |ct| {
        const paste_json: ?[] const u8 = 
        if (std.ascii.eqlIgnoreCase("application/json", ct)) req.body
        else blk: {
            try req.parseBody();
            break :blk try common.ZapParamsFinder.get_string(allocator, req, "paste");
        };

        // json first
        if (paste_json == null) {
            no_valid_payload.send_json(req, strip_null_field);
            return .{ null, null };
        }
        const parsed = try std.json.parseFromSlice(T, allocator, paste_json.?, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });

        // file after
        var file_array: [32]u64 = undefined;
        var file_list = std.ArrayList(u64).initBuffer(&file_array);
        defer file_list.deinit(allocator);
        const file_len = common.ZapParamsFinder.get_file_count(allocator, req, "file") catch |e| switch (e) {
            error.Unsupported => 0,
            else => {
                (try PasteResult.failed(allocator, e, "Failed to get files.")).send_json(req, strip_null_field);
                return .{ null, null };
            }
        };
        if (file_len) |len| for (0..len) |i| {
            const param_file = try common.ZapParamsFinder.get_file(allocator, req, "file", len, i);
            if (param_file) |f| {
                if (try self.file_service.?.save_file(f.data, f.mimetype, f.filename)) |id| {
                    try file_list.append(allocator, id);
                }
            }
        };
        var ids = try std.ArrayList(u8).initCapacity(allocator, 1024);
        // defer ids.deinit(allocator);
        if (file_list.items.len > 0) {
            for (file_list.items) |id| {
                try ids.append(allocator, ',');
                try std.fmt.format(ids.writer(allocator), "{d}", .{ id });
            }
        }
        return .{ parsed, ids };
    }
    return .{ null, null }; 
}