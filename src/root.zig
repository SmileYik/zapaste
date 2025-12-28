//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const paste = @import("paste");
pub const common = @import("common");

pub fn get_config(allocator: std.mem.Allocator, file_path: ?[]const u8) !common.Options {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const read_json_allocator = arena.allocator();

    const options_json = get_json_config(read_json_allocator, file_path)
    catch |e| {
        std.debug.print("Failed to load config: {}\n", .{e});
        return e;
    };

    std.debug.print(
        \\
        \\ Loading config:
        \\ {f}
        \\
        , 
        .{ std.json.fmt(options_json, .{ .whitespace = .indent_4 }) }
    );

    return try common.Options.init(allocator, options_json);
}

fn get_json_config(allocator: std.mem.Allocator, file_path: ?[]const u8) !common.Options.JsonOptions {
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