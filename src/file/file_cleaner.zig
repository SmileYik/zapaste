const std = @import("std");
const common = @import("common");
const FileService = @import("file_service.zig");

const Allocator = std.mem.Allocator;

const FileCleaner = struct {
    
    file_service: *FileService = undefined,
    allocator: Allocator,

    pub fn task_callback(self: FileCleaner) !void {
        self.file_service.clean_files(self.allocator) catch |e| {
            std.debug.print("failed clean file: {}\n", .{e});
        };
        std.debug.print("finshed clean file\n", .{});
    }

    pub fn finish_callback(self: FileCleaner) !void {
        _ = self;
        std.debug.print("Cancel file cleaner\n", .{});
    }
};

const FileCleanerTimer = common.fio_timer.FIOTimer(FileCleaner);

pub fn register_file_cleaner(allocator: Allocator, file_service: *FileService, options: *common.Options) !void {
    const timer = try FileCleanerTimer.init(allocator, .{
        .file_service = file_service,
        .allocator = allocator
    });
    try timer.run_every(options.file_clean_frequency, 0);
    std.debug.print("Clean File every {}s\n", .{ options.file_clean_frequency / 1000 });
}