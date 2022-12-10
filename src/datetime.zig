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
    minutes: u6,
    seconds: u6,
    nanosecond: u30,
};

pub const DateTime = struct {
    date: Date,
    time: Time,
    offset_minutes: ?i16,
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
