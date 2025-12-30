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
    const no_valid_payload = comptime PasteResult.init(500, null, "Not a valid payload or content-type");
    errdefer common.Result.UnknownError.send_json(req, strip_null_field);
    errdefer if (@errorReturnTrace()) |trace| {
        std.debug.dumpStackTrace(trace.*);
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    if (req.body == null) {
        no_valid_payload.send_json(req, strip_null_field);
        return;
    }
    const content_type = req.getHeaderCommon(.content_type);
    if (content_type == null) {
        no_valid_payload.send_json(req, strip_null_field);
        return;
    }

    var paste_json: ?[] const u8 = null;
    var attachements: ?[]const u8 = null;
    if (std.ascii.eqlIgnoreCase("application/json", content_type.?)) {
        paste_json = req.body;
    } else {
        try req.parseBody();
        const body = try req.parametersToOwnedList(allocator);
        // defer body.deinit();
        var file_array: [32]u64 = undefined;
        var file_list = std.ArrayList(u64).initBuffer(&file_array);

        for (body.items) |item| {
            if (std.mem.eql(u8, item.key, "paste")) {
                if (item.value) |value| switch (value) {
                    .String => |s| paste_json = s,
                    else => continue
                };
            } else if (std.mem.eql(u8, item.key, "file")) {
                if (item.value) |value| switch (value) {
                    .Hash_Binfile => |f| {
                        if (try self.file_service.?.save_file(f.data, f.mimetype, f.filename)) |id| {
                            try file_list.append(allocator, id);
                        }
                    },
                    .Array_Binfile => |list| {
                        for (list.items) |f| if (try self.file_service.?.save_file(f.data, f.mimetype, f.filename)) |id| {
                            try file_list.append(allocator, id);
                        };
                    },
                    else => continue
                };
            }
        }

        var ids = try std.ArrayList(u8).initCapacity(allocator, 1024);
        if (file_list.items.len > 0) {
            for (file_list.items) |id| {
                try ids.append(allocator, ',');
                try std.fmt.format(ids.writer(allocator), "{d}", .{ id });
            }
            attachements = ids.items[1..];
        }
    }

    if (paste_json == null) {
        no_valid_payload.send_json(req, strip_null_field);
        return;
    }
    const parsed = try std.json.parseFromSlice(Paste, allocator, paste_json.?, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();
    var entity: Paste = parsed.value;
    entity.attachements = attachements;
    const result = if (self.service.?.create_paste(allocator, entity)) |inserted| blk: {
        break :blk PasteResult.success(inserted, "success");
    } else |e| blk: {
        break :blk try PasteResult.failed(allocator, e, "failed to create");
    };

    result.send_json(req, strip_null_field);
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

    const content_type = req.getHeaderCommon(.content_type);
    var paste_json: ?[] const u8 = null;
    if (content_type) |ctype| {
        if (std.ascii.eqlIgnoreCase("application/json", ctype)) {
            paste_json = req.body;
        } else {
            try req.parseBody();
            const body = try req.parametersToOwnedList(allocator);
            for (body.items) |item| {
                if (std.mem.eql(u8, item.key, "paste") and item.value != null) {
                    switch (item.value.?) {
                        .String => |s| paste_json = s,
                        else => continue
                    }
                    break;
                }
            }
        }
    }

    if (paste_json) |josn| {
        const parsed = try std.json.parseFromSlice(
            UpdatePasteModel, 
            allocator, 
            josn, 
            .{ .ignore_unknown_fields = true }
        );
        defer parsed.deinit();
        const update_model: UpdatePasteModel = parsed.value;
        if (update_model.paste) |p| {
            const name = path_variables.get("name").?;
            var paste = p;
            paste.read_count = null;
            paste.create_at = null;
            paste.latest_read_at = null;
            const updated = self.service.?.update_paste(allocator, paste, name, update_model.password, false)
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
            }
        }
    }

    not_update_message.send_json(req, strip_null_field);
}