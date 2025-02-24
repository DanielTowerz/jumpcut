const std = @import("std");

pub fn getTag(allocator: std.mem.Allocator, data: struct { start: i64, duration: i64, offset: i64 }) ![]const u8 {
    //<asset-clip tcFormat="NDF" ref="r1" start="257257/24000s" duration="1001/800s" offset="0/1s" name="D17.mp4" enabled="1" format="r0">
    const denominator = 24000;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.print(
        \\<asset-clip tcFormat="NDF" ref="r2" start="{d}/{d}s" duration="{d}/{d}s" offset="{d}/{d}s" name="{s}" enabled="1" format="r1"></asset-clip>{s}
    , .{
        data.start * denominator,    denominator,
        data.duration * denominator, denominator,
        data.offset * denominator,   denominator,
        "D17.mp4",                   "\n",
    });
    return buffer.toOwnedSlice();
}
