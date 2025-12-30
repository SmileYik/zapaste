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

inline fn get_file_path(self: *Self, allocator: Allocator, filename: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
        self.store_path, filename[0..2], filename[2..4], filename
    });
}

inline fn file_hash(allocator: Allocator, bytes: []const u8) ![]const u8 {
    var hash: [64]u8 = undefined;
    std.crypto.hash.sha2.Sha512.hash(bytes, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{
        std.fmt.bytesToHex(hash, .upper)
    });
}
// std.crypto.hash.sha2.Sha512