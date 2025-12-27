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
latest_idx: AtomicValue(u32) = AtomicValue(u32).init(0),
capacity: u32,
mutex: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},

/// init a Sqlite pool
/// 
/// ## params
/// + `options`: Sqlite options,
/// + `capacity`: pool capacity
pub fn init(allocator: Allocator, options: sqlite.InitOptions, capacity: u32) !*Self {
    const self = try allocator.create(Self);
    const dbs = try allocator.alloc(sqlite.Db, capacity);

    for (0..capacity) |idx| {
        dbs[idx] = try sqlite.Db.init(options);
        _ = try dbs[idx].pragma(void, .{}, "journal_mode", "WAL");
        _ = try dbs[idx].pragma(void, .{}, "busy_timeout", "1000");
    }

    self.* = .{
        .dbs = dbs,
        .capacity = capacity,
        .occupancy = AtomicValue(u32).init(0),
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
        std.debug.print("[SimpleSqlitePool] acquired pool: {}\n", .{idx});
        return .{
            .pool = self,
            .index = idx
        };
    }
    return SqlitePoolError.Busy;
}

fn try_acquire_index(self: *Self) ?usize {
    const full_mask = (@as(u32, 1) << @intCast(self.capacity)) - 1;
    const current: u32 = self.occupancy.load(.acquire);
    if (current >= full_mask) return null;

    const start = self.latest_idx.load(.acquire);
    var i: u32 = 0;
    while (i < self.capacity) : (i += 1) {
        const candidate = (start + i) % self.capacity;
        const mask = @as(u32, 1) << @intCast(candidate);
        if (current & mask == 0) {
            _ = self.occupancy.cmpxchgStrong(
                current, 
                current | mask, 
                .acquire, 
                .monotonic
            ) orelse {
                self.latest_idx.store((candidate + 1) % self.capacity, .monotonic);
                return candidate;
            };
            break;
        }
    }
    return null;
}

fn acquire_index(self: *Self) ?usize {
    if (self.try_acquire_index()) |idx| return idx;
    const full_mask = (@as(u32, 1) << @intCast(self.capacity)) - 1;
    self.mutex.lock();
    defer self.mutex.unlock();
    while (true) {
        const current = self.occupancy.load(.acquire);
        
        if (current < full_mask) {
            if (self.try_acquire_index()) |idx| return idx;
        }

        self.cond.wait(&self.mutex);
    }
}

fn release_index(self: *Self, index: usize) void {
    const mask = @as(u32, 1) << @intCast(index);
    _ = self.occupancy.fetchAnd(~mask, .release);
    self.cond.signal();
}