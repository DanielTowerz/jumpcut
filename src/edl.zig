const std = @import("std");

pub fn setHead(
    output_str: *std.ArrayList(u8),
    title: []const u8,
) !void {
    var writer = output_str.writer();
    try writer.print(
        \\TITLE: {s}
        \\FCM: NON-DROP FRAME
        \\
        \\
    , .{title});
    // return try buffer.toOwnedSlice();
    // try output_file.write(buffer.items);
}

pub fn getEdlLine(
    // allocator: std.mem.Allocator,
    output_str: *std.ArrayList(u8),
    index: f64,
    offset: f64,
    start: f64,
    end: f64,
    clip_frame_rate: f64,
    add: f16,
) !f64 {
    const duration = end - start;
    const edl_start = try secondsToSMPTETimecode(start - add, clip_frame_rate);
    const edl_end = try secondsToSMPTETimecode(end + add, clip_frame_rate);
    const edl_edit_start = try secondsToSMPTETimecode(offset, clip_frame_rate);
    const new_offset = offset + duration + (add * 2);
    const edl_edit_end = try secondsToSMPTETimecode(new_offset, clip_frame_rate);

    // var buffer = std.ArrayList(u8).init(allocator);
    var writer = output_str.writer();
    try writer.print(
        \\{d:0>3}  AX       AA/V  C        {d:0>2}:{d:0>2}:{d:0>2}:{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}  {d:0>2}:{d:0>2}:{d:0>2}:{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}
        \\* FROM CLIP NAME:  {s}{s}
    , .{
        index,
        edl_start.hours,
        edl_start.minutes,
        edl_start.seconds,
        edl_start.frames,
        edl_end.hours,
        edl_end.minutes,
        edl_end.seconds,
        edl_end.frames,
        edl_edit_start.hours,
        edl_edit_start.minutes,
        edl_edit_start.seconds,
        edl_edit_start.frames,
        edl_edit_end.hours,
        edl_edit_end.minutes,
        edl_edit_end.seconds,
        edl_edit_end.frames,
        "/Users/daniel/D17.mp4",
        "\n\n",
    });
    return new_offset;
}

fn secondsToSMPTETimecode(
    // allocator: std.mem.Allocator,
    sec: f64,
    clip_frame_rate: f64,
) !struct { hours: f64, minutes: f64, seconds: f64, frames: f64 } {
    // const clip_frame_rate = 23.976;
    const round_frames = @round(clip_frame_rate);
    const clip_frames = @floor(sec * clip_frame_rate);
    var clip_seconds = @floor(clip_frames / round_frames);

    if (clip_seconds < 0) {
        clip_seconds = 0;
    }

    const smpte_hours = @floor((clip_seconds / 60) / 60);
    const smpte_minutes = @floor(@mod((clip_seconds / 60), 60));
    const smpte_seconds = @floor(@mod(clip_seconds, 60));
    const smpte_frames = @mod(clip_frames, round_frames);
    return .{ .hours = smpte_hours, .minutes = smpte_minutes, .seconds = smpte_seconds, .frames = smpte_frames };

    // var buffer = std.ArrayList(u8).init(allocator);
    // var writer = buffer.writer();
    // try writer.print("{d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}", .{ smpte_hours, smpte_minutes, smpte_seconds, smpte_frames });
    //
    // return buffer.toOwnedSlice();
}
