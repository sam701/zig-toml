const std = @import("std");
const Io = std.Io;
const toml = @import("toml");

const TomlValue = toml.Value(toml.DefaultDateTypes);
const TomlTable = toml.Table(toml.DefaultDateTypes);
const TomlArray = toml.Array(toml.DefaultDateTypes);

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [4096]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &in_buf);

    const parsed = try toml.parse(TomlTable, &stdin_reader.interface, init.gpa);
    defer parsed.deinit();

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &out_buf);
    const stdout = &stdout_writer.interface;

    const val = TomlValue{ .table = parsed.value };

    try writeValue(&val, stdout);
    try stdout.writeByte('\n');
    try stdout.flush();
}

fn writeValue(v: *const TomlValue, w: *Io.Writer) Io.Writer.Error!void {
    switch (v.*) {
        .table => |*t| try writeTable(t, w),
        .array => |arr| try writeArray(&arr, w),
        .string => |s| try writeTagged("string", s, w),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
            try writeTagged("integer", s, w);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const s = formatFloat(f, &buf);
            try writeTagged("float", s, w);
        },
        .boolean => |b| try writeTagged("bool", if (b) "true" else "false", w),
        .datetime => |s| try writeTagged("datetime", s, w),
        .datetime_local => |s| try writeTagged("datetime-local", s, w),
        .date => |s| try writeTagged("date-local", s, w),
        .time => |s| try writeTagged("time-local", s, w),
    }
}

fn writeTable(t: *const std.StringHashMapUnmanaged(TomlValue), w: *Io.Writer) Io.Writer.Error!void {
    try w.writeByte('{');
    var first = true;
    var it = t.iterator();
    while (it.next()) |entry| {
        if (!first) try w.writeByte(',');
        first = false;
        try writeJsonString(entry.key_ptr.*, w);
        try w.writeByte(':');
        try writeValue(entry.value_ptr, w);
    }
    try w.writeByte('}');
}

fn writeArray(arr: *const TomlArray, w: *Io.Writer) Io.Writer.Error!void {
    try w.writeByte('[');
    for (arr.items, 0..) |*item, i| {
        if (i != 0) try w.writeByte(',');
        try writeValue(item, w);
    }
    try w.writeByte(']');
}

fn writeTagged(typ: []const u8, value: []const u8, w: *Io.Writer) !void {
    try w.print("{{\"type\":\"{s}\",\"value\":", .{typ});
    try writeJsonString(value, w);
    try w.writeByte('}');
}

fn writeJsonString(s: []const u8, w: *Io.Writer) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                var esc_buf: [6]u8 = undefined;
                const esc = std.fmt.bufPrint(&esc_buf, "\\u{x:0>4}", .{c}) catch unreachable;
                try w.writeAll(esc);
            },
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

fn formatFloat(f: f64, buf: []u8) []const u8 {
    if (std.math.isNan(f)) return "nan";
    if (std.math.isPositiveInf(f)) return "inf";
    if (std.math.isNegativeInf(f)) return "-inf";
    return std.fmt.bufPrint(buf, "{d}", .{f}) catch unreachable;
}
