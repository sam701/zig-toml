const std = @import("std");
const parser = @import("parser");
const testing = std.testing;

pub const Date = struct {
    year: u16,
    month: u4,
    day: u5,
};

pub const Time = struct {
    hour: u5,
    minute: u6,
    second: u6,
    nanosecond: u30 = 0,
};

pub const DateTime = struct {
    date: Date,
    time: Time,
    offset_minutes: ?i16 = 0,
};

pub const DateError = error{
    InvalidYear,
    InvalidMonth,
    InvalidDay,
};

pub fn interpretDate(txt: []const u8) DateError!?Date {
    if (txt.len != 10 or txt[4] != '-' or txt[7] != '-') return null;
    var d: Date = undefined;
    d.year = std.fmt.parseInt(u16, txt[0..4], 10) catch return DateError.InvalidYear;

    d.month = std.fmt.parseInt(u4, txt[5..7], 10) catch return DateError.InvalidMonth;
    if (d.month > 12 or d.month == 0) return DateError.InvalidMonth;

    d.day = std.fmt.parseInt(u5, txt[8..], 10) catch return DateError.InvalidDay;
    if (d.day > 31 or d.day == 0) return DateError.InvalidDay;

    return d;
}

test "date" {
    const d = Date{ .year = 2004, .month = 7, .day = 11 };
    const d1 = try interpretDate("2004-07-11");
    try testing.expect(std.meta.eql(d, d1.?));

    try testing.expectError(DateError.InvalidYear, interpretDate("0x04-07-11"));
    try testing.expectError(DateError.InvalidMonth, interpretDate("2004-0a-11"));
    try testing.expectError(DateError.InvalidMonth, interpretDate("2004-15-11"));
    try testing.expectError(DateError.InvalidDay, interpretDate("2004-07-cc"));
    try testing.expectError(DateError.InvalidDay, interpretDate("2004-07-00"));

    try testing.expect(try interpretDate("2004") == null);
}

pub const TimeError = error{
    InvalidHour,
    InvalidMinute,
    InvalidSecond,
    InvalidNanoSecond,
};

pub fn interpretTime(txt: []const u8) TimeError!?Time {
    if (txt.len < 8 or txt[2] != ':' or txt[5] != ':') return null;
    if (txt.len > 8 and (txt[8] != '.' or txt.len < 15 or txt.len % 3 != 0)) return TimeError.InvalidNanoSecond;

    var t: Time = undefined;
    t.hour = std.fmt.parseInt(u5, txt[0..2], 10) catch return TimeError.InvalidHour;
    if (t.hour > 23) return TimeError.InvalidHour;

    t.minute = std.fmt.parseInt(u6, txt[3..5], 10) catch return TimeError.InvalidMinute;
    if (t.minute > 59) return TimeError.InvalidMinute;

    t.second = std.fmt.parseInt(u6, txt[6..8], 10) catch return TimeError.InvalidSecond;
    if (t.second > 59) return TimeError.InvalidSecond;

    if (txt.len == 15) {
        t.nanosecond = std.fmt.parseInt(u30, txt[9..], 10) catch return TimeError.InvalidNanoSecond;
        t.nanosecond *= 1000;
    } else if (txt.len > 15) {
        t.nanosecond = std.fmt.parseInt(u30, txt[9..18], 10) catch return TimeError.InvalidNanoSecond;
    } else {
        t.nanosecond = 0;
    }

    return t;
}

fn testTime(str: []const u8, expected: Time) !void {
    const t = try interpretTime(str);
    try testing.expect(std.meta.eql(t.?, expected));
}

test "time" {
    try testTime("15:16:17", Time{ .hour = 15, .minute = 16, .second = 17 });
    try testTime("15:16:17.123456", Time{ .hour = 15, .minute = 16, .second = 17, .nanosecond = 123456000 });
    try testTime("15:16:17.123456789", Time{ .hour = 15, .minute = 16, .second = 17, .nanosecond = 123456789 });
    try testTime("15:16:17.123456789123", Time{ .hour = 15, .minute = 16, .second = 17, .nanosecond = 123456789 });

    try testing.expectError(TimeError.InvalidHour, interpretTime("33:16:17"));
    try testing.expectError(TimeError.InvalidMinute, interpretTime("23:76:17"));
    try testing.expectError(TimeError.InvalidSecond, interpretTime("23:16:87"));
    try testing.expectError(TimeError.InvalidNanoSecond, interpretTime("23:16:17."));
    try testing.expectError(TimeError.InvalidNanoSecond, interpretTime("23:16:17.12345"));
    try testing.expectError(TimeError.InvalidNanoSecond, interpretTime("23:16:17.12345a"));
    try testing.expectError(TimeError.InvalidNanoSecond, interpretTime("23:16:17.1234567"));
}

pub const TimeWithOffset = struct {
    time: Time,
    offset_minutes: ?i16 = null,
};

pub fn interpretTimeAndOffset(txt: []const u8) !?TimeWithOffset {
    if (txt.len < 8) return null;
    if (txt.len == 8) return TimeWithOffset{ .time = try interpretTime(txt) orelse return null };

    var to: TimeWithOffset = undefined;
    if (txt[txt.len - 1] == 'Z') {
        to.offset_minutes = 0;
        to.time = (try interpretTime(txt[0 .. txt.len - 1])) orelse return null;
    } else if (try interpretOffset(txt[txt.len - 6 ..])) |offset| {
        to.time = try interpretTime(txt[0 .. txt.len - 6]) orelse return null;
        to.offset_minutes = offset;
    } else {
        return null;
    }
    return to;
}

const OffsetError = error{
    InvalidTimeOffset,
};

fn interpretOffset(txt: []const u8) OffsetError!?i16 {
    if ((txt[0] == '+' or txt[0] == '-') and txt[3] == ':') {
        const hour = std.fmt.parseInt(i16, txt[0..3], 10) catch return error.InvalidTimeOffset;
        const minute = std.fmt.parseInt(i16, txt[4..], 10) catch return error.InvalidTimeOffset;
        if (hour > 11 or hour < -11 or minute > 59) return error.InvalidTimeOffset;
        return hour * 60 + std.math.sign(hour) * minute;
    } else return null;
}

pub const DateTimeError = DateError || TimeError || OffsetError;

pub fn interpretDateTime(txt: []const u8) DateTimeError!?DateTime {
    if (txt.len < 19 or txt[10] != 'T') return null;
    const date = try interpretDate(txt[0..10]) orelse return null;
    const time_with_offset = try interpretTimeAndOffset(txt[11..]) orelse return null;
    return DateTime{
        .date = date,
        .time = time_with_offset.time,
        .offset_minutes = time_with_offset.offset_minutes,
    };
}

test "datetime" {
    const dt = try interpretDateTime("2022-12-14T09:14:58.555555-02:30");
    try testing.expect(std.meta.eql(dt.?, DateTime{
        .date = Date{ .year = 2022, .month = 12, .day = 14 },
        .time = Time{ .hour = 9, .minute = 14, .second = 58, .nanosecond = 555555000 },
        .offset_minutes = -150,
    }));
}
