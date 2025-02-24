const std = @import("std");

pub fn getHead(
    allocator: std.mem.Allocator,
    title: []const u8,
) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.print(
        \\TITLE: {s}
        \\FCM: NON-DROP FRAME
        \\
        \\
    , .{title});
    return try buffer.toOwnedSlice();
}

pub fn getEdlLine(
    // Comment to avoid formatting by the editor
    allocator: std.mem.Allocator,
    index: f64,
    current_start: f64,
    start: f64,
    end: f64,
    duration: f64,
    // Comment to avoid formatting by the editor
) !struct { line: ?[]const u8, current_start: f64 } {
    // 00:00:10:00 00:00:15:12  00:00:00:00 00:00:05:12
    // ---fuente-- --fuente--   --edit--     --edit--
    // ---start--- --end---     --c_start--  --c_start + duration--
    const add = 0.3;
    const edl_start = try secondsToSMPTETimecode(allocator, start - add);
    const edl_end = try secondsToSMPTETimecode(allocator, end + add);
    // current_start = current_start + 1;
    const edl_edit_start = try secondsToSMPTETimecode(allocator, current_start);
    // duration = duration + 2;
    const edl_edit_end = try secondsToSMPTETimecode(allocator, current_start + duration + (add * 2));

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    writer.print(
        \\{d:0>3}  AX       AA/V  C        {s} {s}  {s} {s}
        \\* FROM CLIP NAME:  {s}{s}
    , .{
        index,                   edl_start, edl_end, edl_edit_start, edl_edit_end,
        "/Users/daniel/D17.mp4", "\n\n",
    }) catch {
        return .{ .line = null, .current_start = current_start };
    };
    return .{ .line = try buffer.toOwnedSlice(), .current_start = current_start + duration + (add * 2) };
}

fn secondsToSMPTETimecode(
    // Comment to avoid formatting by the editor
    allocator: std.mem.Allocator,
    sec: f64,
) ![]const u8 {
    // std.debug.print("sec: {d}\n", .{sec});
    const fps = 23.976;
    const frame_number = @floor(sec * fps);
    // std.debug.print("frame_number: {d}\n", .{frame_number});
    const frame_round = @round(fps);
    const frames = @mod(frame_number, frame_round);
    const seconds = @floor(@mod((frame_number / frame_round), 60));
    const minutes = @floor(@mod(((frame_number / frame_round) / 60), 60));
    const hours = @floor((((frame_number / frame_round) / 60) / 60));
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.print("{d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds, frames });

    // const ttf = timecodeToFrames(hours, minutes, seconds, frames);
    // std.debug.print("ttf: {d}\n", .{ttf});
    //
    // const stf = framesToSeconds(ttf);
    // std.debug.print("stf: {d}\n", .{stf});

    return buffer.toOwnedSlice();
}

// fn timecodeToFrames(hours: f64, minutes: f64, seconds: f64, frames: f64) f64 {
//     return (hours * 3600 + minutes * 60 + seconds) * 24 + frames;
// }
//
// fn framesToSeconds(frames: f64) f64 {
//     const numerator = frames * 1001;
//     const denominator = 23976;
//     return numerator / denominator;
// }
