//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const VariableRouter = @import("variable_router.zig").VariableRouter;
pub const WrapperRouter = @import("variable_router.zig").WrapperRouter;
pub const RouterOptions = @import("variable_router.zig").RouterOptions;
pub const PasteController = @import("paste_controller.zig");
pub const common = @import("common");

test {
    std.testing.refAllDecls(@This());
}