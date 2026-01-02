// 
// Creates a timer to run a task at the specified interval.
// 
// The task will repeat `repetitions` times. If `repetitions` is set to 0, task
// will repeat forever.
//
// Returns -1 on error.
//
// The `on_finish` handler is always called (even on error).
// 
pub extern fn fio_run_every(
    milliseconds: usize,
    repetitions: usize,
    task: *const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
    on_finish: ?*const fn (?*anyopaque) callconv(.c) void,
) c_int;