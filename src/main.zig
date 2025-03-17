const std = @import("std");
const av = @import("av");
const EDL = @import("edl.zig");

pub extern "c" fn vsnprintf(
    buffer: [*c]u8,
    size: usize,
    format: [*c]const u8,
    args: *anyopaque,
) c_int;

var adjustment: f16 = 0.3;
var decibels: i16 = -25;
var silence_duration: f32 = 1.0;
var output_file: std.fs.File = undefined;
var input_file_path: [:0]const u8 = undefined;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const global_allocator = arena.allocator();
var output_str = std.ArrayList(u8).init(global_allocator);
var dialogue_start: f64 = 0.0;
var cur_clip_index: f64 = 0;
var offset: f64 = 0.0;

const VideoFile = struct {
    audio_codec: *av.Codec.Parameters,
    audio_filter_str: [:0]const u8 = "\x00",
    video_frame_rate: av.Rational,

    pub fn frameRate(self: *VideoFile) f64 {
        return @as(f64, @trunc(tof64(self.video_frame_rate.num) / tof64(self.video_frame_rate.den) * 1000)) / 1000;
    }
};

var video_file = VideoFile{
    .audio_codec = undefined,
    // .audio_filter_str = undefined,
    .video_frame_rate = undefined,
};

fn parseArgs() !void {
    const args = try std.process.argsAlloc(global_allocator);
    defer std.process.argsFree(global_allocator, args);

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return;
        } else if (std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --time requires a value\n", .{});
                return;
            }
            input_file_path = try std.fmt.allocPrintZ(global_allocator, "{s}\x00", .{args[i]});
        } else if (std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: -d decibels requires a value\n", .{});
                return;
            }
            decibels = std.fmt.parseInt(i16, args[i], 10) catch {
                std.debug.print("Error: Invalid decibels value\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: -s silence requires a value\n", .{});
                return;
            }
            silence_duration = std.fmt.parseFloat(f32, args[i]) catch {
                std.debug.print("Error: Invalid silence duration value\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "-a")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: -a adjustment requires a value\n", .{});
                return;
            }
            adjustment = std.fmt.parseFloat(f16, args[i]) catch {
                std.debug.print("Error: Invalid adjustment value\n", .{});
                return;
            };
        } else {
            std.debug.print("Error: Unknown argument: {s}\n", .{arg});
            // return;
        }
        i += 1;
    }
    if (input_file_path.len == 0) {
        std.debug.print("Error: -i input_file_path is required\n", .{});
        return error.InvalidInputFilePath;
    }

    const file_name = std.fs.path.stem(input_file_path);
    const input_file_dir = std.fs.path.dirname(input_file_path);
    if (input_file_dir) |dir| {
        const output_file_path = try std.fmt.allocPrintZ(global_allocator, "{s}/{s}.edl", .{ dir, file_name });
        output_file = try std.fs.cwd().createFile(output_file_path, .{});
    } else {
        std.debug.print("Error: Invalid input file path\n", .{});
        return error.InvalidInputFilePath;
    }
}

fn printArgs() void {
    std.debug.print(
        \\input_file_path: {s}
        \\output_file: {}
        \\decibels: {d}
        \\silence_duration: {d}
        \\adjustment: {d}
        \\
    , .{ input_file_path, output_file, decibels, silence_duration, adjustment });
}

pub fn main() !void {
    //
    av.av_log_set_callback(&logCallback);

    parseArgs() catch return;
    printArgs();

    defer output_file.close();
    defer arena.deinit();

    const fc = try av.FormatContext.open_input(input_file_path, null, null, null);
    defer fc.close_input();

    const frame = try av.Frame.alloc();
    defer frame.free();

    const pkt = try av.Packet.alloc();
    defer pkt.free();

    const fg = try av.FilterGraph.alloc();
    defer fg.free();

    const audio_stream_index = try getMediaStreams(fc, &video_file);

    const silencedetect = try fg.alloc_filter(av.Filter.get_by_name("silencedetect").?, "DNXsilencedetect");
    try silencedetect.init_str(
        try std.fmt.allocPrintZ(
            global_allocator,
            "n={d}dB:d={d}",
            .{ decibels, silence_duration },
        ),
    );

    const abuffersink = try fg.alloc_filter(av.Filter.get_by_name("abuffersink").?, "DNXabuffersink");
    try abuffersink.init_str("");

    const abuffer = try fg.alloc_filter(av.Filter.get_by_name("abuffer").?, "DNXabuffer");
    try abuffer.init_str(video_file.audio_filter_str);

    const codec = try av.Codec.find_decoder(video_file.audio_codec.codec_id);
    const codec_ctx = try av.Codec.Context.alloc(codec);
    defer codec_ctx.free();
    try codec_ctx.parameters_to_context(video_file.audio_codec);
    try codec_ctx.open(codec, null);

    try av.FilterContext.link(abuffer, 0, silencedetect, 0);
    try av.FilterContext.link(silencedetect, 0, abuffersink, 0);
    try fg.config(null);

    try EDL.setHead(&output_str, std.fs.path.stem(input_file_path));

    while (true) {
        fc.read_frame(pkt) catch |err| {
            defer pkt.unref();
            if (err == error.EndOfFile) break;
            return err;
        };

        if (pkt.stream_index != audio_stream_index) {
            pkt.unref();
            continue;
        }

        codec_ctx.send_packet(pkt) catch |err| {
            pkt.unref();
            return err;
        };

        process_frames: while (true) {
            codec_ctx.receive_frame(frame) catch |err| {
                switch (err) {
                    error.WouldBlock => break :process_frames,
                    error.EndOfFile => break :process_frames,
                    else => {
                        pkt.unref();
                        return err;
                    },
                }
            };

            abuffer.buffersrc_add_frame(frame) catch |err| {
                pkt.unref();
                return err;
            };

            get_filtered_samples: while (true) {
                const processed_frame = av.Frame.alloc() catch {
                    pkt.unref();
                    return error.AllocationFailed;
                };

                abuffersink.buffersink_get_samples(processed_frame, frame.nb_samples) catch |err| {
                    defer processed_frame.free();

                    switch (err) {
                        error.WouldBlock, error.EndOfFile => break :get_filtered_samples,
                        else => {
                            pkt.unref();
                            return err;
                        },
                    }
                };

                processed_frame.free();
            }
        }

        pkt.unref();
    }
    output_file.writeAll(output_str.items) catch |err| {
        std.debug.print("Error al escribir archivo: {}\n", .{err});
        return;
    };
    std.debug.print("Archivo escrito correctamente.\n", .{});
}

fn tof64(num: anytype) f64 {
    return @as(f64, @floatFromInt(num));
}

fn getMediaStreams(fc: *av.FormatContext, vf: *VideoFile) !usize {
    try fc.find_stream_info(null);
    var audio_stream_index: usize = 0;

    for (0..fc.nb_streams) |i| {
        //
        switch (fc.streams[i].codecpar.codec_type) {
            av.MediaType.VIDEO => {
                vf.video_frame_rate = fc.streams[i].avg_frame_rate;
            },
            av.MediaType.AUDIO => {
                vf.audio_codec = fc.streams[i].codecpar;
                const as = analyzeAudioStream(vf.audio_codec);
                vf.audio_filter_str = try std.fmt.allocPrintZ(
                    global_allocator,
                    "sample_rate={d}:sample_fmt={s}:channel_layout={s}",
                    .{
                        as.sample_rate,
                        as.sample_fmt,
                        as.channel_layout,
                    },
                );
                audio_stream_index = i;
                break;
            },
            else => {},
        }
    }

    if (std.mem.eql(u8, vf.audio_filter_str, "\x00")) {
        return error.NoAudioStream;
    }

    return audio_stream_index;
}

fn analyzeAudioStream(codec_par: *av.Codec.Parameters) struct {
    sample_rate: c_int,
    sample_fmt: []const u8,
    channel_layout: []const u8,
} {
    return .{
        .sample_rate = codec_par.sample_rate,
        .sample_fmt = switch (codec_par.format) {
            1 => "s16",
            8 => "fltp",
            else => "unknown",
        },
        .channel_layout = switch (codec_par.ch_layout.nb_channels) {
            2 => "stereo",
            else => "unknown",
        },
    };
}

fn extractValue(message: []const u8) ?struct { second: f64, type: u8 } {
    var sub: []const u8 = undefined;
    var type_: u8 = 0;
    var end: usize = 0;

    if (std.mem.indexOf(u8, message, "silence_start:")) |start| {
        sub = message[start + "silence_start:".len ..];
        end = std.mem.indexOf(u8, sub, "\n") orelse sub.len;
        type_ = 0;
    } else if (std.mem.indexOf(u8, message, "silence_end:")) |ends| {
        sub = message[ends + "silence_end:".len ..];
        end = std.mem.indexOf(u8, sub, "|") orelse sub.len;
        type_ = 1;
    } else {
        return null;
    }

    const num_str = std.mem.trim(u8, sub[0..end], " ");
    const second = std.fmt.parseFloat(f64, num_str) catch {
        return null;
    };

    return .{ .type = type_, .second = second };
}

fn logCallback(ptr: ?*anyopaque, level: c_int, fmt: [*c]const u8, vl: [*c]u8) callconv(.C) void {
    _ = ptr;
    _ = level;

    const message = blk: {
        var buffer: [1024]u8 = undefined;
        const len = vsnprintf(&buffer, 1024, fmt, vl);
        break :blk buffer[0..@intCast(len)];
    };

    if (extractValue(message)) |silence_event| {
        switch (silence_event.type) {
            0 => {
                cur_clip_index += 1;

                const new_offset = EDL.getEdlLine(
                    &output_str,
                    cur_clip_index,
                    offset,
                    dialogue_start,
                    silence_event.second,
                    video_file.frameRate(),
                    adjustment,
                ) catch {
                    return;
                };

                // if (clip) |line| {
                // output_file.writeAll(line) catch |err| {
                //     std.debug.print("Error al agregar clip: {}\n", .{err});
                //     return;
                // };
                offset = new_offset;
                // }
            },
            1 => {
                dialogue_start = silence_event.second;
            },
            else => std.debug.print("Evento desconocido: {s}\n", .{message}),
        }
    }
}
