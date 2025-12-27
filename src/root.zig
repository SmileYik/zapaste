//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const VariableRouter = @import("variable_router.zig").VariableRouter;

test {
    std.testing.refAllDecls(@This());
}