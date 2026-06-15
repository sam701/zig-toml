const std = @import("std");
const Io = std.Io;
const toml = @import("toml");

const TomlValue = toml.Value(toml.DateTimesSimple);
const TomlTable = toml.Table(toml.DateTimesSimple);
const TomlArray = toml.Array(toml.DateTimesSimple);

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
        .table => |t| try writeTable(&t.data, w),
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
        .datetime => |dt| {
            var buf: [64]u8 = undefined;
            try writeTagged("datetime", formatDatetime(dt, &buf), w);
        },
        .datetime_local => |dt| {
            var buf: [48]u8 = undefined;
            try writeTagged("datetime-local", formatDatetimeLocal(dt, &buf), w);
        },
        .date => |d| {
            var buf: [16]u8 = undefined;
            try writeTagged("date-local", formatDate(d, &buf), w);
        },
        .time => |t| {
            var buf: [32]u8 = undefined;
            try writeTagged("time-local", formatTime(t, &buf), w);
        },
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
    for (arr.data.items, 0..) |*item, i| {
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

fn formatDate(d: toml.DateTimesSimple.Date, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day }) catch unreachable;
}

fn formatTime(t: toml.DateTimesSimple.Time, buf: []u8) []const u8 {
    if (t.nanosecond != 0) {
        return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d}", .{ t.hour, t.minute, t.second, t.nanosecond }) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ t.hour, t.minute, t.second }) catch unreachable;
}

fn formatDatetime(dt: toml.DateTimesSimple.DateTime, buf: []u8) []const u8 {
    var date_buf: [16]u8 = undefined;
    var time_buf: [32]u8 = undefined;
    const date_s = formatDate(dt.date, &date_buf);
    const time_s = formatTime(dt.time, &time_buf);
    if (dt.offset_minutes) |offset| {
        if (offset == 0) {
            return std.fmt.bufPrint(buf, "{s}T{s}Z", .{ date_s, time_s }) catch unreachable;
        }
        const sign: u8 = if (offset > 0) '+' else '-';
        const abs_off: u16 = @intCast(@abs(offset));
        return std.fmt.bufPrint(buf, "{s}T{s}{c}{d:0>2}:{d:0>2}", .{ date_s, time_s, sign, abs_off / 60, abs_off % 60 }) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "{s}T{s}", .{ date_s, time_s }) catch unreachable;
}

fn formatDatetimeLocal(dt: toml.DateTimesSimple.DateTimeLocal, buf: []u8) []const u8 {
    var date_buf: [16]u8 = undefined;
    var time_buf: [32]u8 = undefined;
    const date_s = formatDate(dt.date, &date_buf);
    const time_s = formatTime(dt.time, &time_buf);
    return std.fmt.bufPrint(buf, "{s}T{s}", .{ date_s, time_s }) catch unreachable;
}

fn formatFloat(f: f64, buf: []u8) []const u8 {
    if (std.math.isNan(f)) return "nan";
    if (std.math.isPositiveInf(f)) return "inf";
    if (std.math.isNegativeInf(f)) return "-inf";
    return std.fmt.bufPrint(buf, "{d}", .{f}) catch unreachable;
}
