const std = @import("std");
const File = @import("file.zig").File;
const FileDao = @import("file_dao.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

pub const FileError = error {
    StoreFailed,
};

dao: *FileDao,
store_path: []const u8,

pub fn save_file(
    self: *Self, 
    data: ?[]const u8, 
    mimetype: ?[]const u8,
    filename: ?[]const u8,
) !?u64 {
    if (data) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_a = arena.allocator();
        const hash = file_hash(temp_a, bytes) catch {
            return FileError.StoreFailed;
        };

        if (try self.dao.get_file_by_hash(temp_a, hash)) |f| {
            return f.id;
        }

        // real store.
        const store_path = self.get_file_path(temp_a, hash) catch {
            return FileError.StoreFailed;
        };
        const parent_path = store_path[0..store_path.len - hash.len];
        std.fs.cwd().makePath(parent_path) catch {
            return FileError.StoreFailed;
        };
        std.fs.cwd().writeFile(.{ .data = bytes, .sub_path = store_path }) catch {
            return FileError.StoreFailed;
        };
        return self.dao.insert_file(.{
            .filename = filename,
            .filesize = @intCast(bytes.len),
            .filepath = null,
            .hash = hash,
            .mimetype = mimetype
        });
    }
    return null;
}

pub fn list_file_by_ids_string(self: *Self, allocator: Allocator, ids: []const u8) !?[]File {
    return self.dao.list_file_by_ids_string(allocator, ids);
}

pub fn get_file_disk_path(self: *Self, allocator: Allocator, hash: []const u8) ![]const u8 {
    return try self.get_file_path(allocator, hash);
}

pub fn clean_files(self: *Self, allocator: Allocator) !void {
    var a = std.heap.ArenaAllocator.init(allocator);
    defer a.deinit();
    const alloc = a.allocator();

    while (true) {
        const list: ?[][]const u8 = try self.dao.delete_useless_file(alloc, 100);
        if (list) |l| {
            if (l.len == 0) break;
            for (l) |item| {
                const store_path = self.get_file_path(alloc, item) catch {
                    continue;
                };
                delete_file_and_empty_parents(store_path) catch |e| {
                    std.debug.print("failed to clean file '{s}': {}\n", .{ store_path, e });
                    continue;
                };
            }
        }
    }
}

inline fn delete_file_and_empty_parents(path: []const u8) !void {
    try std.fs.cwd().deleteFile(path);

    var parent_path = std.fs.path.dirname(path);

    while (parent_path) |p| {
        if (p.len == 0 or std.mem.eql(u8, p, ".")) break;

        std.fs.cwd().deleteDir(p) catch |err| {
            switch (err) {
                error.DirNotEmpty => break,
                error.AccessDenied => return err,
                error.FileNotFound => break,
                else => return err,
            }
        };

        parent_path = std.fs.path.dirname(p);
    }
}

inline fn get_file_path(self: *Self, allocator: Allocator, filename: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
        self.store_path, filename[0..2], filename[2..4], filename
    });
}

inline fn file_hash(allocator: Allocator, bytes: []const u8) ![]const u8 {
    var hash: [64]u8 = undefined;
    std.crypto.hash.sha3.Sha3_512.hash(bytes, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{
        std.fmt.bytesToHex(hash, .upper)
    });
}