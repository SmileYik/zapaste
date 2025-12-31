//!
//! A solution for issue: https://github.com/zigzap/zap/issues/187.
//!
//! some find file code is Zap's copy.
//!

const std = @import("std");
const zap = @import("zap");
const fio = zap.fio;

const Allocator = std.mem.Allocator;

const Self = @This();

pub const TaskType = enum {
    GetFile,
    GetFileFromArray,
    GetFileCount,
    GetParams,
    GetString,
};

pub const Task = union(TaskType) {

    /// get file task
    GetFile: struct {
        result: ?RequestFile = null
    },

    /// get file from array, you must pass `index` param for this task
    GetFileFromArray: struct {
        index: isize,
        result: ?RequestFile = null
    },

    /// get file count of special param name
    /// if result is 1 then you must use `GetFile` to get file, 
    /// else if result is gt then 1 then you must use `GetFileFromArray`
    GetFileCount: struct {
        result: ?usize = null
    },

    /// get requests params name
    GetParams: struct {
        result: ?std.ArrayList([]const u8) = null,
    },

    /// get params value as string, not include files.
    GetString: struct {
        const GetStringType = @This();

        result: ?[]const u8 = null,
        need_deinit: ?bool = null,

        pub fn deinit(self: GetStringType, allocator: Allocator) void {
            if (self.need_deinit) |flag| {
                if (flag) {
                    if (self.result) |r| {
                        allocator.free(r);
                    }
                }
            }
        } 
    }
};

pub const RequestFile = struct {
    data: ?[]const u8 = null,
    mimetype: ?[]const u8 = null,
    filename: ?[]const u8 = null,
};

allocator: std.mem.Allocator,
param_name: ?[]const u8,
task: Task,
last_error: ?anyerror = null,

inline fn get(allocator: Allocator, r: zap.Request, param_name: []const u8, task: Task) !Task {
    var context: Self = .{ 
        .allocator = allocator,
        .param_name = param_name,
        .task = task
    };
    _ = fio.fiobj_each1(r.h.*.params, 0, Self.callback, &context);
    if (context.last_error) |e| return e;
    return context.task;
}

/// find request params, all emelems in array list need to free.
pub fn find_params(allocator: Allocator, r: zap.Request) !?std.ArrayList([]const u8) {
    var context: Self = .{ 
        .allocator = allocator,
        .param_name = null,
        .task = .{
            .GetParams = .{}
        }
    };
    _ = fio.fiobj_each1(r.h.*.params, 0, Self.callback, &context);
    if (context.last_error) |e| return e;
    return context.task.GetParams.result;
}

/// get request param value as string, need to free.
pub fn get_string(allocator: Allocator, r: zap.Request, param_name: []const u8) !?[]const u8 {
    const task = try get(allocator, r, param_name, .{ .GetString = .{} });
    return task.GetString.result;
}

pub fn get_file_count(allocator: Allocator, r: zap.Request, param_name: []const u8) !?usize {
    const task = try get(allocator, r, param_name, .{ .GetFileCount = .{} });
    return task.GetFileCount.result;
}

/// get requests files
pub fn get_file(allocator: Allocator, r: zap.Request, param_name: []const u8, file_count: ?usize, file_index: usize) !?RequestFile {
    if (file_count) |count| if (count == 1) {
        const task = try get(allocator, r, param_name, .{ .GetFile = .{} });
        return task.GetFile.result;
    } else if (count > 1) {
        const task = try get(allocator, r, param_name, .{ .GetFileFromArray = .{ .index = @intCast(file_index) } });
        return task.GetFileFromArray.result;
    };
    return null;
}

pub fn callback(fiobj_value: fio.FIOBJ, context_: ?*anyopaque) callconv(.c) c_int {
    const ctx: *Self = @as(*Self, @ptrCast(@alignCast(context_)));

    const fiobj_key: fio.FIOBJ = fio.fiobj_hash_key_in_loop();
    const key = zap.util.fio2strAlloc(ctx.allocator, fiobj_key) catch |err| {
        ctx.last_error = err;
        return -1;
    };
    defer ctx.allocator.free(key);

    if (ctx.param_name) |param_name| {
        if (std.mem.eql(u8, param_name, key)) {
            switch (ctx.task) {
                .GetFile => |*p| {
                    p.*.result = getBinfile(fiobj_value) catch |e| {
                        ctx.last_error = e;
                        return -1;
                    };
                    return -1;
                },
                .GetFileFromArray => |*p| {
                    p.*.result = getBinfileFromArray(fiobj_value, p.index) catch |e| {
                        ctx.last_error = e;
                        return -1;
                    };
                    return -1;
                },
                .GetFileCount => |*p| {
                    p.*.result = getBinfileArrayLen(fiobj_value) catch |e| {
                        ctx.last_error = e;
                        return -1;
                    };
                    return -1;
                },
                .GetString => |*p| {
                    const str, const need_deinit = getStringData(ctx.allocator, fiobj_value) catch |e| {
                        ctx.last_error = e;
                        return -1;
                    };
                    p.*.result = str;
                    p.*.need_deinit = need_deinit;
                    return -1;
                },
                else => return -1
            }
        }
    } else switch (ctx.task) {
        .GetParams => |*p| {
            if (p.*.result == null) {
                p.*.result = std.ArrayList([]const u8).initCapacity(ctx.allocator, 16) catch |e| {
                    ctx.last_error = e;
                    return -1;
                };
            }
            p.*.result.?.append(ctx.allocator, ctx.allocator.dupe(u8, key) catch |e| {
                ctx.last_error = e;
                return -1;
            }) catch |e| {
                ctx.last_error = e;
                return -1;
            };
        },
        else => return -1
    }
    
    return 0;
}

inline fn getMimetype(o: fio.FIOBJ, key_type_wrapper: ?usize) []const u8 {
    const key_type = if (key_type_wrapper) |t| t else fio.fiobj_str_new("type", 4);
    defer {
        if (key_type_wrapper == null) {
            fio.fiobj_free_wrapped(key_type);
        }
    }

    var mimetype: []const u8 = undefined;
    if (fio.fiobj_hash_haskey(o, key_type) == 1) {
        const mt_fiobj = fio.fiobj_hash_get(o, key_type);
        // for some reason, mimetype can be an array
        if (fio.fiobj_type_is(mt_fiobj, fio.FIOBJ_T_STRING) == 1) {
            const mt = fio.fiobj_obj2cstr(mt_fiobj);
            mimetype = mt.data[0..mt.len];
        } else {
            mimetype = &"application/octet-stream".*;
        }
    } else {
        mimetype = &"application/octet-stream".*;
    }
    return mimetype;
}

inline fn getBinfileFromArray(o: fio.FIOBJ, i: isize) !RequestFile {
    const key_name = fio.fiobj_str_new("name", 4);
    const key_data = fio.fiobj_str_new("data", 4);
    const key_type = fio.fiobj_str_new("type", 4);
    defer {
        fio.fiobj_free_wrapped(key_name);
        fio.fiobj_free_wrapped(key_data);
        fio.fiobj_free_wrapped(key_type);
    } // files: they should have "data" and "filename" keys
    if (fio.fiobj_hash_haskey(o, key_data) == 1 and fio.fiobj_hash_haskey(o, key_name) == 1) {
        const data = fio.fiobj_hash_get(o, key_data);

        switch (fio.fiobj_type(data)) {
            fio.FIOBJ_T_ARRAY => {
                // OK, data is an array
                const len = fio.fiobj_ary_count(data);
                const fn_ary = fio.fiobj_hash_get(o, key_name);
                const mt_ary = fio.fiobj_hash_get(o, key_type);

                if (i < len and fio.fiobj_ary_count(fn_ary) == len and fio.fiobj_ary_count(mt_ary) == len) {
                    const file_data_obj = fio.fiobj_ary_entry(data, i);
                    const file_name_obj = fio.fiobj_ary_entry(fn_ary, i);
                    const file_mimetype_obj = fio.fiobj_ary_entry(mt_ary, i);
                    var has_error: bool = false;
                    if (fio.is_invalid(file_data_obj) == 1) {
                        zap.log.debug("file data invalid in array", .{});
                        has_error = true;
                    }
                    if (fio.is_invalid(file_name_obj) == 1) {
                        zap.log.debug("file name invalid in array", .{});
                        has_error = true;
                    }
                    if (fio.is_invalid(file_mimetype_obj) == 1) {
                        zap.log.debug("file mimetype invalid in array", .{});
                        has_error = true;
                    }
                    if (has_error) {
                        return error.Invalid;
                    }

                    const file_data = fio.fiobj_obj2cstr(file_data_obj);
                    const file_name = fio.fiobj_obj2cstr(file_name_obj);
                    const file_mimetype = fio.fiobj_obj2cstr(file_mimetype_obj);
                    return .{
                        .data = file_data.data[0..file_data.len],
                        .mimetype = file_mimetype.data[0..file_mimetype.len],
                        .filename = file_name.data[0..file_name.len],
                    };
                } else {
                    return error.ArrayLenMismatch;
                }
            },
            else => {
                // don't know what to do
                return error.Unsupported;
            },
        }
    }
    return error.Unsupported;
}

inline fn getBinfileArrayLen(o: fio.FIOBJ) !usize {
    const key_name = fio.fiobj_str_new("name", 4);
    const key_data = fio.fiobj_str_new("data", 4);
    const key_type = fio.fiobj_str_new("type", 4);
    defer {
        fio.fiobj_free_wrapped(key_name);
        fio.fiobj_free_wrapped(key_data);
    } // files: they should have "data" and "filename" keys
    if (fio.fiobj_hash_haskey(o, key_data) == 1 and fio.fiobj_hash_haskey(o, key_name) == 1) {
        const data = fio.fiobj_hash_get(o, key_data);

        switch (fio.fiobj_type(data)) {
            fio.FIOBJ_T_DATA => return 1,
            fio.FIOBJ_T_STRING => return 1,
            fio.FIOBJ_T_ARRAY => {
                // OK, data is an array
                const len = fio.fiobj_ary_count(data);
                const fn_ary = fio.fiobj_hash_get(o, key_name);
                const mt_ary = fio.fiobj_hash_get(o, key_type);

                if (fio.fiobj_ary_count(fn_ary) == len and fio.fiobj_ary_count(mt_ary) == len) {
                    return len;
                } else {
                    return error.ArrayLenMismatch;
                }
            },
            else => {},
        }
    }

    // not file array
    return error.Unsupported;
}

inline fn getBinfile(o: zap.fio.FIOBJ) !RequestFile {
    const key_name = fio.fiobj_str_new("name", 4);
    const key_data = fio.fiobj_str_new("data", 4);
    const key_type = fio.fiobj_str_new("type", 4);
    defer {
        fio.fiobj_free_wrapped(key_name);
        fio.fiobj_free_wrapped(key_data);
        fio.fiobj_free_wrapped(key_type);
    } // files: they should have "data" and "filename" keys
    if (fio.fiobj_hash_haskey(o, key_data) == 1 and fio.fiobj_hash_haskey(o, key_name) == 1) {
        const filename = fio.fiobj_obj2cstr(fio.fiobj_hash_get(o, key_name));
        const data = fio.fiobj_hash_get(o, key_data);

        const mimetype: []const u8 = getMimetype(o, key_type);
        var data_slice: ?[]const u8 = null;

        switch (fio.fiobj_type(data)) {
            fio.FIOBJ_T_DATA => data_slice = readData(data),
            fio.FIOBJ_T_STRING => {
                const fiostr = fio.fiobj_obj2cstr(data);
                if (fiostr.len == 0) {
                    data_slice = "(zap: empty string data)";
                    zap.log.warn("WARNING: HTTP param binary file has empty string object\n", .{});
                } else {
                    data_slice = fiostr.data[0..fiostr.len];
                }
            },
            else => {
                // don't know what to do
                return error.Unsupported;
            },
        }

        return .{
            .filename = filename.data[0..filename.len],
            .mimetype = mimetype,
            .data = data_slice,
        };
    } else {
        return .{};
    }
}

/// return the string and the flag about it need free or not
inline fn getStringData(allocator: Allocator, data: zap.fio.FIOBJ) !struct {
    ?[]const u8, bool
} {
    const param_type = fio.fiobj_type(data);
    return if (param_type == fio.FIOBJ_T_DATA) .{ 
        readData(data), false
    } else .{
        try zap.util.fio2strAlloc(allocator, data), true
    };
}

inline fn readData(data: zap.fio.FIOBJ) ?[]const u8 {
    var data_slice: ?[]const u8 = null;

    if (fio.is_invalid(data) == 1) {
        data_slice = "(zap: invalid data)";
        zap.log.warn("HTTP param binary file is not a data object", .{});
    } else {
        const data_len = fio.fiobj_data_len(data);
        var data_buf = fio.fiobj_data_read(data, data_len);
        if (data_len < 0) {
            zap.log.warn("HTTP param binary file size negative: {d}", .{data_len});
            zap.log.warn("FIOBJ_TYPE of data is: {d}", .{fio.fiobj_type(data)});
        } else {
            if (data_buf.len != data_len) {
                zap.log.warn("HTTP param binary file size mismatch: should {d}, is: {d}", .{ data_len, data_buf.len });
            }

            if (data_buf.len > 0) {
                data_slice = data_buf.data[0..data_buf.len];
            } else {
                zap.log.warn("HTTP param binary file buffer size negative: {d}", .{data_buf.len});
                data_slice = "(zap: invalid data: negative BUFFER size)";
            }
        }
    }
    
    return data_slice;
}