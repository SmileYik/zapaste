const std = @import("std");

pub fn file(comptime file_path: []const u8) []const u8 {
    return @embedFile(file_path);
} 