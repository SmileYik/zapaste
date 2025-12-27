const std = @import("std");
const sqlite = @import("sqlite");

const AtomicValue = std.atomic.Value;
const Allocator = std.mem.Allocator;

pub const Self = @This();

pub const Connection = struct {
    pool: *Self,
    index: usize,

    pub fn get_db(self: Connection) *sqlite.Db {
        return &self.pool.dbs[self.index];
    }

    pub fn release(self: Connection) void {
        self.pool.release_index(self.index);
    }
};

pub const SqlitePoolError = error {
    Busy
};

dbs: []sqlite.Db,
occupancy: AtomicValue(u32),
capacity: u32,
max_retry: ?u32 = 10000,

/// init a Sqlite pool
/// 
/// ## params
/// + `options`: Sqlite options,
/// + `capacity`: pool capacity
/// + `max_retry`: max retry counts while database connections all busy. default is 10000
pub fn init(allocator: Allocator, options: sqlite.InitOptions, capacity: u32, max_retry: ?u32) !*Self {
    const self = try allocator.create(Self);
    const dbs = try allocator.alloc(sqlite.Db, capacity);

    for (0..capacity) |idx| {
        dbs[idx] = try sqlite.Db.init(options);
        _ = try dbs[idx].pragma(void, .{}, "journal_mode", "WAL");
    }

    self.* = .{
        .dbs = dbs,
        .capacity = capacity,
        .occupancy = AtomicValue(u32).init(0),
        .max_retry = max_retry
    };
    return self;
}

/// deinit pool
pub fn deinit(self: *Self) void {
    for (self.dbs) |db| {
        db.deinit();
    }
}

/// get a database connection.
pub fn get_connection(self: *Self) SqlitePoolError!Connection {
    const index = self.acquire_index();
    if (index) |idx| {
        return .{
            .pool = self,
            .index = idx
        };
    }
    return SqlitePoolError.Busy;
}

fn acquire_index(self: *Self) ?usize {
    var retry_count_down: u32 = self.max_retry orelse 10000;
    while (retry_count_down != 0) {
        retry_count_down -= 1;
        const current: u32 = self.occupancy.load(.monotonic);
        const first_free_idx = @ctz(~current);
        if (first_free_idx >= self.capacity) {
            std.Thread.yield() catch {}; 
            continue;
        }

        const mask = @as(u32, 1) << @intCast(first_free_idx);
        const next = current | mask;

        const result = self.occupancy.cmpxchgWeak(
            current, 
            next, 
            .acquire, 
            .monotonic
        );
        if (result) |_| continue;

        return first_free_idx;
    }
    return null;
}

fn release_index(self: *Self, index: usize) void {
    const mask = @as(u32, 1) << @intCast(index);
    _ = self.occupancy.fetchAnd(~mask, .release);
}