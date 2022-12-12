const std = @import("std");
const parser = @import("./parser.zig");
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
    var d = Date{ .year = 2004, .month = 7, .day = 11 };
    var d1 = try interpretDate("2004-07-11");
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
    var t = try interpretTime(str);
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
