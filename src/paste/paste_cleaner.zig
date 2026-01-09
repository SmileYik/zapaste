const std = @import("std");
const common = @import("common");
const PasteService = @import("paste_service.zig").PasteService;

const Allocator = std.mem.Allocator;

const PasteCleaner = struct {
    
    paste_service: *PasteService = undefined,

    pub fn task_callback(self: PasteCleaner) !void {
        self.paste_service.clean_paste() catch |e| {
            std.debug.print("failed clean paste: {}\n", .{e});
        };
        std.debug.print("finshed clean paste\n", .{});
    }

    pub fn finish_callback(self: PasteCleaner) !void {
        _ = self;

        std.debug.print("Cancel paste cleaner\n", .{});
    }
};

const PasteCleanerTimer = common.fio_timer.FIOTimer(PasteCleaner);

pub fn register_paste_cleaner(allocator: Allocator, paste_service: *PasteService, options: *common.Options) !*common.fio_timer.FIOTimer(PasteCleaner) {
    const timer = try PasteCleanerTimer.init(allocator, .{
        .paste_service = paste_service
    });
    try timer.run_every(@intCast(options.paste_clean_frequency), 0);
    std.debug.print("Clean Paste every {}s\n", .{ options.paste_clean_frequency / 1000 });
    return timer;
}