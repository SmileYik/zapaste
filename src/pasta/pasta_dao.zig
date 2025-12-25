const std = @import("std");
const Pasta = @import("pasta.zig").Pasta;
const sqlite = @import("sqlite");

pub const PastaDao = struct {
    ptr: *anyopaque,
    create_table_if_not_exists_fn: *const fn (ptr: *anyopaque) anyerror!void,
    get_pasta_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta,
    get_pasta_by_name_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, name: []u8) anyerror!?Pasta,
    get_pasta_list_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta,
    delete_pasta_fn: *const fn (ptr: *anyopaque, id: u64) anyerror!bool,
    delete_pasta_by_name_fn: *const fn (ptr: *anyopaque, name: []u8) anyerror!bool,
    update_pasta_fn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta,
    insert_pasta_fn: *const fn (ptr: *anyopaque, entity: Pasta) anyerror!void,

    pub fn create_table_if_not_exists(self: PastaDao) anyerror!void {
        return self.create_table_if_not_exists_fn(self.ptr);
    }

    pub fn get_pasta(self: PastaDao, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta {
        return self.get_pasta_fn(self.ptr, allocator, id);
    }

    pub fn get_pasta_by_name(self: PastaDao, allocator: std.mem.Allocator, name: []u8) anyerror!?Pasta {
        return self.get_pasta_by_name_fn(self.ptr, allocator, name);
    }

    pub fn get_pasta_list(self: PastaDao, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta {
        return self.get_pasta_list_fn(self.ptr, allocator, query);
    }

    pub fn delete_pasta(self: PastaDao, id: u64) anyerror!bool {
        return self.delete_pasta_fn(self.ptr, id);
    }

    pub fn delete_pasta_by_name(self: PastaDao, name: []u8) anyerror!bool {
        return self.delete_pasta_by_name_fn(self.ptr, name);
    }

    pub fn update_pasta(self: PastaDao, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta {
        return self.update_pasta_fn(self.ptr, allocator, entity);
    }

    pub fn insert_pasta(self: PastaDao, allocator: std.mem.Allocator, entity: Pasta) !void {
        return self.insert_pasta_fn(self.ptr, allocator, entity);
    }
};

pub const SqlitePastaDao = struct {
    const SELECT = 
        \\SELECT 
        \\  pasta.id, 
        \\  pasta.name, 
        \\  pasta.content, 
        \\  pasta.content_type, 
        \\  pasta.attachements, 
        \\  pasta.private, 
        \\  pasta.read_only, 
        \\  pasta.editable, 
        \\  pasta.has_password, 
        \\  pasta.password, 
        \\  pasta.read_count, 
        \\  pasta.burn_after_reads, 
        \\  pasta.lastest_read_at, 
        \\  pasta.create_at, 
        \\  pasta.expiration_at, 
        \\  pasta.profiles 
        \\FROM pasta
    ;

    db: *sqlite.Db,

    pub fn create(self: *SqlitePastaDao) PastaDao {
        return .{
            .ptr = self,
            .create_table_if_not_exists_fn = create_table_if_not_exists,
            .get_pasta_fn = get_pasta,
            .get_pasta_by_name_fn = get_pasta_by_name,
            .get_pasta_list_fn = get_pasta_list,
            .delete_pasta_fn = delete_pasta,
            .delete_pasta_by_name_fn = delete_pasta_by_name,
            .update_pasta_fn = update_pasta,
            .insert_pasta_fn = insert_pasta,
        };
    }

    fn create_table_if_not_exists(ptr: *anyopaque) anyerror!void {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = 
            \\CREATE TABLE IF NOT EXISTS pasta (
            \\  id INTEGER PRIMARY KEY,
            \\  name TEXT NOT NULL UNIQUE,
            \\  content TEXT,
            \\  content_type TEXT,
            \\  attachements TEXT,
            \\  private INTEGER,
            \\  read_only INTEGER,
            \\  editable INTEGER,
            \\  has_password INTEGER,
            \\  password TEXT,
            \\  read_count INTEGER,
            \\  burn_after_reads INTEGER,
            \\  lastest_read_at INTEGER,
            \\  create_at INTEGER,
            \\  expiration_at INTEGER,
            \\  profiles TEXT
            \\)
        ;
        try self.db.exec(sql, .{}, .{});
    }

    fn get_pasta(ptr: *anyopaque, allocator: std.mem.Allocator, id: u64) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        
        const query = SELECT ++ " WHERE pasta.id = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Pasta,
            allocator,
            .{},
            .{ .id = id },
        );
        return row;
    }

    fn get_pasta_by_name(ptr: *anyopaque, allocator: std.mem.Allocator, name: []u8) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));

        const query = SELECT ++ " WHERE pasta.name = ?";
        var stmt = try self.db.prepare(query);
        defer stmt.deinit();
        const row = try stmt.oneAlloc(
            Pasta,
            allocator,
            .{},
            .{ .name = name },
        );
        return row;
    }

    fn build_entity_query(allocator: std.mem.Allocator, entity: Pasta) anyerror!?[]u8 {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_alloc = arena.allocator();

        var list = try std.ArrayList([]u8).initCapacity(temp_alloc, 16);
        var has = false;
        inline for (std.meta.fields(Pasta)) |field| {
            const value = @field(entity, field.name);
            if (value != null) {
                try list.append(temp_alloc, try std.fmt.allocPrint(temp_alloc, "{s} = ?", .{ field.name }));
                has = true;
            }
        }
        var where: ?[]u8 = undefined;
        if (has) {
            const joined = try std.mem.join(temp_alloc, " AND ", list.items);
            where = try std.fmt.allocPrint(allocator, "WHERE {s}", .{ joined });
        }
        return where;
    }

    fn get_pasta_list(ptr: *anyopaque, allocator: std.mem.Allocator, query: ?Pasta) anyerror!?[]Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_alloc = arena.allocator();
        var sql: []u8 = try std.fmt.allocPrint(temp_alloc, "{s}", .{SELECT});
        var where: ?[]u8 = null;

        if (query) |entity| {
            where = try build_entity_query(temp_alloc, entity);
        }
        if (where) |w| {
            sql = try std.fmt.allocPrint(temp_alloc, "{s} {s}", .{SELECT, w});
        }

        // var param_idx: usize = 1;
        var stmt = try self.db.prepareDynamic(SELECT);
        defer stmt.deinit();
        // if (where) |_| {
        //     inline for (std.meta.fields(Pasta)) |field| {
        //         const value = @field(query.?, field.name);
        //         if (value) |v| {
        //             stmt.bind(param_idx, v);
        //             param_idx += 1;
        //         }
        //     }
        // }
        
        return try stmt.all(
            Pasta,
            allocator,
            .{},
            .{},
        );
    }

    fn delete_pasta(ptr: *anyopaque, id: u64) anyerror!bool {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM pasta WHERE pasta.id = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{ id });
        return true;
    }

    fn delete_pasta_by_name(ptr: *anyopaque, name: []u8) anyerror!bool {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = "DELETE FROM pasta WHERE pasta.name = ?";
        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();
        try stmt.exec(.{}, .{ name });
        return true;
    }

    fn update_pasta(ptr: *anyopaque, allocator: std.mem.Allocator, entity: Pasta) anyerror!?Pasta {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_alloc = arena.allocator();

        var list = try std.ArrayList([]u8).initCapacity(temp_alloc, 16);
        var has = false;
        inline for (std.meta.fields(Pasta)) |field| {
            const value = @field(entity, field.name);
            if (value != null) {
                try list.append(temp_alloc, try std.fmt.allocPrint(temp_alloc, "SET {s} = ?", .{ field.name }));
                has = true;
            }
        }

        var sets: []u8 = undefined;
        if (has) {
            const joined = try std.mem.join(temp_alloc, " ", list.items);
            sets = try std.fmt.allocPrint(temp_alloc, "UPDATE pasta {s} WHERE id = ?", .{ joined });
        }
        if (has) {
            if (entity.id) |id| {
                var stmt = try self.db.prepareDynamic(sets);
                defer stmt.deinit();

                try stmt.exec(.{}, entity);
                return try get_pasta(ptr, allocator, id);
            }
        }
        return entity;
    }

    fn insert_pasta(ptr: *anyopaque, entity: Pasta) !void {
        const self: *SqlitePastaDao = @ptrCast(@alignCast(ptr));
        const sql = 
            \\INSERT INTO pasta (
            \\  pasta.name, 
            \\  pasta.content, 
            \\  pasta.content_type, 
            \\  pasta.attachements, 
            \\  pasta.private, 
            \\  pasta.read_only, 
            \\  pasta.editable, 
            \\  pasta.has_password, 
            \\  pasta.password, 
            \\  pasta.read_count, 
            \\  pasta.burn_after_reads, 
            \\  pasta.lastest_read_at, 
            \\  pasta.create_at, 
            \\  pasta.expiration_at, 
            \\  pasta.profiles 
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try self.db.prepare(sql);
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .name = entity.name,
            .content = entity.content, 
            .content_type = entity.content_type, 
            .attachements = entity.attachements, 
            .private = entity.private, 
            .read_only = entity.read_only, 
            .editable = entity.editable, 
            .has_password = entity.has_password, 
            .password = entity.password, 
            .read_count = entity.read_count, 
            .burn_after_reads = entity.burn_after_reads, 
            .lastest_read_at = entity.latest_read_at, 
            .create_at = entity.create_at, 
            .expiration_at = entity.expiration_at, 
            .profiles = entity.profiles,
        });
    }
};
