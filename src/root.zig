//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const VariableRouter = @import("variable_router.zig").VariableRouter;
pub const WrapperRouter = @import("variable_router.zig").WrapperRouter;
pub const RouterOptions = @import("variable_router.zig").RouterOptions;
pub const PasteController = @import("paste_controller.zig");
pub const common = @import("common");

pub fn get_config(allocator: std.mem.Allocator, file_path: ?[]const u8) !common.Options.JsonOptions {
    const content = if (file_path) |f| blk: {
        const result = try std.fs.cwd().readFileAlloc(allocator, f, 102400);
        std.debug.print("Loading config from: {s}\n", .{ f });
        break :blk result;
    } else blk: {
        std.debug.print("Use default config\n", .{});
        break :blk @embedFile("config.json");
    };
    const parsed = try std.json.parseFromSlice(
        common.Options.JsonOptions, 
        allocator, 
        content, 
        .{ .ignore_unknown_fields = true }
    );
    return parsed.value;
}

test {
    std.testing.refAllDecls(@This());
}