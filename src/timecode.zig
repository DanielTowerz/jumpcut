const std = @import("std");

pub fn fcpData(start: f64, end: f64, current_offset: i64) struct { start: i64, duration: i64, offset: i64 } {
    const istart = @as(i64, @intFromFloat(@round(start)));
    const iend = @as(i64, @intFromFloat(@round(end)));
    const duration: i64 = iend - istart;
    const offset = current_offset + duration;
    if (duration < 1) {
        return .{ .start = 0, .duration = 0, .offset = 0 };
    }
    return .{ .start = istart, .duration = duration, .offset = offset };
}
