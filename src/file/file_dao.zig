const std = @import("std");
const File = @import("file.zig").File;

const Allocator = std.mem.Allocator;

const Self = @This();

ptr: *anyopaque,
create_table_if_not_exists_fn: *const fn (ptr: *anyopaque) anyerror!void,
get_file_fn: *const fn (ptr: *anyopaque, allocator: Allocator, id: u64) anyerror!?File ,
get_file_by_hash_fn: *const fn (ptr: *anyopaque, allocator: Allocator, hash: []const u8) anyerror!?File,
insert_file_fn: *const fn (ptr: *anyopaque, entity: File) anyerror!?u64,
delete_file_fn: *const fn (ptr: *anyopaque, id: u64) anyerror!void,
delete_file_by_hash_fn: *const fn (ptr: *anyopaque, hash: []const u8) anyerror!void,
list_file_by_ids_fn: *const fn (ptr: *anyopaque, allocator: Allocator, ids: []const u64) anyerror!?[]File,
list_file_by_ids_string_fn: *const fn (ptr: *anyopaque, allocator: Allocator, ids: []const u8) anyerror!?[]File,
delete_useless_file_fn: *const fn (ptr: *anyopaque, allocator: Allocator, batch: usize) anyerror!?[][]const u8,

pub fn create_table_if_not_exists(self: Self) anyerror!void {
    return self.create_table_if_not_exists_fn(self.ptr);
}

pub fn get_file(self: Self, allocator: Allocator, id: u64) anyerror!?File {
    return self.get_file_fn(self.ptr, allocator, id);
}

pub fn get_file_by_hash(self: Self, allocator: Allocator, hash: []const u8) anyerror!?File {
    return self.get_file_by_hash_fn(self.ptr, allocator, hash);
}

pub fn list_file_by_ids(self: Self, allocator: Allocator, ids: []const u64) anyerror!?[]File {
    return self.list_file_by_ids_fn(self.ptr, allocator, ids);
}

pub fn list_file_by_ids_string(self: Self, allocator: Allocator, ids: []const u8) anyerror!?[]File {
    return self.list_file_by_ids_string_fn(self.ptr, allocator, ids);
}

pub fn insert_file(self: Self, entity: File) anyerror!?u64 {
    return self.insert_file_fn(self.ptr, entity);
}

pub fn delete_file(self: Self, id: u64) anyerror!void {
    return self.delete_file_fn(self.ptr, id);
}

pub fn delete_file_by_hash(self: Self, hash: []const u8) anyerror!void {
    return self.delete_file_by_hash_fn(self.ptr, hash);
}

pub fn delete_useless_file(self: Self, allocator: Allocator, batch: usize) anyerror!?[][]const u8 {
    return self.delete_useless_file_fn(self.ptr, allocator, batch);
}