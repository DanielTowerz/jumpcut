const std = @import("std");
const av = @import("av");
const Date = @import("date.zig");
const EDL = @import("edl.zig");

pub extern "c" fn vsnprintf(
    buffer: [*c]u8,
    size: usize,
    format: [*c]const u8,
    args: *anyopaque,
) c_int;

const ADD = 0.3;
const DB: i64 = -25;
const SILENCE_DURATION: f64 = 1.0;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const fcpxml_allocator = arena.allocator();
var fcpxml_lines = std.ArrayList([]const u8).init(fcpxml_allocator);
var raw_lines = std.ArrayList([]const u8).init(fcpxml_allocator);
var dialogue_start: f64 = 0.0;
var dialogue_end: f64 = 0.0;
var cur_offset: f64 = 0.0;
var cur_clip_index: f64 = 0;
// var total_duration: f64 = 0.0;
const timebase: u64 = 12000;
const av_time_base: f64 = 1000000.0;

const VideoFile = struct {
    width: c_int,
    height: c_int,
    duration: f64,
    audio_rate: c_int,
    avgFrameRate: struct {
        num: c_int,
        den: c_int,
    },
    audio_channels: c_int,
    mod_date: Date.DateType,
    file_path: [:0]const u8,
    audio_codec: *av.Codec.Parameters,
    pub fn name(self: *VideoFile) []const u8 {
        return std.fs.path.stem(self.file_path);
    }
    pub fn frameRate(self: *VideoFile) f64 {
        const fps = tof64(self.avgFrameRate.num) / tof64(self.avgFrameRate.den);
        return @round(fps * 1000) / 1000;
    }
    pub fn avgFrameRateDuration(self: *VideoFile) f64 {
        const num = tof64(self.avgFrameRate.num);
        const den = tof64(self.avgFrameRate.den);
        return den / num;
    }
};

var video_file = VideoFile{
    .width = 0,
    .height = 0,
    .duration = 0,
    .audio_rate = 0,
    .avgFrameRate = .{ .num = 0, .den = 0 },
    .audio_channels = 0,
    .audio_codec = undefined,
    .mod_date = undefined,
    .file_path = undefined,
};

pub fn main() !void {
    std.debug.print("add: {d}, db: {d}, silence_duration: {d}\n", .{ ADD, DB, SILENCE_DURATION });
    defer arena.deinit();

    video_file.file_path = "/home/daniel/codes/zig/D17.mp4";
    video_file.mod_date = try Date.ISO_8601(fcpxml_allocator);
    av.av_log_set_callback(&logCallback);

    const fc = try av.FormatContext.open_input(video_file.file_path, null, null, null);
    defer fc.close_input();
    const audio_stream_index = try getMediaStreams(fc, &video_file);

    const buffers = try getFilters(&video_file);
    defer buffers.fg.free();

    const pkt = try av.Packet.alloc();
    defer pkt.unref();

    const frame = try av.Frame.alloc();
    defer frame.unref();

    const codec = try av.Codec.find_decoder(video_file.audio_codec.codec_id);
    const codec_ctx = try av.Codec.Context.alloc(codec);
    defer codec_ctx.free();
    try codec_ctx.parameters_to_context(video_file.audio_codec);
    try codec_ctx.open(codec, null);
    while (true) {
        fc.read_frame(pkt) catch |err| switch (err) {
            error.EndOfFile => break,
            else => return err,
        };

        if (pkt.stream_index != audio_stream_index) {
            continue;
        }

        try codec_ctx.send_packet(pkt);
        while (true) {
            codec_ctx.receive_frame(frame) catch |err| switch (err) {
                error.WouldBlock => break,
                error.EndOfFile => break,
                else => return err,
            };

            try buffers.abuffer.buffersrc_add_frame(frame);

            const samples_per_frame = frame.nb_samples;

            while (true) {
                const processed_frame = av.Frame.alloc() catch break;
                defer processed_frame.unref();
                buffers.abuffersink.buffersink_get_samples(processed_frame, samples_per_frame) catch |err| switch (err) {
                    error.WouldBlock => break,
                    error.EndOfFile => break,
                    else => return err,
                };
            }
        }
    }

    // const head = fcxml_1_8_start(fcpxml_allocator) catch |err| {
    // std.debug.print("Error al agregar inicio de fcpxml: {}\n", .{err});
    // return;
    // };
    const head = EDL.getHead(fcpxml_allocator, video_file.name()) catch |err| {
        std.debug.print("Error al agregar inicio de fcpxml: {}\n", .{err});
        return;
    };
    fcpxml_lines.insert(0, head) catch |err| {
        std.debug.print("Error al agregar inicio de fcpxml: {}\n", .{err});
        return;
    };
    // const tail = fcxml_1_8_end(fcpxml_allocator) catch |err| {
    //     std.debug.print("Error al agregar fin de fcpxml: {}\n", .{err});
    //     return;
    // };
    // fcpxml_lines.append(tail) catch |err| {
    //     std.debug.print("Error al agregar fin de fcpxml: {}\n", .{err});
    //     return;
    // };

    const file = try std.fs.cwd().createFile("output.edl", .{});
    defer file.close();
    for (fcpxml_lines.items) |line| {
        try file.writeAll(line);
    }

    // const raw_file = try std.fs.cwd().createFile("raw.json", .{});
    // defer raw_file.close();
    // for (raw_lines.items) |line| {
    //     try raw_file.writeAll(line);
    // }
    std.debug.print("Archivo escrito correctamente.\n", .{});
}

fn tof64(num: anytype) f64 {
    return @as(f64, @floatFromInt(num));
}

fn makeFilterString(
    allocator: std.mem.Allocator,
    sample_rate: c_int,
    sample_fmt: []const u8,
    channel_layout: []const u8,
) ![:0]u8 {
    return try std.fmt.allocPrintZ(allocator, "sample_rate={d}:sample_fmt={s}:channel_layout={s}", .{ sample_rate, sample_fmt, channel_layout });
}

fn getFilters(
    vf: *VideoFile,
) !struct {
    fg: *av.FilterGraph,
    abuffer: *av.FilterContext,
    abuffersink: *av.FilterContext,
} {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var fg = try av.FilterGraph.alloc();
    const abuffer = try fg.alloc_filter(av.Filter.get_by_name("abuffer").?, "DNXabuffer");

    var filter_str: [:0]const u8 = undefined;
    defer allocator.free(filter_str);
    switch (vf.audio_codec.codec_id) {
        av.Codec.ID.AAC => {
            filter_str = try makeFilterString(allocator, 48000, "fltp", "stereo");
        },
        av.Codec.ID.PCM_S16LE => {
            filter_str = try makeFilterString(allocator, 48000, "s16", "stereo");
        },
        else => return error.UnsupportedAudioCodec,
    }

    try abuffer.init_str(filter_str);
    const silencedetect = try fg.alloc_filter(av.Filter.get_by_name("silencedetect").?, "DNXsilencedetect");
    const silence_str = try std.fmt.allocPrintZ(allocator, "n={d}dB:d={d}", .{ DB, SILENCE_DURATION });
    defer allocator.free(silence_str);
    try silencedetect.init_str(silence_str);
    try av.FilterContext.link(abuffer, 0, silencedetect, 0);
    const abuffersink = try fg.alloc_filter(av.Filter.get_by_name("abuffersink").?, "DNXabuffersink");
    try abuffersink.init_str("");
    try av.FilterContext.link(silencedetect, 0, abuffersink, 0);
    try fg.config(null);
    return .{ .fg = fg, .abuffer = abuffer, .abuffersink = abuffersink };
}

fn getMediaStreams(fc: *av.FormatContext, vf: *VideoFile) !usize {
    try fc.find_stream_info(null);
    var has_audio = false;
    var audio_stream_index: usize = 0;
    has_audio = for (0..fc.nb_streams) |i| {
        if (fc.streams[i].codecpar.codec_type == av.MediaType.VIDEO) {
            vf.width = fc.streams[i].codecpar.width;
            vf.height = fc.streams[i].codecpar.height;
            vf.avgFrameRate.num = fc.streams[i].avg_frame_rate.num;
            vf.avgFrameRate.den = fc.streams[i].avg_frame_rate.den;
        }
        if (fc.streams[i].codecpar.codec_type == av.MediaType.AUDIO) {
            vf.audio_codec = fc.streams[i].codecpar;
            vf.audio_rate = fc.streams[i].codecpar.sample_rate;
            vf.audio_channels = fc.streams[i].codecpar.ch_layout.nb_channels;
            audio_stream_index = i;
            break true;
        }
    } else false;
    if (!has_audio) {
        return error.NoAudioStream;
    }
    vf.duration = tof64(fc.duration) / av_time_base;
    return audio_stream_index;
}

fn mayBeFloat(value: ?[]const u8) f64 {
    if (value) |v| {
        return std.fmt.parseFloat(f64, std.mem.trim(u8, v, " \n")) catch 0.0;
    }
    return 0.0;
}

const SilenceEvent = struct {
    start_or_end: f64,
    duration: f64,
    type: u8,

    pub fn init(message: []const u8, type_: u8) ?SilenceEvent {
        var duration: f64 = 0.0;
        var start_or_end: f64 = 0.0;
        var parts = std.mem.splitScalar(u8, message, ' ');
        _ = parts.first();
        start_or_end = mayBeFloat(parts.next());
        if (type_ > 0) {
            _ = parts.next();
            _ = parts.next();
            duration = mayBeFloat(parts.next());
        }
        return .{ .start_or_end = start_or_end, .duration = duration, .type = type_ };
    }
};

fn extractValue(message: []const u8) ?SilenceEvent {
    if (std.mem.indexOf(u8, message, "silence_start") != null) {
        //silence_start: 952.410875
        return SilenceEvent.init(message, 0);
    } else if (std.mem.indexOf(u8, message, "silence_end") != null) {
        return SilenceEvent.init(message, 1);
    }
    return null;
}

// fn fcxml_1_8_start(allocator: std.mem.Allocator) ![]const u8 {
//     var buffer = std.ArrayList(u8).init(allocator);
//     defer buffer.deinit();
//     var writer = buffer.writer();
//     try writer.print(
//         \\<?xml version="1.0" encoding="UTF-8"?>
//         \\<!DOCTYPE fcpxml>
//         \\<fcpxml version="1.11">
//         \\    <resources>
//         \\        <format id="r1" name="FFVideoFormat{d}p{d}" frameDuration="{d}/{d}s" width="{d}" height="{d}"/>
//         \\        <asset id="r2" name="D17" start="0s" duration="{d}/{d}s" hasVideo="1" format="r1" hasAudio="1" videoSources="1" audioSources="1" audioChannels="{d}" audioRate="{d}">
//         \\            <media-rep kind="original-media" src="file://{s}"/>
//         \\        </asset>
//         \\    </resources>
//         \\    <library>
//         \\       <event name="{s}">
//         \\           <project name="{s} Project" modDate="{s}">
//         \\               <sequence format="r1" duration="{d}/{d}s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="{d}">
//         \\                   <spine>{s}
//     , .{
//         video_file.height,
//         video_file.frameRate(),
//         video_file.avgFrameRate.den,
//         video_file.avgFrameRate.num,
//         video_file.width,
//         video_file.height,
//         @round(video_file.duration * tof64(video_file.avgFrameRate.num)),
//         video_file.avgFrameRate.num,
//         video_file.audio_channels,
//         video_file.audio_rate,
//         "/Users/daniel/D17.mp4", // video_file.file_path,
//         video_file.mod_date.full,
//         video_file.name(),
//         video_file.mod_date.y_m_d(),
//         @round(total_duration * tof64(video_file.avgFrameRate.num)),
//         video_file.avgFrameRate.num,
//         video_file.audio_rate,
//         "\n",
//     });
//     return buffer.toOwnedSlice();
// }

// fn fcxml_1_8_end(allocator: std.mem.Allocator) ![]const u8 {
//     var buffer = std.ArrayList(u8).init(allocator);
//     defer buffer.deinit();
//     var writer = buffer.writer();
//     try writer.print(
//         \\                    </spine>
//         \\                </sequence>
//         \\            </project>
//         \\        </event>
//         \\    </library>
//         \\</fcpxml>
//     , .{});
//     return buffer.toOwnedSlice();
// }

// fn formatTime(allocator: std.mem.Allocator, time: f64, key: []const u8, allow_empty: bool) ![]const u8 {
//     if (time == 0.0 and allow_empty) {
//         return "";
//     }
//     std.debug.print("Time: {s}= {d}\n", .{ key, time });
//     var buffer = std.ArrayList(u8).init(allocator);
//     defer buffer.deinit();
//     var writer = buffer.writer();
//     if (time == 0.0) {
//         try writer.print("{s}=\"0s\"", .{key});
//         return buffer.toOwnedSlice();
//     }
//
//     const frame_duration = video_file.avgFrameRateDuration();
//     const frames = @round(time / frame_duration);
//     const time_numerator = @as(i64, @intFromFloat(frames)) * video_file.avgFrameRate.den;
//     try writer.print("{s}=\"{d}/{d}s\"", .{ key, time_numerator, video_file.avgFrameRate.num });
//     // std.debug.print("Time: {s}= {d}/{d}s\n", .{ key, time_numerator, video_file.avgFrameRate.num });
//     return buffer.toOwnedSlice();
// }

var total_duration: f64 = 0.0;

var counter: u32 = 0;
// fn fcxml_1_8_addclip(
//     // Comment to prevent de freakin' linter from collapsing the code
//     allocator: std.mem.Allocator,
//     offset: i64,
//     start: i64,
//     duration: i64,
// ) !struct { clip: []const u8, raw: []const u8 } {
//     // const buff_offset = formatTime(allocator, offset, "offset", false) catch |err| {
//     //     return err;
//     // };
//     // const buff_start = formatTime(allocator, start, "start", true) catch |err| {
//     //     return err;
//     // };
//     // const buff_duration = formatTime(allocator, duration, "duration", false) catch |err| {
//     //     return err;
//     // };
//
//     var buffer = std.ArrayList(u8).init(allocator);
//     // defer buffer.deinit();
//     var writer = buffer.writer();
//     // "                        "
//     try writer.print("                        <asset-clip ref=\"r2\" name=\"{s}\" offset=\"{d}/24000s\" duration=\"{d}/24000s\" start=\"{d}/24000s\" tcFormat=\"NDF\" />\n", .{
//         video_file.name(),
//         offset,
//         start,
//         duration,
//     });
//
//     var rawBuffer = std.ArrayList(u8).init(allocator);
//     var rawWriter = rawBuffer.writer();
//     try rawWriter.print("{{ \"start\": {d}, \"end\": {d}, \"duration\": {d} }}\n", .{ start, start + duration, duration });
//
//     counter += 1;
//
//     // std.debug.print("{d}. <asset-clip ref=\"r2\" {s} name=\"{s}\" {s} {s} tcFormat=\"NDF\" audioRole=\"dialogue\"/>\n", .{
//     //     counter,
//     //     buff_offset,
//     //     video_file.name(),
//     //     buff_start,
//     //     buff_duration,
//     // });
//
//     return .{ .clip = try buffer.toOwnedSlice(), .raw = try rawBuffer.toOwnedSlice() };
// }

var current_start: f64 = 0.0;

fn logCallback(ptr: ?*anyopaque, level: c_int, fmt: [*c]const u8, vl: [*c]u8) callconv(.C) void {
    _ = ptr;
    _ = level;

    const message = blk: {
        var buffer: [1024]u8 = undefined;
        const len = vsnprintf(&buffer, 1024, fmt, vl);
        break :blk buffer[0..@intCast(len)];
    };

    if (extractValue(message)) |sevent| {
        switch (sevent.type) {
            0 => {
                dialogue_end = sevent.start_or_end;

                const duration = dialogue_end - dialogue_start;

                // if (duration < 0.1) {
                //     return;
                // }

                cur_clip_index += 1;

                const clip = EDL.getEdlLine(
                    fcpxml_allocator,
                    cur_clip_index,
                    current_start,
                    dialogue_start,
                    dialogue_end,
                    duration,
                ) catch {
                    return;
                };

                if (clip.line) |line| {
                    fcpxml_lines.append(line) catch |err| {
                        std.debug.print("Error al agregar clip: {}\n", .{err});
                        return;
                    };
                    current_start = clip.current_start;
                }
                // raw_lines.append(clip.raw) catch |err| {
                //     std.debug.print("Error al agregar clip: {}\n", .{err});
                //     return;
                // };
                // cur_offset += dialogue_duration;
                // cur_offset = cur_offset + (duration_frames * 1001);
                // total_duration += duration_frames * 1001;
                // std.debug.print("{d}. start: {d}, end: {d}, duration: {d}\n", .{ counter, dialogue_start, dialogue_end, dialogue_duration });
            },
            1 => {
                dialogue_start = sevent.start_or_end;
            },
            else => std.debug.print("Evento desconocido: {s}\n", .{message}),
        }
    }
}
